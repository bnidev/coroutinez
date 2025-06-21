# coroutinez

coroutinez is a small runtime for running tasks using coroutines in zig.

### Example

```zig
const std = @import("std");
const azync = @import("coroutinez");
const Runtime = coroutinez.Runtime;

fn main() void {
    const allocator = std.heap.page_allocator;
    const rt = Runtime.init(allocator);
    defer rt.deinit();

    const task1 = rt.spawn(returnNumber, .{allocator});
    const task2 = rt.spawn(returnSlice1, .{allocator});
    const task3 = rt.spawn(returnSlice2, .{"hello", allocator});

    // Make sure that you await an output type that matches the output type of the executed function!
    const result1 = task1.Await(i32);
    const result2 = task2.Await([]const u8);
    const result3 = task3.Await([]const u8);
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

coroutinez will spawn as many threads as logical cores are available on your machine and will run worker functions that will iterate over all tasks that you spawned by calling `Runtime.spawn`. Then it will pick the next pending task. Finished tasks will remain in the task queue as long as you call the `Join()`method on a spawned task (which is represented by a `*Task`). You can also spawn the threads on a chosen number of logical cores by using `initWithCores()`:

```zig
const allocator = std.heap.page_allocator;

const rt = Runtime.initWithCores(allocator, 16);
defer rt.deinit();

```
