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

    std.log.info("Creating window...", .{});

    // create a window
    var window = try pw.Window.create(.{
        .width = 800,
        .height = 600,
        .title = "Pine Window - Keyboard Example",
        .resizable = true,
        .visible = true,
    });
    defer window.destroy();

    std.log.info("Window created! Press keys to see events. Press ESC to exit.", .{});

    // event loop with keyboard handling
    while (!(window.shouldClose() catch true)) {
        plt.pollEvents();

        // process all pending events
        while (window.pollEvent()) |event| {
            switch (event) {
                .key_down => |key_event| {
                    std.log.info("Key pressed: {s}{s}{s}{s}{s}", .{
                        @tagName(key_event.key),
                        if (key_event.mods.shift) "+shift" else "",
                        if (key_event.mods.control) "+ctrl" else "",
                        if (key_event.mods.alt) "+alt" else "",
                        if (key_event.mods.command) "+cmd" else "",
                    });

                    // Exit on escape key
                    if (key_event.key == .q) {
                        std.log.info("Q pressed, exiting...", .{});
                        window.requestClose();
                        break;
                    }
                },
                .key_up => |key_event| {
                    std.log.info("Key released: {s}", .{@tagName(key_event.key)});
                },
                .window_close => {
                    std.log.info("Window close requested", .{});
                },
                .none => {},
            }
        }

        // add a small delay to prevent excessive cpu usage
        std.time.sleep(16 * std.time.ns_per_ms); // ~60 FPS
    }

    std.log.info("Exiting...", .{});
}
