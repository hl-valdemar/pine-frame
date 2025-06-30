const std = @import("std");
const pw = @import("pine-window");
const pg = @import("pine-graphics");

pub const std_options = std.Options{
    .logFn = pw.log.logFn,
};

pub fn main() !void {
    std.log.info("initializing pine window platform...", .{});

    // initialize the platform
    var plt = try pw.Platform.init();
    defer plt.deinit();

    std.log.info("creating graphics context...", .{});

    // create graphics context (auto-selects best backend for platform)
    var graphics_ctx = try pg.GraphicsContext.create(.auto);
    defer graphics_ctx.destroy();

    // query and log graphics capabilities
    const caps = graphics_ctx.getCapabilities();
    std.log.info("graphics backend capabilities:", .{});
    std.log.info("  - compute shaders: {}", .{caps.compute_shaders});
    std.log.info("  - tessellation: {}", .{caps.tessellation});
    std.log.info("  - max texture size: {}", .{caps.max_texture_size});

    std.log.info("creating window...", .{});

    // create a window
    var window = try pw.Window.create(std.heap.page_allocator, .{
        .width = 800,
        .height = 600,
        .position = .{ .center = true },
        .title = "Pine Window # Clear Example",
        .resizable = true,
        .visible = true,
    });
    defer window.destroy();

    std.log.info("creating swapchain...", .{});

    // create swapchain for the window
    var swapchain = try pg.Swapchain.create(&graphics_ctx, &window);
    defer swapchain.destroy();

    std.log.info("starting event loop...", .{});

    // event loop
    var frame_count: u32 = 0;
    while (!try window.shouldClose()) {
        plt.pollEvents();

        // handle window resize
        // TODO: Add window resize event handling
        // if (window.wasResized()) {
        //     const size = window.getSize();
        //     swapchain.resize(size.width, size.height);
        // }

        // begin render pass
        var render_pass = try pg.beginPass(&swapchain, .{
            .color = .{
                .action = .clear,
                .r = @sin(@as(f32, @floatFromInt(frame_count)) * 0.01) * 0.5 + 0.5,
                .g = 0.3,
                .b = 0.3,
                .a = 1.0,
            },
        });

        // render commands would go here...

        // end render pass
        render_pass.end();

        // present the frame
        pg.present(&swapchain);

        frame_count += 1;
        std.time.sleep(16 * std.time.ns_per_ms); // ~60 fps
    }

    std.log.info("window closed, exiting...", .{});
}
