const std = @import("std");
const pindow = @import("pine-window");

// use pine-ecs' logging format
pub const std_options = std.Options{
    .logFn = pindow.log.logFn,
};

pub fn main() !void {
    std.log.info("Initializing Pine Window platform...", .{});

    // Initialize the platform
    var plt = try pindow.Platform.init();
    defer plt.deinit();

    std.log.info("Creating window...", .{});

    // Create a window
    var window = try pindow.Window.create(.{
        .width = 800,
        .height = 600,
        .title = "Pine Window - Basic Example",
        .resizable = true,
        .visible = true,
    });
    defer window.destroy();

    std.log.info("Window created successfully! Starting event loop...", .{});

    // Simple event loop
    while (!window.shouldClose()) {
        plt.pollEvents();

        // Add a small delay to prevent excessive CPU usage
        std.time.sleep(16 * std.time.ns_per_ms); // ~60 FPS
    }

    std.log.info("Window closed, exiting...", .{});
}
