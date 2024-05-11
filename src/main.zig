const std = @import("std");
const StringHashMap = std.StringHashMap;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const process = std.process;

const parse = @import("parse.zig").parse;

const Options = enum {
    BuildRequires,
};

pub fn main() !void {
    var args = process.args();
    _ = args.skip();
    const dir = fs.cwd();

    const option = if (args.next()) |option|
        if (std.mem.eql(u8, option, "buildrequires"))
            Options.BuildRequires
        else
            null
    else
        null;

    if (option == null) {
        std.debug.print("No valid option given\n", .{});
        return error.invalidOption;
    }

    const file = try if (args.next()) |path| blk: {
        const path_stat = dir.statFile(path) catch |err| {
            std.debug.print("Failed to stat given path ({})\n", .{err});
            return error.invalidPath;
        };

        break :blk switch (path_stat.kind) {
            .directory => (try dir.openDir(path, .{})).openFile("build.zig.zon", .{}),
            .file => dir.openFile(path, .{}),
            else => error.invalidKind,
        } catch |err| {
            std.debug.print("Failed to read zon ({})\n", .{err});
            return error.invalidPath;
        };
    } else dir.openFile("build.zig.zon", .{});
    defer file.close();

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const data = parse(alloc, file) catch |err| {
        std.debug.print("Failed to parse zon ({})\n", .{err});
        return;
    };

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
    }
    try bw.flush();
}

comptime {
    std.testing.refAllDecls(@This());
}
