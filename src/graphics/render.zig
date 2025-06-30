const builtin = @import("builtin");

const Window = @import("pine-window").Window;

// platform-specific c imports - this is internal to the library
const c = switch (builtin.os.tag) {
    .macos => @cImport({
        @cInclude("macos.h");
    }),
    // future platforms...
    else => @compileError("Unsupported platform"),
};

// Render pass action types
pub const Action = enum(u32) {
    dontcare = 0,
    clear = 1,
    load = 2,
};

pub const ColorAttachment = struct {
    action: Action = .clear,
    r: f32 = 0.0,
    g: f32 = 0.0,
    b: f32 = 0.0,
    a: f32 = 1.0,
};

pub const DepthStencilAttachment = struct {
    action: Action = .dontcare,
    depth: f32 = 1.0,
    stencil: u8 = 0,
};

pub const PassAction = struct {
    color: ColorAttachment = .{},
    depth_stencil: DepthStencilAttachment = .{},
};

pub fn beginPass(window: *Window, pass_action: PassAction) void {
    const c_pass_action = c.PinePassAction{
        .color = c.PineColorAttachment{
            .action = @intFromEnum(pass_action.color.action),
            .r = pass_action.color.r,
            .g = pass_action.color.g,
            .b = pass_action.color.b,
            .a = pass_action.color.a,
        },
        .depth_stencil = c.PineDepthStencilAttachment{
            .action = @intFromEnum(pass_action.depth_stencil.action),
            .depth = pass_action.depth_stencil.depth,
            .stencil = pass_action.depth_stencil.stencil,
        },
    };

    c.pine_window_begin_pass(window.handle.?, &c_pass_action);
}

pub fn endPass(window: *Window) void {
    c.pine_window_end_pass(window.handle.?);
}

pub fn commit(window: *Window) void {
    c.pine_window_commit(window.handle.?);
}
