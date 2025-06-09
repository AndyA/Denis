//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const cli = @import("zig-cli");

const BW = std.io.BufferedWriter;
fn bufferedWriterSize(comptime size: usize, stream: anytype) BW(size, @TypeOf(stream)) {
    return .{ .unbuffered_writer = stream };
}

const FullHash = [32]u8;

fn hashLine(text: []const u8) FullHash {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(text);
    return h.finalResult();
}

fn deniqStream(
    alloc: std.mem.Allocator,
    reader: std.io.AnyReader,
    writer: std.io.AnyWriter,
) !void {
    var line_buf = try std.ArrayList(u8).initCapacity(alloc, 1024);
    defer line_buf.deinit();

    const HashHasher = struct {
        const Self = @This();
        pub fn hash(_: Self, key: FullHash) u64 {
            return std.mem.readInt(u64, key[0..8], .little);
        }
        pub fn eql(_: Self, a: FullHash, b: FullHash) bool {
            return std.mem.eql(u8, &a, &b);
        }
    };

    const ctx = HashHasher{};
    var seen = std.HashMapUnmanaged(FullHash, void, HashHasher, 75){};
    defer seen.deinit(alloc);

    var eof = false;
    while (!eof) {
        reader.readUntilDelimiterArrayList(&line_buf, '\n', undefined) catch |err| switch (err) {
            error.EndOfStream => eof = true,
            else => return err,
        };
        if (line_buf.items.len == 0) continue; // Skip empty lines
        const hash = hashLine(line_buf.items);
        const entry = try seen.getOrPutContext(alloc, hash, ctx);
        if (!entry.found_existing) {
            try writer.print("{s}\n", .{line_buf.items});
        }
    }
}

fn deniqFile(source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const out_file = std.io.getStdOut();
    var out_buf = bufferedWriterSize(128 * 1024, out_file.writer());
    const writer = out_buf.writer().any();

    if (std.mem.eql(u8, source, "-")) {
        const in_file = std.io.getStdIn();

        var in_buf = std.io.bufferedReaderSize(128 * 1024, in_file.reader());
        const reader = in_buf.reader().any();
        try deniqStream(arena.allocator(), reader, writer);
    } else {
        const in_file = try std.fs.cwd().openFile(source, .{});
        defer in_file.close();

        var in_buf = std.io.bufferedReaderSize(128 * 1024, in_file.reader());
        const reader = in_buf.reader().any();
        try deniqStream(arena.allocator(), reader, writer);
    }

    try out_buf.flush();
}

const Config = struct {
    files: []const []const u8,
};

var config = Config{ .files = undefined };

fn deniq() !void {
    for (config.files) |file| {
        deniqFile(file) catch |err| {
            std.debug.print("{s}: {s}\n", .{ file, @errorName(err) });
            std.process.exit(1);
        };
    }
}

pub fn main() !void {
    var r = try cli.AppRunner.init(std.heap.page_allocator);

    const app = cli.App{
        .command = cli.Command{
            .name = "deniq",
            .target = cli.CommandTarget{
                .action = cli.CommandAction{
                    .positional_args = cli.PositionalArgs{
                        .required = try r.allocPositionalArgs(&.{
                            .{
                                .name = "files",
                                .help = "Files to process. Use '-' for stdin.",
                                .value_ref = r.mkRef(&config.files),
                            },
                        }),
                    },
                    .exec = deniq,
                },
            },
        },
    };

    return r.run(&app);
}
