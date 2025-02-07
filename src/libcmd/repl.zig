const std = @import("std");

var has_prompt = true;

pub fn readline(prompt: [*:0]const u8) callconv(.C) ?[*:0]const u8 {
    const stdout = std.io.getStdOut();
    if (!has_prompt) {
        stdout.writeAll(prompt[0..std.mem.len(prompt)]) catch @panic("Failed to write prompt");
        has_prompt = true;
    }

    const stdin = std.io.getStdIn();

    var line = std.ArrayList(u8).init(std.heap.c_allocator);
    defer line.deinit();

    stdin.reader().readUntilDelimiterArrayList(&line, '\n', std.math.maxInt(usize)) catch |err| switch (err) {
        error.StreamTooLong => {
            std.log.err("readline(\"{s}\") failed {}", .{ prompt[0..std.mem.len(prompt)], err });
            return null;
        },
        else => return null,
    };

    has_prompt = line.items.len > 0;
    return line.toOwnedSliceSentinel(0) catch null;
}

comptime {
    @export(&readline, .{ .name = "readline" });
}
