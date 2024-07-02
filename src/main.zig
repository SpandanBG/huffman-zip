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
}

fn decode() !void {}

fn invalid_cmd() void {
    std.log.err("invalid arg\nusage: (-e|-d)\n\t-e\tencode input\n\t-d\tdecode input", .{});
}
