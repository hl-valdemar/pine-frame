const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
        // const platform_dep_lib = b.addStaticLibrary(.{
        //     .name = "pine-platform-dep",
        //     .target = target,
        //     .optimize = optimize,
        // });
        //
        // platform_dep_lib.addCSourceFile(.{
        //     .file = b.path("src/bridge/window/macos.m"),
        //     .language = .objective_c,
        //     .flags = &[_][]const u8{"-fmodules"},
        // });
        // platform_dep_lib.addCSourceFile(.{
        //     .file = b.path("src/bridge/graphics/metal-backend.m"),
        //     .language = .objective_c,
        //     .flags = &[_][]const u8{"-fmodules"},
        // });
        //
        // platform_dep_lib.linkFramework("Metal");
        // platform_dep_lib.linkFramework("MetalKit");
        // platform_dep_lib.linkFramework("QuartzCore");
        // platform_dep_lib.linkFramework("Cocoa"); // For NSView
        //
        // window_lib.linkLibrary(platform_dep_lib);
        // graphics_lib.linkLibrary(platform_dep_lib);

        // window module only needs window-related frameworks
        const macos_window_lib = b.addStaticLibrary(.{
            .name = "pine-cocoa-window",
            .target = target,
            .optimize = optimize,
        });

        macos_window_lib.addCSourceFile(.{
            .file = b.path("src/bridge/window/cocoa-backend.m"),
            .language = .objective_c,
            .flags = &[_][]const u8{"-fmodules"},
        });
        macos_window_lib.linkFramework("Cocoa");
        macos_window_lib.linkFramework("Foundation");

        window_lib.linkLibrary(macos_window_lib);

        // graphics module gets its own metal backend
        const metal_backend_lib = b.addStaticLibrary(.{
            .name = "pine-metal-backend",
            .target = target,
            .optimize = optimize,
        });

        metal_backend_lib.addCSourceFile(.{
            .file = b.path("src/bridge/graphics/metal-backend.m"),
            .language = .objective_c,
            .flags = &[_][]const u8{"-fmodules"},
        });

        metal_backend_lib.linkFramework("Metal");
        metal_backend_lib.linkFramework("MetalKit");
        metal_backend_lib.linkFramework("QuartzCore");
        metal_backend_lib.linkFramework("Cocoa"); // For NSView

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

    // create executable modules for each example in src/examples/
    const examples_path = "src/examples/";
    var dir = try std.fs.cwd().openDir(examples_path, .{ .iterate = true });
    var it = dir.iterate();
    while (try it.next()) |file| {
        if (file.kind != .file) continue;

        // create executable module
        const full_path = b.pathJoin(&.{ examples_path, file.name });
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(full_path),
            .target = target,
            .optimize = optimize,
        });

        exe_mod.addImport("pine-window", window_lib_mod);
        exe_mod.addImport("pine-graphics", graphics_lib_mod);

        // extract name
        var words = std.mem.splitAny(u8, file.name, ".");
        const example_name = words.next().?;

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

        const allocator = std.heap.page_allocator;
        const run_step_desc = std.fmt.allocPrint(allocator, "Run {s} example", .{example_name}) catch "format failed";
        defer allocator.free(run_step_desc);

        const run_step = b.step(example_name, run_step_desc);
        run_step.dependOn(&run_cmd.step);

        // // test steps
        // const exe_unit_tests = b.addTest(.{
        //     .root_module = exe_mod,
        // });
        //
        // const examples_test_step = b.step("test-examples", "Run unit tests for examples");
        //
        // const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
        // examples_test_step.dependOn(&run_exe_unit_tests.step);
    }
}
