const std = @import("std");
const builtin = @import("builtin");

/// A Nix store path like /nix/store/<hash>-<name>
pub const StorePath = struct {
    hash: [32]u8,
    name: []const u8,
    allocator: std.mem.Allocator,

    const STORE_DIR = "/nix/store";
    const HASH_LEN = 32;

    pub fn init(allocator: std.mem.Allocator, hash: [32]u8, name: []const u8) !StorePath {
        return StorePath{
            .hash = hash,
            .name = try allocator.dupe(u8, name),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StorePath) void {
        self.allocator.free(self.name);
    }

    pub fn toPath(self: StorePath, allocator: std.mem.Allocator) ![]u8 {
        // Base32 encode the hash (Nix uses a custom base32)
        var hash_str: [52]u8 = undefined;
        encodeBase32(&self.hash, &hash_str);
        return std.fmt.allocPrint(allocator, "{s}/{s}-{s}", .{ STORE_DIR, hash_str, self.name });
    }

    /// Nix's custom base32 encoding
    fn encodeBase32(input: *const [32]u8, output: *[52]u8) void {
        const alphabet = "0123456789abcdfghijklmnpqrsvwxyz";
        var bits: u64 = 0;
        var bit_count: u6 = 0;
        var out_idx: usize = 51;

        for (input) |byte| {
            bits |= @as(u64, byte) << bit_count;
            bit_count += 8;

            while (bit_count >= 5) {
                output[out_idx] = alphabet[@as(usize, @truncate(bits & 0x1f))];
                if (out_idx > 0) out_idx -= 1;
                bits >>= 5;
                bit_count -= 5;
            }
        }

        if (bit_count > 0) {
            output[out_idx] = alphabet[@as(usize, @truncate(bits & 0x1f))];
        }
    }
};

/// A derivation - a build recipe
pub const Derivation = struct {
    name: []const u8,
    system: []const u8,
    builder: []const u8,
    args: []const []const u8,
    env: std.StringHashMap([]const u8),
    input_drvs: std.StringHashMap([]const []const u8),
    input_srcs: std.ArrayList([]const u8),
    outputs: std.StringHashMap(DerivationOutput),
    allocator: std.mem.Allocator,

    pub const DerivationOutput = struct {
        path: ?[]const u8,
        hash_algo: ?[]const u8,
        hash: ?[]const u8,
    };

    pub fn init(allocator: std.mem.Allocator) Derivation {
        return Derivation{
            .name = "",
            .system = "",
            .builder = "",
            .args = &.{},
            .env = std.StringHashMap([]const u8).init(allocator),
            .input_drvs = std.StringHashMap([]const []const u8).init(allocator),
            .input_srcs = .empty,
            .outputs = std.StringHashMap(DerivationOutput).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Derivation) void {
        self.env.deinit();
        self.input_drvs.deinit();
        self.input_srcs.deinit(self.allocator);
        self.outputs.deinit();
    }

    /// Serialize to ATerm format (.drv file)
    pub fn serialize(self: *const Derivation, allocator: std.mem.Allocator) ![]u8 {
        var result: std.ArrayList(u8) = .empty;

        try result.appendSlice(allocator, "Derive([");

        // Outputs
        var first = true;
        var out_iter = self.outputs.iterator();
        while (out_iter.next()) |entry| {
            if (!first) try result.appendSlice(allocator, ",");
            first = false;
            var buf: [256]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "(\"{s}\",\"{s}\",\"\",\"\")", .{
                entry.key_ptr.*,
                entry.value_ptr.path orelse "",
            });
            try result.appendSlice(allocator, s);
        }

        try result.appendSlice(allocator, "],[");

        // Input derivations
        first = true;
        var drv_iter = self.input_drvs.iterator();
        while (drv_iter.next()) |entry| {
            if (!first) try result.appendSlice(allocator, ",");
            first = false;
            var buf: [256]u8 = undefined;
            const prefix = try std.fmt.bufPrint(&buf, "(\"{s}\",[", .{entry.key_ptr.*});
            try result.appendSlice(allocator, prefix);
            for (entry.value_ptr.*, 0..) |out, i| {
                if (i > 0) try result.appendSlice(allocator, ",");
                const out_buf = try std.fmt.bufPrint(&buf, "\"{s}\"", .{out});
                try result.appendSlice(allocator, out_buf);
            }
            try result.appendSlice(allocator, "])");
        }

        try result.appendSlice(allocator, "],[");

        // Input sources
        for (self.input_srcs.items, 0..) |src, i| {
            if (i > 0) try result.appendSlice(allocator, ",");
            var buf: [256]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "\"{s}\"", .{src});
            try result.appendSlice(allocator, s);
        }

        {
            var buf: [512]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "],\"{s}\",\"{s}\",[", .{ self.system, self.builder });
            try result.appendSlice(allocator, s);
        }

        // Args
        for (self.args, 0..) |arg, i| {
            if (i > 0) try result.appendSlice(allocator, ",");
            var buf: [256]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "\"{s}\"", .{arg});
            try result.appendSlice(allocator, s);
        }

        try result.appendSlice(allocator, "],[");

        // Environment
        first = true;
        var env_iter = self.env.iterator();
        while (env_iter.next()) |entry| {
            if (!first) try result.appendSlice(allocator, ",");
            first = false;
            var buf: [512]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "(\"{s}\",\"{s}\")", .{ entry.key_ptr.*, entry.value_ptr.* });
            try result.appendSlice(allocator, s);
        }

        try result.appendSlice(allocator, "])");

        return result.toOwnedSlice(allocator);
    }

    /// Compute the store path for this derivation
    pub fn computeStorePath(self: *const Derivation, allocator: std.mem.Allocator) !StorePath {
        const drv_str = try self.serialize(allocator);
        defer allocator.free(drv_str);

        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(drv_str, &hash, .{});

        return StorePath.init(allocator, hash, self.name);
    }
};

/// The Nix store interface
pub const Store = struct {
    allocator: std.mem.Allocator,
    store_dir: []const u8,
    db_path: []const u8,

    pub fn init(allocator: std.mem.Allocator) Store {
        return Store{
            .allocator = allocator,
            .store_dir = "/nix/store",
            .db_path = "/nix/var/nix/db/db.sqlite",
        };
    }

    pub fn deinit(self: *Store) void {
        _ = self;
    }

    /// Check if a store path exists
    /// NOTE: Stubbed - requires IO handle
    pub fn isValidPath(self: *Store, path: []const u8) bool {
        _ = self;
        _ = path;
        // TODO: Implement with proper IO
        return false;
    }

    /// Add a path to the store (copy and register)
    /// NOTE: Stubbed - requires IO handle
    pub fn addToStore(self: *Store, name: []const u8, src_path: []const u8) !StorePath {
        _ = src_path;

        // TODO: Implement with proper IO
        // For now, return a dummy store path
        var hash: [32]u8 = undefined;
        @memset(&hash, 0);
        return StorePath.init(self.allocator, hash, name);
    }

    /// Build a derivation
    /// NOTE: Stubbed - requires proper process execution
    pub fn buildDerivation(self: *Store, drv: *const Derivation) ![]const u8 {
        // Compute output path
        const store_path = try drv.computeStorePath(self.allocator);
        defer @constCast(&store_path).deinit();

        const out_path = try store_path.toPath(self.allocator);

        // Check if already built
        if (self.isValidPath(out_path)) {
            return out_path;
        }

        // TODO: Implement proper build with process execution
        std.debug.print("Building {s}... (not implemented)\n", .{drv.name});

        return out_path;
    }

    /// Query the outputs of a built derivation
    pub fn queryDerivationOutputs(self: *Store, drv_path: []const u8) ![]const []const u8 {
        _ = self;
        _ = drv_path;
        // Would query the database for output paths
        return &.{};
    }
};

/// Get the current system string (e.g., "x86_64-linux")
pub fn getCurrentSystem() []const u8 {
    const arch = switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        .x86 => "i686",
        .arm => "armv7l",
        .riscv64 => "riscv64",
        else => "unknown",
    };

    const os = switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "darwin",
        .freebsd => "freebsd",
        .windows => "windows",
        else => "unknown",
    };

    return arch ++ "-" ++ os;
}

test "store path encoding" {
    const allocator = std.testing.allocator;
    var hash: [32]u8 = undefined;
    @memset(&hash, 0xab);

    var sp = try StorePath.init(allocator, hash, "test");
    defer sp.deinit();

    const path = try sp.toPath(allocator);
    defer allocator.free(path);

    try std.testing.expect(std.mem.startsWith(u8, path, "/nix/store/"));
    try std.testing.expect(std.mem.endsWith(u8, path, "-test"));
}

test "derivation serialization" {
    const allocator = std.testing.allocator;
    var drv = Derivation.init(allocator);
    defer drv.deinit();

    drv.name = "hello";
    drv.system = "x86_64-linux";
    drv.builder = "/bin/sh";

    try drv.outputs.put("out", .{ .path = "/nix/store/xxx-hello", .hash_algo = null, .hash = null });

    const serialized = try drv.serialize(allocator);
    defer allocator.free(serialized);

    try std.testing.expect(std.mem.indexOf(u8, serialized, "Derive") != null);
}
