const std = @import("std");
const cli = @import("zig-cli");
const Denis = @import("denis.zig").Denis;

const BW = std.io.BufferedWriter;
fn bufferedWriterSize(comptime size: usize, stream: anytype) BW(size, @TypeOf(stream)) {
    return .{ .unbuffered_writer = stream };
}

fn processShim(denis: *Denis, in_file: anytype) !void {
    var in_buf = std.io.bufferedReaderSize(128 * 1024, in_file.reader());
    const reader = in_buf.reader().any();
    try denis.process(reader);
}

fn processFile(denis: *Denis, source: []const u8) !void {
    if (std.mem.eql(u8, source, "-")) {
        const in_file = std.io.getStdIn();
        try processShim(denis, in_file);
    } else {
        const in_file = try std.fs.cwd().openFile(source, .{});
        defer in_file.close();
        try processShim(denis, in_file);
    }
}

const Config = struct {
    files: []const []const u8,
};

var config = Config{ .files = undefined };

fn runner() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const out_file = std.io.getStdOut();
    var out_buf = bufferedWriterSize(128 * 1024, out_file.writer());
    const writer = out_buf.writer().any();

    var denis = try Denis.init(arena.allocator(), writer);

    for (config.files) |file| {
        processFile(&denis, file) catch |err| {
            std.debug.print("{s}: {s}\n", .{ file, @errorName(err) });
            std.process.exit(1);
        };
    }
    try out_buf.flush();
}

pub fn main() !void {
    var r = try cli.AppRunner.init(std.heap.page_allocator);

    const app = cli.App{
        .command = cli.Command{
            .name = "denis",
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
                    .exec = runner,
                },
            },
        },
    };

    return r.run(&app);
}
