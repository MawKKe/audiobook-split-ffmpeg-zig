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

test "parse chapters from example audio file containing 3 chapters" {
    const res = try readChapters("src/testdata/beep.m4a", std.testing.allocator);
    defer res.deinit();

    try std.testing.expectEqual(res.value.chapters.len, 3);

    const first = res.value.chapters[0];
    try std.testing.expectEqual(first.id, 0);
    try std.testing.expectEqualStrings(first.time_base, "1/1000");
    try std.testing.expectEqual(first.start, 0);
    try std.testing.expectEqualStrings(first.start_time, "0.000000");
    try std.testing.expectEqual(first.end, 20000);
    try std.testing.expectEqualStrings(first.end_time, "20.000000");
    try std.testing.expectEqualStrings(first.tags.title, "It All Started With a Simple BEEP");

    const second = res.value.chapters[1];
    try std.testing.expectEqual(second.id, 1);
    try std.testing.expectEqualStrings(second.time_base, "1/1000");
    try std.testing.expectEqual(second.start, 20000);
    try std.testing.expectEqualStrings(second.start_time, "20.000000");
    try std.testing.expectEqual(second.end, 40000);
    try std.testing.expectEqualStrings(second.end_time, "40.000000");
    try std.testing.expectEqualStrings(second.tags.title, "All You Can BEEP Buffee");

    const third = res.value.chapters[2];
    try std.testing.expectEqual(third.id, 2);
    try std.testing.expectEqualStrings(third.time_base, "1/1000");
    try std.testing.expectEqual(third.start, 40000);
    try std.testing.expectEqualStrings(third.start_time, "40.000000");
    try std.testing.expectEqual(third.end, 60000);
    try std.testing.expectEqualStrings(third.end_time, "60.000000");
    try std.testing.expectEqualStrings(third.tags.title, "The Final Beep");
}

test "parse chapters from example audio file containing no chapters" {
    const res = try readChapters("src/testdata/beep-nochap.m4a", std.testing.allocator);
    defer res.deinit();
    try std.testing.expectEqual(res.value.chapters.len, 0);
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
