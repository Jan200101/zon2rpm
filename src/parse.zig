const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const File = std.fs.File;
const Index = std.zig.Ast.Node.Index;
const StringHashMap = std.StringHashMap;
const fs = std.fs;
const mem = std.mem;
const string_literal = std.zig.string_literal;

const ZonDependency = struct {
    url: []const u8,
    hash: []const u8,
};

const ZonData = struct {
    name: []const u8,
    version: []const u8,
    dependencies: StringHashMap(ZonDependency),
};

pub fn findZon(dir: fs.Dir, path: []const u8) !File {
    const path_stat = try dir.statFile(path);

    return switch (path_stat.kind) {
        .directory => (try dir.openDir(path, .{})).openFile("build.zig.zon", .{}),
        .file => dir.openFile(path, .{}),
        else => error.invalidKind,
    } catch |err| {
        std.debug.print("Failed to read zon ({})\n", .{err});
        return error.invalidPath;
    };
}

pub fn parse(alloc: Allocator, dir: fs.Dir, file: File) !ZonData {
    const content = try alloc.allocSentinel(u8, try file.getEndPos(), 0);
    _ = try file.reader().readAll(content);

    const ast = try Ast.parse(alloc, content, .zon);

    var buf: [2]Index = undefined;
    const root_init = ast.fullStructInit(&buf, ast.nodes.items(.data)[0].lhs) orelse {
        return error.ParseError;
    };

    var data = ZonData{
        .name = undefined,
        .version = undefined,
        .dependencies = StringHashMap(ZonDependency).init(alloc),
    };
    for (root_init.ast.fields) |field_idx| {
        const field_name = try parseFieldName(alloc, ast, field_idx);
        if (mem.eql(u8, field_name, "name")) {
            data.name = try parseString(alloc, ast, field_idx);
        } else if (mem.eql(u8, field_name, "version")) {
            data.version = try parseString(alloc, ast, field_idx);
        } else if (mem.eql(u8, field_name, "dependencies")) {
            const deps_init = ast.fullStructInit(&buf, field_idx) orelse {
                return error.ParseError;
            };

            for (deps_init.ast.fields) |dep_idx| {
                const dep_name = try parseFieldName(alloc, ast, dep_idx);
                var url: ?[]const u8 = null;
                var hash: ?[]const u8 = null;

                var dep_buf: [2]Index = undefined;
                const dep_init = ast.fullStructInit(&dep_buf, dep_idx) orelse {
                    return error.parseError;
                };

                for (dep_init.ast.fields) |dep_field_idx| {
                    const name = try parseFieldName(alloc, ast, dep_field_idx);

                    if (mem.eql(u8, name, "path")) {
                        const path = try parseString(alloc, ast, dep_field_idx);

                        const zon_dir = try dir.openDir(path, .{});
                        const zon_file = findZon(zon_dir, "build.zig.zon") catch continue;

                        const zon_data = try parse(alloc, zon_dir, zon_file);

                        var iter = zon_data.dependencies.iterator();
                        while (iter.next()) |dep| {
                            try data.dependencies.put(dep.key_ptr.*, dep.value_ptr.*);
                        }

                    } else if (mem.eql(u8, name, "url")) {
                        url = try parseString(alloc, ast, dep_field_idx);
                    } else if (mem.eql(u8, name, "hash")) {
                        hash = try parseString(alloc, ast, dep_field_idx);
                    }
                }

                if (url) |dep_url| {
                    if (hash) |dep_hash| {
                       try data.dependencies.putNoClobber(dep_name, .{
                            .url = dep_url,
                            .hash = dep_hash,
                        });
                    } else {
                        std.debug.print("unsuited dependency {s}\n", .{dep_url});
                    }
                }
            }
        }
    }

    return data;
}

fn parseFieldName(alloc: Allocator, ast: Ast, idx: Index) ![]const u8 {
    const name = ast.tokenSlice(ast.firstToken(idx) - 2);
    return if (name[0] == '@') string_literal.parseAlloc(alloc, name[1..]) else name;
}

fn parseString(alloc: Allocator, ast: Ast, idx: Index) ![]const u8 {
    return string_literal.parseAlloc(alloc, ast.tokenSlice(ast.nodes.items(.main_token)[idx]));
}
