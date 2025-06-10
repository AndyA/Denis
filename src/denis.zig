const std = @import("std");

/// A DenisHash is a 32-byte SHA-256 hash, used as a key in the Denis set.
const DenisHash = [32]u8;

/// Computes a SHA-256 hash of the given string.
fn hashBytes(text: []const u8) DenisHash {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(text);
    return h.finalResult();
}

/// A HashMap context for DenisHash (where the keys are already sha256 hashes).
const HashHasher = struct {
    const Self = @This();

    pub fn hash(_: Self, key: DenisHash) u64 {
        // Use the first 8 bytes of the sha256 hash as the HashMap's hash value
        return std.mem.readInt(u64, key[0..8], .little);
    }

    pub fn eql(_: Self, a: DenisHash, b: DenisHash) bool {
        return std.mem.eql(u8, &a, &b);
    }
};

/// A set of DenisHashes
const HashSet = std.HashMapUnmanaged(DenisHash, void, HashHasher, 85);

/// A HashMap backed set of DenisHashes.
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

    /// Check if the given line is novel (not seen before). Only returns true
    /// the first time a particular line is seen.
    pub fn novel(self: *Self, line: []const u8) !bool {
        const hash = hashBytes(line);
        const entry = try self.set.getOrPutContext(self.alloc, hash, HashHasher{});
        return !entry.found_existing;
    }
};

const StringBuffer = std.ArrayList(u8);

/// Reads lines from multiple input streams and outputs the unique lines to an output
/// stream.
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

    /// Process an input stream, reading lines and printing novel ones to the output stream.
    pub fn process(self: *Self, reader: std.io.AnyReader) !void {
        var eof = false;
        while (!eof) {
            self.line_buf.items.len = 0; // clear the buffer for the next line
            reader.streamUntilDelimiter(self.line_buf.writer(), '\n', null) catch |err| switch (err) {
                error.EndOfStream => eof = true,
                else => return err,
            };
            if (eof and self.line_buf.items.len == 0) break; // skip empty last line
            if (try self.seen.novel(self.line_buf.items))
                try self.writer.print("{s}\n", .{self.line_buf.items});
        }
    }
};
