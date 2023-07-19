// A GOST R 34.11-94 hashing library
// Based on the original C written by Markku-Juhani Saarinen <mjos@ssh.fi>
// Written by Léon van der Kaap <leonkaap@gmail.com>

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = std.mem.Allocator;

const BLOCK_SIZE = 64;
const HASH_SIZE = 20;
const MESSAGE_UNITS = BLOCK_SIZE / @sizeOf(u32);
const HASH_UNITS = HASH_SIZE / @sizeOf(u32);

pub const Has160 = struct {
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
        var ints: *[MESSAGE_UNITS]u32 = mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(self.partial[0..])))[0..16];

        const shift: u5 = @as(u5, @truncate((self.length % 4) * 8));
        var index = (self.length % BLOCK_SIZE) / 4;

        ints[index] &= ~(@as(u32, std.math.maxInt(u32)) << shift);
        ints[index] ^= @as(u32, 0x80) << shift;
        index += 1;

        if (index > 14) {
            @memset(ints[index..], 0);
            self.process_partials();
            index = 0;
        }

        @memset(ints[index..14], 0);
        ints[14] = @as(u32, @truncate(self.length << 3));
        ints[15] = @as(u32, @truncate(self.length >> 29));
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
        self.hash = .{ 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0 };
        self.partial_bytes = 0;
    }

    fn process_partials(self: *Self) void {
        self.process_block(mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(self.partial[0..])))[0..MESSAGE_UNITS].*);
    }

    fn process_block(self: *Self, block: [MESSAGE_UNITS]u32) void {
        var X: [32]u32 = undefined;
        {
            var j: usize = 0;
            while (j < 16) : (j += 1) {
                X[j] = block[j];
            }

            X[16] = X[0] ^ X[1] ^ X[2] ^ X[3]; // for rounds  1..20
            X[17] = X[4] ^ X[5] ^ X[6] ^ X[7];
            X[18] = X[8] ^ X[9] ^ X[10] ^ X[11];
            X[19] = X[12] ^ X[13] ^ X[14] ^ X[15];
            X[20] = X[3] ^ X[6] ^ X[9] ^ X[12]; // for rounds 21..40
            X[21] = X[2] ^ X[5] ^ X[8] ^ X[15];
            X[22] = X[1] ^ X[4] ^ X[11] ^ X[14];
            X[23] = X[0] ^ X[7] ^ X[10] ^ X[13];
            X[24] = X[5] ^ X[7] ^ X[12] ^ X[14]; // for rounds 41..60
            X[25] = X[0] ^ X[2] ^ X[9] ^ X[11];
            X[26] = X[4] ^ X[6] ^ X[13] ^ X[15];
            X[27] = X[1] ^ X[3] ^ X[8] ^ X[10];
            X[28] = X[2] ^ X[7] ^ X[8] ^ X[13]; // for rounds 61..80
            X[29] = X[3] ^ X[4] ^ X[9] ^ X[14];
            X[30] = X[0] ^ X[5] ^ X[10] ^ X[15];
            X[31] = X[1] ^ X[6] ^ X[11] ^ X[12];
        }

        var a = self.hash[0];
        var b = self.hash[1];
        var c = self.hash[2];
        var d = self.hash[3];
        var e = self.hash[4];
        var A = &a;
        var B = &b;
        var C = &c;
        var D = &d;
        var E = &e;

        STEP_F1(A, B, C, D, E, X[18], 5);
        STEP_F1(E, A, B, C, D, X[0], 11);
        STEP_F1(D, E, A, B, C, X[1], 7);
        STEP_F1(C, D, E, A, B, X[2], 15);
        STEP_F1(B, C, D, E, A, X[3], 6);
        STEP_F1(A, B, C, D, E, X[19], 13);
        STEP_F1(E, A, B, C, D, X[4], 8);
        STEP_F1(D, E, A, B, C, X[5], 14);
        STEP_F1(C, D, E, A, B, X[6], 7);
        STEP_F1(B, C, D, E, A, X[7], 12);
        STEP_F1(A, B, C, D, E, X[16], 9);
        STEP_F1(E, A, B, C, D, X[8], 11);
        STEP_F1(D, E, A, B, C, X[9], 8);
        STEP_F1(C, D, E, A, B, X[10], 15);
        STEP_F1(B, C, D, E, A, X[11], 6);
        STEP_F1(A, B, C, D, E, X[17], 12);
        STEP_F1(E, A, B, C, D, X[12], 9);
        STEP_F1(D, E, A, B, C, X[13], 14);
        STEP_F1(C, D, E, A, B, X[14], 5);
        STEP_F1(B, C, D, E, A, X[15], 13);

        STEP_F2(A, B, C, D, E, X[22], 5);
        STEP_F2(E, A, B, C, D, X[3], 11);
        STEP_F2(D, E, A, B, C, X[6], 7);
        STEP_F2(C, D, E, A, B, X[9], 15);
        STEP_F2(B, C, D, E, A, X[12], 6);
        STEP_F2(A, B, C, D, E, X[23], 13);
        STEP_F2(E, A, B, C, D, X[15], 8);
        STEP_F2(D, E, A, B, C, X[2], 14);
        STEP_F2(C, D, E, A, B, X[5], 7);
        STEP_F2(B, C, D, E, A, X[8], 12);
        STEP_F2(A, B, C, D, E, X[20], 9);
        STEP_F2(E, A, B, C, D, X[11], 11);
        STEP_F2(D, E, A, B, C, X[14], 8);
        STEP_F2(C, D, E, A, B, X[1], 15);
        STEP_F2(B, C, D, E, A, X[4], 6);
        STEP_F2(A, B, C, D, E, X[21], 12);
        STEP_F2(E, A, B, C, D, X[7], 9);
        STEP_F2(D, E, A, B, C, X[10], 14);
        STEP_F2(C, D, E, A, B, X[13], 5);
        STEP_F2(B, C, D, E, A, X[0], 13);

        STEP_F3(A, B, C, D, E, X[26], 5);
        STEP_F3(E, A, B, C, D, X[12], 11);
        STEP_F3(D, E, A, B, C, X[5], 7);
        STEP_F3(C, D, E, A, B, X[14], 15);
        STEP_F3(B, C, D, E, A, X[7], 6);
        STEP_F3(A, B, C, D, E, X[27], 13);
        STEP_F3(E, A, B, C, D, X[0], 8);
        STEP_F3(D, E, A, B, C, X[9], 14);
        STEP_F3(C, D, E, A, B, X[2], 7);
        STEP_F3(B, C, D, E, A, X[11], 12);
        STEP_F3(A, B, C, D, E, X[24], 9);
        STEP_F3(E, A, B, C, D, X[4], 11);
        STEP_F3(D, E, A, B, C, X[13], 8);
        STEP_F3(C, D, E, A, B, X[6], 15);
        STEP_F3(B, C, D, E, A, X[15], 6);
        STEP_F3(A, B, C, D, E, X[25], 12);
        STEP_F3(E, A, B, C, D, X[8], 9);
        STEP_F3(D, E, A, B, C, X[1], 14);
        STEP_F3(C, D, E, A, B, X[10], 5);
        STEP_F3(B, C, D, E, A, X[3], 13);

        STEP_F4(A, B, C, D, E, X[30], 5);
        STEP_F4(E, A, B, C, D, X[7], 11);
        STEP_F4(D, E, A, B, C, X[2], 7);
        STEP_F4(C, D, E, A, B, X[13], 15);
        STEP_F4(B, C, D, E, A, X[8], 6);
        STEP_F4(A, B, C, D, E, X[31], 13);
        STEP_F4(E, A, B, C, D, X[3], 8);
        STEP_F4(D, E, A, B, C, X[14], 14);
        STEP_F4(C, D, E, A, B, X[9], 7);
        STEP_F4(B, C, D, E, A, X[4], 12);
        STEP_F4(A, B, C, D, E, X[28], 9);
        STEP_F4(E, A, B, C, D, X[15], 11);
        STEP_F4(D, E, A, B, C, X[10], 8);
        STEP_F4(C, D, E, A, B, X[5], 15);
        STEP_F4(B, C, D, E, A, X[0], 6);
        STEP_F4(A, B, C, D, E, X[29], 12);
        STEP_F4(E, A, B, C, D, X[11], 9);
        STEP_F4(D, E, A, B, C, X[6], 14);
        STEP_F4(C, D, E, A, B, X[1], 5);
        STEP_F4(B, C, D, E, A, X[12], 13);

        self.hash[0] +%= A.*;
        self.hash[1] +%= B.*;
        self.hash[2] +%= C.*;
        self.hash[3] +%= D.*;
        self.hash[4] +%= E.*;
    }
};

fn STEP_F1(A: *u32, B: *u32, C: *u32, D: *u32, E: *u32, msg: u32, rot: u4) void {
    E.* +%= rotl32(A.*, rot) +% (D.* ^ (B.* & (C.* ^ D.*))) +% msg;
    B.* = rotl32(B.*, 10);
}

fn STEP_F2(A: *u32, B: *u32, C: *u32, D: *u32, E: *u32, msg: u32, rot: u4) void {
    E.* +%= rotl32(A.*, rot) +% (B.* ^ C.* ^ D.*) +% msg +% 0x5A827999;
    B.* = rotl32(B.*, 17);
}

fn STEP_F3(A: *u32, B: *u32, C: *u32, D: *u32, E: *u32, msg: u32, rot: u4) void {
    E.* +%= rotl32(A.*, rot) +% (C.* ^ (B.* | ~D.*)) +% msg +% 0x6ED9EBA1;
    B.* = rotl32(B.*, 25);
}

fn STEP_F4(A: *u32, B: *u32, C: *u32, D: *u32, E: *u32, msg: u32, rot: u4) void {
    E.* +%= rotl32(A.*, rot) +% (B.* ^ C.* ^ D.*) +% msg +% 0x8F1BBCDC;
    B.* = rotl32(B.*, 30);
}

fn rotl32(dword: u32, n: u5) u32 {
    if (n == 0) return dword;
    const remaining_shift: u5 = @as(u5, @truncate(32 - @as(u6, n)));
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
    var processor = Has160.init();

    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "307964EF34151D37C8047ADEC7AB50F4FF89762D";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'a'" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Has160.init();
    processor.update("a");
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "4872BCBC4CD0F0A9DC7C2F7045E5B43B6C830DB8";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'a' as slice" {
    var processor = Has160.init();
    processor.update("a");
    const allocator = std.heap.page_allocator;
    var result = try processor.make_final_slice(allocator);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(result, &string);

    const expected: []const u8 = "4872BCBC4CD0F0A9DC7C2F7045E5B43B6C830DB8";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'abc'" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Has160.init();
    processor.update("abc");
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "975E810488CF2A3D49838478124AFCE4B1C78804";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'message digest'" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Has160.init();
    processor.update("message digest");
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "2338DBC8638D31225F73086246BA529F96710BC6";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'abcdefghijklmnopqrstuvwxyz'" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Has160.init();
    processor.update("abcdefghijklmnopqrstuvwxyz");
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "596185C9AB6703D0D0DBB98702BC0F5729CD1D3C";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'The quick brown fox jumps over the lazy dog'" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Has160.init();
    processor.update("The quick brown fox jumps over the lazy dog");
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "ABE2B8C711F9E8579AA8EB40757A27B4EF14A7EA";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'1234567890' ** 8" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Has160.init();
    processor.update("1234567890" ** 8);
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "07F05C8C0773C55CA3A5A695CE6ACA4C438911B5";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'1234567890' ** 8 piecewise" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Has160.init();
    processor.update("1234567890" ** 4);
    processor.update("1234567890" ** 4);
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "07F05C8C0773C55CA3A5A695CE6ACA4C438911B5";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "'a' ** 1_000_000" {
    var result: [HASH_UNITS]u32 = undefined;
    var processor = Has160.init();
    processor.update("a" ** 1_000_000);
    processor.make_final(&result);

    var string: [2 * HASH_SIZE]u8 = undefined;
    digest_to_hex_string(&result, &string);

    const expected: []const u8 = "D6AD6F0608B878DA9B87999C2525CC84F4C9F18D";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}
