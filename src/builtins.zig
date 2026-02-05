const std = @import("std");
const eval = @import("eval.zig");
const store = @import("store.zig");

const Value = eval.Value;
const Env = eval.Env;

pub fn registerBuiltins(env: *Env) !void {
    // Basic builtins
    try env.define("true", Value{ .bool = true });
    try env.define("false", Value{ .bool = false });
    try env.define("null", Value{ .null_val = {} });

    // Create builtins attrset
    var builtins_set = std.StringHashMap(Value).init(env.allocator);

    // Core type functions
    try builtins_set.put("toString", Value{ .builtin = .{ .name = "toString", .func = builtinToString } });
    try builtins_set.put("typeOf", Value{ .builtin = .{ .name = "typeOf", .func = builtinTypeOf } });
    try builtins_set.put("import", Value{ .builtin = .{ .name = "import", .func = builtinImport } });

    // List functions
    try builtins_set.put("length", Value{ .builtin = .{ .name = "length", .func = builtinLength } });
    try builtins_set.put("head", Value{ .builtin = .{ .name = "head", .func = builtinHead } });
    try builtins_set.put("tail", Value{ .builtin = .{ .name = "tail", .func = builtinTail } });
    try builtins_set.put("elemAt", Value{ .builtin = .{ .name = "elemAt", .func = builtinElemAt } });
    try builtins_set.put("map", Value{ .builtin = .{ .name = "map", .func = builtinMap } });
    try builtins_set.put("filter", Value{ .builtin = .{ .name = "filter", .func = builtinFilter } });
    try builtins_set.put("foldl'", Value{ .builtin = .{ .name = "foldl'", .func = builtinFoldl } });
    try builtins_set.put("concatLists", Value{ .builtin = .{ .name = "concatLists", .func = builtinConcatLists } });
    try builtins_set.put("genList", Value{ .builtin = .{ .name = "genList", .func = builtinGenList } });

    // Attrset functions
    try builtins_set.put("attrNames", Value{ .builtin = .{ .name = "attrNames", .func = builtinAttrNames } });
    try builtins_set.put("attrValues", Value{ .builtin = .{ .name = "attrValues", .func = builtinAttrValues } });
    try builtins_set.put("hasAttr", Value{ .builtin = .{ .name = "hasAttr", .func = builtinHasAttr } });
    try builtins_set.put("getAttr", Value{ .builtin = .{ .name = "getAttr", .func = builtinGetAttr } });
    try builtins_set.put("removeAttrs", Value{ .builtin = .{ .name = "removeAttrs", .func = builtinRemoveAttrs } });
    try builtins_set.put("listToAttrs", Value{ .builtin = .{ .name = "listToAttrs", .func = builtinListToAttrs } });
    try builtins_set.put("intersectAttrs", Value{ .builtin = .{ .name = "intersectAttrs", .func = builtinIntersectAttrs } });
    try builtins_set.put("mapAttrs", Value{ .builtin = .{ .name = "mapAttrs", .func = builtinMapAttrs } });

    // String functions
    try builtins_set.put("stringLength", Value{ .builtin = .{ .name = "stringLength", .func = builtinStringLength } });
    try builtins_set.put("substring", Value{ .builtin = .{ .name = "substring", .func = builtinSubstring } });
    try builtins_set.put("concatStrings", Value{ .builtin = .{ .name = "concatStrings", .func = builtinConcatStrings } });
    try builtins_set.put("concatStringsSep", Value{ .builtin = .{ .name = "concatStringsSep", .func = builtinConcatStringsSep } });
    try builtins_set.put("replaceStrings", Value{ .builtin = .{ .name = "replaceStrings", .func = builtinReplaceStrings } });
    try builtins_set.put("split", Value{ .builtin = .{ .name = "split", .func = builtinSplit } });

    // Comparison and logic
    try builtins_set.put("isNull", Value{ .builtin = .{ .name = "isNull", .func = builtinIsNull } });
    try builtins_set.put("isFunction", Value{ .builtin = .{ .name = "isFunction", .func = builtinIsFunction } });
    try builtins_set.put("isList", Value{ .builtin = .{ .name = "isList", .func = builtinIsList } });
    try builtins_set.put("isAttrs", Value{ .builtin = .{ .name = "isAttrs", .func = builtinIsAttrs } });
    try builtins_set.put("isString", Value{ .builtin = .{ .name = "isString", .func = builtinIsString } });
    try builtins_set.put("isInt", Value{ .builtin = .{ .name = "isInt", .func = builtinIsInt } });
    try builtins_set.put("isBool", Value{ .builtin = .{ .name = "isBool", .func = builtinIsBool } });
    try builtins_set.put("isPath", Value{ .builtin = .{ .name = "isPath", .func = builtinIsPath } });

    // System and derivation
    try builtins_set.put("currentSystem", Value{ .string = store.getCurrentSystem() });
    try builtins_set.put("derivation", Value{ .builtin = .{ .name = "derivation", .func = builtinDerivation } });
    try builtins_set.put("derivationStrict", Value{ .builtin = .{ .name = "derivationStrict", .func = builtinDerivation } });
    try builtins_set.put("placeholder", Value{ .builtin = .{ .name = "placeholder", .func = builtinPlaceholder } });

    // Path operations
    try builtins_set.put("pathExists", Value{ .builtin = .{ .name = "pathExists", .func = builtinPathExists } });
    try builtins_set.put("readFile", Value{ .builtin = .{ .name = "readFile", .func = builtinReadFile } });
    try builtins_set.put("readDir", Value{ .builtin = .{ .name = "readDir", .func = builtinReadDir } });
    try builtins_set.put("toPath", Value{ .builtin = .{ .name = "toPath", .func = builtinToPath } });
    try builtins_set.put("baseNameOf", Value{ .builtin = .{ .name = "baseNameOf", .func = builtinBaseNameOf } });
    try builtins_set.put("dirOf", Value{ .builtin = .{ .name = "dirOf", .func = builtinDirOf } });

    // Fetchers
    try builtins_set.put("fetchurl", Value{ .builtin = .{ .name = "fetchurl", .func = builtinFetchurl } });
    try builtins_set.put("fetchTarball", Value{ .builtin = .{ .name = "fetchTarball", .func = builtinFetchTarball } });
    try builtins_set.put("fetchGit", Value{ .builtin = .{ .name = "fetchGit", .func = builtinFetchGit } });

    // JSON
    try builtins_set.put("toJSON", Value{ .builtin = .{ .name = "toJSON", .func = builtinToJSON } });
    try builtins_set.put("fromJSON", Value{ .builtin = .{ .name = "fromJSON", .func = builtinFromJSON } });

    // Math
    try builtins_set.put("add", Value{ .builtin = .{ .name = "add", .func = builtinAdd } });
    try builtins_set.put("sub", Value{ .builtin = .{ .name = "sub", .func = builtinSub } });
    try builtins_set.put("mul", Value{ .builtin = .{ .name = "mul", .func = builtinMul } });
    try builtins_set.put("div", Value{ .builtin = .{ .name = "div", .func = builtinDiv } });

    // Misc
    try builtins_set.put("seq", Value{ .builtin = .{ .name = "seq", .func = builtinSeq } });
    try builtins_set.put("deepSeq", Value{ .builtin = .{ .name = "deepSeq", .func = builtinDeepSeq } });
    try builtins_set.put("trace", Value{ .builtin = .{ .name = "trace", .func = builtinTrace } });
    try builtins_set.put("throw", Value{ .builtin = .{ .name = "throw", .func = builtinThrow } });
    try builtins_set.put("abort", Value{ .builtin = .{ .name = "abort", .func = builtinAbort } });
    try builtins_set.put("tryEval", Value{ .builtin = .{ .name = "tryEval", .func = builtinTryEval } });

    // Also put common builtins at top level for convenience
    try env.define("toString", Value{ .builtin = .{ .name = "toString", .func = builtinToString } });
    try env.define("typeOf", Value{ .builtin = .{ .name = "typeOf", .func = builtinTypeOf } });
    try env.define("import", Value{ .builtin = .{ .name = "import", .func = builtinImport } });
    try env.define("derivation", Value{ .builtin = .{ .name = "derivation", .func = builtinDerivation } });

    // Register builtins attrset
    try env.define("builtins", Value{ .attrs = .{ .bindings = builtins_set } });
}

fn builtinToString(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;

    const arg = args[0];

    switch (arg) {
        .int => |v| {
            const str = try std.fmt.allocPrint(allocator, "{}", .{v});
            return Value{ .string = str };
        },
        .float => |v| {
            const str = try std.fmt.allocPrint(allocator, "{d}", .{v});
            return Value{ .string = str };
        },
        .bool => |v| return Value{ .string = if (v) "true" else "false" },
        .string => |s| return Value{ .string = s },
        .path => |p| return Value{ .string = p },
        .null_val => return Value{ .string = "null" },
        else => return Value{ .string = "<value>" },
    }
}

fn builtinTypeOf(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;

    const type_name = switch (args[0]) {
        .int => "int",
        .float => "float",
        .bool => "bool",
        .string => "string",
        .path => "path",
        .null_val => "null",
        .list => "list",
        .attrs => "set",
        .lambda => "lambda",
        .builtin => "lambda",
        .thunk => "thunk",
    };

    return Value{ .string = type_name };
}

fn builtinImport(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;

    // Stub: Would need to read file, parse, and evaluate
    std.debug.print("import: stub implementation for {any}\n", .{args[0]});
    return Value{ .null_val = {} };
}

// ============== List functions ==============

fn builtinLength(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .list) return error.TypeError;
    return Value{ .int = @intCast(args[0].list.len) };
}

fn builtinHead(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .list) return error.TypeError;
    if (args[0].list.len == 0) return error.EmptyList;
    return args[0].list[0];
}

fn builtinTail(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .list) return error.TypeError;
    if (args[0].list.len == 0) return error.EmptyList;
    return Value{ .list = args[0].list[1..] };
}

fn builtinElemAt(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[0] != .list) return error.TypeError;
    if (args[1] != .int) return error.TypeError;
    const idx: usize = @intCast(args[1].int);
    if (idx >= args[0].list.len) return error.IndexOutOfBounds;
    return args[0].list[idx];
}

fn builtinMap(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    // map takes a function and a list
    // This is a placeholder - proper implementation needs evaluator access
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[1] != .list) return error.TypeError;
    // Would need to apply function to each element
    return args[1];
}

fn builtinFilter(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[1] != .list) return error.TypeError;
    // Would need to apply predicate to each element
    return args[1];
}

fn builtinFoldl(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 3) return error.InvalidArgCount;
    // builtins.foldl' op init list
    return args[1]; // Return init as placeholder
}

fn builtinConcatLists(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .list) return error.TypeError;

    var total_len: usize = 0;
    for (args[0].list) |inner| {
        if (inner != .list) return error.TypeError;
        total_len += inner.list.len;
    }

    const result = try allocator.alloc(Value, total_len);
    var idx: usize = 0;
    for (args[0].list) |inner| {
        @memcpy(result[idx .. idx + inner.list.len], inner.list);
        idx += inner.list.len;
    }

    return Value{ .list = result };
}

fn builtinGenList(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[1] != .int) return error.TypeError;

    const len: usize = @intCast(args[1].int);
    const result = try allocator.alloc(Value, len);

    for (0..len) |i| {
        result[i] = Value{ .int = @intCast(i) };
    }

    return Value{ .list = result };
}

// ============== Attrset functions ==============

fn builtinAttrNames(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .attrs) return error.TypeError;

    const attrs = args[0].attrs;
    const result = try allocator.alloc(Value, attrs.bindings.count());

    var i: usize = 0;
    var iter = attrs.bindings.iterator();
    while (iter.next()) |entry| {
        result[i] = Value{ .string = entry.key_ptr.* };
        i += 1;
    }

    return Value{ .list = result };
}

fn builtinAttrValues(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .attrs) return error.TypeError;

    const attrs = args[0].attrs;
    const result = try allocator.alloc(Value, attrs.bindings.count());

    var i: usize = 0;
    var iter = attrs.bindings.iterator();
    while (iter.next()) |entry| {
        result[i] = entry.value_ptr.*;
        i += 1;
    }

    return Value{ .list = result };
}

fn builtinHasAttr(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[0] != .string) return error.TypeError;
    if (args[1] != .attrs) return error.TypeError;

    const key = args[0].string;
    return Value{ .bool = args[1].attrs.bindings.contains(key) };
}

fn builtinGetAttr(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[0] != .string) return error.TypeError;
    if (args[1] != .attrs) return error.TypeError;

    const key = args[0].string;
    if (args[1].attrs.bindings.get(key)) |val| {
        return val;
    }
    return error.AttributeNotFound;
}

fn builtinRemoveAttrs(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[0] != .attrs) return error.TypeError;
    if (args[1] != .list) return error.TypeError;

    var new_bindings = std.StringHashMap(Value).init(allocator);
    var iter = args[0].attrs.bindings.iterator();
    while (iter.next()) |entry| {
        var should_remove = false;
        for (args[1].list) |item| {
            if (item == .string and std.mem.eql(u8, item.string, entry.key_ptr.*)) {
                should_remove = true;
                break;
            }
        }
        if (!should_remove) {
            try new_bindings.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    return Value{ .attrs = .{ .bindings = new_bindings } };
}

fn builtinListToAttrs(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .list) return error.TypeError;

    var bindings = std.StringHashMap(Value).init(allocator);

    for (args[0].list) |item| {
        if (item != .attrs) return error.TypeError;
        const name = item.attrs.bindings.get("name") orelse return error.MissingAttribute;
        const value = item.attrs.bindings.get("value") orelse return error.MissingAttribute;
        if (name != .string) return error.TypeError;
        try bindings.put(name.string, value);
    }

    return Value{ .attrs = .{ .bindings = bindings } };
}

fn builtinIntersectAttrs(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[0] != .attrs) return error.TypeError;
    if (args[1] != .attrs) return error.TypeError;

    var bindings = std.StringHashMap(Value).init(allocator);
    var iter = args[1].attrs.bindings.iterator();
    while (iter.next()) |entry| {
        if (args[0].attrs.bindings.contains(entry.key_ptr.*)) {
            try bindings.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    return Value{ .attrs = .{ .bindings = bindings } };
}

fn builtinMapAttrs(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[1] != .attrs) return error.TypeError;
    // Would need evaluator access to apply function
    return args[1];
}

// ============== String functions ==============

fn builtinStringLength(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .string) return error.TypeError;
    return Value{ .int = @intCast(args[0].string.len) };
}

fn builtinSubstring(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 3) return error.InvalidArgCount;
    if (args[0] != .int) return error.TypeError;
    if (args[1] != .int) return error.TypeError;
    if (args[2] != .string) return error.TypeError;

    const start: usize = @intCast(@max(0, args[0].int));
    const len: usize = @intCast(@max(0, args[1].int));
    const str = args[2].string;

    if (start >= str.len) return Value{ .string = "" };
    const end = @min(start + len, str.len);

    return Value{ .string = try allocator.dupe(u8, str[start..end]) };
}

fn builtinConcatStrings(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .list) return error.TypeError;

    var total_len: usize = 0;
    for (args[0].list) |item| {
        if (item != .string) return error.TypeError;
        total_len += item.string.len;
    }

    const result = try allocator.alloc(u8, total_len);
    var idx: usize = 0;
    for (args[0].list) |item| {
        @memcpy(result[idx .. idx + item.string.len], item.string);
        idx += item.string.len;
    }

    return Value{ .string = result };
}

fn builtinConcatStringsSep(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[0] != .string) return error.TypeError;
    if (args[1] != .list) return error.TypeError;

    const sep = args[0].string;
    const list = args[1].list;

    if (list.len == 0) return Value{ .string = "" };

    var total_len: usize = sep.len * (list.len - 1);
    for (list) |item| {
        if (item != .string) return error.TypeError;
        total_len += item.string.len;
    }

    const result = try allocator.alloc(u8, total_len);
    var idx: usize = 0;

    for (list, 0..) |item, i| {
        if (i > 0) {
            @memcpy(result[idx .. idx + sep.len], sep);
            idx += sep.len;
        }
        @memcpy(result[idx .. idx + item.string.len], item.string);
        idx += item.string.len;
    }

    return Value{ .string = result };
}

fn builtinReplaceStrings(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 3) return error.InvalidArgCount;
    if (args[0] != .list) return error.TypeError;
    if (args[1] != .list) return error.TypeError;
    if (args[2] != .string) return error.TypeError;

    var result = try allocator.dupe(u8, args[2].string);

    for (args[0].list, 0..) |from, i| {
        if (from != .string) return error.TypeError;
        if (i >= args[1].list.len) break;
        const to = args[1].list[i];
        if (to != .string) return error.TypeError;

        // Simple replacement (could be more efficient)
        var new_result: std.ArrayList(u8) = .empty;
        var j: usize = 0;
        while (j < result.len) {
            if (j + from.string.len <= result.len and
                std.mem.eql(u8, result[j .. j + from.string.len], from.string))
            {
                try new_result.appendSlice(allocator, to.string);
                j += from.string.len;
            } else {
                try new_result.append(allocator, result[j]);
                j += 1;
            }
        }
        allocator.free(result);
        result = try new_result.toOwnedSlice(allocator);
    }

    return Value{ .string = result };
}

fn builtinSplit(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[0] != .string) return error.TypeError;
    if (args[1] != .string) return error.TypeError;

    // Simplified split - not regex
    const sep = args[0].string;
    const str = args[1].string;

    var parts: std.ArrayList(Value) = .empty;
    var iter = std.mem.splitSequence(u8, str, sep);
    while (iter.next()) |part| {
        try parts.append(allocator, Value{ .string = try allocator.dupe(u8, part) });
    }

    return Value{ .list = try parts.toOwnedSlice(allocator) };
}

// ============== Type checking functions ==============

fn builtinIsNull(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    return Value{ .bool = args[0] == .null_val };
}

fn builtinIsFunction(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    return Value{ .bool = args[0] == .lambda or args[0] == .builtin };
}

fn builtinIsList(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    return Value{ .bool = args[0] == .list };
}

fn builtinIsAttrs(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    return Value{ .bool = args[0] == .attrs };
}

fn builtinIsString(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    return Value{ .bool = args[0] == .string };
}

fn builtinIsInt(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    return Value{ .bool = args[0] == .int };
}

fn builtinIsBool(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    return Value{ .bool = args[0] == .bool };
}

fn builtinIsPath(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    return Value{ .bool = args[0] == .path };
}

// ============== Derivation functions ==============

fn builtinDerivation(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .attrs) return error.TypeError;

    const input_attrs = args[0].attrs;

    // Extract required attributes
    const name = input_attrs.bindings.get("name") orelse return error.MissingAttribute;
    const system = input_attrs.bindings.get("system") orelse return error.MissingAttribute;
    const builder = input_attrs.bindings.get("builder") orelse return error.MissingAttribute;

    if (name != .string) return error.TypeError;
    if (system != .string) return error.TypeError;
    if (builder != .string and builder != .path) return error.TypeError;

    // Create derivation
    var drv = store.Derivation.init(allocator);
    drv.name = name.string;
    drv.system = system.string;
    drv.builder = if (builder == .string) builder.string else builder.path;

    // Extract args if present
    if (input_attrs.bindings.get("args")) |args_val| {
        if (args_val == .list) {
            const drv_args = try allocator.alloc([]const u8, args_val.list.len);
            for (args_val.list, 0..) |arg, i| {
                if (arg == .string) {
                    drv_args[i] = arg.string;
                } else {
                    drv_args[i] = "";
                }
            }
            drv.args = drv_args;
        }
    }

    // Compute store path
    const store_path = try drv.computeStorePath(allocator);
    const out_path = try store_path.toPath(allocator);

    // Build result attrset
    var result_bindings = std.StringHashMap(Value).init(allocator);
    try result_bindings.put("type", Value{ .string = "derivation" });
    try result_bindings.put("name", name);
    try result_bindings.put("system", system);
    try result_bindings.put("builder", builder);
    try result_bindings.put("outPath", Value{ .path = out_path });
    try result_bindings.put("drvPath", Value{ .path = out_path });

    // Copy through other attributes
    var iter = input_attrs.bindings.iterator();
    while (iter.next()) |entry| {
        if (!result_bindings.contains(entry.key_ptr.*)) {
            try result_bindings.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    return Value{ .attrs = .{ .bindings = result_bindings } };
}

fn builtinPlaceholder(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .string) return error.TypeError;
    // Return a placeholder string that will be replaced during build
    return Value{ .string = try std.fmt.allocPrint(allocator, "/nix/store/placeholder-{s}", .{args[0].string}) };
}

// ============== Path functions ==============
// NOTE: Path functions are currently stubbed as they require IO handle
// which the builtins API doesn't support yet

fn builtinPathExists(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    _ = switch (args[0]) {
        .path => |p| p,
        .string => |s| s,
        else => return error.TypeError,
    };

    // TODO: Implement with proper IO handle
    return Value{ .bool = false };
}

fn builtinReadFile(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    _ = switch (args[0]) {
        .path => |p| p,
        .string => |s| s,
        else => return error.TypeError,
    };

    // TODO: Implement with proper IO handle
    return error.NotImplemented;
}

fn builtinReadDir(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;
    _ = switch (args[0]) {
        .path => |p| p,
        .string => |s| s,
        else => return error.TypeError,
    };

    // TODO: Implement with proper IO handle
    const bindings = std.StringHashMap(Value).init(allocator);
    return Value{ .attrs = .{ .bindings = bindings } };
}

fn builtinToPath(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .string) return error.TypeError;
    return Value{ .path = args[0].string };
}

fn builtinBaseNameOf(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    const path = switch (args[0]) {
        .path => |p| p,
        .string => |s| s,
        else => return error.TypeError,
    };

    const basename = std.fs.path.basename(path);
    return Value{ .string = basename };
}

fn builtinDirOf(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;
    const path = switch (args[0]) {
        .path => |p| p,
        .string => |s| s,
        else => return error.TypeError,
    };

    const dirname = std.fs.path.dirname(path) orelse ".";
    return Value{ .path = try allocator.dupe(u8, dirname) };
}

// ============== JSON functions ==============

fn builtinToJSON(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;

    var result: std.ArrayList(u8) = .empty;
    try valueToJson(allocator, args[0], &result);

    return Value{ .string = try result.toOwnedSlice(allocator) };
}

fn valueToJson(allocator: std.mem.Allocator, value: Value, result: *std.ArrayList(u8)) !void {
    switch (value) {
        .null_val => try result.appendSlice(allocator, "null"),
        .bool => |b| try result.appendSlice(allocator, if (b) "true" else "false"),
        .int => |i| {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{}", .{i}) catch unreachable;
            try result.appendSlice(allocator, s);
        },
        .float => |f| {
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch unreachable;
            try result.appendSlice(allocator, s);
        },
        .string, .path => |s| {
            try result.append(allocator, '"');
            for (s) |c| {
                switch (c) {
                    '"' => try result.appendSlice(allocator, "\\\""),
                    '\\' => try result.appendSlice(allocator, "\\\\"),
                    '\n' => try result.appendSlice(allocator, "\\n"),
                    '\r' => try result.appendSlice(allocator, "\\r"),
                    '\t' => try result.appendSlice(allocator, "\\t"),
                    else => try result.append(allocator, c),
                }
            }
            try result.append(allocator, '"');
        },
        .list => |l| {
            try result.append(allocator, '[');
            for (l, 0..) |item, i| {
                if (i > 0) try result.append(allocator, ',');
                try valueToJson(allocator, item, result);
            }
            try result.append(allocator, ']');
        },
        .attrs => |a| {
            try result.append(allocator, '{');
            var iter = a.bindings.iterator();
            var first = true;
            while (iter.next()) |entry| {
                if (!first) try result.append(allocator, ',');
                first = false;
                try result.append(allocator, '"');
                try result.appendSlice(allocator, entry.key_ptr.*);
                try result.appendSlice(allocator, "\":");
                try valueToJson(allocator, entry.value_ptr.*, result);
            }
            try result.append(allocator, '}');
        },
        .lambda, .builtin, .thunk => try result.appendSlice(allocator, "null"),
    }
}

fn builtinFromJSON(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .string) return error.TypeError;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args[0].string, .{});
    defer parsed.deinit();

    return try jsonToValue(allocator, parsed.value);
}

fn jsonToValue(allocator: std.mem.Allocator, json: std.json.Value) !Value {
    return switch (json) {
        .null => Value{ .null_val = {} },
        .bool => |b| Value{ .bool = b },
        .integer => |i| Value{ .int = i },
        .float => |f| Value{ .float = f },
        .string => |s| Value{ .string = try allocator.dupe(u8, s) },
        .array => |arr| {
            const values = try allocator.alloc(Value, arr.items.len);
            for (arr.items, 0..) |item, i| {
                values[i] = try jsonToValue(allocator, item);
            }
            return Value{ .list = values };
        },
        .object => |obj| {
            var bindings = std.StringHashMap(Value).init(allocator);
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                try bindings.put(
                    try allocator.dupe(u8, entry.key_ptr.*),
                    try jsonToValue(allocator, entry.value_ptr.*),
                );
            }
            return Value{ .attrs = .{ .bindings = bindings } };
        },
        else => Value{ .null_val = {} },
    };
}

// ============== Math functions ==============

fn builtinAdd(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[0] == .int and args[1] == .int) {
        return Value{ .int = args[0].int + args[1].int };
    }
    return error.TypeError;
}

fn builtinSub(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[0] == .int and args[1] == .int) {
        return Value{ .int = args[0].int - args[1].int };
    }
    return error.TypeError;
}

fn builtinMul(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[0] == .int and args[1] == .int) {
        return Value{ .int = args[0].int * args[1].int };
    }
    return error.TypeError;
}

fn builtinDiv(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    if (args[0] == .int and args[1] == .int) {
        if (args[1].int == 0) return error.DivisionByZero;
        return Value{ .int = @divTrunc(args[0].int, args[1].int) };
    }
    return error.TypeError;
}

// ============== Misc functions ==============

fn builtinSeq(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    // Force evaluation of first arg (already done), return second
    return args[1];
}

fn builtinDeepSeq(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;
    // Would need to recursively force first arg
    return args[1];
}

fn builtinTrace(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 2) return error.InvalidArgCount;

    // Print the trace message
    switch (args[0]) {
        .string => |s| std.debug.print("trace: {s}\n", .{s}),
        else => std.debug.print("trace: {any}\n", .{args[0]}),
    }

    return args[1];
}

fn builtinThrow(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .string) return error.TypeError;

    std.debug.print("error: {s}\n", .{args[0].string});
    return error.ThrownError;
}

fn builtinAbort(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;
    if (args[0] != .string) return error.TypeError;

    std.debug.print("abort: {s}\n", .{args[0].string});
    return error.Aborted;
}

fn builtinTryEval(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    if (args.len != 1) return error.InvalidArgCount;

    // In a proper implementation, this would catch errors during evaluation
    // For now, just return success
    var bindings = std.StringHashMap(Value).init(allocator);
    try bindings.put("success", Value{ .bool = true });
    try bindings.put("value", args[0]);

    return Value{ .attrs = .{ .bindings = bindings } };
}

fn builtinFetchurl(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;

    std.debug.print("TODO: fetchurl (stubbed)\n", .{});
    return Value{ .path = "/tmp/stub-fetchurl" };
}

fn builtinFetchTarball(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;

    std.debug.print("TODO: fetchTarball (stubbed)\n", .{});
    return Value{ .path = "/tmp/stub-fetchtarball" };
}

fn builtinFetchGit(io: std.Io, allocator: std.mem.Allocator, args: []Value) !Value {
    _ = io;
    _ = io;
    _ = allocator;
    if (args.len != 1) return error.InvalidArgCount;

    std.debug.print("TODO: fetchGit (stubbed)\n", .{});
    return Value{ .path = "/tmp/stub-fetchgit" };
}
