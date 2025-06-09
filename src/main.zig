const std = @import("std");
const cli = @import("zig-cli");

const BW = std.io.BufferedWriter;
fn bufferedWriterSize(comptime size: usize, stream: anytype) BW(size, @TypeOf(stream)) {
    return .{ .unbuffered_writer = stream };
}

const DenisHash = [32]u8;

fn hashLine(text: []const u8) DenisHash {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(text);
    return h.finalResult();
}

const HashHasher = struct {
    const Self = @This();
    pub fn hash(_: Self, key: DenisHash) u64 {
        return std.mem.readInt(u64, key[0..8], .little);
    }
    pub fn eql(_: Self, a: DenisHash, b: DenisHash) bool {
        return std.mem.eql(u8, &a, &b);
    }
};

pub const Denis = struct {
    alloc: std.mem.Allocator,
    line_buf: std.ArrayList(u8),
    seen: std.HashMapUnmanaged(DenisHash, void, HashHasher, 75),
    writer: std.io.AnyWriter,

    const Self = @This();

    pub fn init(
        alloc: std.mem.Allocator,
        writer: std.io.AnyWriter,
    ) !Self {
        var line_buf = try std.ArrayList(u8).initCapacity(alloc, 1000);
        errdefer line_buf.deinit();
        var seen = std.HashMapUnmanaged(DenisHash, void, HashHasher, 75){};
        errdefer seen.deinit(alloc);

        return Self{
            .alloc = alloc,
            .writer = writer,
            .line_buf = line_buf,
            .seen = seen,
        };
    }

    pub fn deinit(self: *Self) void {
        self.line_buf.deinit();
        self.seen.deinit(self.alloc);
    }

    pub fn process(self: *Self, reader: std.io.AnyReader) !void {
        var eof = false;
        while (!eof) {
            reader.readUntilDelimiterArrayList(&self.line_buf, '\n', undefined) catch |err| switch (err) {
                error.EndOfStream => eof = true,
                else => return err,
            };
            if (self.line_buf.items.len == 0) continue; // Skip empty lines
            const hash = hashLine(self.line_buf.items);
            const entry = try self.seen.getOrPutContext(self.alloc, hash, HashHasher{});
            if (!entry.found_existing) {
                // novelty!
                try self.writer.print("{s}\n", .{self.line_buf.items});
            }
        }
    }
};

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
