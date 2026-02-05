const std = @import("std");
const ast = @import("ast.zig");
const eval = @import("eval.zig");
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const FlakeRef = @import("flakeref.zig").FlakeRef;
const Registry = @import("flakeref.zig").Registry;
const LockFile = @import("lockfile.zig").LockFile;
const Fetcher = @import("fetcher.zig").Fetcher;
const FetchResult = @import("fetcher.zig").FetchResult;
const store = @import("store.zig");

const Value = eval.Value;
const Env = eval.Env;
const Expr = ast.Expr;

/// A parsed flake structure
pub const Flake = struct {
    description: ?[]const u8,
    inputs: std.StringHashMap(FlakeInput),
    outputs_expr: ?*Expr,
    path: []const u8,
    source: ?[]const u8, // Keep source alive for AST identifiers
    allocator: std.mem.Allocator,

    pub const FlakeInput = struct {
        ref: FlakeRef,
        follows: ?[]const []const u8,
    };

    pub fn deinit(self: *Flake) void {
        if (self.description) |d| self.allocator.free(d);
        var iter = self.inputs.iterator();
        while (iter.next()) |entry| {
            @constCast(&entry.value_ptr.ref).deinit();
            if (entry.value_ptr.follows) |f| {
                for (f) |part| self.allocator.free(part);
                self.allocator.free(f);
            }
        }
        self.inputs.deinit();
        if (self.outputs_expr) |expr| {
            expr.deinit(self.allocator);
            self.allocator.destroy(expr);
        }
        self.allocator.free(self.path);
        if (self.source) |s| self.allocator.free(s);
    }
};

/// Resolved flake with evaluated inputs
pub const ResolvedFlake = struct {
    flake: Flake,
    inputs: std.StringHashMap(ResolvedInput),
    outputs: ?Value,
    allocator: std.mem.Allocator,

    pub const ResolvedInput = struct {
        flake: ?*ResolvedFlake,
        source_path: []const u8,
        rev: ?[]const u8,
    };

    pub fn deinit(self: *ResolvedFlake) void {
        self.flake.deinit();
        var iter = self.inputs.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.flake) |f| {
                f.deinit();
                self.allocator.destroy(f);
            }
            self.allocator.free(entry.value_ptr.source_path);
            if (entry.value_ptr.rev) |r| self.allocator.free(r);
        }
        self.inputs.deinit();
    }
};

/// The flake evaluator
pub const FlakeEvaluator = struct {
    allocator: std.mem.Allocator,
    fetcher: Fetcher,
    registry: Registry,
    evaluator: eval.Evaluator,
    nix_store: store.Store,
    system: []const u8,

    pub fn init(allocator: std.mem.Allocator) !FlakeEvaluator {
        var fe = FlakeEvaluator{
            .allocator = allocator,
            .fetcher = Fetcher.init(allocator),
            .registry = Registry.init(allocator),
            .evaluator = try eval.Evaluator.init(allocator),
            .nix_store = store.Store.init(allocator),
            .system = store.getCurrentSystem(),
        };

        try fe.registry.loadDefaults();

        return fe;
    }

    pub fn deinit(self: *FlakeEvaluator) void {
        self.fetcher.deinit();
        self.registry.deinit();
        self.evaluator.deinit();
        self.nix_store.deinit();
    }

    /// Load and parse a flake.nix file
    /// NOTE: File I/O temporarily stubbed - requires IO handle
    pub fn loadFlake(self: *FlakeEvaluator, path: []const u8) !Flake {
        // TODO: Implement proper file I/O with new Zig Io API
        _ = path;

        // Return a basic empty flake for now
        const flake = Flake{
            .description = null,
            .inputs = std.StringHashMap(Flake.FlakeInput).init(self.allocator),
            .outputs_expr = null,
            .path = try self.allocator.dupe(u8, "."),
            .source = null,
            .allocator = self.allocator,
        };

        return flake;
    }

    /// Load and parse a flake.nix file (with IO handle)
    pub fn loadFlakeWithIo(self: *FlakeEvaluator, io: std.Io, path: []const u8) !Flake {
        const Dir = std.Io.Dir;

        // Read flake.nix
        const flake_path = try std.fs.path.join(self.allocator, &.{ path, "flake.nix" });
        defer self.allocator.free(flake_path);

        const file = try Dir.openFile(.cwd(), io, flake_path, .{});
        defer file.close(io);

        const len = try file.length(io);
        var read_buf: [8192]u8 = undefined;
        var reader = file.reader(io, &read_buf);
        const source = try reader.interface.readAlloc(self.allocator, @intCast(len));
        // NOTE: Don't free source! The parsed AST points into it.
        // The source will be freed when the Flake is deinitialized.

        // Parse the flake.nix
        var p = try parser.Parser.init(self.allocator, source, flake_path);
        defer p.deinit();

        const flake_expr = try p.parseExpr();

        // The flake.nix should be an attribute set
        if (flake_expr != .attrs) {
            return error.InvalidFlake;
        }

        var flake = Flake{
            .description = null,
            .inputs = std.StringHashMap(Flake.FlakeInput).init(self.allocator),
            .outputs_expr = undefined,
            .path = try self.allocator.dupe(u8, path),
            .source = source,
            .allocator = self.allocator,
        };
        errdefer flake.deinit();

        // Extract flake attributes
        for (flake_expr.attrs.bindings) |binding| {
            const key = try self.attrPathToString(binding.key);
            defer self.allocator.free(key);

            if (std.mem.eql(u8, key, "description")) {
                if (binding.value.* == .string) {
                    flake.description = try self.allocator.dupe(u8, binding.value.string);
                }
            } else if (std.mem.eql(u8, key, "inputs")) {
                try self.parseInputs(&flake, binding.value.*);
            } else if (std.mem.eql(u8, key, "outputs")) {
                flake.outputs_expr = binding.value;
            }
        }

        return flake;
    }

    fn attrPathToString(self: *FlakeEvaluator, path: Expr.AttrPath) ![]u8 {
        var result: std.ArrayList(u8) = .empty;
        for (path.parts, 0..) |part, i| {
            if (i > 0) try result.append(self.allocator, '.');
            switch (part) {
                .ident => |id| try result.appendSlice(self.allocator, id),
                .string => |s| try result.appendSlice(self.allocator, s),
                .expr => return error.DynamicAttrPath,
            }
        }
        return result.toOwnedSlice(self.allocator);
    }

    fn parseInputs(self: *FlakeEvaluator, flake: *Flake, expr: Expr) !void {
        if (expr != .attrs) return;

        for (expr.attrs.bindings) |binding| {
            const name = try self.attrPathToString(binding.key);
            errdefer self.allocator.free(name);

            var input = Flake.FlakeInput{
                .ref = FlakeRef.init(self.allocator),
                .follows = null,
            };

            // Input can be a string (shorthand) or an attrset
            switch (binding.value.*) {
                .string => |s| {
                    input.ref = try FlakeRef.parse(self.allocator, s);
                },
                .attrs => |attrs| {
                    for (attrs.bindings) |attr_binding| {
                        const attr_key = try self.attrPathToString(attr_binding.key);
                        defer self.allocator.free(attr_key);

                        if (std.mem.eql(u8, attr_key, "url")) {
                            if (attr_binding.value.* == .string) {
                                input.ref = try FlakeRef.parse(self.allocator, attr_binding.value.string);
                            }
                        } else if (std.mem.eql(u8, attr_key, "follows")) {
                            if (attr_binding.value.* == .string) {
                                var follows: std.ArrayList([]const u8) = .empty;
                                var parts = std.mem.splitScalar(u8, attr_binding.value.string, '/');
                                while (parts.next()) |part| {
                                    try follows.append(self.allocator, try self.allocator.dupe(u8, part));
                                }
                                input.follows = try follows.toOwnedSlice(self.allocator);
                            }
                        }
                    }
                },
                else => {},
            }

            // If no URL was specified, use the input name as an indirect ref
            if (input.ref.url.len == 0) {
                input.ref = try FlakeRef.parse(self.allocator, name);
            }

            try flake.inputs.put(name, input);
        }
    }

    /// Resolve all inputs and evaluate the flake
    pub fn resolve(self: *FlakeEvaluator, flake: Flake) !ResolvedFlake {
        var resolved = ResolvedFlake{
            .flake = flake,
            .inputs = std.StringHashMap(ResolvedFlake.ResolvedInput).init(self.allocator),
            .outputs = null,
            .allocator = self.allocator,
        };
        errdefer resolved.deinit();

        // Resolve each input
        var iter = flake.inputs.iterator();
        while (iter.next()) |entry| {
            const input_name = entry.key_ptr.*;
            const input = entry.value_ptr.*;

            // Handle follows
            if (input.follows != null) {
                // Would need to resolve from parent flake
                continue;
            }

            // Resolve indirect refs through registry
            var ref = input.ref;
            if (ref.type == .indirect) {
                if (self.registry.resolve(ref.url)) |resolved_ref| {
                    ref = resolved_ref;
                }
            }

            // Fetch the input
            var fetch_result = self.fetcher.fetch(&ref, flake.path) catch |err| {
                std.debug.print("Failed to fetch input {s}: {}\n", .{ input_name, err });
                continue;
            };

            // Load the input as a flake (if it has a flake.nix)
            const input_flake_path = std.fs.path.join(self.allocator, &.{ fetch_result.path, "flake.nix" }) catch continue;
            defer self.allocator.free(input_flake_path);

            // TODO: Check if flake.nix exists with proper IO
            const has_flake = false;

            var resolved_input = ResolvedFlake.ResolvedInput{
                .flake = null,
                .source_path = fetch_result.path,
                .rev = fetch_result.rev,
            };

            if (has_flake) {
                const input_flake = self.loadFlake(fetch_result.path) catch null;
                if (input_flake) |fl| {
                    const resolved_fl = try self.allocator.create(ResolvedFlake);
                    resolved_fl.* = try self.resolve(fl);
                    resolved_input.flake = resolved_fl;
                }
            }

            try resolved.inputs.put(input_name, resolved_input);
        }

        return resolved;
    }

    /// Evaluate the flake outputs
    pub fn evalOutputs(self: *FlakeEvaluator, resolved: *ResolvedFlake) !Value {
        // Build the inputs attrset to pass to the outputs function
        var inputs_env = try Env.init(self.allocator, null);
        defer inputs_env.deinit();

        // Add self
        var self_attrs = std.StringHashMap(Value).init(self.allocator);
        try self_attrs.put("outPath", Value{ .path = resolved.flake.path });
        try inputs_env.define("self", Value{ .attrs = .{ .bindings = self_attrs } });

        // Add each resolved input
        var iter = resolved.inputs.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const input = entry.value_ptr.*;

            var input_attrs = std.StringHashMap(Value).init(self.allocator);
            try input_attrs.put("outPath", Value{ .path = input.source_path });
            if (input.rev) |r| {
                try input_attrs.put("rev", Value{ .string = r });
            }

            // If the input is a flake, add its outputs
            if (input.flake) |fl| {
                if (fl.outputs) |outputs| {
                    // Merge outputs into input attrs
                    if (outputs == .attrs) {
                        var out_iter = outputs.attrs.bindings.iterator();
                        while (out_iter.next()) |out_entry| {
                            try input_attrs.put(out_entry.key_ptr.*, out_entry.value_ptr.*);
                        }
                    }
                }
            }

            try inputs_env.define(name, Value{ .attrs = .{ .bindings = input_attrs } });
        }

        // The outputs expression should be a lambda
        if (resolved.flake.outputs_expr) |outputs_expr| {
            const outputs_val = try self.evaluator.evalInEnv(outputs_expr.*, inputs_env);

            // If it's a lambda, call it with inputs
            if (outputs_val == .lambda) {
                const inputs_val = try self.buildInputsValue(resolved);
                const result = try self.evaluator.apply(outputs_val, inputs_val);
                resolved.outputs = result;
                return result;
            }

            resolved.outputs = outputs_val;
            return outputs_val;
        }

        return Value{ .null_val = {} };
    }

    fn buildInputsValue(self: *FlakeEvaluator, resolved: *ResolvedFlake) !Value {
        var inputs_attrs = std.StringHashMap(Value).init(self.allocator);

        // Add self
        var self_attrs = std.StringHashMap(Value).init(self.allocator);
        try self_attrs.put("outPath", Value{ .path = resolved.flake.path });
        try inputs_attrs.put("self", Value{ .attrs = .{ .bindings = self_attrs } });

        // Add each input
        var iter = resolved.inputs.iterator();
        while (iter.next()) |entry| {
            var input_attrs = std.StringHashMap(Value).init(self.allocator);
            try input_attrs.put("outPath", Value{ .path = entry.value_ptr.source_path });
            if (entry.value_ptr.rev) |r| {
                try input_attrs.put("rev", Value{ .string = r });
            }
            try inputs_attrs.put(entry.key_ptr.*, Value{ .attrs = .{ .bindings = input_attrs } });
        }

        return Value{ .attrs = .{ .bindings = inputs_attrs } };
    }

    /// Select an attribute path from flake outputs
    /// e.g., "legacyPackages.x86_64-linux.hello"
    pub fn selectOutput(self: *FlakeEvaluator, outputs: Value, attr_path: []const u8) !Value {
        var current = outputs;
        var parts = std.mem.splitScalar(u8, attr_path, '.');

        while (parts.next()) |part| {
            // Force thunks
            current = try self.evaluator.force(current);

            if (current != .attrs) {
                return error.NotAnAttrSet;
            }

            if (current.attrs.bindings.get(part)) |val| {
                current = val;
            } else {
                std.debug.print("Attribute not found: {s}\n", .{part});
                return error.AttributeNotFound;
            }
        }

        return self.evaluator.force(current);
    }

    /// Build a package from the flake
    pub fn build(self: *FlakeEvaluator, io: std.Io, flake_ref: []const u8, attr_path: []const u8) ![]const u8 {
        // Parse the flake reference (e.g., "." or "github:NixOS/nixpkgs")
        var ref = try FlakeRef.parse(self.allocator, flake_ref);
        defer ref.deinit();

        // Resolve the path
        const flake_path = try ref.resolve(self.allocator, ".");
        defer self.allocator.free(flake_path);

        // Load the flake
        const fl = try self.loadFlakeWithIo(io, flake_path);

        // Resolve inputs
        var resolved = try self.resolve(fl);
        defer resolved.deinit();

        // Evaluate outputs
        const outputs = try self.evalOutputs(&resolved);

        // Select the requested output
        const selected = try self.selectOutput(outputs, attr_path);

        // Check if it's a derivation
        if (selected == .attrs) {
            if (selected.attrs.bindings.get("type")) |type_val| {
                if (type_val == .string and std.mem.eql(u8, type_val.string, "derivation")) {
                    // Build the derivation
                    return self.buildDerivation(selected);
                }
            }

            // Check for drvPath attribute
            if (selected.attrs.bindings.get("drvPath")) |drv_path_val| {
                if (drv_path_val == .path or drv_path_val == .string) {
                    const drv_path = if (drv_path_val == .path) drv_path_val.path else drv_path_val.string;
                    std.debug.print("Would build: {s}\n", .{drv_path});
                    return try self.allocator.dupe(u8, drv_path);
                }
            }
        }

        return error.NotADerivation;
    }

    fn buildDerivation(self: *FlakeEvaluator, drv_val: Value) ![]const u8 {
        if (drv_val != .attrs) return error.NotADerivation;

        // Extract derivation attributes
        var drv = store.Derivation.init(self.allocator);
        defer drv.deinit();

        if (drv_val.attrs.bindings.get("name")) |v| {
            if (v == .string) drv.name = v.string;
        }
        if (drv_val.attrs.bindings.get("system")) |v| {
            if (v == .string) drv.system = v.string;
        }
        if (drv_val.attrs.bindings.get("builder")) |v| {
            if (v == .string or v == .path) {
                drv.builder = if (v == .string) v.string else v.path;
            }
        }

        // Build using the store
        return self.nix_store.buildDerivation(&drv);
    }
};

test "flake evaluator init" {
    const allocator = std.testing.allocator;

    var fe = try FlakeEvaluator.init(allocator);
    defer fe.deinit();

    try std.testing.expect(fe.registry.entries.count() > 0);
}
