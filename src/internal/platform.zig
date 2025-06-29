const std = @import("std");
const builtin = @import("builtin");

// platform-specific c imports - this is internal to the library
const c = switch (builtin.os.tag) {
    .macos => @cImport({
        @cInclude("macos_bridge.h");
    }),
    // future platforms...
    else => @compileError("Unsupported platform"),
};

pub const WindowConfig = struct {
    width: i32 = 800,
    height: i32 = 600,
    x: i32 = 100,
    y: i32 = 100,
    title: []const u8 = "Pine Window",
    resizable: bool = true,
    visible: bool = true,
};

pub const Window = struct {
    handle: *c.PineWindow,

    pub fn create(config: WindowConfig) !Window {
        // convert zig string to null-terminated c string
        var title_buffer: [256]u8 = undefined;
        const title_cstr = std.fmt.bufPrintZ(&title_buffer, "{s}", .{config.title}) catch {
            return error.TitleTooLong;
        };

        const c_config = c.PineWindowConfig{
            .width = config.width,
            .height = config.height,
            .x = config.x,
            .y = config.y,
            .title = title_cstr.ptr,
            .resizable = config.resizable,
            .visible = config.visible,
        };

        const handle = c.pine_window_create(&c_config);
        if (handle == null) {
            return error.WindowCreationFailed;
        }

        return Window{
            .handle = handle.?,
        };
    }

    pub fn destroy(self: *Window) void {
        c.pine_window_destroy(self.handle);
    }

    pub fn show(self: *Window) void {
        c.pine_window_show(self.handle);
    }

    pub fn hide(self: *Window) void {
        c.pine_window_hide(self.handle);
    }

    pub fn shouldClose(self: *Window) bool {
        return c.pine_window_should_close(self.handle);
    }
};

pub const Platform = struct {
    initialized: bool = false,

    pub fn init() !Platform {
        if (!c.pine_platform_init()) {
            return error.PlatformInitFailed;
        }

        return Platform{
            .initialized = true,
        };
    }

    pub fn deinit(self: *Platform) void {
        if (self.initialized) {
            c.pine_platform_shutdown();
            self.initialized = false;
        }
    }

    pub fn pollEvents(_: *Platform) void {
        c.pine_platform_poll_events();
    }
};
