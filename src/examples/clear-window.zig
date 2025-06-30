const std = @import("std");
const pw = @import("pine-window");
const pg = @import("pine-graphics");

// use pine-ecs' logging format
pub const std_options = std.Options{
    .logFn = pw.log.logFn,
};

pub fn main() !void {
    std.log.info("initializing pine window platform...", .{});

    // initialize the platform
    var plt = try pw.Platform.init();
    defer plt.deinit();

    std.log.info("creating window...", .{});

    // create a window
    var window = try pw.Window.create(std.heap.page_allocator, .{
        .width = 800,
        .height = 600,
        .title = "Pine Window - Basic Example",
        .resizable = true,
        .visible = true,
    });
    defer window.destroy();

    std.log.info("window created successfully! starting event loop...", .{});

    // simple event loop
    while (!try window.shouldClose()) {
        plt.pollEvents();

        pg.render.beginPass(&window, .{
            .color = .{ .action = .clear },
        });

        // render logic here...

        pg.render.endPass(&window);
        pg.render.commit(&window);

        // add a small delay to prevent excessive cpu usage
        std.time.sleep(16 * std.time.ns_per_ms); // ~60 FPS
    }

    std.log.info("window closed, exiting...", .{});
}
