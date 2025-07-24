const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const c = @import("c-imports").c;

pub const PineWindowError = error{
    PlatformInitFailed,
    WindowDestroyed,
    TitleTooLong,
    WindowCreationFailed,
    BackendCreationFailed,
    BackendNotImplemented,
};

pub const WindowBackend = enum {
    cocoa, // macOS
    win32, // windows
    x11, // linux x11
    wayland, // linux wayland
    auto, // auto-detect best for platform
};

pub const Platform = struct {
    backend: *c.PineWindowBackend,
    initialized: bool = false,

    pub fn init() !Platform {
        return initWithBackend(.auto);
    }

    pub fn initWithBackend(backend_type: WindowBackend) !Platform {
        const backend = switch (backend_type) {
            .cocoa => c.pine_create_cocoa_backend(),
            // TODO: implement these backends
            // .win32 => c.pine_create_win32_backend(),
            // .x11 => c.pine_create_x11_backend(),
            // .wayland => c.pine_create_wayland_backend(),
            .auto => switch (builtin.os.tag) {
                .macos => c.pine_create_cocoa_backend(),
                // TODO:
                // .windows => c.pine_create_win32_backend(),
                // .linux => c.pine_create_x11_backend(), // or wayland based on detection
                else => return PineWindowError.BackendNotImplemented,
            },
            else => return PineWindowError.BackendNotImplemented,
        };

        if (backend == null) return PineWindowError.BackendCreationFailed;

        if (!backend.*.platform_init.?()) {
            return PineWindowError.PlatformInitFailed;
        }

        return Platform{
            .backend = backend,
            .initialized = true,
        };
    }

    pub fn deinit(self: *Platform) void {
        if (self.initialized) {
            self.backend.platform_shutdown.?();
            self.initialized = false;
        }
    }

    pub fn pollEvents(self: *const Platform) void {
        self.backend.platform_poll_events.?();
    }

    // utility method for creating a window without having to pass the platform
    pub fn createWindow(self: *const Platform, desc: WindowDesc) !Window {
        try Window.init(self, desc);
    }
};

pub const WindowDesc = struct {
    width: i32 = 800,
    height: i32 = 600,
    position: struct {
        x: i32 = 0,
        y: i32 = 0,
        center: bool = false,
    } = .{},
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

    pub fn asUsize(self: KeyCode) usize {
        return @as(usize, @intCast(@intFromEnum(self)));
    }

    pub fn maxValue() i32 {
        const type_info = @typeInfo(KeyCode).@"enum";
        var max_value = type_info.fields[0].value;
        for (type_info.fields) |field| {
            if (field.value > max_value) {
                max_value = field.value;
            }
        }
        return max_value;
    }
};

pub const KeyModifiers = struct {
    shift: bool = false,
    control: bool = false,
    opt: bool = false,
    command: bool = false, // macOS specific, maps to windows key on other platforms
};

pub const KeyEvent = struct {
    key: KeyCode,
    mods: KeyModifiers,
    is_repeat: bool = false,
    window_id: WindowID,
};

pub const Event = union(EventType) {
    none: void,
    key_down: KeyEvent,
    key_up: KeyEvent,
    window_close: struct {
        id: WindowID,
    },
};

pub const WindowID = usize;

pub const Window = struct {
    var next_id: WindowID = 0;

    backend: *c.PineWindowBackend,
    handle: ?*c.PineWindow,
    id: WindowID,
    destroyed: bool,
    key_states: [KeyCode.maxValue()]EventType, // without .unknown

    pub fn init(platform: *Platform, config: WindowDesc) !Window {
        const backend = platform.backend;
        const allocator = std.heap.c_allocator;

        const title_cstr = try std.fmt.allocPrintZ(allocator, "{s}", .{config.title});
        defer allocator.free(title_cstr);

        const c_config = c.PineWindowDesc{
            .width = config.width,
            .height = config.height,
            .position = .{
                .x = config.position.x,
                .y = config.position.y,
                .center = config.position.center,
            },
            .title = title_cstr.ptr,
            .resizable = config.resizable,
            .visible = config.visible,
        };

        const handle = backend.window_create.?(&c_config);
        if (handle == null) return PineWindowError.WindowCreationFailed;

        return Window{
            .backend = backend,
            .handle = handle.?,
            .id = nextId(),
            .destroyed = false,
            .key_states = [_]EventType{.none} ** KeyCode.maxValue(),
        };
    }

    pub fn deinit(self: *Window) void {
        if (!self.destroyed) {
            self.backend.window_destroy.?(self.handle.?);
            self.handle = null;
            self.destroyed = true;
        }
    }

    pub fn show(self: *Window) void {
        self.backend.window_show.?(self.handle);
    }

    pub fn hide(self: *Window) void {
        self.backend.window_hide.?(self.handle);
    }

    pub fn shouldClose(self: *Window) PineWindowError!bool {
        if (self.destroyed) return PineWindowError.WindowDestroyed;
        return self.backend.window_should_close.?(self.handle.?);
    }

    pub fn requestClose(self: *Window) void {
        if (self.destroyed) return; // just ignore
        self.backend.window_request_close.?(self.handle.?);
    }

    pub fn pollEvent(self: *Window) !?Event {
        var c_event: c.PineEvent = undefined;
        if (!self.backend.window_poll_event.?(self.handle, &c_event)) {
            return null;
        }

        return switch (c_event.type) {
            c.PINE_EVENT_NONE => Event{ .none = {} },
            c.PINE_EVENT_KEY_DOWN => {
                var key_event = KeyEvent{
                    .key = std.meta.intToEnum(KeyCode, c_event.data.key_event.key) catch .unknown,
                    .mods = KeyModifiers{
                        .shift = c_event.data.key_event.shift,
                        .control = c_event.data.key_event.control,
                        .opt = c_event.data.key_event.opt,
                        .command = c_event.data.key_event.command,
                    },
                    .is_repeat = false,
                    .window_id = self.id,
                };

                // first check previous key state
                if (self.key_states[key_event.key.asUsize()] == .key_down) {
                    key_event.is_repeat = true;
                }
                // then set new key state
                self.key_states[key_event.key.asUsize()] = .key_down;

                return Event{ .key_down = key_event };
            },
            c.PINE_EVENT_KEY_UP => {
                var key_event = KeyEvent{
                    .key = std.meta.intToEnum(KeyCode, c_event.data.key_event.key) catch .unknown,
                    .mods = KeyModifiers{
                        .shift = c_event.data.key_event.shift,
                        .control = c_event.data.key_event.control,
                        .opt = c_event.data.key_event.opt,
                        .command = c_event.data.key_event.command,
                    },
                    .is_repeat = false,
                    .window_id = self.id,
                };

                // NOTE: this may be foolish if no platforms release events when no key is pressed.
                // if that's the case, then all key-up events will be essentially unable to "repeat".
                {
                    // first check previous key state
                    if (self.key_states[key_event.key.asUsize()] == .key_up) {
                        key_event.is_repeat = true;
                    }
                    // then set new key state
                    self.key_states[key_event.key.asUsize()] = .key_up;
                }

                return Event{ .key_up = key_event };
            },
            c.PINE_EVENT_WINDOW_CLOSE => Event{
                .window_close = .{ .id = self.id },
            },
            else => Event{ .none = {} },
        };
    }

    fn nextId() WindowID {
        defer next_id += 1;
        return next_id;
    }
};
