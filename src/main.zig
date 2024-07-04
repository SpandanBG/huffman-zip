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

    const root = try build_huffman_tree(data);

    var memo = std.AutoHashMap(u8, node.ctx).init(std.heap.page_allocator);
    defer memo.deinit();

    var encoded_buff = std.ArrayList(u8).init(std.heap.page_allocator);
    defer encoded_buff.deinit();

    var curr_byte: u64 = 0;
    var bit_len: u64 = 0;

    for (data.items) |char| {
        const ctx: node.ctx = memo.get(char) orelse blk: {
            const c = get_huff_encoding(root, char) orelse unreachable;
            try memo.put(char, c);
            break :blk c;
        };

        if (bit_len == 8) {
            try encoded_buff.append(@intCast(curr_byte));
            curr_byte = 0;
            bit_len = 0;
        }

        var encoding = ctx.encoding;
        var encoding_len = ctx.depth;

        if (bit_len + encoding_len <= 8) {
            curr_byte = (curr_byte << @intCast(encoding_len)) + encoding;
            bit_len += encoding_len;
            continue;
        }

        while (bit_len + encoding_len > 8) {
            const push_len = 8 - bit_len;
            const left_over_len = encoding_len - push_len;

            const push_encoding = encoding >> @intCast(left_over_len);
            const left_over_encoding = (push_encoding << @intCast(left_over_len)) ^ encoding;

            curr_byte = (curr_byte << @intCast(push_len)) + push_encoding;
            try encoded_buff.append(@intCast(curr_byte));

            if (left_over_len <= 8) {
                curr_byte = left_over_encoding;
                bit_len = left_over_len;
                break;
            }

            encoding = left_over_encoding;
            encoding_len = left_over_len;
            curr_byte = 0;
            bit_len = 0;
        }
    }

    var truncate_len: u8 = 0; // the number of bits to be truncated when decompressing
    if (bit_len > 0) {
        truncate_len = @intCast(8 - bit_len);
        curr_byte <<= @intCast(truncate_len);
        try encoded_buff.append(@intCast(curr_byte));
    }

    var tree_map = std.ArrayList(u8).init(std.heap.page_allocator);
    defer tree_map.deinit();

    var memoIter = memo.iterator();
    while (memoIter.next()) |item| {
        try tree_map.append(@intCast(item.key_ptr.*));
        const index_of_size = tree_map.items.len;
        try tree_map.append(0); // placeholder for size
        var size: u8 = 0;
        for (split_u64_to_u8s(item.value_ptr.encoding)) |ue| {
            if (ue == 0) continue;
            size += 1;
            try tree_map.append(ue);
        }
        if (size == 0) try tree_map.append(0);
        tree_map.items[index_of_size] = if (size == 0) 1 else size;
    }

    // ---------------- Write To File
    var wrote = try out.write(&[_]u8{truncate_len});
    wrote += try out.write(tree_map.items);
    wrote += try out.write(encoded_buff.items);
}

fn decode() !void {}

const node = struct {
    size: u64,
    char: ?u8,

    left: ?*node,
    right: ?*node,

    // must be initialized all 0. index should be marked 1 if present in the
    // left node. 2 if present in the right node
    char_map: [128]u2,

    const ctx = struct {
        encoding: u64,
        depth: u64,
    };

    const Self = @This();

    fn lt(_: void, a: *Self, b: *Self) bool {
        return a.size < b.size;
    }

    fn dfs(self: *Self, char: u8, encoding: u64, depth: u64) ?ctx {
        if (self.char) |c| {
            return if (c == char) .{
                .encoding = encoding,
                .depth = depth,
            } else null;
        }

        const n_encoding = encoding << 1;

        if (self.char_map[@intCast(char)] == 1) {
            if (self.left) |l| return l.dfs(char, n_encoding, depth + 1);
        }

        if (self.char_map[@intCast(char)] == 2) {
            if (self.right) |r| return r.dfs(char, n_encoding + 1, depth + 1);
        }

        return null;
    }
};

fn get_huff_encoding(root: *node, char: u8) ?node.ctx {
    return root.dfs(char, 0, 0);
}

fn build_huffman_tree(data: std.ArrayList(u8)) !*node {
    const allocator = std.heap.page_allocator;

    // ------------ count chars
    var all_ascii = std.mem.zeroes([128]u64);
    var unique_chars: usize = 0;

    for (data.items) |ch| {
        const char = @as(usize, ch);
        if (all_ascii[char] == 0) unique_chars += 1;
        all_ascii[char] += 1;
    }
    // ------------------------

    // ------------ create min queue
    var min_queue = try allocator.alloc(*node, unique_chars);
    defer allocator.free(min_queue);

    var qi: usize = 0; // queue index
    for (all_ascii, 0..) |size, i| {
        if (size == 0) continue;
        const ch: u8 = @intCast(i);

        var nn = try allocator.create(node);
        nn.size = size;
        nn.char = ch;
        nn.char_map = std.mem.zeroes([128]u2);
        nn.char_map[i] = 1;

        min_queue[qi] = nn;
        qi += 1;
    }

    std.sort.insertion(*node, min_queue, {}, node.lt);
    // -----------------------------

    // ------------- create tree
    qi = 0;
    while (qi < min_queue.len) {
        if (min_queue.len - qi <= 1) break;

        var internal_node = try allocator.create(node);
        internal_node.char = null;
        internal_node.char_map = std.mem.zeroes([128]u2);

        const first_node = min_queue[qi];
        const second_node = min_queue[qi + 1];

        internal_node.size = first_node.size + second_node.size;

        if (node.lt({}, first_node, second_node)) {
            internal_node.left = first_node;
            for (first_node.char_map, 0..) |c, i| if (c > 0) {
                internal_node.char_map[i] = 1;
            };

            internal_node.right = second_node;
            for (second_node.char_map, 0..) |c, i| if (c > 0) {
                internal_node.char_map[i] = 2;
            };
        } else {
            internal_node.left = second_node;
            for (second_node.char_map, 0..) |c, i| if (c > 0) {
                internal_node.char_map[i] = 1;
            };

            internal_node.right = first_node;
            for (first_node.char_map, 0..) |c, i| if (c > 0) {
                internal_node.char_map[i] = 2;
            };
        }

        min_queue[qi + 1] = internal_node;
        std.sort.insertion(*node, min_queue, {}, node.lt);

        qi += 1;
    }

    const root = min_queue[min_queue.len - 1];
    // -------------------------

    return root;
}

fn split_u64_to_u8s(value: u64) [8]u8 {
    return [_]u8{
        @intCast(value >> 56),
        @intCast(value >> 48),
        @intCast(value >> 40),
        @intCast(value >> 32),
        @intCast(value >> 24),
        @intCast(value >> 16),
        @intCast(value >> 8),
        @intCast(value),
    };
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
