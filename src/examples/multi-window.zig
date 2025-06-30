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

    std.log.info("creating windows...", .{});

    // create windows with proper cleanup on errors
    var window1 = try pw.Window.create(std.heap.page_allocator, .{
        .width = 800,
        .height = 600,
        .position = .{ .center = true },
        .title = "Pine Window - Main Window",
        .resizable = true,
        .visible = true,
    });
    errdefer window1.destroy();

    var window2 = try pw.Window.create(std.heap.page_allocator, .{
        .width = 400,
        .height = 300,
        .position = .{ .x = 20, .y = 20 },
        .title = "Pine Window - Secondary Window",
        .resizable = true,
        .visible = true,
    });
    errdefer window2.destroy();

    std.log.info("both windows created successfully! starting event loop...", .{});

    // event loop - very similar to your original!
    while (!(window1.shouldClose() catch true) or // ...shouldClose() fails only if the window was destroyed
        !(window2.shouldClose() catch true))
    {
        plt.pollEvents();

        // check and close window1 if needed
        if (window1.shouldClose() catch false) { // again, if shouldClose fails, the window is already destroyed
            std.log.info("main window requested close", .{});
            window1.destroy();
        }

        // check and close window2 if needed
        if (window2.shouldClose() catch false) {
            std.log.info("secondary window requested close", .{});
            window2.destroy();
        }

        // add a small delay to prevent excessive cpu usage
        std.time.sleep(16 * std.time.ns_per_ms); // ~60 FPS
    }

    std.log.info("all windows closed, exiting...", .{});
}
