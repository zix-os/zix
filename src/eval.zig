const std = @import("std");
const ast = @import("ast.zig");
const builtins = @import("builtins.zig");

const Expr = ast.Expr;

pub const Value = union(enum) {
    int: i64,
    float: f64,
    bool: bool,
    string: []const u8,
    path: []const u8,
    null_val,
    list: []Value,
    attrs: AttrSet,
    lambda: Lambda,
    builtin: Builtin,
    thunk: *Thunk,

    pub const AttrSet = struct {
        bindings: std.StringHashMap(Value),
    };

    pub const Lambda = struct {
        param: ast.Expr.Param,
        body: *Expr,
        env: *Env,
    };

    pub const Builtin = struct {
        name: []const u8,
        func: *const fn (allocator: std.mem.Allocator, args: []Value) anyerror!Value,
    };

    pub fn print(self: Value, writer: anytype) error{OutOfMemory}!void {
        switch (self) {
            .int => |v| writer.print("{}", .{v}) catch {},
            .float => |v| writer.print("{d}", .{v}) catch {},
            .bool => |v| writer.writeAll(if (v) "true" else "false") catch {},
            .string => |s| writer.print("\"{s}\"", .{s}) catch {},
            .path => |p| writer.print("{s}", .{p}) catch {},
            .null_val => writer.writeAll("null") catch {},
            .list => |l| {
                writer.writeAll("[ ") catch {};
                for (l) |elem| {
                    elem.print(writer) catch {};
                    writer.writeAll(" ") catch {};
                }
                writer.writeAll("]") catch {};
            },
            .attrs => |a| {
                writer.writeAll("{ ") catch {};
                var iter = a.bindings.iterator();
                while (iter.next()) |entry| {
                    writer.print("{s} = ", .{entry.key_ptr.*}) catch {};
                    entry.value_ptr.print(writer) catch {};
                    writer.writeAll("; ") catch {};
                }
                writer.writeAll("}") catch {};
            },
            .lambda => writer.writeAll("<lambda>") catch {},
            .builtin => |b| writer.print("<builtin:{s}>", .{b.name}) catch {},
            .thunk => writer.writeAll("<thunk>") catch {},
        }
    }

    pub fn deinit(self: Value, allocator: std.mem.Allocator) void {
        switch (self) {
            .int, .float, .bool, .null_val => {},
            // string and path are slices into source, don't free
            .string, .path => {},
            .list => |l| {
                for (l) |elem| {
                    elem.deinit(allocator);
                }
                allocator.free(l);
            },
            .attrs => |a| {
                var iter = a.bindings.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.deinit(allocator);
                }
                // Cast away const to call deinit
                var bindings_mut = @as(*std.StringHashMap(Value), @ptrCast(@constCast(&a.bindings)));
                bindings_mut.deinit();
            },
            .lambda => {
                // Don't deinit the env, body, or param - they're managed elsewhere
            },
            .builtin => {},
            .thunk => |t| {
                t.expr.deinit(allocator);
                allocator.destroy(t.expr);
                t.env.deinit();
                if (t.value) |v| {
                    v.deinit(allocator);
                }
                allocator.destroy(t);
            },
        }
    }
};

pub const Thunk = struct {
    expr: *Expr,
    env: *Env,
    value: ?Value,
    evaluating: bool,
};

pub const Env = struct {
    allocator: std.mem.Allocator,
    bindings: std.StringHashMap(Value),
    parent: ?*Env,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Env) !*Env {
        const env = try allocator.create(Env);
        env.* = Env{
            .allocator = allocator,
            .bindings = std.StringHashMap(Value).init(allocator),
            .parent = parent,
        };
        return env;
    }

    pub fn deinit(self: *Env) void {
        var iter = self.bindings.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.bindings.deinit();
        self.allocator.destroy(self);
    }

    pub fn define(self: *Env, name: []const u8, value: Value) !void {
        try self.bindings.put(name, value);
    }

    pub fn lookup(self: *Env, name: []const u8) ?Value {
        if (self.bindings.get(name)) |val| {
            return val;
        }
        if (self.parent) |parent| {
            return parent.lookup(name);
        }
        return null;
    }
};

pub const Evaluator = struct {
    allocator: std.mem.Allocator,
    global_env: *Env,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const global_env = try Env.init(allocator, null);

        // Register builtins
        try builtins.registerBuiltins(global_env);

        return Self{
            .allocator = allocator,
            .global_env = global_env,
        };
    }

    pub fn deinit(self: *Self) void {
        self.global_env.deinit();
    }

    pub fn eval(self: *Self, expr: Expr) !Value {
        return try self.evalInEnv(expr, self.global_env);
    }

    pub fn evalInEnv(self: *Self, expr: Expr, env: *Env) anyerror!Value {
        switch (expr) {
            .int => |v| return Value{ .int = v },
            .float => |v| return Value{ .float = v },
            .string => |s| return Value{ .string = s },
            .interpolated_string => |is| {
                // Evaluate all parts and concatenate
                var result: std.ArrayList(u8) = .empty;
                defer result.deinit(self.allocator);

                for (is.parts) |part| {
                    switch (part) {
                        .literal => |lit| try result.appendSlice(self.allocator, lit),
                        .expr => |e| {
                            const val = try self.evalInEnv(e.*, env);
                            const forced = try self.force(val);
                            // Coerce to string
                            switch (forced) {
                                .string => |s| try result.appendSlice(self.allocator, s),
                                .int => |i| {
                                    var buf: [32]u8 = undefined;
                                    const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "";
                                    try result.appendSlice(self.allocator, s);
                                },
                                .path => |p| try result.appendSlice(self.allocator, p),
                                else => try result.appendSlice(self.allocator, "<value>"),
                            }
                        },
                    }
                }
                return Value{ .string = try result.toOwnedSlice(self.allocator) };
            },
            .path => |p| return Value{ .path = p },
            .uri => |u| return Value{ .string = u },

            .var_ref => |name| {
                if (env.lookup(name)) |val| {
                    return try self.force(val);
                }
                std.debug.print("Undefined variable: {s}\n", .{name});
                return error.UndefinedVariable;
            },

            .list => |l| {
                var values = try self.allocator.alloc(Value, l.elements.len);
                for (l.elements, 0..) |elem, i| {
                    values[i] = try self.evalInEnv(elem, env);
                }
                return Value{ .list = values };
            },

            .attrs => |a| {
                var attr_env = try Env.init(self.allocator, env);
                defer if (!a.recursive) attr_env.deinit();
                var bindings = std.StringHashMap(Value).init(self.allocator);

                // If recursive, evaluate in extended env
                if (a.recursive) {
                    // First pass: create thunks
                    for (a.bindings) |binding| {
                        if (binding.key.parts.len == 1) {
                            if (binding.key.parts[0] == .ident) {
                                const key = binding.key.parts[0].ident;
                                const thunk = try self.allocator.create(Thunk);
                                thunk.* = Thunk{
                                    .expr = binding.value,
                                    .env = attr_env,
                                    .value = null,
                                    .evaluating = false,
                                };
                                try bindings.put(key, Value{ .thunk = thunk });
                                try attr_env.define(key, Value{ .thunk = thunk });
                            }
                        }
                    }
                } else {
                    // Non-recursive: evaluate immediately
                    for (a.bindings) |binding| {
                        if (binding.key.parts.len == 1) {
                            if (binding.key.parts[0] == .ident) {
                                const key = binding.key.parts[0].ident;
                                const value = try self.evalInEnv(binding.value.*, env);
                                try bindings.put(key, value);
                            }
                        }
                    }
                }

                return Value{ .attrs = .{ .bindings = bindings } };
            },

            .select => |s| {
                const base = try self.evalInEnv(s.base.*, env);
                const forced = try self.force(base);

                if (forced != .attrs) {
                    if (s.default) |def| {
                        return try self.evalInEnv(def.*, env);
                    }
                    return error.NotAnAttrSet;
                }

                // Navigate through attribute path
                var current = forced.attrs;
                for (s.path.parts, 0..) |part, i| {
                    const key = switch (part) {
                        .ident => |id| id,
                        .string => |str| str,
                        else => return error.DynamicAttrPath,
                    };

                    if (current.bindings.get(key)) |val| {
                        if (i == s.path.parts.len - 1) {
                            return try self.force(val);
                        }
                        const forced_val = try self.force(val);
                        if (forced_val != .attrs) {
                            if (s.default) |def| {
                                return try self.evalInEnv(def.*, env);
                            }
                            return error.NotAnAttrSet;
                        }
                        current = forced_val.attrs;
                    } else {
                        if (s.default) |def| {
                            return try self.evalInEnv(def.*, env);
                        }
                        return error.AttributeNotFound;
                    }
                }
                return error.EmptyAttrPath;
            },

            .call => |c| {
                const func = try self.force(try self.evalInEnv(c.func.*, env));
                const arg = try self.evalInEnv(c.arg.*, env);

                switch (func) {
                    .lambda => |lam| {
                        const call_env = try Env.init(self.allocator, lam.env);
                        defer call_env.deinit();

                        switch (lam.param) {
                            .ident => |name| {
                                try call_env.define(name, arg);
                            },
                            .pattern => |p| {
                                const forced_arg = try self.force(arg);
                                if (forced_arg != .attrs) {
                                    return error.PatternMatchFailed;
                                }

                                for (p.formals) |formal| {
                                    if (forced_arg.attrs.bindings.get(formal.name)) |val| {
                                        try call_env.define(formal.name, val);
                                    } else if (formal.default) |def| {
                                        const default_val = try self.evalInEnv(def.*, lam.env);
                                        try call_env.define(formal.name, default_val);
                                    } else {
                                        return error.MissingAttribute;
                                    }
                                }

                                if (p.at_name) |at| {
                                    try call_env.define(at, arg);
                                }
                            },
                        }

                        return try self.evalInEnv(lam.body.*, call_env);
                    },
                    .builtin => |b| {
                        const args = try self.allocator.alloc(Value, 1);
                        args[0] = arg;
                        return try b.func(self.allocator, args);
                    },
                    else => return error.NotAFunction,
                }
            },

            .lambda => |l| {
                return Value{
                    .lambda = .{
                        .param = l.param,
                        .body = l.body,
                        .env = env,
                    },
                };
            },

            .let_in => |l| {
                const let_env = try Env.init(self.allocator, env);
                defer let_env.deinit();

                for (l.bindings) |binding| {
                    if (binding.key.parts.len == 1) {
                        if (binding.key.parts[0] == .ident) {
                            const key = binding.key.parts[0].ident;
                            const value = try self.evalInEnv(binding.value.*, let_env);
                            try let_env.define(key, value);
                        }
                    }
                }

                return try self.evalInEnv(l.body.*, let_env);
            },

            .if_then_else => |i| {
                const cond = try self.force(try self.evalInEnv(i.cond.*, env));
                const cond_bool = try self.toBool(cond);

                if (cond_bool) {
                    return try self.evalInEnv(i.then_expr.*, env);
                } else {
                    return try self.evalInEnv(i.else_expr.*, env);
                }
            },

            .with => |w| {
                const with_set = try self.force(try self.evalInEnv(w.env.*, env));
                if (with_set != .attrs) {
                    return error.WithRequiresAttrSet;
                }

                const with_env = try Env.init(self.allocator, env);
                defer with_env.deinit();
                var iter = with_set.attrs.bindings.iterator();
                while (iter.next()) |entry| {
                    try with_env.define(entry.key_ptr.*, entry.value_ptr.*);
                }

                return try self.evalInEnv(w.body.*, with_env);
            },

            .assert_expr => |a| {
                const cond = try self.force(try self.evalInEnv(a.cond.*, env));
                const cond_bool = try self.toBool(cond);

                if (!cond_bool) {
                    return error.AssertionFailed;
                }

                return try self.evalInEnv(a.body.*, env);
            },

            .binary_op => |b| {
                return try self.evalBinaryOp(b.op, b.left.*, b.right.*, env);
            },

            .unary_op => |u| {
                return try self.evalUnaryOp(u.op, u.operand.*, env);
            },
        }
    }

    fn evalBinaryOp(self: *Self, op: Expr.BinaryOperator, left: Expr, right: Expr, env: *Env) !Value {
        const lval = try self.force(try self.evalInEnv(left, env));
        const rval = try self.force(try self.evalInEnv(right, env));

        switch (op) {
            .add => {
                if (lval == .int and rval == .int) {
                    return Value{ .int = lval.int + rval.int };
                }
                if (lval == .float or rval == .float) {
                    const l = if (lval == .int) @as(f64, @floatFromInt(lval.int)) else lval.float;
                    const r = if (rval == .int) @as(f64, @floatFromInt(rval.int)) else rval.float;
                    return Value{ .float = l + r };
                }
                return error.TypeError;
            },
            .sub => {
                if (lval == .int and rval == .int) {
                    return Value{ .int = lval.int - rval.int };
                }
                if (lval == .float or rval == .float) {
                    const l = if (lval == .int) @as(f64, @floatFromInt(lval.int)) else lval.float;
                    const r = if (rval == .int) @as(f64, @floatFromInt(rval.int)) else rval.float;
                    return Value{ .float = l - r };
                }
                return error.TypeError;
            },
            .mul => {
                if (lval == .int and rval == .int) {
                    return Value{ .int = lval.int * rval.int };
                }
                if (lval == .float or rval == .float) {
                    const l = if (lval == .int) @as(f64, @floatFromInt(lval.int)) else lval.float;
                    const r = if (rval == .int) @as(f64, @floatFromInt(rval.int)) else rval.float;
                    return Value{ .float = l * r };
                }
                return error.TypeError;
            },
            .div => {
                if (lval == .int and rval == .int) {
                    if (rval.int == 0) return error.DivisionByZero;
                    return Value{ .int = @divTrunc(lval.int, rval.int) };
                }
                if (lval == .float or rval == .float) {
                    const l = if (lval == .int) @as(f64, @floatFromInt(lval.int)) else lval.float;
                    const r = if (rval == .int) @as(f64, @floatFromInt(rval.int)) else rval.float;
                    return Value{ .float = l / r };
                }
                return error.TypeError;
            },
            .concat => {
                if (lval == .list and rval == .list) {
                    const new_list = try self.allocator.alloc(Value, lval.list.len + rval.list.len);
                    @memcpy(new_list[0..lval.list.len], lval.list);
                    @memcpy(new_list[lval.list.len..], rval.list);
                    return Value{ .list = new_list };
                }
                return error.TypeError;
            },
            .update => {
                if (lval == .attrs and rval == .attrs) {
                    var new_bindings = std.StringHashMap(Value).init(self.allocator);
                    var iter = lval.attrs.bindings.iterator();
                    while (iter.next()) |entry| {
                        try new_bindings.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                    var iter2 = rval.attrs.bindings.iterator();
                    while (iter2.next()) |entry| {
                        try new_bindings.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                    return Value{ .attrs = .{ .bindings = new_bindings } };
                }
                return error.TypeError;
            },
            .eq => return Value{ .bool = try self.equal(lval, rval) },
            .neq => return Value{ .bool = !(try self.equal(lval, rval)) },
            .lt, .lte, .gt, .gte => {
                if (lval == .int and rval == .int) {
                    return Value{
                        .bool = switch (op) {
                            .lt => lval.int < rval.int,
                            .lte => lval.int <= rval.int,
                            .gt => lval.int > rval.int,
                            .gte => lval.int >= rval.int,
                            else => unreachable,
                        },
                    };
                }
                return error.TypeError;
            },
            .and_op => {
                const l = try self.toBool(lval);
                if (!l) return Value{ .bool = false };
                return Value{ .bool = try self.toBool(rval) };
            },
            .or_op => {
                const l = try self.toBool(lval);
                if (l) return Value{ .bool = true };
                return Value{ .bool = try self.toBool(rval) };
            },
            .implies => {
                const l = try self.toBool(lval);
                if (!l) return Value{ .bool = true };
                return Value{ .bool = try self.toBool(rval) };
            },
            .has_attr => {
                // lval ? attr  - check if attrset has the attribute
                // Note: rval should be a var_ref representing the attribute name
                // In Nix, `set ? attr` has attr as an identifier, not evaluated
                // For now, we check if lval is an attrset and rval is a string key
                if (lval != .attrs) return Value{ .bool = false };
                if (rval == .string) {
                    return Value{ .bool = lval.attrs.bindings.contains(rval.string) };
                }
                // The right side is usually a var_ref that wasn't evaluated
                return Value{ .bool = false };
            },
        }
    }

    fn evalUnaryOp(self: *Self, op: Expr.UnaryOperator, operand: Expr, env: *Env) !Value {
        const val = try self.force(try self.evalInEnv(operand, env));

        switch (op) {
            .not => {
                const b = try self.toBool(val);
                return Value{ .bool = !b };
            },
            .negate => {
                if (val == .int) {
                    return Value{ .int = -val.int };
                }
                if (val == .float) {
                    return Value{ .float = -val.float };
                }
                return error.TypeError;
            },
        }
    }

    pub fn force(self: *Self, value: Value) anyerror!Value {
        if (value == .thunk) {
            const thunk = value.thunk;
            if (thunk.value) |val| {
                return val;
            }
            if (thunk.evaluating) {
                return error.InfiniteRecursion;
            }

            thunk.evaluating = true;
            const result = try self.evalInEnv(thunk.expr.*, thunk.env);
            thunk.value = result;
            thunk.evaluating = false;

            return result;
        }
        return value;
    }

    /// Apply a function value to an argument
    pub fn apply(self: *Self, func: Value, arg: Value) anyerror!Value {
        const forced_func = try self.force(func);

        switch (forced_func) {
            .lambda => |lam| {
                const call_env = try Env.init(self.allocator, lam.env);
                defer call_env.deinit();

                switch (lam.param) {
                    .ident => |name| {
                        try call_env.define(name, arg);
                    },
                    .pattern => |p| {
                        const forced_arg = try self.force(arg);
                        if (forced_arg != .attrs) {
                            return error.PatternMatchFailed;
                        }

                        for (p.formals) |formal| {
                            if (forced_arg.attrs.bindings.get(formal.name)) |val| {
                                try call_env.define(formal.name, val);
                            } else if (formal.default) |def| {
                                const default_val = try self.evalInEnv(def.*, lam.env);
                                try call_env.define(formal.name, default_val);
                            } else if (!p.ellipsis) {
                                return error.MissingAttribute;
                            }
                        }

                        if (p.at_name) |at| {
                            try call_env.define(at, arg);
                        }
                    },
                }

                return try self.evalInEnv(lam.body.*, call_env);
            },
            .builtin => |b| {
                const args = try self.allocator.alloc(Value, 1);
                args[0] = arg;
                return try b.func(self.allocator, args);
            },
            else => return error.NotAFunction,
        }
    }

    fn toBool(self: *Self, value: Value) !bool {
        _ = self;
        return switch (value) {
            .bool => |b| b,
            .null_val => false,
            else => true,
        };
    }

    fn equal(self: *Self, lval: Value, rval: Value) !bool {
        _ = self;
        if (@intFromEnum(lval) != @intFromEnum(rval)) return false;

        return switch (lval) {
            .int => lval.int == rval.int,
            .float => lval.float == rval.float,
            .bool => lval.bool == rval.bool,
            .string => std.mem.eql(u8, lval.string, rval.string),
            .path => std.mem.eql(u8, lval.path, rval.path),
            .null_val => true,
            else => false,
        };
    }
};

test "evaluator basic" {
    const allocator = std.testing.allocator;

    var evaluator = try Evaluator.init(allocator);
    defer evaluator.deinit();

    // Test integer
    {
        const result = try evaluator.eval(Expr{ .int = 42 });
        try std.testing.expectEqual(@as(i64, 42), result.int);
    }

    // Test arithmetic
    {
        const left = try allocator.create(Expr);
        left.* = Expr{ .int = 10 };
        const right = try allocator.create(Expr);
        right.* = Expr{ .int = 5 };

        const expr = Expr{
            .binary_op = .{
                .op = .add,
                .left = left,
                .right = right,
                .span = .{ .start = 0, .end = 0, .line = 1, .column = 1 },
            },
        };
        defer expr.deinit(allocator);

        const result = try evaluator.eval(expr);
        try std.testing.expectEqual(@as(i64, 15), result.int);
    }
}
