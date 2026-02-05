const std = @import("std");

/// Read entire file into allocated memory using std.Io
pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    // Use allocator to read file
    // For now, simplified - would need proper Io integration
    _ = path;
    _ = allocator;
    return error.NotImplemented;
}

/// Read all from stdin using std.Io
pub fn readStdinAlloc(io: std.Io) ![]u8 {
    const stdin_file = std.Io.File.stdin();

    // Read from stdin using io
    var buf: [4096]u8 = undefined;
    const reader = stdin_file.reader(io, &buf);

    // For now return stub
    _ = reader;
    return error.NotImplemented;
}

/// Write formatted output to writer
pub fn writeFmt(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try writer.print(fmt, args);
}
