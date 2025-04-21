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
};

fn printHelp(program_name: []const u8) void {
    std.debug.print(
        \\Usage:
        \\  {0s} --input-file <path> --output-dir <path>
        \\
        \\ Splits audio file into per-chapter files using ffmpeg and chapter metadata
        \\
        \\Options:
        \\  -i, --input-file  Path to input file (required)
        \\  -o, --output-dir  Path to output directory (required)
        \\  -h, --help        Show this help message
        \\  --no-use-title    Don't use chapter title as output filename stem (even
        \\                    if title is available). If title is not available, this
        \\                    option is implied.
        \\
    , .{program_name});
}

fn parseArgs(argv: []const []const u8) !Args {
    var infile: ?[]const u8 = null;
    var outdir: ?[]const u8 = null;
    var no_use_title = false;

    const prog_name = std.fs.path.basename(argv[0]);

    if (argv.len == 1) {
        std.debug.print("ERROR: no arguments given.\n---\n", .{});
        printHelp(prog_name);
        return error.NoArgs;
    }

    var i: usize = 1; // skip argv[0]
    while (i < argv.len) {
        const arg = argv[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp(prog_name);
            return error.ShowedHelp;
        } else if (std.mem.eql(u8, arg, "--input-file") or std.mem.eql(u8, arg, "-i")) {
            i += 1;
            if (i >= argv.len) return error.MissingInfileValue;
            infile = argv[i];
        } else if (std.mem.eql(u8, arg, "--output-dir") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= argv.len) return error.MissingOutdirValue;
            outdir = argv[i];
        } else if (std.mem.eql(u8, arg, "--no-use-title")) {
            no_use_title = true;
        } else {
            std.debug.print("ERROR: Unknown argument: {s}\n---\n", .{arg});
            printHelp(prog_name);
            return error.UnknownArgument;
        }

        i += 1;
    }

    if (infile == null) return error.MissingInfile;
    if (outdir == null) return error.MissingOutdir;

    return Args{
        .infile = infile.?,
        .outdir = outdir.?,
        .no_use_title = no_use_title,
    };
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    defer std.process.argsFree(allocator, args);

    if (parseArgs(args)) |parsed| {
        std.debug.print(
            "Infile: {s}\nOutdir: {s}\n",
            .{
                parsed.infile,
                parsed.outdir,
            },
        );
        const meta = try lib.readInputFileMetaData(allocator, parsed.infile);
        defer meta.deinit();

        if (meta.chapters().len == 0) {
            std.debug.print(
                "ERROR: Input file contains no chapter metadata - unable to proceed. Exiting...\n",
                .{},
            );
            std.process.exit(3);
        }

        const opts = lib.OutputOpts{
            .output_dir = parsed.outdir,
            .no_use_title = parsed.no_use_title,
        };

        for (0.., meta.chapters()) |i, ch| {
            const retcode = try lib.extractChapter(allocator, i, &meta, &opts);
            const result = if (retcode == 0) "SUCCESS" else "FAILURE";
            std.debug.print("[{s}] Extract chapter id={} ({s} -> {s}) title='{s}'\n", .{
                result,
                ch.id,
                ch.start_time,
                ch.end_time,
                ch.tags.title,
            });
        }
    } else |err| switch (err) {
        error.ShowedHelp => std.process.exit(0), // don't treat as a failure
        error.NoArgs => std.process.exit(1),
        else => std.process.exit(2),
    }
}
