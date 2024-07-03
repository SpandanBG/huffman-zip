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
    _ = root.dfs(@as(u8, 0), 0);
}

fn decode() !void {}

const node = struct {
    size: u64,
    char: ?u8,

    left: ?*node,
    right: ?*node,

    const Self = @This();

    fn lt(_: void, a: *Self, b: *Self) bool {
        return a.size < b.size;
    }

    fn dfs(self: *Self, char: u8, bin: u64) ?u64 {
        if (self.char) |c| {
            // std.log.debug("({d})-{b}", .{ self.char.?, bin });
            return if (c == char) bin else null;
        }

        // std.log.debug("in-{b}", .{bin});

        const n_bin = bin << 1;

        // std.log.err("left <_<", .{});
        if (self.left) |l| if (l.dfs(char, n_bin)) |left_bin| {
            return left_bin;
        };

        // std.log.err("right >_>", .{});
        if (self.right) |r| if (r.dfs(char, n_bin + 1)) |right_bin| {
            return right_bin;
        };

        // std.log.err("exit in-{b}", .{bin});
        return null;
    }
};

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

        const first_node = min_queue[qi];
        const second_node = min_queue[qi + 1];

        internal_node.size = first_node.size + second_node.size;

        if (node.lt({}, first_node, second_node)) {
            internal_node.left = first_node;
            internal_node.right = second_node;
        } else {
            internal_node.left = second_node;
            internal_node.right = first_node;
        }

        min_queue[qi + 1] = internal_node;
        std.sort.insertion(*node, min_queue, {}, node.lt);

        qi += 1;
    }

    const root = min_queue[min_queue.len - 1];
    // -------------------------

    return root;
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
