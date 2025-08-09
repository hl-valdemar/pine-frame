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

    // create a window
    var window = try pw.Window.init(&plt, .{
        .width = 400,
        .height = 300,
        .position = .{ .center = true },
        .title = "Pine Window # Keyboard Example",
        .resizable = true,
        .visible = true,
    });
    defer window.deinit();

    std.log.info("window created! press keys to see events. press esc to exit.", .{});

    // event loop with keyboard handling
    while (!(window.shouldClose() catch true)) {
        plt.pollEvents();

        // process all pending events
        while (try window.pollEvent()) |event| {
            switch (event) {
                .key_down => |key_event| {
                    logKeyEvent("pressed", &key_event);

                    // Exit on escape key
                    if (key_event.key == .escape) {
                        std.log.info("escape pressed, exiting...", .{});
                        window.requestClose();
                        break;
                    }
                },
                .key_up => |key_event| logKeyEvent("released", &key_event),
                .window_close => std.log.info("window close requested", .{}),
                .window_resize => std.log.info("window resized", .{}),
            }
        }

        // add a small delay to prevent excessive cpu usage
        std.time.sleep(16 * std.time.ns_per_ms); // ~60 FPS
    }

    std.log.info("exiting...", .{});
}

fn logKeyEvent(msg: []const u8, key_event: *const pw.KeyEvent) void {
    std.log.info("key {s}{s}: {s}{s}{s}{s}{s}", .{
        msg,
        if (key_event.is_repeat) " (repeat)" else "",
        @tagName(key_event.key),
        if (key_event.mods.shift) "+shift" else "",
        if (key_event.mods.control) "+ctrl" else "",
        if (key_event.mods.opt) "+opt" else "",
        if (key_event.mods.command) "+cmd" else "",
    });
}
