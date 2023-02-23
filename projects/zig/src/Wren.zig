//! Provides a small zig wrapper for the Wren API

const Wren = @This();

config: c.WrenConfiguration = undefined,

const Options = struct {
    reallocateFn: ?c.WrenReallocateFn = null,
    resolveModuleFn: ?c.WrenResolveModuleFn = null,
    loadModuleFn: ?c.WrenLoadModuleFn = null,
    bindForeignMethodFn: ?c.WrenBindForeignMethodFn = null,
    bindForeignClassFn: ?c.WrenBindForeignClassFn = null,
    writeFn: ?c.WrenWriteFn = null,
    errorFn: ?c.WrenErrorFn = null,
    initial_heap_size: ?usize = null,
    min_heap_size: ?usize = null,
    heap_growth_percent: ?c_int = null,
    userData: ?*anyopaque = null,
};

pub fn init(opt: Options) Wren {
    var self = Wren{};
    c.wrenInitConfiguration(&self.config);
    // Configure wren
    if (opt.reallocateFn) |reallocateFn| self.config.reallocateFn = reallocateFn;
    if (opt.resolveModuleFn) |resolveModuleFn| self.config.resolveModuleFn = resolveModuleFn;
    if (opt.loadModuleFn) |loadModuleFn| self.config.loadModuleFn = loadModuleFn;
    if (opt.bindForeignClassFn) |bindForeignClassFn| self.config.bindForeignClassFn = bindForeignClassFn;
    if (opt.bindForeignMethodFn) |bindForeignMethodFn| self.config.bindForeignMethodFn = bindForeignMethodFn;
    if (opt.writeFn) |writeFn| self.config.writeFn = writeFn;
    if (opt.errorFn) |errorFn| self.config.errorFn = errorFn;
    if (opt.initial_heap_size) |initial_heap_size| self.config.initialHeapSize = initial_heap_size;
    if (opt.min_heap_size) |min_heap_size| self.config.minHeapSize = min_heap_size;
    if (opt.heap_growth_percent) |heap_growth_percent| self.config.heapGrowthPercent = heap_growth_percent;
    if (opt.userData) |userData| self.config.userData = userData;
    return self;
}

pub fn getVersionNumber() c_int {
    return c.wrenGetVersionNumber();
}

pub fn new(self: *Wren) !*VM {
    var vm: *c.WrenVM = c.wrenNewVM(&self.config) orelse return error.NullVM;
    return @ptrCast(*VM, vm);
}

pub const VM = opaque {
    /// Casts anyopaque to self pointer
    pub fn from_anyopaque(ptr_opt: ?*anyopaque) *@This() {
        const ptr = ptr_opt orelse @panic("Passed null ptr");
        return @ptrCast(*@This(), @constCast(@alignCast(@alignOf(@This()), ptr)));
    }
    /// Turns opaque pointer into a *c.WrenVM
    fn as_raw(vm: *VM) *c.WrenVM {
        return @ptrCast(*c.WrenVM, @constCast(@alignCast(@alignOf(@This()), vm)));
    }
    /// Frees the VM
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
    pub fn releaseHandle(vm: *VM, handle: *c.WrenHandle) void {
        c.wrenReleaseHandle(vm.as_raw(), handle);
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

/// Converts a Wren result code into a zig error
pub fn handle_result(result: c.WrenInterpretResult) !void {
    switch (result) {
        c.WREN_RESULT_SUCCESS => {},
        c.WREN_RESULT_COMPILE_ERROR => return error.Compile,
        c.WREN_RESULT_RUNTIME_ERROR => return error.Runtime,
        else => return error.Unexpected,
    }
}

const std = @import("std");
const c = @import("c.zig");
