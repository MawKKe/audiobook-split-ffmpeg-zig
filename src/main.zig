//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("audiobook_split_ffmpeg_zig_lib");

const Args = struct {
    infile: []const u8,
    outdir: []const u8,
    no_use_title: bool = true,
    no_use_title_in_meta: bool = false,
};

fn printHelp(program_name: []const u8, log: anytype) !void {
    try log.print(
        \\Usage:
        \\  {0s} --input-file <path> --output-dir <path>
        \\
        \\Splits audio file into per-chapter files using ffmpeg and chapter metadata
        \\
        \\Options:
        \\  -i, --input-file  Path to input file (required)
        \\  -o, --output-dir  Path to output directory (required)
        \\  -h, --help        Show this help message
        \\  --no-use-title    Don't use chapter title as output filename stem (even
        \\                    if title is available). If title is not available, this
        \\                    option is implied.
        \\  --no-use-title-in-meta
        \\                    Do not set chapter title in output metadata, even if the
        \\                    title information is available.
        \\
    , .{program_name});
}

fn parseArgs(argv: []const []const u8, log: anytype) !Args {
    var infile: ?[]const u8 = null;
    var outdir: ?[]const u8 = null;
    var no_use_title = false;
    var no_use_title_in_meta = false;

    const prog_name = std.fs.path.basename(argv[0]);

    if (argv.len == 1) {
        try log.print("ERROR: no arguments given.\n---\n", .{});
        try printHelp(prog_name, log);
        return error.NoArgs;
    }

    var i: usize = 1; // skip argv[0]
    while (i < argv.len) {
        const arg = argv[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(prog_name, log);
            return error.ShowedHelp;
        } else if (std.mem.eql(u8, arg, "--input-file") or std.mem.eql(u8, arg, "-i")) {
            i += 1;
            if (i >= argv.len) return error.MissingInputFileValue;
            infile = argv[i];
        } else if (std.mem.eql(u8, arg, "--output-dir") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= argv.len) return error.MissingOutputDirValue;
            outdir = argv[i];
        } else if (std.mem.eql(u8, arg, "--no-use-title")) {
            no_use_title = true;
        } else if (std.mem.eql(u8, arg, "--no-use-title-in-meta")) {
            no_use_title_in_meta = true;
        } else {
            try log.print("ERROR: Unknown argument: {s}\n---\n", .{arg});
            try printHelp(prog_name, log);
            return error.UnknownArgument;
        }

        i += 1;
    }

    if (infile == null) return error.MissingInputFile;
    if (outdir == null) return error.MissingOutputDir;

    return Args{
        .infile = infile.?,
        .outdir = outdir.?,
        .no_use_title = no_use_title,
        .no_use_title_in_meta = no_use_title_in_meta,
    };
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    const argv = try std.process.argsAlloc(allocator);

    defer std.process.argsFree(allocator, argv);

    const stderr = std.io.getStdErr().writer();

    const code = try inner_main(allocator, argv, stderr);

    return std.process.exit(code);
}

pub fn inner_main(allocator: std.mem.Allocator, argv: []const []const u8, log: anytype) anyerror!u8 {
    const args = parseArgs(argv, log) catch |err|
        switch (err) {
            error.ShowedHelp => return 0, // don't treat as a failure
            error.NoArgs => return 1,
            else => {
                try log.print(
                    "ERROR: failed to parse arguments, reason: {}\n",
                    .{err},
                );
                return 2;
            },
        };

    try log.print(
        "Infile: {s}\nOutdir: {s}\n",
        .{
            args.infile,
            args.outdir,
        },
    );

    const meta = try lib.readInputFileMetaData(
        allocator,
        args.infile,
    );
    defer meta.deinit();

    if (meta.chapters().len == 0) {
        try log.print(
            "ERROR: Input file contains no chapter metadata - unable to proceed. Exiting...\n",
            .{},
        );
        std.process.exit(3);
    }

    const opts = lib.OutputOpts{
        .output_dir = args.outdir,
        .no_use_title = args.no_use_title,
        .no_use_title_in_meta = args.no_use_title_in_meta,
    };

    for (meta.chapters()) |ch| {
        const retcode = try lib.extractChapter(
            allocator,
            &ch,
            &meta,
            &opts,
        );
        const result = if (retcode == 0) "SUCCESS" else "FAILURE";
        try log.print("[{s}] Extract chapter id={} ({s} -> {s}) title='{s}'\n", .{
            result,
            ch.id,
            ch.start_time,
            ch.end_time,
            ch.meta_title() orelse "<no title>",
        });
    }

    return 0;
}

test "run main" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    const cases: [3]struct { skip: bool, argv: []const []const u8, expect_code: u8 } = .{
        .{
            .skip = false,
            .argv = &.{ "testmain", "-h" },
            .expect_code = 0,
        },
        .{
            .skip = false,
            .argv = &.{"testmain"},
            .expect_code = 1,
        },
        .{
            .skip = false,
            .argv = &.{ "testmain", "foobar" },
            .expect_code = 2,
        },
    };

    for (cases) |case| {
        if (case.skip) {
            continue;
        }

        var buf = std.ArrayList(u8).init(alloc);
        defer buf.deinit();

        const out = buf.writer();

        const code = try inner_main(alloc, case.argv, out);

        try std.testing.expectEqual(case.expect_code, code);
    }
}
