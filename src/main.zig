//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("audiobook_split_ffmpeg_zig_lib");

const Args = struct {
    infile: []const u8,
    outdir: []const u8,
};

fn printHelp(program_name: []const u8) void {
    std.debug.print(
        \\Usage:
        \\  {0s} --input-file <path> --output-dir <path>
        \\
        \\Options:
        \\  -i, --input-file  Path to input file (required)
        \\  -o, --output-dir  Path to output directory (required)
        \\  -h, --help        Show this help message
        \\
    , .{program_name});
}

fn parseArgs(argv: []const []const u8) !Args {
    var infile: ?[]const u8 = null;
    var outdir: ?[]const u8 = null;

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
    };
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    defer std.process.argsFree(allocator, args);

    const result = parseArgs(args);

    if (result) |parsed| {
        std.debug.print(
            "Infile: {s}\nOutdir: {s}\n",
            .{
                parsed.infile,
                parsed.outdir,
            },
        );
        const meta = try lib.readInputFileMetaData(allocator, parsed.infile);
        defer meta.deinit();

        for (meta.chapters()) |ch| {
            std.debug.print("Ch id={}: ({} -> {}) '{s}'\n", .{
                ch.id,
                ch.start,
                ch.end,
                ch.tags.title,
            });
        }
        std.debug.print("WARNING: No files were actually produced (WIP)\n", .{});
    } else |err| switch (err) {
        error.ShowedHelp => std.process.exit(0), // don't treat as a failure
        error.NoArgs => std.process.exit(1),
        else => std.process.exit(2),
    }
}
