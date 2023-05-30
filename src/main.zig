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

pub fn readChapters(input_file: [*:0]const u8, allocator: std.mem.Allocator) !FFProbeOutput {
    const ffprobe_cmd = &.{ "ffprobe", "-i", std.mem.sliceTo(input_file, 0), "-v", "error", "-print_format", "json", "-show_chapters" };
    const proc = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = ffprobe_cmd,
    });
    //var proc = std.ChildProcess.init(ffprobe_cmd, allocator);
    //const term = try proc.wait();

    defer allocator.free(proc.stdout);
    defer allocator.free(proc.stderr);

    if (proc.term.Exited != 0) {
        if (proc.stderr[proc.stderr.len - 1] == '\n') {
            proc.stderr[proc.stderr.len - 1] = 0;
        }
        std.debug.print("ERROR (ffprobe): {s}\n", .{proc.stderr});
        return error.FFProbeCallError;
    }
    //std.debug.print("out: {s}\n", .{proc.stdout});

    return try std.json.parseFromSlice(FFProbeOutput, allocator, proc.stdout, .{
        //.ignore_unknown_fields = true,
    });
}

pub fn main() anyerror!void {
    //std.debug.print("usage: {s}\n", .{std.builtin.SourceLocation.fn_name});
    if (std.os.argv.len < 2) {
        std.debug.print("usage: {s} <path-to-file>\n", .{std.os.argv[0]});
        std.os.exit(1);
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fnam = std.mem.sliceTo(std.os.argv[1], 0);

    const parsed = try readChapters(fnam, allocator);

    for (parsed.chapters) |ch| {
        std.debug.print("Ch id={}: ({} -> {}) '{s}'\n", .{ ch.id, ch.start, ch.end, ch.tags.title });
    }
}

test "parse chapters from example audio file" {
    const res = try readChapters("src/testdata/beep.m4a", std.testing.allocator);
    for (res.chapters) |ch| {
        std.testing.allocator.free(ch.time_base);
        std.testing.allocator.free(ch.start_time);
        std.testing.allocator.free(ch.end_time);
        std.testing.allocator.free(ch.tags.title);
    }
    std.testing.allocator.free(res.chapters);
    try std.testing.expect(res.chapters.len == 3);
}
