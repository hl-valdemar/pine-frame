const std = @import("std");
const pw = @import("pine-window");

// use pine-window's logging format
pub const std_options = std.Options{
    .logFn = pw.log.logFn,
};

pub fn main() !void {
    std.log.info("Initializing Pine Window platform...", .{});

    // initialize the platform
    var plt = try pw.Platform.init();
    defer plt.deinit();

    std.log.info("Creating windows...", .{});

    // create windows with proper cleanup on errors
    var window1 = try pw.Window.create(.{
        .width = 800,
        .height = 600,
        .x = 100,
        .y = 100,
        .title = "Pine Window - Main Window",
        .resizable = true,
        .visible = true,
    });
    errdefer window1.destroy();

    var window2 = try pw.Window.create(.{
        .width = 400,
        .height = 300,
        .x = 200,
        .y = 200,
        .title = "Pine Window - Secondary Window",
        .resizable = true,
        .visible = true,
    });
    errdefer window2.destroy();

    std.log.info("Both windows created successfully! Starting event loop...", .{});

    // track window states
    var window1_closed = false;
    var window2_closed = false;

    // event loop - very similar to your original!
    while (!window1_closed or !window2_closed) {
        plt.pollEvents();

        // check and close window1 if needed
        if (!window1_closed and window1.shouldClose()) {
            std.log.info("Main window requested close", .{});
            window1.destroy();
            window1_closed = true;
        }

        // check and close window2 if needed
        if (!window2_closed and window2.shouldClose()) {
            std.log.info("Secondary window requested close", .{});
            window2.destroy();
            window2_closed = true;
        }

        // add a small delay to prevent excessive cpu usage
        std.time.sleep(16 * std.time.ns_per_ms); // ~60 FPS
    }

    std.log.info("All windows closed, exiting...", .{});
}
