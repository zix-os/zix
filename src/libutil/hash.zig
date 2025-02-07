const std = @import("std");

pub const HashAlgorithm = enum(c_char) {
    md5 = 42,
    sha1,
    sha256,
    sha512,
    blake3,
};

pub const Ctx = union(HashAlgorithm) {
    md5: std.crypto.hash.Md5,
    sha1: std.crypto.hash.Sha1,
    sha256: std.crypto.hash.sha2.Sha256,
    sha512: std.crypto.hash.sha2.Sha512,
    blake3: std.crypto.hash.Blake3,

    pub const Extern = opaque {};

    pub inline fn toExtern(self: *Ctx) *Extern {
        return @ptrCast(@alignCast(self));
    }

    pub inline fn fromExtern(e: *Extern) *Ctx {
        return @ptrCast(@alignCast(e));
    }
};

pub fn create(t: HashAlgorithm) callconv(.C) *Ctx.Extern {
    const self = std.heap.c_allocator.create(Ctx) catch @panic("OOM");
    inline for (comptime std.meta.fields(Ctx)) |field| {
        const v = comptime std.meta.stringToEnum(HashAlgorithm, field.name) orelse unreachable;
        if (v == t) {
            self.* = @unionInit(Ctx, field.name, field.type.init(.{}));
            return self.toExtern();
        }
    }
    unreachable;
}

pub fn update(e: *Ctx.Extern, raw_data: [*]const u8, size: usize) callconv(.C) void {
    const self = Ctx.fromExtern(e);

    const data = raw_data[0..size];

    inline for (comptime std.meta.fields(Ctx)) |field| {
        const v = comptime std.meta.stringToEnum(HashAlgorithm, field.name) orelse unreachable;
        if (self.* == v) {
            @field(self, field.name).update(data);
            return;
        }
    }

    unreachable;
}

pub fn finish(e: *Ctx.Extern, raw_hash: [*:0]u8) callconv(.C) void {
    const self = Ctx.fromExtern(e);

    inline for (comptime std.meta.fields(Ctx)) |field| {
        const v = comptime std.meta.stringToEnum(HashAlgorithm, field.name) orelse unreachable;
        const size = field.type.digest_length;
        if (self.* == v) {
            std.debug.assert(size <= 64);
            const hash = raw_hash[0..size];
            @field(self, field.name).final(hash[0..size]);
            @memset(raw_hash[size..64], 0);
            return;
        }
    }

    unreachable;
}

comptime {
    @export(&create, .{ .name = "nix_libutil_hash_create" });
    @export(&update, .{ .name = "nix_libutil_hash_update" });
    @export(&finish, .{ .name = "nix_libutil_hash_finish" });
}
