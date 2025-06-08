# azync

azync is a runtime for running asynchronous tasks in zig.

### Example:

```zig
const std = @import("std");
const azync = @import("azync");
const Runtime = azync.Runtime;

fn main() void {
    const allocator = std.heap.page_allocator;
    const rt = Runtime.init(allocator);
    defer rt.deinit();

    const future1 = rt.spawn(returnNumber, .{allocator});
    const future2 = rt.spawn(returnSlice1, .{allocator});
    const future3 = rt.spawn(returnSlice2, .{"hello", allocator});

    // Make sure that you await an output type that matches the asynchronous executed function!
    const result1 = future1.Await(i32);
    const result2 = future2.Await([]const u8);
    const result3 = future3.Await([]const u8);
    defer allocator.free(result2);
    defer allocator.free(result3);

    std.debug.print("{d}", .{result1});
    std.debug.print("{s}", .{result2});
    std.debug.print("{s}", .{result3});
}

fn returnNumber() i32 {
    return 42;
}

fn returnSlice1(allocator: std.mem.Allocator) ![]const u8 {

    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    _ = try str.appendSlice("hello");
    _ = try str.appendSlice(" world!");

    return try str.toOwnedSlice();
}

fn returnSlice2(s: []const u8, allocator: std.mem.Allocator) ![]const u8 {

    var str = std.ArrayList(u8).init(allocator);
    defer str.deinit();

    _ = try str.appendSlice(s);
    _ = try str.appendSlice(" world!");

    return try str.toOwnedSlice();
}
```

azync is a work-stealing runtime. That means it will spawn as many threads as logical cores are available on your machine. On each of them it will run a worker function that will iterate over all tasks that you spawn by calling `Runtime.spawn` and pick the next pending task. Finished tasks will remain in the task queue as long as you call the `Await()`method on a spawned task (which is represented by a `*Future`). `Await` is written with a capital "A" to distinguish it from the `await` keyword in Zig, which is already reserved. You can also spawn the threads on a chosen number of logical cores like this:

```zig
const allocator = std.heap.page_allocator;

const rt = Runtime.init(16, allocator);
defer rt.deinit();

```
