const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const native_endian = @import("builtin").target.cpu.arch.endian();

const Allocator = std.mem.Allocator;

pub const HashType = enum(u16) {
    HASH_224 = 224,
    HASH_256 = 256,
    HASH_384 = 384,
    HASH_512 = 512,
    
    fn bitlen(self: HashType) u16 {
        return @enumToInt(self);
    }
};

const roundconstant_zero: [64]u4 = .{0x6,0xa,0x0,0x9,0xe,0x6,0x6,0x7,0xf,0x3,0xb,0xc,0xc,0x9,0x0,0x8,0xb,0x2,0xf,0xb,0x1,0x3,0x6,0x6,0xe,0xa,0x9,0x5,0x7,0xd,0x3,0xe,0x3,0xa,0xd,0xe,0xc,0x1,0x7,0x5,0x1,0x2,0x7,0x7,0x5,0x0,0x9,0x9,0xd,0xa,0x2,0xf,0x5,0x9,0x0,0xb,0x0,0x6,0x6,0x7,0x3,0x2,0x2,0xa};
const S: [2][16]u4 = .{.{9,0,4,11,13,12,3,15,1,10,2,6,7,5,8,14}, .{3,12,6,13,5,7,1,9,15,2,0,4,11,10,14,8}};

const buffer_size: u64 = 64;

pub const JH = struct {
    hash_type: HashType,
    databitlen: u64,
    datasize_in_buffer: u64,
    H: [128]u8,
    A: [256]u4,
    roundconstant: [64]u4,
    buffer: [buffer_size]u8,

    const Self = @This();

    pub fn init(hash_type: HashType) Self {
        var result = Self{ .hash_type = hash_type, .databitlen = undefined, .datasize_in_buffer = undefined, .H = undefined, .A = undefined, .roundconstant = undefined, .buffer = undefined };
        result.reset();
        return result;
    }

    
    pub fn update(self: *Self, buf: []const u8) void {
        const message_length = buf.len;
        
        self.databitlen += message_length;
        
        if (self.datasize_in_buffer + message_length < buffer_size) {
            mem.copy(u8, self.buffer[self.datasize_in_buffer..], buf);
            self.datasize_in_buffer += message_length;
        } else if (self.datasize_in_buffer + message_length == buffer_size) {
            mem.copy(u8, self.buffer[self.datasize_in_buffer..], buf);
            self.F8();
            self.datasize_in_buffer = 0;
        } else {
            mem.copy(u8, self.buffer[self.datasize_in_buffer..], buf);
            self.F8();
            var buf_start: u64 = 64 - self.datasize_in_buffer;
            self.datasize_in_buffer = 0;
            while (buf_start + buffer_size < message_length): (buf_start += buffer_size) {
                mem.copy(u8, self.buffer[0..], buf[buf_start..buf_start + buffer_size]);
                self.F8();
            }
            const buffer_remaining = message_length - buf_start;
            self.datasize_in_buffer = buffer_remaining;
            mem.copy(u8, self.buffer[0..], buf[buf_start..]);
        }
        
    }
    
    pub fn make_final(self: *Self, digest: *[128]u8) []u8 {
        const bit_length = self.databitlen * 8;
        if (self.datasize_in_buffer == 0) {
            self.buffer = .{0} ** 64;
            self.buffer[0] = 0x80;
            var i: usize = 63;
            while (i >= 56): ( i -= 1) {
                self.buffer[i] = @truncate(u8, bit_length >> @intCast(u6, (63 - i)*8));
            }
            
            self.F8();
        } else {
            mem.set(u8, self.buffer[self.datasize_in_buffer..], 0);
            self.buffer[self.datasize_in_buffer] |= 1 << 7;
            
            self.F8();
            self.buffer = .{0} ** 64;
            
            var j: usize = 63;
            while (j >= 56): ( j -= 1) {
                self.buffer[j] = @truncate(u8, bit_length >> @intCast(u6, (63 - j)*8));
            }
            self.F8();
        }
        
        const bytelen = self.hash_type.bitlen() / 8;
        const end_index: usize = 128 - bytelen;
        mem.copy(u8, digest[0..], self.H[end_index..]);
        return digest[0..bytelen];
    }


    pub fn reset(self: *Self) void {
        self.databitlen = 0;
        self.datasize_in_buffer = 0;
        self.buffer = [1]u8{0} ** 64;
        self.H = [1]u8{0} ** 128;
        
        const bitlen = self.hash_type.bitlen();
        
        self.H[0] = @truncate(u8, bitlen >> 8);
        self.H[1] = @truncate(u8, bitlen);
        
        self.F8();
    }
    
    fn F8(self: *Self) void {
        for (self.buffer) |_, i| {
            self.H[i] ^= self.buffer[i];
        }
        
        self.E8();
        
        for (self.buffer) |_, i| {
            self.H[i+64] ^= self.buffer[i];
        }
        
    }
    
    fn E8(self: *Self) void {
        mem.copy(u4, self.roundconstant[0..], roundconstant_zero[0..]);
        
        self.E8_initialgroup();
        
        var i: usize = 0;
        while (i < 42): (i += 1) {
            self.R8();
            self.update_roundconstant();
        }
        
        self.E8_finaldegroup();        
    }
    
    fn E8_initialgroup(self: *Self) void {
        var t: [4]u1 = undefined;
        var temp: [256]u4 = undefined;
        for (temp) |_, i| {
            var j: usize = 0;
            while (j < 4): (j += 1) {
                t[j] = @truncate(u1, self.H[(i + j*256) >> 3] >> @intCast(u3, (7 - (i & 7))));
            }
            temp[i] = (@as(u4, t[0]) << 3) | (@as(u4, t[1]) << 2) | (@as(u4, t[2]) << 1) | (@as(u4, t[3]) << 0);
        }
        
        for (temp[0..128]) |_, i| {
            const j = i*2;
            self.A[j] = temp[i];
            self.A[j+1] = temp[i + 128];
        }
    }
    
    fn update_roundconstant(self: *Self) void {
        var temp: [64]u4 = undefined;
        var t: u4 = undefined;
        
        for (temp) |_, i| {
            temp[i] = S[0][self.roundconstant[i]];
        }
        
        var i: usize = 0;
        while (i < 64): (i += 2) {
            L(&temp[i], &temp[i+1]);
        }
        
        i = 0;
        while (i < 64): ( i += 4) {
            t = temp[i + 2];
            temp[i + 2] = temp[i + 3];
            temp[i + 3] = t;
        }
        
        i = 0;
        while (i < 32): (i += 1) {
            const j = i*2;
            self.roundconstant[i] = temp[j];
            self.roundconstant[i+32] = temp[j+1];
        }
        
        i=32;
        while (i < 64): ( i += 2) {
            t = self.roundconstant[i];
            self.roundconstant[i] = self.roundconstant[i + 1];
            self.roundconstant[i + 1] = t;
        }
    }
    
    fn E8_finaldegroup(self: *Self) void {
        var t: [4]u1 = undefined;
        var temp: [256]u4 = undefined;
        for (temp[0..128]) |_, i| {
            const j = i*2;
            temp[i] = self.A[j];
            temp[128 + i] = self.A[j+1];
        }
        
        self.H = .{0} ** 128;
        for (temp) |byte, i| {
            var j: usize = 0;
            while (j < 4): (j += 1) {
                t[j] = @truncate(u1, byte >> @intCast(u2, 3 - j));
            }
            j = 0;
            while (j < 4): (j += 1) {
                const shift: u3 = @intCast(u3, 7 - (i % 8));
                self.H[(i + j * 256) >> 3] |= (@as(u8, t[j]) << shift);
            }
        }  
    }
    
    fn R8(self: *Self) void {
        var i: usize = 0;
        var temp: [256]u4 = undefined;
        var t: u4 = undefined;
        var roundconstant_expanded: [256]u1 = undefined;
        while (i < 256): (i += 1) {
            roundconstant_expanded[i] = @truncate(u1, self.roundconstant[i >> 2] >> @intCast(u2, (3 - (i & 3))));
        }
        
        for (temp) |_, j| {
            temp[j] = S[roundconstant_expanded[j]][self.A[j]];
        }
        
        i = 0;
        while (i < 256): (i += 2) {
            L(&temp[i], &temp[i + 1]);
        }
        
        i = 0;
        while (i < 256): (i += 4) {
            t = temp[i + 2];
            temp[i + 2] = temp[i + 3];
            temp[i + 3] = t;
        }
        
        i = 0;
        while (i < 128): (i += 1) {
            const j = i * 2;
            self.A[i] = temp[j];
            self.A[i + 128] = temp[j + 1];
        }
        
        i = 128;
        while (i < 256): (i += 2) {
            t = self.A[i];
            self.A[i] = self.A[i + 1];
            self.A[i + 1] = t;
        }
    }
};

fn L(a: *u4, b: *u4) void {
    b.* ^= ( (a.*) << 1) ^ ( (a.*) >> 3) ^ (( (a.*) >> 2) & 2);
    a.* ^= ( (b.*) << 1) ^ ( (b.*) >> 3) ^ (( (b.*) >> 2) & 2);
}

fn output_224(hash: []u8, string: *[56]u8) void {
    const array = "0123456789abcdef";
    var i: usize = 0;
    while (i < 56): (i += 2) {
        var j = i / 2;
        string[i] = array[@truncate(u4, hash[j] >> 4)];
        string[i + 1] = array[@truncate(u4, hash[j])];
    }
}

fn output_256(hash: []u8, string: *[64]u8) void {
    const array = "0123456789abcdef";
    var i: usize = 0;
    while (i < 64): (i += 2) {
        var j = i / 2;
        string[i] = array[@truncate(u4, hash[j] >> 4)];
        string[i + 1] = array[@truncate(u4, hash[j])];
    }
}

fn output_384(hash: []u8, string: *[96]u8) void {
    const array = "0123456789abcdef";
    var i: usize = 0;
    while (i < 96): (i += 2) {
        var j = i / 2;
        string[i] = array[@truncate(u4, hash[j] >> 4)];
        string[i + 1] = array[@truncate(u4, hash[j])];
    }
}

fn output_512(hash: []u8, string: *[128]u8) void {
    const array = "0123456789abcdef";
    var i: usize = 0;
    while (i < 128): (i += 2) {
        var j = i / 2;
        string[i] = array[@truncate(u4, hash[j] >> 4)];
        string[i + 1] = array[@truncate(u4, hash[j])];
    }
}

const TextPair = struct {
    first: []const u8,
    second: []const u8,
};

test "empty string 224" {
    var input: [128]u8 = .{0} ** 128;
    var processor = JH.init(HashType.HASH_224);
    const result = processor.make_final(&input);
    
    var string: [56]u8 = undefined;
    output_224(result, &string);
    
    const expected: []const u8 = "2c99df889b019309051c60fecc2bd285a774940e43175b76b2626630";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "empty string 256" {
    var input: [128]u8 = .{0} ** 128;
    var processor = JH.init(HashType.HASH_256);
    const result = processor.make_final(&input);
    
    var string: [64]u8 = undefined;
    output_256(result, &string);
    
    const expected: []const u8 = "46e64619c18bb0a92a5e87185a47eef83ca747b8fcc8e1412921357e326df434";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "empty string 384" {
    var input: [128]u8 = .{0} ** 128;
    var processor = JH.init(HashType.HASH_384);
    const result = processor.make_final(&input);
    
    var string: [96]u8 = undefined;
    output_384(result, &string);
    
    const expected: []const u8 = "2fe5f71b1b3290d3c017fb3c1a4d02a5cbeb03a0476481e25082434a881994b0ff99e078d2c16b105ad069b569315328";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "empty string 512" {
    var input: [128]u8 = .{0} ** 128;
    var processor = JH.init(HashType.HASH_512);
    const result = processor.make_final(&input);
    
    var string: [128]u8 = undefined;
    output_512(result, &string);
    
    const expected: []const u8 = "90ecf2f76f9d2c8017d979ad5ab96b87d58fc8fc4b83060f3f900774faa2c8fabe69c5f4ff1ec2b61d6b316941cedee117fb04b1f4c5bc1b919ae841c50eec4f";
    try testing.expectEqualSlices(u8, expected[0..], string[0..]);
}

test "224 test strings" {
    var maps: [2]TextPair = .{
        TextPair{.first = "The quick brown fox jumps over the lazy dog", .second = "6a049fed5fc6874acfdc4a08b568a4f8cbac27de933496f031015b38961608a0"}, 
        TextPair{.first = "The quick brown fox jumps over the lazy dog.", .second = "d001ae2315421c5d3272bac4f4aa524bddd207530d5d26bbf51794f0da18fafc"}
    };
    
    for (maps) |pair| {
        var input: [128]u8 = .{0} ** 128;
        var processor = JH.init(HashType.HASH_256);
        processor.update(pair.first);
        const result = processor.make_final(&input);
        
        var string: [64]u8 = undefined;
        output_256(result, &string);
        
        try testing.expectEqualSlices(u8, pair.second[0..], string[0..]);
    }
    
    
}
