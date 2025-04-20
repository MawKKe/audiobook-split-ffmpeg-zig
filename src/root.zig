//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");

const Chapter = struct {
    id: usize,
    time_base: []u8,
    start: usize,
    start_time: []u8,
    end: usize,
    end_time: []u8,
    tags: Tags,
};

const Tags = struct {
    title: []u8,
};

const FFProbeOutput = struct {
    chapters: []Chapter,
};

const InputFileMetaData = struct {
    path: []const u8,
    stem: []const u8,
    ext: []const u8,
    _ffprobeOutput: std.json.Parsed(FFProbeOutput),

    const Self = @This();

    pub fn chapters(self: Self) []Chapter {
        return self._ffprobeOutput.value.chapters;
    }

    pub fn deinit(self: Self) void {
        self._ffprobeOutput.deinit();
    }
};

pub const OutputOpts = struct {
    output_dir: []const u8,
    no_pad_num: bool = false,

    const Self = @This();

    fn padding_width(self: Self, num_chapters: usize) usize {
        if (self.no_pad_num) {
            return 0;
        } else {
            return numDigits(num_chapters);
        }
    }
};

fn numDigits(num: usize) usize {
    if (num == 0) {
        return 1;
    }
    // ay carumba, SNR is quite poor
    const fval = @as(f64, @floatFromInt(num));
    const log = @floor(std.math.log10(fval));
    return @as(usize, @intFromFloat(log + 1));
}

test "numDigits" {
    try std.testing.expectEqual(1, numDigits(0));
    try std.testing.expectEqual(1, numDigits(9));
    try std.testing.expectEqual(2, numDigits(10));
    try std.testing.expectEqual(2, numDigits(99));
    try std.testing.expectEqual(3, numDigits(100));
}

pub fn readInputFileMetaData(alloc: std.mem.Allocator, path: []const u8) !InputFileMetaData {
    return InputFileMetaData{
        .path = path,
        .stem = std.fs.path.stem(path),
        .ext = std.fs.path.extension(path),
        ._ffprobeOutput = try readChapters(alloc, path),
    };
}

test "InputFileMetadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const meta = try readInputFileMetaData(alloc, "src/testdata/beep.m4a");
    try std.testing.expectEqualStrings(meta.ext, ".m4a");
    try std.testing.expectEqualStrings(meta.stem, "beep");
    try std.testing.expectEqual(meta.chapters().len, 3);
}

pub fn extractChapter(
    alloc: std.mem.Allocator,
    chapter_num: usize,
    meta: *const InputFileMetaData,
    opts: *const OutputOpts,
) !u8 {
    const chapters = meta.chapters();

    if (chapter_num >= chapters.len) {
        return error.OutOfBounds;
    }

    const chap = &chapters[chapter_num];

    const name = try formatName(alloc, .{
        .num = chap.id,
        .num_width = numDigits(chapters.len),
        .title = chap.tags.title,
        .ext = meta.ext,
    });

    defer alloc.free(name);

    try std.fs.cwd().makePath(opts.output_dir);

    const out = try std.fs.path.join(
        alloc,
        &[_][]const u8{ opts.output_dir, name },
    );
    defer alloc.free(out);

    const argv = [_][]const u8{
        // zig fmt: off
        "ffmpeg",
        "-nostdin",
        "-i", meta.path,
        "-v", "error",
        "-map_chapters", "-1",
        "-vn",
        "-c", "copy",
        "-ss", chap.start_time,
        "-to", chap.end_time,
        "-n",
        out,
    };

    const proc = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &argv,
    });

    defer alloc.free(proc.stdout);
    defer alloc.free(proc.stderr);

    if (proc.term.Exited != 0) {
        if (proc.stderr[proc.stderr.len - 1] == '\n') {
            proc.stderr[proc.stderr.len - 1] = 0;
        }
        std.debug.print("ERROR (ffprobe): {s}\n", .{proc.stderr});
        return error.FFMpegCallError;
    }

    return proc.term.Exited;
}

fn exists(path: []const u8) std.posix.AccessError!bool {
    std.fs.cwd().access(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false;
        }
        return err;
    };
    return true;
}
test "extractChapter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const meta = try readInputFileMetaData(alloc, "src/testdata/beep.m4a");
    const tmp = std.testing.tmpDir(.{});
    const tmp_dir = try tmp.dir.realpathAlloc(alloc, ".");
    const opts = OutputOpts{ .output_dir = tmp_dir };

    const ret = try extractChapter(alloc, 0, &meta, &opts);

    try std.testing.expectEqual(ret, 0);

    const expect_name = "0 - It All Started With a Simple BEEP.m4a";

    const expect_this_file_to_have_been_created =
        try std.fs.path.join(alloc, &[_][]const u8{tmp_dir, expect_name});

    const fp = try tmp.dir.openFile(expect_this_file_to_have_been_created, .{});

    const stat = try fp.stat();

    try std.testing.expect(stat.size > 500*1024);
}

pub fn readChapters(allocator: std.mem.Allocator, input_file: []const u8) !std.json.Parsed(FFProbeOutput) {
    const ffprobe_cmd = &.{ "ffprobe", "-i", input_file, "-v", "error", "-print_format", "json", "-show_chapters" };
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

const NameFormatDetails = struct {
    num: usize,
    num_width: usize = 0,
    title: []const u8,
    ext: []const u8,
};

fn formatName(allocator: std.mem.Allocator, details: NameFormatDetails) ![]u8 {
    const ext_clean = if (details.ext.len > 0 and details.ext[0] == '.') details.ext[1..] else details.ext;
    const width = if (details.num_width < 1) 1 else details.num_width;
    return try std.fmt.allocPrint(
        allocator,
        "{[number]d:0>[width]} - {[name]s}.{[ext]s}",
        .{
            .number = details.num,
            .width = width,
            .name = details.title,
            .ext = ext_clean,
        },
    );
}

test "formatName with variable chapter number padding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    try std.testing.expectEqualStrings(
        "0 - nimi on .m4a",
        try formatName(
            alloc,
            .{ .num = 0, .title = "nimi on ", .ext = "m4a" },
        ),
    );

    try std.testing.expectEqualStrings(
        "001 - nimi on.m4a",
        try formatName(
            alloc,
            .{ .num = 1, .num_width = 3, .title = "nimi on", .ext = ".m4a" },
        ),
    );

    try std.testing.expectEqualStrings(
        "42 - nimi on.m4a",
        try formatName(
            alloc,
            .{ .num = 42, .title = "nimi on", .ext = ".m4a" },
        ),
    );
}

test "parse chapters from example audio file containing 3 chapters" {
    const res = try readChapters(std.testing.allocator, "src/testdata/beep.m4a");
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

    const res = try readChapters(alloc, "src/testdata/beep.m4a");

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
    const res = try readChapters(std.testing.allocator, "src/testdata/beep-nochap.m4a");
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
