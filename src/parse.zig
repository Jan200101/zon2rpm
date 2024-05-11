const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const File = std.fs.File;
const Index = std.zig.Ast.Node.Index;
const StringHashMap = std.StringHashMap;
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

pub fn parse(alloc: Allocator, file: File) !ZonData {
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
                var dep: ZonDependency = .{
                    .url = undefined,
                    .hash = undefined,
                };
                var has_url = false;
                var has_hash = false;

                var dep_buf: [2]Index = undefined;
                const dep_init = ast.fullStructInit(&dep_buf, dep_idx) orelse {
                    return error.parseError;
                };

                for (dep_init.ast.fields) |dep_field_idx| {
                    const name = try parseFieldName(alloc, ast, dep_field_idx);

                    if (mem.eql(u8, name, "url")) {
                        dep.url = try parseString(alloc, ast, dep_field_idx);
                        has_url = true;
                    } else if (mem.eql(u8, name, "hash")) {
                        dep.hash = try parseString(alloc, ast, dep_field_idx);
                        has_hash = true;
                    }
                }

                if (has_url and has_hash) {
                    try data.dependencies.putNoClobber(dep.hash, dep);
                } else {
                    return error.parseError;
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
