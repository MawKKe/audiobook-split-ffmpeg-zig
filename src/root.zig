//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");

const Chapter = struct {
    id: i32,
    time_base: []u8,
    start: i32,
    start_time: []u8,
    end: i32,
    end_time: []u8,
    tags: Tags,
};

const Tags = struct {
    title: []u8,
};

const FFProbeOutput = struct {
    chapters: []Chapter,

    fn _release(self: FFProbeOutput, allocator: std.mem.Allocator) void {
        for (self.chapters) |ch| {
            allocator.free(ch.time_base);
            allocator.free(ch.start_time);
            allocator.free(ch.end_time);
            allocator.free(ch.tags.title);
        }
        allocator.free(self.chapters);
    }
};

pub fn readChapters(input_file: [*:0]const u8, allocator: std.mem.Allocator) !std.json.Parsed(FFProbeOutput) {
    const ffprobe_cmd = &.{ "ffprobe", "-i", std.mem.sliceTo(input_file, 0), "-v", "error", "-print_format", "json", "-show_chapters" };
    const proc = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = ffprobe_cmd,
    });
    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited != 0) {
        if (proc.stderr[proc.stderr.len - 1] == '\n') {
            proc.stderr[proc.stderr.len - 1] = 0;
        }
        std.debug.print("ERROR (ffprobe): {s}\n", .{proc.stderr});
        return error.FFProbeCallError;
    }

    return try std.json.parseFromSlice(FFProbeOutput, allocator, proc.stdout, .{});
}

test "parse chapters from example audio file" {
    const res = try readChapters("src/testdata/beep.m4a", std.testing.allocator);
    defer res.deinit();
    try std.testing.expect(res.value.chapters.len == 3);
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
