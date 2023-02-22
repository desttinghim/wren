const std = @import("std");
const testing = std.testing;
const c = @import("c.zig");

const WrenCtx = @This();

var wren_contexts_global: ?std.AutoHashMap(*c.WrenVM, WrenCtx) = undefined;

log: ?*std.ArrayList(u8),
log_to_stdout: bool,

methods: ?*std.StringHashMap(c.WrenForeignMethodFn),
classes: ?*std.StringHashMap(c.WrenForeignClassMethods),

const WrenContextOptions = struct {
    log_to_std: bool = false,
};

fn WrenContext(comptime options: WrenContextOptions) type {
    return struct {
        var config: c.WrenConfiguration = undefined;
        var log_allocator: ?std.mem.Allocator = null;
        var log = std.ArrayListUnmanaged(u8){};
        var data_allocator: ?std.mem.Allocator = null;
        var methods = std.StringHashMapUnmanaged(c.WrenForeignMethodFn){};
        var classes = std.StringHashMapUnmanaged(c.WrenForeignClassMethods){};

        pub fn init_config() void {
            c.wrenInitConfiguration(&config);
            config.writeFn = writeFn;
            config.errorFn = errorFn;
            config.bindForeignClassFn = bindForeignClass;
            config.bindForeignMethodFn = bindForeignMethod;
        }
        pub fn init_vm() !*c.WrenVM {
            return c.wrenNewVM(&config) orelse return error.NullVM;
        }
        pub fn deinit_vm(vm: *c.WrenVM) void {
            c.wrenFreeVM(vm);
        }
        pub fn deinit() void {
            if (log_allocator) |allocator| {
                log.clearAndFree(allocator);
            }
        }
        fn _log(text: [*:0]const u8) void {
            if (options.log_to_std) {
                std.debug.print("{s}", .{text});
            }

            if (log_allocator) |allocator| {
                const text_span = std.mem.span(text);
                _ = log.writer(allocator).write(text_span) catch {};
            }
        }

        // Binding functions
        pub fn writeFn(vm_opt: ?*c.WrenVM, text_opt: ?[*:0]const u8) callconv(.C) void {
            _ = vm_opt;
            const text = text_opt orelse "null";
            _log(text);
        }
        pub fn errorFn(
            vm_opt: ?*c.WrenVM,
            errorType: c.WrenErrorType,
            module_opt: ?[*:0]const u8,
            line: c_int,
            msg_opt: ?[*:0]const u8,
        ) callconv(.C) void {
            _ = msg_opt;
            _ = line;
            _ = module_opt;
            _ = errorType;
            _ = vm_opt;
            // const vm = vm_opt orelse return;
            // const msg = msg_opt orelse return;
            // const module = module_opt orelse return;
            // switch (errorType) {
            //     c.WREN_ERROR_COMPILE => _log(std.fmt.format("[{s} line {}] [Error] {s}\n", .{ module, line, msg }) catch return),
            //     c.WREN_ERROR_STACK_TRACE => std.debug.print("[{s} line {}] in {s}\n", .{ module, line, msg }),
            //     c.WREN_ERROR_RUNTIME => std.debug.print("[Runtime Error] {s}\n", .{msg}),
            //     else => std.debug.print("[Unexpected Error] {s}", .{msg}),
            // }
        }
        pub fn bindForeignMethod(
            vm_opt: ?*c.WrenVM,
            module_opt: ?[*:0]const u8,
            class_name_opt: ?[*:0]const u8,
            is_static: bool,
            signature_opt: ?[*:0]const u8,
        ) callconv(.C) c.WrenForeignMethodFn {
            _ = vm_opt;
            const module = module_opt orelse @panic("Passed null module");
            const class_name = class_name_opt orelse @panic("Passed null class_name");
            const signature = signature_opt orelse @panic("Passed null signature");

            var buffer: [4096]u8 = undefined;

            const name = std.fmt.bufPrintZ(&buffer, "{s}/{s}.{s}{s}", .{ module, class_name, signature, if (is_static) "static" else "" }) catch return null;

            std.debug.print("Looking for method: {s}\n", .{name});

            return methods.get(name) orelse null;
        }

        pub fn bindForeignClass(
            vm_opt: ?*c.WrenVM,
            module_opt: ?[*:0]const u8,
            class_name_opt: ?[*:0]const u8,
        ) callconv(.C) c.WrenForeignClassMethods {
            _ = vm_opt;
            const null_class: c.WrenForeignClassMethods = .{
                .allocate = null,
                .finalize = null,
            };

            const module = module_opt orelse @panic("Passed null module");
            const class_name = class_name_opt orelse @panic("Passed null class_name");

            var buffer: [4096]u8 = undefined;

            const name = std.fmt.bufPrintZ(&buffer, "{s}/{s}", .{ module, class_name }) catch return null_class;

            std.debug.print("Looking for class: {s}\n", .{name});

            return classes.get(name) orelse null_class;
        }
    };
}

test WrenContext {
    const Wren = WrenContext(.{});
    defer Wren.deinit();

    Wren.init_config();

    Wren.log_allocator = testing.allocator;
    Wren.data_allocator = testing.allocator;

    var vm = try Wren.init_vm();
    defer Wren.deinit_vm(vm);

    const module = "main";
    const script =
        \\System.print("I am running in a VM!")
    ;

    try handle_result(c.wrenInterpret(vm, module, script));

    try testing.expectEqualStrings("I am running in a VM!\n", Wren.log.items);
}

pub fn handle_result(result: c.WrenInterpretResult) !void {
    switch (result) {
        c.WREN_RESULT_SUCCESS => {},
        c.WREN_RESULT_COMPILE_ERROR => return error.Compile,
        c.WREN_RESULT_RUNTIME_ERROR => return error.Runtime,
        else => return error.Unexpected,
    }
}

// test "init wren vm" {
//     var log = std.ArrayList(u8).init(testing.allocator);
//     defer log.deinit();

//     var config: c.WrenConfiguration = undefined;
//     c.wrenInitConfiguration(&config);
//     {
//         // Configure wren
//         config.writeFn = writeFn;
//         config.errorFn = errorFn;
//     }

//     var vm: *c.WrenVM = c.wrenNewVM(&config) orelse return error.NullVM;
//     defer c.wrenFreeVM(vm);

//     try register_context(vm, .{ .log_list = &log });
//     defer free_all_contexts();

//     const module = "main";
//     const script =
//         \\System.print("I am running in a VM!")
//     ;

//     try handle_result(c.wrenInterpret(vm, module, script));

//     try testing.expectEqualStrings("I am running in a VM!\n", log.items);
// }

// test "call static method" {
//     var log = std.ArrayList(u8).init(testing.allocator);
//     defer log.deinit();

//     var config: c.WrenConfiguration = undefined;
//     c.wrenInitConfiguration(&config);
//     {
//         // Configure wren
//         config.writeFn = writeFn;
//         config.errorFn = errorFn;
//     }

//     var vm: *c.WrenVM = c.wrenNewVM(&config) orelse return error.NullVM;
//     defer c.wrenFreeVM(vm);

//     try register_context(vm, .{ .log_list = &log });
//     defer free_all_contexts();

//     const module = "main";
//     const script =
//         \\class GameEngine {
//         \\  static update(elapsedTime) {
//         \\    System.print(elapsedTime)
//         \\  }
//         \\}
//     ;

//     try handle_result(c.wrenInterpret(vm, module, script));

//     c.wrenEnsureSlots(vm, 1);
//     c.wrenGetVariable(vm, "main", "GameEngine", 0);
//     const game_engine_class = c.wrenGetSlotHandle(vm, 0);
//     const update_method = c.wrenMakeCallHandle(vm, "update(_)");
//     {
//         // Perform GameEngine.update method call
//         c.wrenSetSlotHandle(vm, 0, game_engine_class);
//         c.wrenSetSlotDouble(vm, 1, 6.9);
//         try handle_result(c.wrenCall(vm, update_method));
//     }

//     try testing.expectEqualStrings("6.9\n", log.items);
// }

// fn add(vm_opt: ?*c.WrenVM) callconv(.C) void {
//     const vm = vm_opt orelse {
//         std.debug.print("Passed null vm\n", .{});
//         return;
//     };
//     const a = c.wrenGetSlotDouble(vm, 1);
//     const b = c.wrenGetSlotDouble(vm, 2);
//     c.wrenSetSlotDouble(vm, 0, a + b);
// }

// test "foreign method binding" {
//     var log = std.ArrayList(u8).init(testing.allocator);
//     defer log.deinit();

//     var methods = std.StringHashMap(c.WrenForeignMethodFn).init(testing.allocator);
//     defer methods.deinit();

//     var config: c.WrenConfiguration = undefined;
//     c.wrenInitConfiguration(&config);
//     {
//         // Configure wren
//         config.writeFn = writeFn;
//         config.errorFn = errorFn;
//         config.bindForeignMethodFn = bindForeignMethod;
//     }

//     var vm: *c.WrenVM = c.wrenNewVM(&config) orelse return error.NullVM;
//     defer c.wrenFreeVM(vm);

//     try register_context(vm, .{
//         .log_list = &log,
//         .methods = &methods,
//     });
//     defer free_all_contexts();

//     try methods.put("main/Math.add(_,_)static", add);

//     const module = "main";
//     const script =
//         \\class Math {
//         \\  foreign static add(a, b)
//         \\}
//     ;

//     try handle_result(c.wrenInterpret(vm, module, script));
// }

// const File = struct {
//     buffer: [4096]u8 = undefined,
//     slice: []u8 = undefined,
//     fn from_anyopaque(self_ptr_opt: ?*anyopaque) *@This() {
//         const self_ptr = self_ptr_opt orelse @panic("Passed null self ptr");
//         return @ptrCast(*@This(), @constCast(@alignCast(@alignOf(@This()), self_ptr)));
//     }
//     fn allocate(vm_opt: ?*c.WrenVM) callconv(.C) void {
//         const vm = vm_opt orelse @panic("Passed null vm");
//         const self = File.from_anyopaque(c.wrenSetSlotNewForeign(vm, 0, 0, @sizeOf(@This())));
//         const path = c.wrenGetSlotString(vm, 1);
//         self.*.slice = std.fmt.bufPrint(&self.*.buffer, "{s}\n", .{path}) catch @panic("Couldn't bufPrint");
//     }
//     fn write(vm_opt: ?*c.WrenVM) callconv(.C) void {
//         const vm = vm_opt orelse @panic("Passed null vm");
//         const self = File.from_anyopaque(c.wrenGetSlotForeign(vm, 0));
//         const text_res = c.wrenGetSlotString(vm, 1);
//         const text = std.mem.span(text_res);
//         self.*.slice = std.fmt.bufPrint(&self.*.buffer, "{s}", .{text}) catch @panic("Couldn't bufPrint");
//     }
//     fn close(vm_opt: ?*c.WrenVM) callconv(.C) void {
//         _ = vm_opt;
//     }
//     fn finalize(self_ptr: ?*anyopaque) callconv(.C) void {
//         const self = @ptrCast(*@This(), @alignCast(@alignOf(@This()), self_ptr));
//         std.debug.print("finalizing {*}, buffer is {s}\n", .{ self, self.slice });
//     }
// };

// test "foreign class" {
//     var log = std.ArrayList(u8).init(testing.allocator);
//     defer log.deinit();

//     var methods = std.StringHashMap(c.WrenForeignMethodFn).init(testing.allocator);
//     defer methods.deinit();

//     var classes = std.StringHashMap(c.WrenForeignClassMethods).init(testing.allocator);
//     defer classes.deinit();

//     var config: c.WrenConfiguration = undefined;
//     c.wrenInitConfiguration(&config);
//     {
//         // Configure wren
//         config.writeFn = writeFn;
//         config.errorFn = errorFn;
//         config.bindForeignClassFn = bindForeignClass;
//         config.bindForeignMethodFn = bindForeignMethod;
//     }

//     var vm: *c.WrenVM = c.wrenNewVM(&config) orelse return error.NullVM;
//     defer c.wrenFreeVM(vm);

//     try register_context(vm, .{
//         .log_list = &log,
//         .methods = &methods,
//         .classes = &classes,
//     });
//     defer free_all_contexts();

//     try methods.put("main/File.write(_)", File.write);
//     try methods.put("main/File.close()", File.close);
//     try classes.put("main/File", .{ .allocate = File.allocate, .finalize = File.finalize });

//     const module = "main";
//     const script =
//         \\foreign class File {
//         \\  construct create(path) {}
//         \\
//         \\  foreign write(text)
//         \\  foreign close()
//         \\}
//         \\var file = File.create("some/path.txt")
//         \\file.write("hello!")
//         \\file.close()
//     ;

//     try handle_result(c.wrenInterpret(vm, module, script));
// }
