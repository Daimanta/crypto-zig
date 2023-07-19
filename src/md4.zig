const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = std.mem.Allocator;

const BLOCK_SIZE = 64;
const HASH_SIZE = 16;
const MESSAGE_UNITS = BLOCK_SIZE / @sizeOf(u32);
const HASH_UNITS = HASH_SIZE / @sizeOf(u32);

pub const Md4 = struct {
    partial: [BLOCK_SIZE]u8,
    partial_bytes: usize,
    hash: [HASH_UNITS]u32,
    length: u64,

    const Self = @This();

    pub fn init() Self {
        var result = Self{ .hash = undefined, .partial = undefined, .partial_bytes = undefined, .length = undefined };
        result.reset();
        return result;
    }

    //Mix in len bytes of data for the given buffer.
    pub fn update(self: *Self, buf: []const u8) void {
        self.length += buf.len;
        if (buf.len + self.partial_bytes < BLOCK_SIZE) {
            mem.copy(u8, self.partial[self.partial_bytes..], buf[0..]);
            self.partial_bytes += buf.len;
            return;
        } else {
            const taken_from_buffer = BLOCK_SIZE - self.partial_bytes;
            mem.copy(u8, self.partial[self.partial_bytes..], buf[0..taken_from_buffer]);
            self.process_partials();
            const remaining_in_buffer = buf.len - taken_from_buffer;
            if (remaining_in_buffer > 0) {
                const taken = (remaining_in_buffer / BLOCK_SIZE) * BLOCK_SIZE;
                const units = taken / 4;
                var block_slice: []align(1) const u32 = mem.bytesAsSlice(u32, buf[taken_from_buffer .. taken_from_buffer + taken]);
                var i: usize = 0;
                while (i * MESSAGE_UNITS < units) : (i += 1) {
                    var fixed_size_block: [MESSAGE_UNITS]u32 = block_slice[i * MESSAGE_UNITS .. (i + 1) * MESSAGE_UNITS][0..MESSAGE_UNITS].*;
                    self.process_block(fixed_size_block);
                }
                mem.copy(u8, self.partial[0..], buf[taken_from_buffer + taken ..]);
                self.partial_bytes = remaining_in_buffer - taken;
            } else {
                self.partial_bytes = 0;
            }
        }
    }

    pub fn make_final(self: *Self, digest: *[HASH_UNITS]u32) void {
        var ints: *[MESSAGE_UNITS]u32 = mem.bytesAsSlice(u32, @alignCast(4, self.partial[0..]))[0..16];

        const shift: u5 = @truncate(u5, (self.length % 4) * 8);
        var index = (self.length % BLOCK_SIZE) / 4;

        ints[index] &= ~(@as(u32, std.math.maxInt(u32)) << shift);
        ints[index] ^= @as(u32, 0x80) << shift;
        index += 1;

        if (index > 14) {
            mem.set(u32, ints[index..], 0);
            self.process_partials();
            index = 0;
        }

        mem.set(u32, ints[index..14], 0);
        ints[14] = @truncate(u32, self.length << 3);
        ints[15] = @truncate(u32, self.length >> 29);
        self.process_partials();
        mem.copy(u32, digest[0..], self.hash[0..]);
    }

    // Returns a slice owned by the caller
    pub fn make_final_slice(self: *Self, allocator: Allocator) !*[HASH_UNITS]u32 {
        var result: *[HASH_UNITS]u32 = try allocator.create([HASH_UNITS]u32);
        self.make_final(result);
        return result;
    }

    pub fn reset(self: *Self) void {
        self.partial = [1]u8{0} ** BLOCK_SIZE;
        self.length = 0;
        self.hash = .{ 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476 };
        self.partial_bytes = 0;
    }

    fn process_partials(self: *Self) void {
        self.process_block(mem.bytesAsSlice(u32, @alignCast(@sizeOf(u32), self.partial[0..]))[0..MESSAGE_UNITS].*);
    }

    fn process_block(self: *Self, block: [MESSAGE_UNITS]u32) void {
        var A = self.hash[0];
        var B = self.hash[1];
        var C = self.hash[2];
        var D = self.hash[3];

        var a = &A;
        var b = &B;
        var c = &C;
        var d = &D;
        var x = block;

        MD4_ROUND1(a, b, c, d, x[0], 3);
        MD4_ROUND1(d, a, b, c, x[1], 7);
        MD4_ROUND1(c, d, a, b, x[2], 11);
        MD4_ROUND1(b, c, d, a, x[3], 19);
        MD4_ROUND1(a, b, c, d, x[4], 3);
        MD4_ROUND1(d, a, b, c, x[5], 7);
        MD4_ROUND1(c, d, a, b, x[6], 11);
        MD4_ROUND1(b, c, d, a, x[7], 19);
        MD4_ROUND1(a, b, c, d, x[8], 3);
        MD4_ROUND1(d, a, b, c, x[9], 7);
        MD4_ROUND1(c, d, a, b, x[10], 11);
        MD4_ROUND1(b, c, d, a, x[11], 19);
        MD4_ROUND1(a, b, c, d, x[12], 3);
        MD4_ROUND1(d, a, b, c, x[13], 7);
        MD4_ROUND1(c, d, a, b, x[14], 11);
        MD4_ROUND1(b, c, d, a, x[15], 19);

        MD4_ROUND2(a, b, c, d, x[0], 3);
        MD4_ROUND2(d, a, b, c, x[4], 5);
        MD4_ROUND2(c, d, a, b, x[8], 9);
        MD4_ROUND2(b, c, d, a, x[12], 13);
        MD4_ROUND2(a, b, c, d, x[1], 3);
        MD4_ROUND2(d, a, b, c, x[5], 5);
        MD4_ROUND2(c, d, a, b, x[9], 9);
        MD4_ROUND2(b, c, d, a, x[13], 13);
        MD4_ROUND2(a, b, c, d, x[2], 3);
        MD4_ROUND2(d, a, b, c, x[6], 5);
        MD4_ROUND2(c, d, a, b, x[10], 9);
        MD4_ROUND2(b, c, d, a, x[14], 13);
        MD4_ROUND2(a, b, c, d, x[3], 3);
        MD4_ROUND2(d, a, b, c, x[7], 5);
        MD4_ROUND2(c, d, a, b, x[11], 9);
        MD4_ROUND2(b, c, d, a, x[15], 13);

        MD4_ROUND3(a, b, c, d, x[0], 3);
        MD4_ROUND3(d, a, b, c, x[8], 9);
        MD4_ROUND3(c, d, a, b, x[4], 11);
        MD4_ROUND3(b, c, d, a, x[12], 15);
        MD4_ROUND3(a, b, c, d, x[2], 3);
        MD4_ROUND3(d, a, b, c, x[10], 9);
        MD4_ROUND3(c, d, a, b, x[6], 11);
        MD4_ROUND3(b, c, d, a, x[14], 15);
        MD4_ROUND3(a, b, c, d, x[1], 3);
        MD4_ROUND3(d, a, b, c, x[9], 9);
        MD4_ROUND3(c, d, a, b, x[5], 11);
        MD4_ROUND3(b, c, d, a, x[13], 15);
        MD4_ROUND3(a, b, c, d, x[3], 3);
        MD4_ROUND3(d, a, b, c, x[11], 9);
        MD4_ROUND3(c, d, a, b, x[7], 11);
        MD4_ROUND3(b, c, d, a, x[15], 15);

        self.hash[0] +%= a.*;
        self.hash[1] +%= b.*;
        self.hash[2] +%= c.*;
        self.hash[3] +%= d.*;
    }
};

fn MD4_F(x: u32, y: u32, z: u32) u32 {
    return ((y ^ z) & x) ^ z;
}

fn MD4_G(x: u32, y: u32, z: u32) u32 {
    return (x & y) | (x & z) | (y & z);
}

fn MD4_H(x: u32, y: u32, z: u32) u32 {
    return x ^ y ^ z;
}

fn MD4_ROUND1(a: *u32, b: *u32, c: *u32, d: *u32, x: u32, s: u5) void {
    a.* +%= MD4_F(b.*, c.*, d.*) +% x;
    a.* = rotl32(a.*, s);
}

fn MD4_ROUND2(a: *u32, b: *u32, c: *u32, d: *u32, x: u32, s: u5) void {
    a.* +%= MD4_G(b.*, c.*, d.*) +% x +% 0x5a827999;
    a.* = rotl32(a.*, s);
}

fn MD4_ROUND3(a: *u32, b: *u32, c: *u32, d: *u32, x: u32, s: u5) void {
    a.* +%= MD4_H(b.*, c.*, d.*) +% x +% 0x6ed9eba1;
    a.* = rotl32(a.*, s);
}

fn rotl32(dword: u32, n: u5) u32 {
    if (n == 0) return dword;
    const remaining_shift: u5 = @truncate(u5, 32 - @as(u6, n));
    return (dword) << n ^ (dword >> remaining_shift);
}

fn digest_to_hex_string(digest: *[HASH_UNITS]u32, string: *[2 * HASH_SIZE]u8) void {
    var i: usize = 0;
    while (i < digest.len) : (i += 1) {
        const start = i * 8;
        const end = start + 8;
        const digest_val = digest[i];
        var my_num: u32 = ((digest_val & 0xFF000000) >> 24) | ((digest_val & 0x00FF0000) >> 8) | ((digest_val & 0x0000FF00) << 8) | ((digest_val & 0x000000FF) << 24);
        _ = std.fmt.bufPrintIntToSlice(string[start..end], my_num, 16, .upper, std.fmt.FormatOptions{ .width = 8, .fill = '0' });
    }
}

test "empty string" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Md4.init();

    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "31D6CFE0D16AE931B73C59D7E0C089C0";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'a'" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Md4.init();
    processor.update("a");
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "BDE52CB31DE33E46245E05FBDBD6FB24";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'a' as slice" {
    var processor = Md4.init();
    processor.update("a");
    const allocator = std.heap.page_allocator;
    var result = try processor.make_final_slice(allocator);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(result, &string);

    const expected: []const u8 = "BDE52CB31DE33E46245E05FBDBD6FB24";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'abc'" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Md4.init();
    processor.update("abc");
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "A448017AAF21D8525FC10AE87AA6729D";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'message digest'" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Md4.init();
    processor.update("message digest");
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "D9130A8164549FE818874806E1C7014B";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'abcdefghijklmnopqrstuvwxyz'" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Md4.init();
    processor.update("abcdefghijklmnopqrstuvwxyz");
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "D79E1C308AA5BBCDEEA8ED63DF412DA9";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'The quick brown fox jumps over the lazy dog'" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Md4.init();
    processor.update("The quick brown fox jumps over the lazy dog");
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "1BEE69A46BA811185C194762ABAEAE90";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'1234567890' ** 8" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Md4.init();
    processor.update("1234567890" ** 8);
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "E33B4DDC9C38F2199C3E7B164FCC0536";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'1234567890' ** 8 piecewise" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Md4.init();
    processor.update("1234567890" ** 4);
    processor.update("1234567890" ** 4);
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "E33B4DDC9C38F2199C3E7B164FCC0536";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Md4.init();
    processor.update("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "043F8582F241DB351CE627E153E7F0E4";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}
