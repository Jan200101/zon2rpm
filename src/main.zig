const std = @import("std");
const StringHashMap = std.StringHashMap;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const process = std.process;

const parse = @import("parse.zig").parse;
const findZon = @import("parse.zig").findZon;

const Options = enum {
    BuildRequires,
    Show,
    Spec
};

pub fn main() !void {
    var args = process.args();
    _ = args.skip();

    const option = if (args.next()) |option|
        if (std.mem.eql(u8, option, "buildrequires"))
            Options.BuildRequires
        else if (std.mem.eql(u8, option, "show"))
            Options.Show
        else if (std.mem.eql(u8, option, "spec"))
            Options.Spec
        else
            null
    else
        null;

    if (option == null) {
        std.debug.print("No valid option given\n", .{});
        return error.invalidOption;
    }

    const path = args.next();
    if (path == null) {
        std.debug.print("No valid option given\n", .{});
        return error.invalidOption;
    }

    try std.posix.chdir(path.?);

    const dir = fs.cwd();
    const file = try findZon(dir, "build.zig.zon");
    defer file.close();

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const data = try parse(alloc, dir, file);

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    switch (option.?) {
        .BuildRequires => {
            var iter = data.dependencies.valueIterator();
            while (iter.next()) |dep| {
                try stdout.print("zig({s})\n", .{dep.hash});
            }
        },

        .Show => {
            var iter = data.dependencies.iterator();
            while (iter.next()) |dep| {
                try stdout.print("{s} => {s}\n", .{dep.key_ptr.*, dep.value_ptr.hash});
            }
        },

        .Spec => {
            var iter = data.dependencies.valueIterator();
            var i: u8 = 1;
            while (iter.next()) |dep| : (i += 1) {
                try stdout.print("Source{}: {s}\n", .{i, dep.url});
            }
        },
    }
    try bw.flush();
}

comptime {
    std.testing.refAllDecls(@This());
}
