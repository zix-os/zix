const std = @import("std");
const zig = @import("zig");
const compile = @import("compile.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const compilation = try compile.createCompilation(
        allocator,
        arena_allocator,
        "/home/theo/dev/zig-bootstrap/out/zig-x86_64-linux-musl-baseline/lib/zig",
        "/home/theo/.cache/zig",
    );
    defer compilation.destroy();
}
