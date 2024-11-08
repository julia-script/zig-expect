const std = @import("std");
const builtin = @import("builtin");
const io = std.io;

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
                // expectType(T, actual, false) catch |err| {
                //     try stderr.writeAll("...\n");
                //     try stderr.writeAll("\nExpected: ");
                //     try tty_config.setColor(stderr, .red);
                //     try stderr.print("{any}\n", .{self.expected});
                //     try tty_config.setColor(stderr, .reset);
                //     return err;
                // };

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
        // // pub fn toBe(self: Self, actual: T) !void {
        // //     try std.testing.expect(self.expected != actual);
        // // }

        // pub fn toEqual(self: Self, actual: T) !void {
        //     try std.testing.expectEqual(self.expected, actual);
        // }
        // pub fn toNotEqual(self: Self, actual: T) !void {
        //     try std.testing.expect(self.expected != actual);
        // }
        // pub fn toNotBeNull(self: Self) !void {
        //     try std.testing.expect(self.expected != null);
        // }
        pub fn toBeNull(self: Self) !void {
            try std.testing.expect(self.expected == null);
        }
    };
}
pub inline fn expect(expected: anytype) Matchers(@TypeOf(expected)) {
    return .{
        .expected = expected,
        .not = &.{
            .expected = expected,
            .is_not = true,
        },
    };
}

test "basic add functionality" {
    try expect(2).not.toBe(2);
}
