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

const HashSet = std.HashMapUnmanaged(DenisHash, void, HashHasher, 85);

const DenisSet = struct {
    alloc: std.mem.Allocator,
    set: HashSet,
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, millions: u32) !Self {
        var set = HashSet{};
        errdefer set.deinit(alloc);

        if (millions != 0)
            try set.ensureTotalCapacity(alloc, millions * 1_000_000);

        return Self{ .alloc = alloc, .set = set };
    }

    pub fn deinit(self: *Self) void {
        self.set.deinit(self.alloc);
    }

    pub fn novel(self: *Self, line: []const u8) !bool {
        const hash = hashLine(line);
        const entry = try self.set.getOrPutContext(self.alloc, hash, HashHasher{});
        return !entry.found_existing;
    }
};

const StringBuffer = std.ArrayList(u8);

pub const Denis = struct {
    line_buf: StringBuffer,
    seen: DenisSet,
    writer: std.io.AnyWriter,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, writer: std.io.AnyWriter, millions: u32) !Self {
        var line_buf = try StringBuffer.initCapacity(alloc, 1000);
        errdefer line_buf.deinit();
        var seen = try DenisSet.init(alloc, millions);
        errdefer seen.deinit();

        return Self{
            .writer = writer,
            .line_buf = line_buf,
            .seen = seen,
        };
    }

    pub fn deinit(self: *Self) void {
        self.line_buf.deinit();
        self.seen.deinit();
    }

    pub fn process(self: *Self, reader: std.io.AnyReader) !void {
        var eof = false;
        while (!eof) {
            reader.readUntilDelimiterArrayList(&self.line_buf, '\n', undefined) catch |err| switch (err) {
                error.EndOfStream => eof = true,
                else => return err,
            };
            if (self.line_buf.items.len == 0) continue; // skip empty lines
            if (try self.seen.novel(self.line_buf.items))
                try self.writer.print("{s}\n", .{self.line_buf.items});
        }
    }
};
