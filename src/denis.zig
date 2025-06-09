const std = @import("std");

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

const LOAD = 85;

pub const Denis = struct {
    alloc: std.mem.Allocator,
    line_buf: std.ArrayList(u8),
    seen: std.HashMapUnmanaged(DenisHash, void, HashHasher, LOAD),
    writer: std.io.AnyWriter,

    const Self = @This();

    pub fn init(
        alloc: std.mem.Allocator,
        writer: std.io.AnyWriter,
        millions: u32,
    ) !Self {
        var line_buf = try std.ArrayList(u8).initCapacity(alloc, 1000);
        errdefer line_buf.deinit();
        var seen = std.HashMapUnmanaged(DenisHash, void, HashHasher, LOAD){};
        errdefer seen.deinit(alloc);

        if (millions != 0) {
            try seen.ensureTotalCapacity(alloc, millions * 1_000_000);
        }

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
