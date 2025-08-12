const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zm_dep = b.dependency("zm", .{
        .target = target,
        .optimize = optimize,
    });

    // create the pine-window library module
    const window_lib_mod = b.addModule("pine-window", .{
        .root_source_file = b.path("src/window/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // create static pine-window library
    const window_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "pine-window",
        .root_module = window_lib_mod,
    });

    // create the pine-graphics library module
    const graphics_lib_mod = b.addModule("pine-graphics", .{
        .root_source_file = b.path("src/graphics/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // create static pine-window library
    const graphics_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "pine-graphics",
        .root_module = graphics_lib_mod,
    });

    // create the c-imports library module for shared c imports
    const c_imports_mod = b.addModule("c-imports", .{
        .root_source_file = b.path("src/c-imports.zig"),
        .target = target,
        .optimize = optimize,
    });
    c_imports_mod.addIncludePath(b.path("src/bridge"));

    window_lib_mod.addImport("pine-graphics", graphics_lib_mod);
    window_lib_mod.addImport("c-imports", c_imports_mod);

    graphics_lib_mod.addImport("pine-window", window_lib_mod);
    graphics_lib_mod.addImport("c-imports", c_imports_mod);

    // link platform specific dependencies
    if (target.result.os.tag == .macos) {
        // window module only needs window-related frameworks
        const cocoa_backend_lib = b.addStaticLibrary(.{
            .name = "pine-cocoa-window",
            .target = target,
            .optimize = optimize,
        });

        cocoa_backend_lib.addCSourceFile(.{
            .file = b.path("src/bridge/window/cocoa-backend.m"),
            .language = .objective_c,
            .flags = &[_][]const u8{
                "-fmodules",
                if (optimize == .Debug) "-DDEBUG" else "",
            },
        });
        cocoa_backend_lib.addCSourceFile(.{
            .file = b.path("src/bridge/log.c"),
            .language = .c,
            .flags = &[_][]const u8{
                if (optimize == .Debug) "-DDEBUG" else "",
            },
        });

        cocoa_backend_lib.linkFramework("Cocoa");
        cocoa_backend_lib.linkFramework("Foundation");

        window_lib.linkLibrary(cocoa_backend_lib);

        // graphics module gets its own metal backend
        const metal_backend_lib = b.addStaticLibrary(.{
            .name = "pine-metal-backend",
            .target = target,
            .optimize = optimize,
        });

        metal_backend_lib.addCSourceFile(.{
            .file = b.path("src/bridge/graphics/metal-backend.m"),
            .language = .objective_c,
            .flags = &[_][]const u8{
                "-fmodules",
                if (optimize == .Debug) "-DDEBUG" else "",
            },
        });
        metal_backend_lib.addCSourceFile(.{
            .file = b.path("src/bridge/log.c"),
            .language = .c,
            .flags = &[_][]const u8{
                if (optimize == .Debug) "-DDEBUG" else "",
            },
        });

        metal_backend_lib.linkFramework("Metal");
        metal_backend_lib.linkFramework("MetalKit");
        metal_backend_lib.linkFramework("QuartzCore");
        metal_backend_lib.linkFramework("Cocoa"); // for NSView

        graphics_lib.linkLibrary(metal_backend_lib);
    }

    // install relevant libraries in the zig-out folder
    b.installArtifact(window_lib);
    b.installArtifact(graphics_lib);

    // tests steps
    const window_lib_unit_tests = b.addTest(.{
        .root_module = window_lib_mod,
    });

    const run_window_lib_unit_tests = b.addRunArtifact(window_lib_unit_tests);

    const window_test_step = b.step("test-window", "Run unit tests for pine-window");
    window_test_step.dependOn(&run_window_lib_unit_tests.step);

    // doc steps
    const install_window_docs = b.addInstallDirectory(.{
        .source_dir = window_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs/pine-window",
    });

    const window_docs_step = b.step("docs-window", "Install pine-window docs into zig-out/docs/pine-window");
    window_docs_step.dependOn(&install_window_docs.step);

    const install_graphics_docs = b.addInstallDirectory(.{
        .source_dir = graphics_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs/pine-graphics",
    });

    const graphics_docs_step = b.step("docs-graphics", "Install pine-window docs into zig-out/docs/pine-graphics");
    graphics_docs_step.dependOn(&install_graphics_docs.step);

    // create executable modules for all examples
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try addExamples(
        allocator,
        b,
        EXAMPLES_DIR,
        &.{ .{
            .name = "pine-window",
            .module = window_lib_mod,
        }, .{
            .name = "pine-graphics",
            .module = graphics_lib_mod,
        }, .{
            .name = "zm",
            .module = zm_dep.module("zm"),
        } },
        .{
            .target = target,
            .optimize = optimize,
        },
    );
}

const EXAMPLES_DIR = "examples/";

/// Create executable modules for each example in `EXAMPLES_DIR`.
///
/// Note: assumes path with trailing '/' (slash).
fn addExamples(
    allocator: std.mem.Allocator,
    b: *std.Build,
    path: []const u8,
    imports: []const struct {
        name: []const u8,
        module: *std.Build.Module,
    },
    options: struct {
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    },
) !void {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
    var it = dir.iterate();
    while (try it.next()) |file| {
        switch (file.kind) {
            .file => {
                if (std.mem.eql(u8, file.name, "main.zig")) {
                    // create executable module
                    const full_path = b.pathJoin(&.{ path, file.name });
                    const exe_mod = b.createModule(.{
                        .root_source_file = b.path(full_path),
                        .target = options.target,
                        .optimize = options.optimize,
                    });

                    for (imports) |import| {
                        exe_mod.addImport(import.name, import.module);
                    }

                    // extract name
                    var dir_names = std.mem.splitScalar(u8, path, '/');
                    var example_name: []const u8 = undefined;
                    while (dir_names.next()) |name| {
                        example_name = name;
                    } // get the last name in the path (parent of `main.zig`)

                    // create executable
                    const exe = b.addExecutable(.{
                        .name = example_name,
                        .root_module = exe_mod,
                    });

                    b.installArtifact(exe);

                    // run step
                    const run_cmd = b.addRunArtifact(exe);
                    run_cmd.step.dependOn(b.getInstallStep());

                    if (b.args) |args| {
                        run_cmd.addArgs(args);
                    }

                    const run_desc = try std.fmt.allocPrint(allocator, "Run {s} example", .{example_name});
                    defer allocator.free(run_desc);

                    const run_step = b.step(example_name, run_desc);
                    run_step.dependOn(&run_cmd.step);
                }
            },
            .directory => {
                try addExamples(allocator, b, b.pathJoin(&.{ path, file.name }), imports, options);
            },
            else => {},
        }
    }
}
