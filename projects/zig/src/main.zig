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

pub fn getVersionNumber() c_int {
    return c.wrenGetVersionNumber();
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
    pub fn collectGarbage(vm: *VM) void {
        c.wrenCollectGarbage(vm.as_raw());
    }
    pub fn interpret(vm: *VM, module: [*:0]const u8, script: [*:0]const u8) !void {
        try handle_result(c.wrenInterpret(vm.as_raw(), module, script));
    }
    pub fn makeCallHandle(vm: *VM, signature: [*:0]const u8) ?*c.WrenHandle {
        return c.wrenMakeCallHandle(vm.as_raw(), signature);
    }
    pub fn call(vm: *VM, method: *c.WrenHandle) !void {
        try handle_result(c.wrenCall(vm.as_raw(), method));
    }
    pub fn releaseHandle(vm: *VM, handle: *c.WrenHandle) !void {
        try handle_result(c.wrenReleaseHandle(vm.as_raw(), handle));
    }
    pub fn getSlotCount(vm: *VM) c_int {
        return c.wrenGetSlotCount(vm.as_raw());
    }
    pub fn ensureSlots(vm: *VM, numSlots: c_int) void {
        c.wrenEnsureSlots(vm.as_raw(), numSlots);
    }
    pub fn getSlotType(vm: *VM) c.WrenType {
        return c.wrenGetSlotType(vm.as_raw());
    }
    const WrenInterfaceType = enum {
        Bool,
        Bytes,
        Double,
        Foreign,
        String,
        Handle,
        pub fn as_string(T: @This()) []const u8 {
            return @tagName(T);
        }
        pub fn as_zig_type(comptime T: @This()) type {
            return switch (T) {
                .Bool => bool,
                .Bytes => ?[]const u8,
                .Double => f64,
                .Foreign => ?*anyopaque,
                .String => ?[*:0]const u8,
                .Handle => ?*c.WrenHandle,
            };
        }
    };
    pub fn getSlot(vm: *VM, comptime T: WrenInterfaceType, slot: c_int) T.as_zig_type() {
        switch (T) {
            .Bytes => {
                var len: c_int = undefined;
                var ptr = c.wrenGetSlotBytes(vm.as_raw(), slot, &len);
                return ptr[0..len];
            },
            else => |t| return @call(.auto, @field(c, "wrenGetSlot" ++ t.as_string()), .{ vm.as_raw(), slot }),
        }
    }
    pub fn setSlot(vm: *VM, comptime T: WrenInterfaceType, slot: c_int, value: T.as_zig_type()) void {
        switch (T) {
            .Bytes => {
                c.wrenSetSlotBytes(vm.as_raw(), value.ptr, value.len);
            },
            else => |t| @call(.auto, @field(c, "wrenSetSlot" ++ t.as_string()), .{ vm.as_raw(), slot, value }),
        }
    }

    // Foreign
    pub fn setSlotNewForeign(vm: *VM, slot: c_int, class_slot: c_int, size: usize) ?*anyopaque {
        return c.wrenSetSlotNewForeign(vm.as_raw(), slot, class_slot, size);
    }

    // Reference types
    const WrenRefType = union(enum) {
        List,
        Map,
        Null,
    };

    pub fn setSlotNew(vm: *VM, comptime T: WrenRefType, slot: c_int) void {
        @call(.auto, @field(c, "wrenSetSlotNew" ++ @tagName(T)), .{ vm.as_raw(), slot });
    }

    // Lists
    pub fn getListCount(vm: *VM, slot: c_int) c_int {
        return c.wrenGetListCount(vm.as_raw(), slot);
    }

    pub fn getListElement(vm: *VM, list_slot: c_int, index: c_int, element_slot: c_int) void {
        return c.wrenGetListElement(vm.as_raw(), list_slot, index, element_slot);
    }

    pub fn setListElement(vm: *VM, list_slot: c_int, index: c_int, element_slot: c_int) void {
        return c.wrenSetListElement(vm.as_raw(), list_slot, index, element_slot);
    }

    pub fn insertInList(vm: *VM, list_slot: c_int, index: c_int, element_slot: c_int) void {
        return c.wrenInsertInList(vm.as_raw(), list_slot, index, element_slot);
    }

    // Maps
    pub fn getMapCount(vm: *VM, slot: c_int) c_int {
        return c.wrenGetMapCount(vm.as_raw(), slot);
    }

    pub fn getMapContainsKey(vm: *VM, map_slot: c_int, key_slot: c_int) bool {
        return c.wrenGetMapContainsKey(vm.as_raw(), map_slot, key_slot);
    }

    pub fn getMapValue(vm: *VM, map_slot: c_int, key_slot: c_int, value_slot: c_int) void {
        return c.wrenGetMapValue(vm.as_raw(), map_slot, key_slot, value_slot);
    }

    pub fn setMapValue(vm: *VM, map_slot: c_int, key_slot: c_int, value_slot: c_int) void {
        return c.wrenSetMapValue(vm.as_raw(), map_slot, key_slot, value_slot);
    }

    pub fn removeMapValue(vm: *VM, map_slot: c_int, key_slot: c_int, removed_value_slot: c_int) void {
        return c.wrenInsertInMap(vm.as_raw(), map_slot, key_slot, removed_value_slot);
    }

    // Variables
    pub fn getVariable(vm: *VM, module: [*:0]const u8, name: [*:0]const u8, slot: c_int) void {
        c.wrenGetVariable(vm.as_raw(), module, name, slot);
    }
    pub fn hasVariable(vm: *VM, module: [*:0]const u8, name: [*:0]const u8) bool {
        return c.wrenHasVariable(vm.as_raw(), module, name);
    }

    // Runtime
    pub fn hasModule(vm: *VM, module: [*:0]const u8) bool {
        return c.wrenHasModule(vm.as_raw(), module);
    }
    pub fn abortFiber(vm: *VM, slot: c_int) bool {
        return c.wrenAbortFiber(vm.as_raw(), slot);
    }
    pub fn getUserData(vm: *VM) ?*anyopaque {
        return c.wrenGetUserData(vm.as_raw());
    }
    pub fn setUserData(vm: *VM, user_data: *anyopaque) void {
        c.wrenSetUserData(vm.as_raw(), user_data);
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

test "call static method" {
    var harness = TestHarness{};
    try harness.init();
    defer harness.deinit();

    const module = "main";
    const script =
        \\class GameEngine {
        \\  static update(elapsedTime) {
        \\    System.print(elapsedTime)
        \\  }
        \\}
    ;

    try harness.vm.interpret(module, script);

    harness.vm.ensureSlots(1);
    harness.vm.getVariable(module, "GameEngine", 0);
    const game_engine_class = harness.vm.getSlot(.Handle, 0) orelse return error.GetSlot;
    const update_method = harness.vm.makeCallHandle("update(_)") orelse return error.MakeCallHandle;
    {
        // Perform GameEngine.update method call
        harness.vm.setSlot(.Handle, 0, game_engine_class);
        harness.vm.setSlot(.Double, 1, 6.9);
        try harness.vm.call(update_method);
    }

    try testing.expectEqualStrings("6.9\n", harness.log.items);
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
    var harness = TestHarness{};
    try harness.init();
    defer harness.deinit();

    try harness.methods.put(testing.allocator, "main/Math.add(_,_)static", add);

    const module = "main";
    const script =
        \\class Math {
        \\  foreign static add(a, b)
        \\}
        \\System.print(Math.add(5, 4))
    ;

    try harness.vm.interpret(module, script);

    try testing.expectEqualStrings(
        \\Looking for method: main/Math.add(_,_)static
        \\9
        \\
    , harness.log.items);
}

const File = struct {
    buffer: [4096]u8 = undefined,
    slice: []u8 = undefined,
    fn from_anyopaque(self_ptr_opt: ?*anyopaque) *@This() {
        const self_ptr = self_ptr_opt orelse @panic("Passed null self ptr");
        return @ptrCast(*@This(), @constCast(@alignCast(@alignOf(@This()), self_ptr)));
    }
    fn allocate(vm_opt: ?*c.WrenVM) callconv(.C) void {
        const vm = VM.from_anyopaque(vm_opt);
        const self = File.from_anyopaque(vm.setSlotNewForeign(0, 0, @sizeOf(@This())));
        const path = vm.getSlot(.String, 1) orelse @panic("Couldn't get slot string");
        self.*.slice = std.fmt.bufPrint(&self.*.buffer, "{s}\n", .{path}) catch @panic("Couldn't bufPrint");
    }
    fn write(vm_opt: ?*c.WrenVM) callconv(.C) void {
        const vm = VM.from_anyopaque(vm_opt);
        const self = File.from_anyopaque(vm.getSlot(.Foreign, 0));
        const text_res = vm.getSlot(.String, 1) orelse @panic("Couldn't get slot string");
        const text = std.mem.span(text_res);
        self.*.slice = std.fmt.bufPrint(&self.*.buffer, "{s}", .{text}) catch @panic("Couldn't bufPrint");
    }
    fn close(vm_opt: ?*c.WrenVM) callconv(.C) void {
        _ = vm_opt;
    }
    fn finalize(self_ptr: ?*anyopaque) callconv(.C) void {
        const self = @ptrCast(*@This(), @alignCast(@alignOf(@This()), self_ptr));
        self.* = undefined;
    }
};

test "foreign class" {
    var harness = TestHarness{};
    try harness.init();
    defer harness.deinit();

    try harness.classes.put(testing.allocator, "main/File", .{ .allocate = File.allocate, .finalize = File.finalize });
    try harness.methods.put(testing.allocator, "main/File.write(_)", File.write);
    try harness.methods.put(testing.allocator, "main/File.close()", File.close);

    const module = "main";
    const script =
        \\foreign class File {
        \\  construct create(path) {}
        \\
        \\  foreign write(text)
        \\  foreign close()
        \\}
        \\var file = File.create("some/path.txt")
        \\file.write("hello!")
        \\file.close()
    ;

    try harness.vm.interpret(module, script);
    try testing.expectEqualStrings(
        \\Looking for class: main/File
        \\Looking for method: main/File.write(_)
        \\Looking for method: main/File.close()
        \\
    , harness.log.items);
}
