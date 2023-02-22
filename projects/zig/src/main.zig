const std = @import("std");
const testing = std.testing;
const c = @import("c.zig");

const Wren = @This();

config: c.WrenConfiguration = undefined,

const Options = struct {
    writeFn: ?c.WrenWriteFn,
    errorFn: ?c.WrenErrorFn,
    bindForeignClassFn: ?c.WrenBindForeignClassFn,
    bindForeignMethodFn: ?c.WrenBindForeignMethodFn,
};

pub fn init(opt: Options) Wren {
    var self = Wren{};
    c.wrenInitConfiguration(&self.config);
    // Configure wren
    if (opt.writeFn) |writeFn| self.config.writeFn = writeFn;
    if (opt.errorFn) |errorFn| self.config.errorFn = errorFn;
    if (opt.bindForeignClassFn) |bindForeignClassFn| self.config.bindForeignClassFn = bindForeignClassFn;
    if (opt.bindForeignMethodFn) |bindForeignMethodFn| self.config.bindForeignMethodFn = bindForeignMethodFn;
    return self;
}

pub fn new(self: *Wren) !*VM {
    var vm: *c.WrenVM = c.wrenNewVM(&self.config) orelse return error.NullVM;
    return @ptrCast(*VM, vm);
}

const VM = opaque {
    /// Casts anyopaque to self pointer
    pub fn from_anyopaque(ptr_opt: ?*anyopaque) *@This() {
        const ptr = ptr_opt orelse @panic("Passed null ptr");
        return @ptrCast(*@This(), @constCast(@alignCast(@alignOf(@This()), ptr)));
    }
    fn as_raw(vm: *VM) *c.WrenVM {
        return @ptrCast(*c.WrenVM, @constCast(@alignCast(@alignOf(@This()), vm)));
    }
    pub fn deinit(vm: *VM) void {
        c.wrenFreeVM(vm.as_raw());
    }
    pub fn interpret(vm: *VM, module: [*:0]const u8, script: [*:0]const u8) !void {
        try handle_result(c.wrenInterpret(vm.as_raw(), module, script));
    }
    pub fn setUserData(vm: *VM, user_data: *anyopaque) void {
        c.wrenSetUserData(vm.as_raw(), user_data);
    }
    pub fn getUserData(vm: *VM) ?*anyopaque {
        return c.wrenGetUserData(vm.as_raw());
    }
};

pub fn handle_result(result: c.WrenInterpretResult) !void {
    switch (result) {
        c.WREN_RESULT_SUCCESS => {},
        c.WREN_RESULT_COMPILE_ERROR => return error.Compile,
        c.WREN_RESULT_RUNTIME_ERROR => return error.Runtime,
        else => return error.Unexpected,
    }
}

const TestHarness = struct {
    vm: *VM = undefined,
    log: std.ArrayListUnmanaged(u8) = .{},
    methods: std.StringHashMapUnmanaged(c.WrenForeignMethodFn) = .{},
    classes: std.StringHashMapUnmanaged(c.WrenForeignClassMethods) = .{},

    /// Casts anyopaque to self pointer
    fn from(ptr_opt: ?*anyopaque) *@This() {
        const ptr = ptr_opt orelse @panic("Passed null ptr");
        return @ptrCast(*@This(), @constCast(@alignCast(@alignOf(@This()), ptr)));
    }

    /// Creates a new vm on the stack
    fn init(harness: *@This()) !void {
        var config = Wren.init(.{
            .writeFn = writeFn,
            .errorFn = errorFn,
            .bindForeignClassFn = bindForeignClass,
            .bindForeignMethodFn = bindForeignMethod,
        });
        harness.vm = try config.new();
        harness.vm.setUserData(harness);
    }

    pub fn deinit(self: *@This()) void {
        self.vm.deinit();
        self.log.clearAndFree(testing.allocator);
        self.methods.clearAndFree(testing.allocator);
        self.classes.clearAndFree(testing.allocator);
    }

    fn writeFn(vm_opt: ?*c.WrenVM, text_opt: ?[*:0]const u8) callconv(.C) void {
        const vm = VM.from_anyopaque(vm_opt);
        const self = from(vm.getUserData());
        const text = text_opt orelse @panic("null string");
        const writer = self.log.writer(testing.allocator);
        std.fmt.format(writer, "{s}", .{text}) catch @panic("Error formatting write");
    }

    fn errorFn(
        vm_opt: ?*c.WrenVM,
        errorType: c.WrenErrorType,
        module_opt: ?[*:0]const u8,
        line: c_int,
        msg_opt: ?[*:0]const u8,
    ) callconv(.C) void {
        const vm = VM.from_anyopaque(vm_opt);
        const module = module_opt orelse @panic("null msg");
        const msg = msg_opt orelse @panic("null msg");

        const self = from(vm.getUserData());
        const writer = self.log.writer(testing.allocator);

        _ = switch (errorType) {
            c.WREN_ERROR_COMPILE => std.fmt.format(writer, "[{s} line {}] [Error] {s}\n", .{ module, line, msg }),
            c.WREN_ERROR_STACK_TRACE => std.fmt.format(writer, "[{s} line {}] in {s}\n", .{ module, line, msg }),
            c.WREN_ERROR_RUNTIME => std.fmt.format(writer, "[Runtime Error] {s}\n", .{msg}),
            else => std.fmt.format(writer, "[Unexpected Error] {s}", .{msg}),
        } catch @panic("Error formatting error");
    }
    fn bindForeignMethod(
        vm_opt: ?*c.WrenVM,
        module_opt: ?[*:0]const u8,
        class_name_opt: ?[*:0]const u8,
        is_static: bool,
        signature_opt: ?[*:0]const u8,
    ) callconv(.C) c.WrenForeignMethodFn {
        const vm = VM.from_anyopaque(vm_opt);
        const module = module_opt orelse @panic("Passed null module");
        const class_name = class_name_opt orelse @panic("Passed null class_name");
        const signature = signature_opt orelse @panic("Passed null signature");

        const self = from(vm.getUserData());
        const writer = self.log.writer(testing.allocator);

        var buffer: [4096]u8 = undefined;

        const name = std.fmt.bufPrintZ(&buffer, "{s}/{s}.{s}{s}", .{ module, class_name, signature, if (is_static) "static" else "" }) catch return null;

        std.fmt.format(writer, "Looking for method: {s}\n", .{name}) catch @panic("Error logging");

        return self.methods.get(name) orelse null;
    }

    const null_class: c.WrenForeignClassMethods = .{
        .allocate = null,
        .finalize = null,
    };

    fn bindForeignClass(
        vm_opt: ?*c.WrenVM,
        module_opt: ?[*:0]const u8,
        class_name_opt: ?[*:0]const u8,
    ) callconv(.C) c.WrenForeignClassMethods {
        const vm = VM.from_anyopaque(vm_opt);
        const module = module_opt orelse @panic("Passed null module");
        const class_name = class_name_opt orelse @panic("Passed null class_name");

        const self = from(vm.getUserData());
        const writer = self.log.writer(testing.allocator);

        var buffer: [4096]u8 = undefined;

        const name = std.fmt.bufPrintZ(&buffer, "{s}/{s}", .{ module, class_name }) catch return null_class;

        std.fmt.format(writer, "Looking for class: {s}\n", .{name}) catch @panic("Error logging");

        return self.classes.get(name) orelse null_class;
    }
};

test "init wren vm" {
    var harness = TestHarness{};
    try harness.init();
    defer harness.deinit();

    const module = "main";
    const script =
        \\System.print("I am running in a VM!")
    ;

    try harness.vm.interpret(module, script);

    try testing.expectEqualStrings("I am running in a VM!\n", harness.log.items);
}

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
