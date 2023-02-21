const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "wren",
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 0, .minor = 4, .patch = 0 },
    });

    lib.linkLibC();

    lib.addIncludePath("../../src/include");
    lib.addIncludePath("../../src/vm");
    lib.addIncludePath("../../src/optional");

    lib.addCSourceFiles(&.{
        "../../src/vm/wren_compiler.c",
        "../../src/vm/wren_core.c",
        "../../src/vm/wren_debug.c",
        "../../src/optional/wren_opt_meta.c",
        "../../src/optional/wren_opt_random.c",
        "../../src/optional/wren_opt_random.c",
        "../../src/vm/wren_primitive.c",
        "../../src/vm/wren_utils.c",
        "../../src/vm/wren_value.c",
        "../../src/vm/wren_vm.c",
    }, &.{
        "",
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    lib.install();
    lib.installHeader("../../src/include/wren.h", "wren.h");

    // Creates a step for unit testing.
    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    main_tests.linkLibrary(lib);
    main_tests.installLibraryHeaders(lib);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
