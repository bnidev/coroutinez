const std = @import("std");
const runtime = @import("runtime.zig");

// Make the Runtime available at the root level
pub const Runtime = runtime.Runtime;

// Test functions
fn testfn(_: []const u8) i32 {
    return 31;
}

fn testfn2(s: []const u8, n: i32, allocator: std.mem.Allocator) []const u8 {
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    _ = str.appendSlice(s) catch unreachable;
    _ = str.appendSlice("world!") catch unreachable;
    _ = str.writer().print("{d}", .{n}) catch unreachable;

    return str.toOwnedSlice() catch unreachable;
}

fn testfn3() ![]const u8 {
    const allocator = std.testing.allocator;
    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    _ = try str.appendSlice("testfn3");
    _ = try str.appendSlice(" world!");

    return try str.toOwnedSlice();
}
// TESTS

test "init and deinit Runtime" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    std.time.sleep(10 * std.time.ns_per_ms);
    rt.deinit();
}

test "init Runtime, spawn task, await it and deinit Runtime" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();
    const future = try rt.spawn(testfn, .{"testparam"});
    const result = future.Await(i32);
    std.debug.assert(result == 31);
}

test "init Runtime, spawn two tasks with testfn, await them and deinit Runtime" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();
    const future1 = try rt.spawn(testfn, .{"testparam"});
    const future2 = try rt.spawn(testfn, .{"testparam"});
    const result1 = future1.Await(i32);
    const result2 = future2.Await(i32);
    std.debug.assert(result2 == 31);
    std.debug.assert(result1 == 31);
}

test "init Runtime, spawn task without awaiting it and deinit Runtime" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();
    const future = try rt.spawn(testfn, .{"testparam"});
    _ = future;
}

test "testfn2" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();
    const future = try rt.spawn(testfn2, .{ "hello ", 42, allocator });
    const result = future.Await([]const u8);
    defer allocator.free(result);
    std.debug.assert(std.mem.eql(u8, result, "hello world!42"));
}

test "spawn two tasks, await them and deinit Runtime" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();

    const future1 = try rt.spawn(testfn, .{"task1"});

    const future2 = try rt.spawn(testfn2, .{ "task2 ", 100, allocator });

    const result1 = future1.Await(i32);
    std.debug.assert(result1 == 31);

    const result2 = future2.Await([]const u8);
    defer allocator.free(result2);

    std.debug.assert(std.mem.eql(u8, result2, "task2 world!100"));
}

test "testfn3" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();
    const future = try rt.spawn(testfn3, .{});
    const result = future.Await([]const u8);
    defer allocator.free(result);
    std.debug.assert(std.mem.eql(u8, result, "testfn3 world!"));
}

test "testfn, testfn2 and testfn3" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();

    const future1 = try rt.spawn(testfn, .{"task1"});
    const future2 = try rt.spawn(testfn2, .{ "task2 ", 100, allocator });
    const future3 = try rt.spawn(testfn3, .{});

    const result1 = future1.Await(i32);
    std.debug.assert(result1 == 31);

    const result2 = future2.Await([]const u8);
    defer allocator.free(result2);
    std.debug.assert(std.mem.eql(u8, result2, "task2 world!100"));

    const result3 = future3.Await([]const u8);
    defer allocator.free(result3);
    std.debug.assert(std.mem.eql(u8, result3, "testfn3 world!"));
}

test "test all testfns two times and await them" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();

    const future1 = try rt.spawn(testfn, .{"task1"});
    const future2 = try rt.spawn(testfn2, .{ "task2 ", 100, allocator });
    const future3 = try rt.spawn(testfn3, .{});

    const result1 = future1.Await(i32);
    std.debug.assert(result1 == 31);

    const result2 = future2.Await([]const u8);
    defer allocator.free(result2);
    std.debug.assert(std.mem.eql(u8, result2, "task2 world!100"));

    const result3 = future3.Await([]const u8);
    defer allocator.free(result3);
    std.debug.assert(std.mem.eql(u8, result3, "testfn3 world!"));

    // Run them again
    const future4 = try rt.spawn(testfn, .{"task1"});
    const future5 = try rt.spawn(testfn2, .{ "task2 ", 200, allocator });
    const future6 = try rt.spawn(testfn3, .{});

    const result4 = future4.Await(i32);
    std.debug.assert(result4 == 31);

    const result5 = future5.Await([]const u8);
    defer allocator.free(result5);
    std.debug.assert(std.mem.eql(u8, result5, "task2 world!200"));

    const result6 = future6.Await([]const u8);
    defer allocator.free(result6);
    std.debug.assert(std.mem.eql(u8, result6, "testfn3 world!"));
}
