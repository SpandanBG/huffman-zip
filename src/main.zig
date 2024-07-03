const std = @import("std");

const Allocator = std.mem.Allocator;

const RunType = enum {
    Encode,
    Decode,
    None,
};

const encode_flag = "-e";
const decode_flag = "-d";

pub fn main() !void {
    switch (try get_run_type()) {
        .Encode => try encode(),
        .Decode => try decode(),
        else => invalid_cmd(),
    }
}

fn get_run_type() !RunType {
    const allocator = std.heap.page_allocator;
    var args_iter = try std.process.ArgIterator.initWithAllocator(allocator);

    _ = args_iter.next(); // skip first arg
    const run_type = args_iter.next() orelse return RunType.None;

    if (std.mem.eql(u8, encode_flag, run_type)) {
        return RunType.Encode;
    } else if (std.mem.eql(u8, decode_flag, run_type)) {
        return RunType.Decode;
    }

    return RunType.None;
}

fn encode() !void {
    var in = std.io.getStdIn();
    defer in.close();

    var out = std.io.getStdOut();
    defer out.close();

    var data = try read_in(in);
    defer data.deinit();

    try build_huffman_tree(data);
}

fn decode() !void {}

const size_pair = struct {
    size: u64,
    char: u8,

    const Self = @This();

    fn lt(_: void, a: Self, b: Self) bool {
        return a.size < b.size;
    }
};

fn build_huffman_tree(data: std.ArrayList(u8)) !void {
    const allocator = std.heap.page_allocator;

    // ------------ count chars
    var all_ascii = std.mem.zeroes([128]u64);
    var unique_chars: usize = 0;

    for (data.items) |ch| {
        const char = @as(usize, ch);
        if (all_ascii[char] == 0) unique_chars += 1;
        all_ascii[char] += 1;
    }
    // -------------------------

    // ------------ create sorted count-char pairs
    var pairs = try allocator.alloc(size_pair, unique_chars);
    defer allocator.free(pairs);

    var pi: usize = 0;
    for (all_ascii, 0..) |size, i| {
        if (size == 0) continue;
        const ch: u8 = @intCast(i);
        pairs[pi] = .{ .size = size, .char = ch };
        pi += 1;
    }

    std.sort.insertion(size_pair, pairs[0..], {}, size_pair.lt);
    // ----------------------------
}

fn read_in(in: std.fs.File) !std.ArrayList(u8) {
    var data = std.ArrayList(u8).init(std.heap.page_allocator);
    var char_buff: [1:0]u8 = undefined;

    while (true) {
        const read = try in.read(&char_buff);
        if (read == 0) break;
        try data.append(char_buff[0]);
    }

    return data;
}

fn invalid_cmd() void {
    std.log.err(
        \\invalid arg
        \\
        \\usage: <input> | zig build run -- (-e|-d) > <output>
        \\      -e      encode
        \\      -d      decode
    , .{});
}
