//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("audiobook_split_ffmpeg_zig_lib");

pub fn main() anyerror!void {
    if (std.os.argv.len < 2) {
        std.debug.print("usage: {s} <path-to-file>\n", .{std.os.argv[0]});
        std.process.exit(1);
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input_file = std.mem.sliceTo(std.os.argv[1], 0);

    const parsed = try lib.readChapters(allocator, input_file);
    defer parsed.deinit();

    for (parsed.value.chapters) |ch| {
        std.debug.print("Ch id={}: ({} -> {}) '{s}'\n", .{ ch.id, ch.start, ch.end, ch.tags.title });
    }
}
