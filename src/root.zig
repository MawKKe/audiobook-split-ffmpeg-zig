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
    tags: ?Tags = null,

    const Self = @This();

    pub fn meta_title(self: Self) ?[]u8 {
        if (self.tags == null or
            self.tags.?.title == null or
            self.tags.?.title.?.len == 0)
        {
            return null;
        }
        return self.tags.?.title;
    }
};

const Tags = struct {
    title: ?[]u8 = null,
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
    no_use_title: bool = false,
    no_use_title_in_meta: bool = false,
};

/// Compute how many digits are needed to represent number in base 10
fn numDigitsBase10(num: usize) usize {
    if (num == 0) {
        return 1;
    }
    // ay carumba, SNR is quite poor
    const fval = @as(f64, @floatFromInt(num));
    const log = @floor(std.math.log10(fval));
    return @as(usize, @intFromFloat(log + 1));
}

test "numDigitsBase10" {
    try std.testing.expectEqual(1, numDigitsBase10(0));
    try std.testing.expectEqual(1, numDigitsBase10(9));
    try std.testing.expectEqual(2, numDigitsBase10(10));
    try std.testing.expectEqual(2, numDigitsBase10(99));
    try std.testing.expectEqual(3, numDigitsBase10(100));
}

pub fn readInputFileMetaData(
    alloc: std.mem.Allocator,
    path: []const u8,
) !InputFileMetaData {
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

    const meta = try readInputFileMetaData(
        alloc,
        "src/testdata/beep.m4a",
    );

    try std.testing.expectEqualStrings(".m4a", meta.ext);
    try std.testing.expectEqualStrings("beep", meta.stem);
    try std.testing.expectEqual(3, meta.chapters().len);
}

pub fn extractChapter(
    alloc: std.mem.Allocator,
    chapter: *const Chapter,
    meta: *const InputFileMetaData,
    opts: *const OutputOpts,
) !u8 {
    const stem = if (!opts.no_use_title)
        chapter.meta_title() orelse meta.stem
    else
        meta.stem;

    const name = try formatName(alloc, .{
        .num = chapter.id,
        .num_width = numDigitsBase10(meta.chapters().len),
        .stem = stem,
        .ext = meta.ext,
    });

    defer alloc.free(name);

    try std.fs.cwd().makePath(opts.output_dir);

    const out = try std.fs.path.join(
        alloc,
        &[_][]const u8{ opts.output_dir, name },
    );
    defer alloc.free(out);

    const meta_title = if (opts.no_use_title_in_meta)
        ""
    else
        chapter.meta_title() orelse "";

    const meta_title_arg = try std.fmt.allocPrint(
        alloc,
        "title={s}",
        .{
            meta_title,
        },
    );
    defer alloc.free(meta_title_arg);

    // zig fmt: off
    const argv = [_][]const u8{
        // BUG?
        // If I place pragmas 'zig fmt: off' on this line and 'zig fmt: on' after the last element
        // => formatting remains disabled. The pragmas need to be placed around the whole statement
        // for it to work as expected.
        "ffmpeg",
        "-nostdin",
        "-i", meta.path,
        "-v", "error",
        "-map_chapters", "-1",
        "-vn",
        "-c", "copy",
        "-ss", chapter.start_time,
        "-to", chapter.end_time,
        "-metadata", meta_title_arg,
        "-y",
        out,
    };
    // zig fmt: on

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

test "extractChapter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const meta = try readInputFileMetaData(
        alloc,
        "src/testdata/beep.m4a",
    );

    const cases: [2]struct { no_use_title: bool, expect_name: []const u8 } = .{
        .{
            .no_use_title = false,
            .expect_name = "0 - It All Started With a Simple BEEP.m4a",
        },
        .{
            .no_use_title = true,
            .expect_name = "0 - beep.m4a",
        },
    };

    for (cases) |case| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();

        // Resolves the absolute path to the tmp directory. Why couldn't tmpDir do this already?
        const tmp_dir = try tmp.dir.realpathAlloc(alloc, ".");

        const opts = OutputOpts{
            .output_dir = tmp_dir,
            .no_use_title = case.no_use_title,
        };

        const ret = try extractChapter(
            alloc,
            &meta.chapters()[0],
            &meta,
            &opts,
        );

        try std.testing.expectEqual(0, ret);

        const expect_name = case.expect_name;

        const expect_this_file_to_have_been_created =
            try std.fs.path.join(
                alloc,
                &[_][]const u8{ tmp_dir, expect_name },
            );

        const fp = try tmp.dir.openFile(
            expect_this_file_to_have_been_created,
            .{},
        );

        defer fp.close();

        const stat = try fp.stat();

        try std.testing.expect(stat.size > 500 * 1024);
    }
}

fn parseFFProbeOutput(
    allocator: std.mem.Allocator,
    json_content: []const u8,
) !std.json.Parsed(FFProbeOutput) {
    return try std.json.parseFromSlice(
        FFProbeOutput,
        allocator,
        json_content,
        .{},
    );
}

test "parseFFProbeOutput" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    {
        // test case: 1 chapter, with title meta
        const input_json =
            \\ {
            \\    "chapters": [
            \\        {
            \\            "id": 999,
            \\            "time_base": "1/1000",
            \\            "start": 123,
            \\            "start_time": "0.123000",
            \\            "end": 19876,
            \\            "end_time": "19.876000",
            \\            "tags": {
            \\                "title": "Title goes here"
            \\            }
            \\        }
            \\    ]
            \\ }
            \\
        ;

        const res = try parseFFProbeOutput(
            alloc,
            input_json,
        );

        const expect = [1]Chapter{
            .{
                .id = 999,
                .time_base = try alloc.dupe(u8, "1/1000"),
                .start = 123,
                .start_time = try alloc.dupe(u8, "0.123000"),
                .end = 19876,
                .end_time = try alloc.dupe(u8, "19.876000"),
                .tags = Tags{
                    .title = try alloc.dupe(u8, "Title goes here"),
                },
            },
        };
        try std.testing.expectEqualDeep(
            expect[0..],
            res.value.chapters,
        );
    }

    {
        // test case: 1 chapter, without title meta, and even without the "tags" field
        const input_json =
            \\ {
            \\    "chapters": [
            \\        {
            \\            "id": 999,
            \\            "time_base": "1/1000",
            \\            "start": 123,
            \\            "start_time": "0.123000",
            \\            "end": 19876,
            \\            "end_time": "19.876000"
            \\        }
            \\     ]
            \\ }
        ;
        const res = try parseFFProbeOutput(
            alloc,
            input_json,
        );

        const expect = [1]Chapter{
            .{
                .id = 999,
                .time_base = try alloc.dupe(u8, "1/1000"),
                .start = 123,
                .start_time = try alloc.dupe(u8, "0.123000"),
                .end = 19876,
                .end_time = try alloc.dupe(u8, "19.876000"),
                .tags = null,
            },
        };
        try std.testing.expectEqualDeep(
            expect[0..],
            res.value.chapters,
        );
    }
    {
        const three_chapters_with_titles =
            \\ {
            \\    "chapters": [
            \\        {
            \\            "id": 0,
            \\            "time_base": "1/1000",
            \\            "start": 0,
            \\            "start_time": "0.000000",
            \\            "end": 20000,
            \\            "end_time": "20.000000",
            \\            "tags": {
            \\                "title": "It All Started With a Simple BEEP"
            \\            }
            \\        },
            \\        {
            \\            "id": 1,
            \\            "time_base": "1/1000",
            \\            "start": 20000,
            \\            "start_time": "20.000000",
            \\            "end": 40000,
            \\            "end_time": "40.000000",
            \\            "tags": {
            \\                "title": "All You Can BEEP Buffee"
            \\            }
            \\        },
            \\        {
            \\            "id": 2,
            \\            "time_base": "1/1000",
            \\            "start": 40000,
            \\            "start_time": "40.000000",
            \\            "end": 60000,
            \\            "end_time": "60.000000",
            \\            "tags": {
            \\                "title": "The Final Beep"
            \\            }
            \\        }
            \\    ]
            \\ }
            \\
        ;

        const res = try parseFFProbeOutput(
            alloc,
            three_chapters_with_titles,
        );

        try std.testing.expectEqual(
            3,
            res.value.chapters.len,
        );

        const expect = [3]Chapter{
            .{
                .id = 0,
                .time_base = try alloc.dupe(u8, "1/1000"),
                .start = 0,
                .start_time = try alloc.dupe(u8, "0.000000"),
                .end = 20000,
                .end_time = try alloc.dupe(u8, "20.000000"),
                .tags = Tags{
                    .title = try alloc.dupe(
                        u8,
                        "It All Started With a Simple BEEP",
                    ),
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
                    .title = try alloc.dupe(
                        u8,
                        "All You Can BEEP Buffee",
                    ),
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
                    .title = try alloc.dupe(
                        u8,
                        "The Final Beep",
                    ),
                },
            },
        };

        try std.testing.expectEqualDeep(
            expect[0..],
            res.value.chapters,
        );
    }
}

fn ffProbe(
    allocator: std.mem.Allocator,
    input_file: []const u8,
) ![]u8 {
    // zig fmt: off
    const ffprobe_cmd = &.{
        "ffprobe",
        "-i", input_file,
        "-v", "error",
        "-print_format", "json",
        "-show_chapters",
    };
    // zig fmt: on

    const proc = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = ffprobe_cmd,
    });

    defer allocator.free(proc.stderr);

    if (proc.term.Exited != 0) {
        if (proc.stderr[proc.stderr.len - 1] == '\n') {
            proc.stderr[proc.stderr.len - 1] = 0;
        }
        std.debug.print("ERROR (ffprobe): {s}\n", .{proc.stderr});
        return error.FFProbeCallError;
    }

    return proc.stdout;
}

pub fn readChapters(
    allocator: std.mem.Allocator,
    input_file: []const u8,
) !std.json.Parsed(FFProbeOutput) {
    const json_data = try ffProbe(allocator, input_file);
    defer allocator.free(json_data);
    return try parseFFProbeOutput(allocator, json_data);
}

fn formatName(
    allocator: std.mem.Allocator,
    details: struct {
        num: usize,
        num_width: usize = 0,
        stem: []const u8,
        ext: []const u8,
    },
) ![]u8 {
    const ext_clean = if (details.ext.len > 0 and details.ext[0] == '.')
        details.ext[1..]
    else
        details.ext;

    const width = if (details.num_width < 1) 1 else details.num_width;

    return try std.fmt.allocPrint(
        allocator,
        "{[number]d:0>[width]} - {[name]s}.{[ext]s}",
        .{
            .number = details.num,
            .width = width,
            .name = details.stem,
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
            .{
                .num = 0,
                .stem = "nimi on ",
                .ext = "m4a",
            },
        ),
    );

    try std.testing.expectEqualStrings(
        "001 - nimi on.m4a",
        try formatName(
            alloc,
            .{
                .num = 1,
                .num_width = 3,
                .stem = "nimi on",
                .ext = ".m4a",
            },
        ),
    );

    try std.testing.expectEqualStrings(
        "42 - nimi on.m4a",
        try formatName(
            alloc,
            .{
                .num = 42,
                .stem = "nimi on",
                .ext = ".m4a",
            },
        ),
    );
}

test "parse chapters from example audio file containing 3 chapters" {
    const res = try readChapters(
        std.testing.allocator,
        "src/testdata/beep.m4a",
    );
    defer res.deinit();

    try std.testing.expectEqual(3, res.value.chapters.len);

    const first = res.value.chapters[0];
    try std.testing.expectEqual(0, first.id);
    try std.testing.expectEqualStrings("1/1000", first.time_base);
    try std.testing.expectEqual(0, first.start);
    try std.testing.expectEqualStrings("0.000000", first.start_time);
    try std.testing.expectEqual(20000, first.end);
    try std.testing.expectEqualStrings("20.000000", first.end_time);
    try std.testing.expectEqualStrings("It All Started With a Simple BEEP", first.tags.?.title.?);

    const second = res.value.chapters[1];
    try std.testing.expectEqual(1, second.id);
    try std.testing.expectEqualStrings("1/1000", second.time_base);
    try std.testing.expectEqual(20000, second.start);
    try std.testing.expectEqualStrings("20.000000", second.start_time);
    try std.testing.expectEqual(40000, second.end);
    try std.testing.expectEqualStrings("40.000000", second.end_time);
    try std.testing.expectEqualStrings("All You Can BEEP Buffee", second.tags.?.title.?);

    const third = res.value.chapters[2];
    try std.testing.expectEqual(2, third.id);
    try std.testing.expectEqualStrings("1/1000", third.time_base);
    try std.testing.expectEqual(40000, third.start);
    try std.testing.expectEqualStrings("40.000000", third.start_time);
    try std.testing.expectEqual(60000, third.end);
    try std.testing.expectEqualStrings("60.000000", third.end_time);
    try std.testing.expectEqualStrings("The Final Beep", third.tags.?.title.?);

    // NOTE: Problem with this field-by-field comparison is that if we add a field to the
    // definition of the struct (here: Chapter), it is very likely we forget to augment our
    // tests for that specific field => testing becomes leaky.
}

test "parse chapters from example audio file containing 3 chapters - alt solution" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const res = try readChapters(
        alloc,
        "src/testdata/beep.m4a",
    );

    try std.testing.expectEqual(3, res.value.chapters.len);

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
    //   try std.testing.expectEqualDeep(expect, res.value.chapters);
    //   => error: incompatible types: '[3]root.Chapter' and '[]root.Chapter'

    try std.testing.expectEqualDeep(expect[0..], res.value.chapters);
}

test "parse chapters from example audio file containing no chapters" {
    const res = try readChapters(
        std.testing.allocator,
        "src/testdata/beep-nochap.m4a",
    );
    defer res.deinit();
    try std.testing.expectEqual(0, res.value.chapters.len);
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
