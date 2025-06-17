const std = @import("std");
const root = @import("root.zig");
const AsyncFnWrapper = @import("wrapper.zig").AsyncFnWrapper;

/// Represents an error that occurs when the CPU count is invalid.
const CpuCountError = error{
    InvalidCpuCount,
};

/// The `Runtime` struct provides a thread pool and task management for asynchronous execution.
/// It allows spawning tasks that can be awaited, and manages the lifecycle of these tasks.
/// The runtime can be initialized with a specific number of CPU cores, or it defaults to the number of available cores.
/// It handles task scheduling, execution, and cleanup, ensuring that resources are properly managed.
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    task_queue: std.ArrayList(*Future),
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,
    threads: []std.Thread,
    threads_started: bool = false,
    stop_flag: *bool,
    const Self = @This();

    /// Initializes the runtime with the default number of CPU cores available on the system.
    pub fn init(allocator: std.mem.Allocator) !Self {
        const cores = try std.Thread.getCpuCount();
        return try Self.initRuntime(cores, allocator);
    }

    /// Initializes the runtime with a specific number of CPU cores.
    pub fn initWithCores(allocator: std.mem.Allocator, cpu_count: usize) !Self {
        const cores = try std.Thread.getCpuCount();
        if (cpu_count == 0 or cpu_count > cores) return CpuCountError.InvalidCpuCount;
        return try Self.initRuntime(cores, allocator);
    }

    // Private function to initialize the runtime with a specific number of CPU cores.
    fn initRuntime(cpu_count: usize, allocator: std.mem.Allocator) !Self {
        const stop = try allocator.create(bool);
        stop.* = false;
        const task_queue = std.ArrayList(*Future).init(allocator);
        const threads = try allocator.alloc(std.Thread, cpu_count);
        return Self{
            .allocator = allocator,
            .task_queue = task_queue,
            .threads = threads,
            .mutex = .{},
            .cond = .{},
            .stop_flag = stop,
        };
    }

    /// Deinitializes the runtime, cleaning up resources and ensuring all tasks are completed.
    /// This method waits for all tasks in the queue to finish before shutting down the worker threads.
    /// It is important to call this method to avoid memory leaks and ensure that all resources are properly released.
    pub fn deinit(self: *Self) void {
        for (self.task_queue.items) |task| {
            _ = task.Await(*anyopaque);
        }

        if (self.threads_started) {
            self.mutex.lock();
            self.stop_flag.* = true;
            self.cond.broadcast();
            self.mutex.unlock();
            for (self.threads) |thread| {
                thread.join();
            }
        }

        self.allocator.free(self.threads);
        self.allocator.destroy(self.stop_flag);
        self.task_queue.deinit();
    }

    /// Spawns an asynchronous task using the provided function `F` and parameters `params`.
    /// Params must match the expected parameters of the function `F` and must be passed as a tuple.
    /// The spawn-method returns a `Future` that can be awaited to get the result of the asynchronous operation.
    pub fn spawn(self: *Self, comptime F: anytype, params: anytype) !*Future {
        if (!self.threads_started) {
            for (self.threads) |*thread| {
                thread.* = try std.Thread.spawn(.{}, workerThread, .{self});
            }
            self.threads_started = true;
        }
        const ParamType = @TypeOf(params);
        const async_fn_wrapper = AsyncFnWrapper(F, ParamType);
        var gen_instance = async_fn_wrapper.create(self.allocator);
        gen_instance.params = params;

        const wrapper_instance = try self.allocator.create(WrapperStruct);

        wrapper_instance.* = .{
            .self = @alignCast(@ptrCast(gen_instance)),
            .run_fn = @alignCast(@ptrCast(gen_instance.run_fn)),
            .params = @alignCast(@ptrCast(&gen_instance.params)),
            .output = @alignCast(@ptrCast(&gen_instance.output)),
            .wrapper_destroy_fn = @alignCast(@ptrCast(gen_instance.destroy_fn)),
        };
        const future = try self.allocator.create(Future);
        future.* = Future{
            .runtime = self,
            .async_fn_wrapper = wrapper_instance,
        };
        self.mutex.lock();
        try self.task_queue.append(future);
        self.mutex.unlock();
        self.cond.signal();
        return future;
    }
};

/// Represents a future that can be awaited, encapsulating the result of an asynchronous operation.
pub const Future = struct {
    const FutSelf = @This();
    runtime: *Runtime,
    async_fn_wrapper: *WrapperStruct,
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    status: TaskStatus = .Pending,

    /// Awaits a future, blocking until the asynchronous operation is complete.
    /// Returns the result of the operation, which is of type `T`.
    /// The future must be created with a compatible type for `T`.
    /// Make sure that the type `T` matches the output type of the asynchronous executed function.
    /// After awaiting, the future is cleaned up and its resources are released.
    /// `Await` is written with a capital "A" to distinguish it from the `await` keyword in Zig, which is already reserved.
    pub fn Await(self: *Future, T: type) T {
        self.mutex.lock();
        while (self.status != .Finished) {
            self.cond.wait(&self.mutex);
        }

        const output: *T = @alignCast(@ptrCast(self.async_fn_wrapper.output));
        const result = output.*;

        self.async_fn_wrapper.wrapper_destroy_fn(self.async_fn_wrapper.self);
        self.runtime.allocator.destroy(self.async_fn_wrapper);

        for (self.runtime.task_queue.items, 0..) |item, idx| {
            if (item == self) {
                self.runtime.mutex.lock();
                _ = self.runtime.task_queue.orderedRemove(idx);
                self.runtime.mutex.unlock();
                self.runtime.cond.broadcast();
                break;
            }
        }

        self.mutex.unlock();
        self.runtime.allocator.destroy(self);
        return result;
    }
};

// A helper struct to encapsulate the asynchronous function and its parameters.
const WrapperStruct = struct {
    self: *anyopaque,
    run_fn: *const fn (*anyopaque) void,
    params: *const anyopaque,
    output: *anyopaque,
    wrapper_destroy_fn: *const fn (*anyopaque) void,
};

// Represents the status of a task in the runtime.
const TaskStatus = enum {
    Pending,
    Running,
    Finished,
};
// The worker thread function that processes tasks from the runtime's task queue.
fn workerThread(runtime: *Runtime) void {
    while (true) {
        runtime.mutex.lock();

        while (runtime.task_queue.items.len == 0 and !runtime.stop_flag.*) {
            runtime.cond.wait(&runtime.mutex);
        }

        if (runtime.stop_flag.*) {
            runtime.mutex.unlock();
            break;
        }

        var task: ?*Future = null;

        for (runtime.task_queue.items) |t| {
            if (t.status == .Pending) {
                t.status = .Running;
                task = t;
                break;
            }
        }

        runtime.mutex.unlock();

        if (task) |t| {
            t.mutex.lock();
            t.async_fn_wrapper.run_fn(t.async_fn_wrapper.self);
            t.status = .Finished;
            t.mutex.unlock();
            t.cond.broadcast();
        }
    }
}
