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

pub const PineWindowError = error{
    PlatformInitFailed,
    WindowDestroyed,
    TitleTooLong,
    WindowCreationFailed,
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

pub const EventType = enum(u32) {
    none = 0,
    key_down,
    key_up,
    window_close,
};

pub const KeyCode = enum(i32) {
    unknown = -1,
    a = 0,
    s = 1,
    d = 2,
    f = 3,
    h = 4,
    g = 5,
    z = 6,
    x = 7,
    c = 8,
    v = 9,
    b = 11,
    q = 12,
    w = 13,
    e = 14,
    r = 15,
    y = 16,
    t = 17,
    one = 18,
    two = 19,
    three = 20,
    four = 21,
    six = 22,
    five = 23,
    nine = 25,
    seven = 26,
    eight = 28,
    zero = 29,
    o = 31,
    u = 32,
    i = 34,
    p = 35,
    enter = 36,
    l = 37,
    j = 38,
    k = 40,
    n = 45,
    m = 46,
    tab = 48,
    space = 49,
    backspace = 51,
    escape = 53,
    left = 123,
    right = 124,
    down = 125,
    up = 126,
};

pub const KeyModifiers = struct {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    command: bool = false, // macOS specific, maps to Windows key on other platforms
};

pub const KeyEvent = struct {
    key: KeyCode,
    mods: KeyModifiers,
};

pub const Event = union(EventType) {
    none: void,
    key_down: KeyEvent,
    key_up: KeyEvent,
    window_close: void,
};

pub const Window = struct {
    handle: ?*c.PineWindow,
    destroyed: bool,

    pub fn create(config: WindowConfig) !Window {
        // convert zig string to null-terminated c string
        // todo: support "infinite" strings
        var title_buffer: [256]u8 = undefined;
        const title_cstr = std.fmt.bufPrintZ(&title_buffer, "{s}", .{config.title}) catch {
            return PineWindowError.TitleTooLong;
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
        if (handle == null) return PineWindowError.WindowCreationFailed;

        return Window{
            .handle = handle.?,
            .destroyed = false,
        };
    }

    pub fn destroy(self: *Window) void {
        if (!self.destroyed) {
            c.pine_window_destroy(self.handle.?);
            self.handle = null;
            self.destroyed = true;
        }
    }

    pub fn show(self: *Window) void {
        c.pine_window_show(self.handle);
    }

    pub fn hide(self: *Window) void {
        c.pine_window_hide(self.handle);
    }

    pub fn shouldClose(self: *Window) PineWindowError!bool {
        if (self.destroyed) return PineWindowError.WindowDestroyed;
        return c.pine_window_should_close(self.handle.?);
    }

    pub fn requestClose(self: *Window) void {
        if (self.destroyed) return; // just ignore
        c.pine_window_request_close(self.handle.?);
    }

    pub fn pollEvent(self: *Window) ?Event {
        var c_event: c.PineEvent = undefined;
        if (!c.pine_window_poll_event(self.handle, &c_event)) {
            return null;
        }

        return switch (c_event.type) {
            c.PINE_EVENT_NONE => Event{ .none = {} },
            c.PINE_EVENT_KEY_DOWN => Event{
                .key_down = KeyEvent{
                    .key = @enumFromInt(c_event.data.key_event.key),
                    .mods = KeyModifiers{
                        .shift = c_event.data.key_event.shift,
                        .control = c_event.data.key_event.control,
                        .alt = c_event.data.key_event.alt,
                        .command = c_event.data.key_event.command,
                    },
                },
            },
            c.PINE_EVENT_KEY_UP => Event{
                .key_up = KeyEvent{
                    .key = @enumFromInt(c_event.data.key_event.key),
                    .mods = KeyModifiers{
                        .shift = c_event.data.key_event.shift,
                        .control = c_event.data.key_event.control,
                        .alt = c_event.data.key_event.alt,
                        .command = c_event.data.key_event.command,
                    },
                },
            },
            c.PINE_EVENT_WINDOW_CLOSE => Event{ .window_close = {} },
            else => Event{ .none = {} },
        };
    }
};

pub const Platform = struct {
    initialized: bool = false,

    pub fn init() !Platform {
        if (!c.pine_platform_init()) {
            return PineWindowError.PlatformInitFailed;
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
