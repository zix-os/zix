const std = @import("std");
const builtin = @import("builtin");

pub fn cpuid() callconv(.C) ?[*:null]const ?[*:0]const u8 {
    const target = std.zig.system.resolveTargetQuery(.{}) catch return null;
    const cpuModels = @field(std.Target, switch (builtin.cpu.arch) {
        .x86_64 => "x86",
        else => @tagName(builtin.cpu.arch),
    }).cpu;
    inline for (comptime std.meta.declarations(cpuModels)) |decl| {
        const value = @field(cpuModels, decl.name);
        if (target.cpu.model == &value) return &.{decl.name};
    }
    return null;
}

comptime {
    @export(&cpuid, .{ .name = "nix_libutil_cpuid", .linkage = .strong });
}
