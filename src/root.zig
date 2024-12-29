const std = @import("std");
const builtin = @import("builtin");
const io = std.io;
const PatienceDiff = @import("PatienceDiff.zig");

inline fn getContext() std.debug.ThreadContext {
    var context: std.debug.ThreadContext = undefined;
    std.debug.assert(std.debug.getContext(&context));
    return context;
}
const StackIter = struct {
    address_iterator: std.debug.StackIterator,
    debug_info: *std.debug.SelfInfo,
    tty_config: io.tty.Config,
    pub fn init() !StackIter {
        const debug_info = try std.debug.getSelfDebugInfo();
        const tty_config = io.tty.detectConfig(io.getStdErr());

        var context: std.debug.ThreadContext = undefined;
        const has_context = std.debug.getContext(&context);
        const it = (if (has_context) blk: {
            break :blk std.debug.StackIterator.initWithContext(null, debug_info, &context) catch null;
        } else null) orelse std.debug.StackIterator.init(null, null);
        return .{
            .address_iterator = it,
            .debug_info = debug_info,
            .tty_config = tty_config,
        };
    }
    pub fn deinit(self: *StackIter) void {
        self.address_iterator.deinit();
    }

    const Entry = struct {
        return_address: usize,
        module: *std.debug.SelfInfo.Module,
        symbol_info: std.debug.Symbol,
    };

    pub fn next(self: *StackIter) !?Entry {
        const return_address = self.address_iterator.next() orelse return null;
        const address = return_address -| 1;

        const module = try self.debug_info.getModuleForAddress(address);
        const symbol_info = try module.getSymbolAtAddress(self.debug_info.allocator, address);
        return .{
            .return_address = address,
            .module = module,
            .symbol_info = symbol_info,
        };
    }
};
fn expectType(comptime T: type, actual: anytype, strict: bool) !void {
    _ = strict; // autofix
    const ActualType = @TypeOf(actual);

    const ok = T == ActualType;
    if (!ok) {
        // @compileLog("aaaa\n\n\n\n");
        const GREEN = "\x1b[32m";
        const RED = "\x1b[31m";
        const RESET = "\x1b[0m";

        const msg = std.fmt.comptimePrint("\n\n" ++ RESET ++ "Expected type: " ++ GREEN ++ "{any}" ++ RESET ++ "\nReceived type: " ++ RED ++ "{any}" ++ RESET ++ "\n", .{ T, ActualType });

        @compileError(msg);
        // return error.TestUnexpectedResult;
    }
}
const assert = std.debug.assert;

const testing = std.testing;

fn Matchers(comptime T: type) type {
    const stderr = io.getStdErr().writer().any();
    return struct {
        expected: T,
        is_not: bool = false,
        not: *const Self = undefined,
        const Self = @This();

        pub fn toBe(self: Self, actual: T) !void {
            const tty_config = io.tty.detectConfig(io.getStdErr());
            if (self.is_not) {
                testing.expect(self.expected != actual) catch |err| {
                    try stderr.writeAll("...\n");
                    try stderr.writeAll("\nExpected not: ");
                    try tty_config.setColor(stderr, .red);
                    try stderr.print("{any}\n\n", .{self.expected});
                    try tty_config.setColor(stderr, .reset);
                    return err;
                };
            } else {
                testing.expect(self.expected == actual) catch |err| {
                    try stderr.writeAll("...\n");
                    try stderr.writeAll("\nExpected: ");
                    try tty_config.setColor(stderr, .red);
                    try stderr.print("{any}\n", .{self.expected});
                    try tty_config.setColor(stderr, .reset);
                    try stderr.writeAll("Received: ");
                    try tty_config.setColor(stderr, .green);
                    try stderr.print("{any}\n\n", .{actual});
                    try tty_config.setColor(stderr, .reset);
                    return err;
                };
            }
        }
        fn isOptional(Type: type) bool {
            return switch (@typeInfo(Type)) {
                .optional => true,
                else => false,
            };
        }
        fn UnwrapType(Type: type) type {
            return switch (@typeInfo(Type)) {
                .optional => |info| info.child,
                else => Type,
            };
        }
        fn unwrap(value: anytype) !UnwrapType(@TypeOf(value)) {
            if (isOptional(@TypeOf(value))) {
                try std.testing.expect(value != null);
                return value.?;
            }
            return value;
            // return switch (@typeInfo(@TypeOf(value))) {
            //     .optional => {
            //         try std.testing.expect(value != null);
            //         return value.?;
            //     },
            //     else => value,
            // };
        }
        pub fn toBeEqualString(self: Self, allocator: std.mem.Allocator, actual: T) !void {
            const is_equal = std.mem.eql(u8, self.expected, actual);

            if (self.is_not) {
                std.testing.expect(!is_equal) catch |err| {
                    return err;
                };
            } else {
                std.testing.expect(is_equal) catch |err| {
                    var res = try PatienceDiff.diff(
                        allocator,
                        self.expected,
                        actual,
                    );
                    defer res.deinit();
                    try stderr.writeAll("...\n\n");
                    try res.format(stderr, .{});
                    try stderr.writeAll("\n\n");
                    return err;
                };
            }
        }
        pub fn toBeNull(self: Self) !void {
            try std.testing.expect(self.expected == null);
        }
    };
}
pub inline fn expect(expected: anytype) Matchers(@TypeOf(expected)) {
    return .{
        .expected = expected,
        .is_not = false,
        .not = &.{
            .expected = expected,
            .is_not = true,
        },
    };
}

test "basic add functionality" {
    try expect(2).toBe(2);
    try expect("Hello, World!").not.toBeEqualString("Hello, world!");
}
fn satisfies(comptime Expected: type, comptime Actual: type) !void {
    comptime {
        const expected_info = @typeInfo(Expected);
        _ = expected_info; // autofix
        const actual_info = @typeInfo(Actual);
        const actual_struct = actual_info.@"struct";
        const actual_fields = actual_struct.fields;
        const actual_decls = actual_struct.decls;
        var kv: [actual_fields.len + actual_decls.len]struct { []const u8, []const u8 } = undefined;
        var i: usize = 0;
        for (actual_fields) |field| {
            kv[i] = .{ "field: " ++ field.name, @typeName(field.type) };
            i += 1;
        }

        for (actual_decls) |decl| {
            const Decl = @TypeOf(@field(Actual, decl.name));
            kv[i] = .{ "decl: " ++ decl.name, @typeName(Decl) };
            i += 1;
        }
        const map = std.StaticStringMap([]const u8).initComptime(kv);

        const expected_struct = @typeInfo(Expected).@"struct";
        const expected_fields = expected_struct.fields;
        const expected_decls = expected_struct.decls;
        for (expected_fields) |field| {
            const key = "field: " ++ field.name;
            if (map.get(key)) |expected_field_signature| {
                const actual_field_signature = @typeName(field.type);
                try std.testing.expectEqualStrings(expected_field_signature, actual_field_signature);
            } else {
                @compileError("Expected field " ++ key ++ " not found in actual");
            }
        }

        for (expected_decls) |decl| {
            const key = "decl: " ++ decl.name;
            if (map.get(key)) |expected_decl_signature| {
                const actual_decl_signature = @typeName(@field(Actual, decl.name));
                try std.testing.expectEqualStrings(expected_decl_signature, actual_decl_signature);
            } else {
                @compileError("Expected decl " ++ key ++ " not found in actual");
            }
        }
    }
}
test "satisfies" {
    try satisfies(struct {
        a: i64,
        pub fn foo(b: usize) void {
            _ = b; // autofix
        }
    }, struct {
        a: i32,
        pub fn foo(b: usize) void {
            _ = b; // autofix
        }
    });
}
