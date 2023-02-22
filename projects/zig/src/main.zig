const std = @import("std");
const testing = std.testing;
const c = @import("c.zig");

const WrenCtx = @This();

var wren_contexts_global: ?std.AutoHashMap(*c.WrenVM, WrenCtx) = undefined;

log: ?*std.ArrayList(u8),
log_to_stdout: bool,

modules: ?*std.StringHashMap(c.WrenForeignMethodFn),

const WrenVMOptions = struct {
    log_to_stdout: bool = false,
    log_list: ?*std.ArrayList(u8) = null,
    modules: ?*std.StringHashMap(c.WrenForeignMethodFn) = null,
};

pub fn register_context(vm: *c.WrenVM, opt: WrenVMOptions) !void {
    std.debug.print("Registering {*} as wrenvm ptr\n", .{vm});

    _ = wren_contexts_global orelse contexts: {
        wren_contexts_global = std.AutoHashMap(*c.WrenVM, WrenCtx).init(testing.allocator);
        break :contexts wren_contexts_global.?;
    };
    var wren_contexts = &wren_contexts_global.?;

    try wren_contexts.put(vm, .{
        .log = opt.log_list,
        .log_to_stdout = opt.log_to_stdout,
        .modules = opt.modules,
    });
}

pub fn free_all_contexts() void {
    var wren_contexts = &(wren_contexts_global orelse return);
    wren_contexts.deinit();
    wren_contexts.* = undefined;
    wren_contexts_global = null;
    // var iter = wren_contexts.iterator();
    // while (iter.next()) |context| {
    //     c.wrenFreeVM(context.key_ptr.*);
    // }
}

pub fn writeFn(vm_opt: ?*c.WrenVM, text_opt: ?[*:0]const u8) callconv(.C) void {
    const vm = vm_opt orelse @panic("Passed null vm");
    std.debug.print("writefn recieved {*} as wrenvm ptr\n", .{vm});
    const contexts = wren_contexts_global orelse @panic("No wren contexts registered");
    const ctx = contexts.get(vm) orelse @panic("Unregistered context");
    const text = text_opt orelse "null";

    if (ctx.log_to_stdout) {
        std.debug.print("{s}", .{text});
    }

    if (ctx.log) |array_list| {
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

pub fn bindForeignMethod(
    vm_opt: ?*c.WrenVM,
    module_opt: ?[*:0]const u8,
    class_name_opt: ?[*:0]const u8,
    is_static: bool,
    signature_opt: ?[*:0]const u8,
) callconv(.C) c.WrenForeignMethodFn {
    const vm = vm_opt orelse @panic("Passed null vm");
    const contexts = wren_contexts_global orelse @panic("No wren contexts registered");
    const ctx = contexts.get(vm) orelse @panic("Unregistered context");
    const modules = ctx.modules orelse @panic("couldn't find modules");

    const module = module_opt orelse @panic("Passed null module");
    const class_name = class_name_opt orelse @panic("Passed null class_name");
    const signature = signature_opt orelse @panic("Passed null signature");

    var buffer: [4096]u8 = undefined;

    const name = std.fmt.bufPrintZ(&buffer, "{s}/{s}.{s}{s}", .{ module, class_name, signature, if (is_static) "static" else "" }) catch return null;

    std.debug.print("Looking for method: {s}", .{name});

    return modules.get(name) orelse null;
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
    var log = std.ArrayList(u8).init(testing.allocator);
    defer log.deinit();

    var config: c.WrenConfiguration = undefined;
    c.wrenInitConfiguration(&config);
    {
        // Configure wren
        config.writeFn = writeFn;
        config.errorFn = errorFn;
    }

    var vm: *c.WrenVM = c.wrenNewVM(&config) orelse return error.NullVM;
    defer c.wrenFreeVM(vm);

    try register_context(vm, .{ .log_list = &log });
    defer free_all_contexts();

    const module = "main";
    const script =
        \\System.print("I am running in a VM!")
    ;

    try handle_result(c.wrenInterpret(vm, module, script));

    try testing.expectEqualStrings("I am running in a VM!\n", log.items);
}

test "call static method" {
    var log = std.ArrayList(u8).init(testing.allocator);
    defer log.deinit();

    var config: c.WrenConfiguration = undefined;
    c.wrenInitConfiguration(&config);
    {
        // Configure wren
        config.writeFn = writeFn;
        config.errorFn = errorFn;
    }

    var vm: *c.WrenVM = c.wrenNewVM(&config) orelse return error.NullVM;
    defer c.wrenFreeVM(vm);

    try register_context(vm, .{ .log_list = &log });
    defer free_all_contexts();

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

    try testing.expectEqualStrings("6.9\n", log.items);
}

fn add(vm_opt: ?*c.WrenVM) callconv(.C) void {
    const vm = vm_opt orelse {
        std.debug.print("Passed null vm\n", .{});
        return;
    };
    const a = c.wrenGetSlotDouble(vm, 1);
    const b = c.wrenGetSlotDouble(vm, 2);
    c.wrenSetSlotDouble(vm, 0, a + b);
}

test "foreign method binding" {
    var log = std.ArrayList(u8).init(testing.allocator);
    defer log.deinit();

    var modules = std.StringHashMap(c.WrenForeignMethodFn).init(testing.allocator);
    defer modules.deinit();

    var config: c.WrenConfiguration = undefined;
    c.wrenInitConfiguration(&config);
    {
        // Configure wren
        config.writeFn = writeFn;
        config.errorFn = errorFn;
        config.bindForeignMethodFn = bindForeignMethod;
    }

    var vm: *c.WrenVM = c.wrenNewVM(&config) orelse return error.NullVM;
    defer c.wrenFreeVM(vm);

    try register_context(vm, .{
        .log_list = &log,
        .modules = &modules,
    });
    defer free_all_contexts();

    try modules.put("main/Math.add(_,_)static", add);

    const module = "main";
    const script =
        \\class Math {
        \\  foreign static add(a, b)
        \\}
    ;

    try handle_result(c.wrenInterpret(vm, module, script));
}
