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

    // NOTE: Problem with this field-by-field comparison is that if we add a field to the
    // definition of the struct (here: Chapter), it is very likely we forget to augment our
    // tests for that specific field => testing becomes leaky.
}

test "parse chapters from example audio file containing 3 chapters - alt solution" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const res = try readChapters("src/testdata/beep.m4a", alloc);

    try std.testing.expectEqual(res.value.chapters.len, 3);

    // NOTE: Doing testing using deep equality comparison with the whole struct + using inline
    // struct initialization, the compiler is able to tell us if any of the field initializers are
    // missing => test quality is enforced whenever struct definition is augmented.
    //
    // Although this inline initialization requires some extra hoops with dynamic fields like
    // the []u8 string fields of Chapter and Tags. I guess we could've used @constCast to coerce
    // the string literals to []u8, but that would feel...dirty.
    //
    // Fortunately we have ArenaAllocator etc., which makes memory management really simple :)
    const expect = [3]Chapter{
        .{
            .id = 0,
            .time_base = try alloc.dupe(u8, "1/1000"),
            .start = 0,
            .start_time = try alloc.dupe(u8, "0.000000"),
            .end = 20000,
            .end_time = try alloc.dupe(u8, "20.000000"),
            .tags = Tags{
                .title = try alloc.dupe(u8, "It All Started With a Simple BEEP"),
            },
        },
        .{
            .id = 1,
            .time_base = try alloc.dupe(u8, "1/1000"),
            .start = 20000,
            .start_time = try alloc.dupe(u8, "20.000000"),
            .end = 40000,
            .end_time = try alloc.dupe(u8, "40.000000"),
            .tags = Tags{
                .title = try alloc.dupe(u8, "All You Can BEEP Buffee"),
            },
        },
        .{
            .id = 2,
            .time_base = try alloc.dupe(u8, "1/1000"),
            .start = 40000,
            .start_time = try alloc.dupe(u8, "40.000000"),
            .end = 60000,
            .end_time = try alloc.dupe(u8, "60.000000"),
            .tags = Tags{
                .title = try alloc.dupe(u8, "The Final Beep"),
            },
        },
    };

    // NOTE: attempting to compare directly like this:
    //   try std.testing.expectEqualDeep(res.value.chapters, expect);
    //   => error: incompatible types: '[]root.Chapter' and '[3]root.Chapter'

    try std.testing.expectEqualDeep(res.value.chapters, expect[0..]);
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
