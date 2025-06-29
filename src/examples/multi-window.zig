const std = @import("std");
const pw = @import("pine-window");

// use pine-ecs' logging format
pub const std_options = std.Options{
    .logFn = pw.log.logFn,
};

pub fn main() !void {
    std.log.info("Initializing Pine Window platform...", .{});

    // initialize the platform
    var plt = try pw.Platform.init();
    defer plt.deinit();

    std.log.info("Creating window...", .{});

    // create a window
    var window1 = try pw.Window.create(.{
        .width = 800,
        .height = 600,
        .title = "Pine Window - Basic Example",
        .resizable = true,
        .visible = true,
    });

    std.log.info("First window created successfully!", .{});

    // create another window
    var window2 = try pw.Window.create(.{
        .width = 400,
        .height = 300,
        .title = "Pine Window - Basic Example",
        .resizable = true,
        .visible = true,
    });

    std.log.info("Second window created successfully! Starting event loop...", .{});

    var window1_closed = false;
    var window2_closed = false;

    // simple event loop
    var running = true;
    while (running) {
        plt.pollEvents();

        if (window1.shouldClose()) {
            window1.destroy();
            window1_closed = true;
        }

        if (window2.shouldClose()) {
            window2.destroy();
            window2_closed = true;
        }

        if (window1_closed and window2_closed)
            running = false;

        // add a small delay to prevent excessive cpu usage
        std.time.sleep(16 * std.time.ns_per_ms); // ~60 FPS
    }

    std.log.info("Windows closed, exiting...", .{});
}
