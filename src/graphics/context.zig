const std = @import("std");
const builtin = @import("builtin");
const Window = @import("pine-window").Window;
const c = @import("c-imports").c;

pub const GraphicsError = error{
    BackendCreationFailed,
    ContextCreationFailed,
    SwapchainCreationFailed,
    NoSwapchain,
};

pub const Backend = enum {
    metal,
    vulkan,
    d3d12,
    auto,
};

pub const GraphicsCapabilities = struct {
    compute_shaders: bool,
    tessellation: bool,
    geometry_shaders: bool,
    max_texture_size: u32,
    max_vertex_attributes: u32,
};

pub const GraphicsContext = struct {
    backend: *c.PineGraphicsBackend,
    handle: *c.PineGraphicsContext,

    pub fn create(backend_type: Backend) !GraphicsContext {
        const backend = switch (backend_type) {
            .metal => c.pine_create_metal_backend(),
            // .vulkan => c.pine_create_vulkan_backend(),
            // .d3d12 => c.pine_create_d3d12_backend(),
            .auto => switch (builtin.os.tag) {
                .macos => c.pine_create_metal_backend(),
                .windows => c.pine_create_d3d12_backend(),
                .linux => c.pine_create_vulkan_backend(),
                else => return GraphicsError.BackendCreationFailed,
            },
            else => @panic("Unsupported platform"),
        };

        if (backend == null) return GraphicsError.BackendCreationFailed;

        const handle = backend.*.create_context.?();
        if (handle == null) return GraphicsError.ContextCreationFailed;

        return GraphicsContext{
            .backend = backend,
            .handle = handle.?,
        };
    }

    pub fn destroy(self: *GraphicsContext) void {
        self.backend.destroy_context.?(self.handle);
    }

    pub fn getCapabilities(self: *GraphicsContext) GraphicsCapabilities {
        var caps: c.PineGraphicsCapabilities = undefined;
        self.backend.get_capabilities.?(self.handle, &caps);

        return GraphicsCapabilities{
            .compute_shaders = caps.compute_shaders,
            .tessellation = caps.tessellation,
            .geometry_shaders = caps.geometry_shaders,
            .max_texture_size = caps.max_texture_size,
            .max_vertex_attributes = caps.max_vertex_attributes,
        };
    }
};

pub const Swapchain = struct {
    context: *GraphicsContext,
    handle: *c.PineSwapchain,
    window: *Window,

    pub fn create(context: *GraphicsContext, window: *Window) !Swapchain {
        const native_handle = c.pine_window_get_native_handle(window.handle);

        var width: u32 = undefined;
        var height: u32 = undefined;
        c.pine_window_get_size(window.handle, &width, &height);

        const config = c.PineSwapchainDesc{
            .native_window_handle = native_handle,
            .width = width,
            .height = height,
            .vsync = true,
        };

        const handle = context.backend.create_swapchain.?(context.handle, &config);
        if (handle == null) return GraphicsError.SwapchainCreationFailed;

        // Associate swapchain with window
        c.pine_window_set_swapchain(window.handle, handle);

        return Swapchain{
            .context = context,
            .handle = handle.?,
            .window = window,
        };
    }

    pub fn destroy(self: *Swapchain) void {
        c.pine_window_set_swapchain(self.window.handle, null);
        self.context.backend.destroy_swapchain.?(self.handle);
    }

    pub fn resize(self: *Swapchain, width: u32, height: u32) void {
        self.context.backend.resize_swapchain.?(self.handle, width, height);
    }
};

// Keep the same PassAction types
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

pub const RenderPass = struct {
    swapchain: *Swapchain,
    handle: *c.PineRenderPass,

    pub fn end(self: *RenderPass) void {
        self.swapchain.context.backend.end_render_pass.?(self.handle);
    }
};

// New API that works with swapchains instead of windows
pub fn beginPass(swapchain: *Swapchain, pass_action: PassAction) !RenderPass {
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

    const handle = swapchain.context.backend.begin_render_pass.?(swapchain.handle, &c_pass_action);
    if (handle == null) return GraphicsError.NoSwapchain;

    return RenderPass{
        .swapchain = swapchain,
        .handle = handle.?,
    };
}

pub fn present(swapchain: *Swapchain) void {
    if (swapchain.context.backend.present) |p| {
        p(swapchain.handle);
    }
}
