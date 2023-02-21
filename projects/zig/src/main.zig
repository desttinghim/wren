const std = @import("std");
const testing = std.testing;
const c = @import("c.zig");

pub fn writeFn(vm_opt: ?*c.WrenVM, text_opt: ?[*:0]const u8) callconv(.C) void {
    const vm = vm_opt orelse @panic("Passed null vm");
    _ = vm;
    const text = text_opt orelse "null";
    std.debug.print("{s}", .{text});
}

var vm_logs: std.AutoHashMap(*c.WrenVM, std.ArrayList(u8)) = undefined;
fn testWriteFn(vm_opt: ?*c.WrenVM, text_opt: ?[*:0]const u8) callconv(.C) void {
    const vm = vm_opt orelse @panic("Passed null vm");
    const text = text_opt orelse "null";
    if (vm_logs.getPtr(vm)) |array_list| {
        std.fmt.format(array_list.writer(), "{s}", .{text}) catch |e| {
            std.debug.print("Error while logging: {s}", .{@errorName(e)});
        };
    }
}

pub fn errorFn(
    vm_opt: ?*c.WrenVM,
    errorType: c.WrenErrorType,
    module_opt: ?[*:0]const u8,
    line: c_int,
    msg_opt: ?[*:0]const u8,
) callconv(.C) void {
    const vm = vm_opt orelse return;
    _ = vm;
    const msg = msg_opt orelse return;
    const module = module_opt orelse return;
    switch (errorType) {
        c.WREN_ERROR_COMPILE => std.debug.print("[{s} line {}] [Error] {s}\n", .{ module, line, msg }),
        c.WREN_ERROR_STACK_TRACE => std.debug.print("[{s} line {}] in {s}\n", .{ module, line, msg }),
        c.WREN_ERROR_RUNTIME => std.debug.print("[Runtime Error] {s}\n", .{msg}),
        else => std.debug.print("[Unexpected Error] {s}", .{msg}),
    }
}

pub fn handle_result(result: c.WrenInterpretResult) !void {
    switch (result) {
        c.WREN_RESULT_SUCCESS => {},
        c.WREN_RESULT_COMPILE_ERROR => return error.Compile,
        c.WREN_RESULT_RUNTIME_ERROR => return error.Runtime,
        else => return error.Unexpected,
    }
}

test "init wren vm" {
    var config: c.WrenConfiguration = undefined;
    c.wrenInitConfiguration(&config);
    {
        // Configure wren
        config.writeFn = testWriteFn;
        config.errorFn = errorFn;
    }

    var vm: *c.WrenVM = c.wrenNewVM(&config) orelse return error.NullVM;
    defer c.wrenFreeVM(vm);

    vm_logs = std.AutoHashMap(*c.WrenVM, std.ArrayList(u8)).init(testing.allocator);
    defer {
        var iter = vm_logs.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        vm_logs.deinit();
    }

    try vm_logs.put(vm, std.ArrayList(u8).init(testing.allocator));

    const module = "main";
    const script =
        \\System.print("I am running in a VM!")
    ;

    var result: c.WrenInterpretResult = c.wrenInterpret(vm, module, script);
    switch (result) {
        c.WREN_RESULT_COMPILE_ERROR => std.debug.print("Compile Error!\n", .{}),
        c.WREN_RESULT_RUNTIME_ERROR => std.debug.print("Runtime Error!\n", .{}),
        c.WREN_RESULT_SUCCESS => std.debug.print("Success\n", .{}),
        else => return error.UnexpectedResult,
    }

    const log = vm_logs.get(vm) orelse return error.UnitializedLog;

    try testing.expectEqualStrings("I am running in a VM!\n", log.items);
}

test "call static method" {
    var config: c.WrenConfiguration = undefined;
    c.wrenInitConfiguration(&config);
    {
        // Configure wren
        config.writeFn = testWriteFn;
        config.errorFn = errorFn;
    }

    var vm: *c.WrenVM = c.wrenNewVM(&config) orelse return error.NullVM;
    defer c.wrenFreeVM(vm);

    vm_logs = std.AutoHashMap(*c.WrenVM, std.ArrayList(u8)).init(testing.allocator);
    defer {
        var iter = vm_logs.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        vm_logs.deinit();
    }

    try vm_logs.put(vm, std.ArrayList(u8).init(testing.allocator));

    const module = "main";
    const script =
        \\class GameEngine {
        \\  static update(elapsedTime) {
        \\    System.print(elapsedTime)
        \\  }
        \\}
    ;

    try handle_result(c.wrenInterpret(vm, module, script));

    c.wrenEnsureSlots(vm, 1);
    c.wrenGetVariable(vm, "main", "GameEngine", 0);
    const game_engine_class = c.wrenGetSlotHandle(vm, 0);
    const update_method = c.wrenMakeCallHandle(vm, "update(_)");
    {
        // Perform GameEngine.update method call
        c.wrenSetSlotHandle(vm, 0, game_engine_class);
        c.wrenSetSlotDouble(vm, 1, 6.9);
        try handle_result(c.wrenCall(vm, update_method));
    }

    const log = vm_logs.get(vm) orelse return error.UnitializedLog;

    try testing.expectEqualStrings("6.9\n", log.items);
}
