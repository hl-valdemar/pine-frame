const std = @import("std");

const pw = @import("pine-window");

// use pine-window's logging format
pub const std_options = std.Options{
    .logFn = pw.log.logFn,
};

pub fn main() !void {
    std.log.info("initializing pine window platform...", .{});

    // initialize the platform
    var plt = try pw.Platform.init();
    defer plt.deinit();

    std.log.info("creating window...", .{});

    // create windows with proper cleanup on errors
    var window = try pw.Window.init(&plt, .{
        .width = 800,
        .height = 600,
        .position = .{ .center = true },
        .title = "Pine Window # Main Window",
        .resizable = true,
        .visible = true,
    });
    defer window.deinit();

    std.log.info("window created successfully! starting event loop...", .{});

    // event loop - very similar to your original!
    while (!(window.shouldClose() catch true)) { // ...shouldClose() fails only if the window was destroyed
        plt.pollEvents();

        // add a small delay to prevent excessive cpu usage
        std.time.sleep(16 * std.time.ns_per_ms); // ~60 FPS
    }

    std.log.info("window closed, exiting...", .{});
}
