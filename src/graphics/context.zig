const std = @import("std");
const builtin = @import("builtin");

const c = @import("c-imports").c;
const Window = @import("pine-window").Window;

pub const GraphicsError = error{
    BackendCreationFailed,
    ContextCreationFailed,
    SwapchainCreationFailed,
    NoSwapchain,
    BufferCreationFailed,
    ShaderCreationFailed,
    PipelineCreationFailed,
    BackendNotImplemented,
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

pub const Context = struct {
    backend: *c.PineGraphicsBackend,
    handle: *c.PineGraphicsContext,

    pub fn create(backend_type: Backend) !Context {
        const backend = switch (backend_type) {
            .metal => c.pine_create_metal_backend(),
            // TODO:
            // .vulkan => c.pine_create_vulkan_backend(),
            // .d3d12 => c.pine_create_d3d12_backend(),
            .auto => switch (builtin.os.tag) {
                .macos => c.pine_create_metal_backend(),
                // TODO:
                // .windows => c.pine_create_d3d12_backend(),
                // .linux => c.pine_create_vulkan_backend(),
                else => return GraphicsError.BackendNotImplemented,
            },
            else => return GraphicsError.BackendNotImplemented,
        };

        if (backend == null) return GraphicsError.BackendCreationFailed;

        const handle = backend.*.create_context.?();
        if (handle == null) return GraphicsError.ContextCreationFailed;

        return Context{
            .backend = backend,
            .handle = handle.?,
        };
    }

    pub fn destroy(self: *Context) void {
        self.backend.destroy_context.?(self.handle);
    }

    pub fn getCapabilities(self: *Context) GraphicsCapabilities {
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
    context: *Context,
    handle: *c.PineSwapchain,
    window: *Window,

    pub fn create(context: *Context, window: *Window) !Swapchain {
        // access window functions through the backend vtable
        const native_handle = window.backend.window_get_native_handle.?(window.handle);

        var width: u32 = undefined;
        var height: u32 = undefined;
        window.backend.window_get_size.?(window.handle, &width, &height);

        const config = c.PineSwapchainDesc{
            .native_window_handle = native_handle,
            .width = width,
            .height = height,
            .vsync = true,
        };

        const handle = context.backend.create_swapchain.?(context.handle, &config);
        if (handle == null) return GraphicsError.SwapchainCreationFailed;

        // associate swapchain with window
        window.backend.window_set_swapchain.?(window.handle, handle);

        return Swapchain{
            .context = context,
            .handle = handle.?,
            .window = window,
        };
    }

    pub fn destroy(self: *Swapchain) void {
        self.window.backend.window_set_swapchain.?(self.window.handle, null);
        self.context.backend.destroy_swapchain.?(self.handle);
    }

    pub fn present(self: *Swapchain) void {
        if (self.context.backend.present) |p| {
            p(self.handle);
        }
    }

    pub fn resize(self: *Swapchain, width: u32, height: u32) void {
        self.context.backend.resize_swapchain.?(self.handle, width, height);
    }
};

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

    pub fn setPipeline(self: *RenderPass, pipeline: *Pipeline) void {
        self.swapchain.context.backend.set_pipeline.?(self.handle, pipeline.handle);
    }

    pub fn setVertexBuffer(self: *RenderPass, index: u32, buffer: *Buffer) void {
        self.swapchain.context.backend.set_vertex_buffer.?(self.handle, index, buffer.handle);
    }

    pub fn draw(self: *RenderPass, vertex_count: u32, first_vertex: u32) void {
        self.swapchain.context.backend.draw.?(self.handle, vertex_count, first_vertex);
    }

    pub fn drawIndexed(self: *RenderPass, buffer: *Buffer, first_index: u32, vertex_offset: i32) void {
        self.swapchain.context.backend.draw_indexed.?(self.handle, buffer.handle, first_index, vertex_offset);
    }

    pub fn end(self: *RenderPass) void {
        self.swapchain.context.backend.end_render_pass.?(self.handle);
    }
};

// api that works with swapchains instead of windows
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

pub const BufferType = enum(u32) {
    vertex = 0,
    index = 1,
    uniform = 2,
};

pub const IndexType = enum(u32) {
    U16 = 0,
    U32 = 1,
};

pub const BufferDesc = struct {
    data: []const u8,
    type: BufferType = .vertex,
    index_type: IndexType = .U16,
};

pub const Buffer = struct {
    handle: *c.PineBuffer,
    context: *Context,
    len: usize,

    pub fn create(context: *Context, desc: BufferDesc) !Buffer {
        const c_desc = c.PineBufferDesc{
            .data = desc.data.ptr,
            .len = desc.data.len,
            .type = @intFromEnum(desc.type),
            .index_type = @intFromEnum(desc.index_type),
        };

        const handle = context.backend.create_buffer.?(context.handle, &c_desc);
        if (handle == null) return GraphicsError.BufferCreationFailed;

        return Buffer{
            .handle = handle.?,
            .context = context,
            .len = c_desc.len,
        };
    }

    pub fn destroy(self: *Buffer) void {
        self.context.backend.destroy_buffer.?(self.handle);
    }
};

pub const ShaderType = enum(u32) {
    vertex = 0,
    fragment = 1,
};

pub const Shader = struct {
    handle: *c.PineShader,
    context: *Context,

    pub fn create(context: *Context, source: [:0]const u8, shader_type: ShaderType) !Shader {
        const desc = c.PineShaderDesc{
            .source = source.ptr,
            .type = @intFromEnum(shader_type),
        };

        const handle = context.backend.create_shader.?(context.handle, &desc);
        if (handle == null) return GraphicsError.ShaderCreationFailed;

        return Shader{
            .handle = handle.?,
            .context = context,
        };
    }

    pub fn destroy(self: *Shader) void {
        self.context.backend.destroy_shader.?(self.handle);
    }
};

pub const VertexFormat = enum(u32) {
    float2 = 0,
    float3 = 1,
    float4 = 2,
};

pub const VertexAttribute = struct {
    format: VertexFormat,
    offset: usize,
    buffer_index: u32 = 0,
};

pub const PipelineDesc = struct {
    vertex_shader: *Shader,
    fragment_shader: *Shader,
    attributes: []const VertexAttribute,
    vertex_stride: usize,
};

pub const Pipeline = struct {
    handle: *c.PinePipeline,
    context: *Context,

    pub fn create(
        context: *Context,
        desc: PipelineDesc,
    ) !Pipeline {
        const allocator = std.heap.c_allocator;

        // convert attributes to c format
        var c_attrs = try allocator.alloc(c.PineVertexAttribute, desc.attributes.len);
        defer allocator.free(c_attrs);

        for (desc.attributes, 0..) |attr, i| {
            c_attrs[i] = .{
                .format = @intFromEnum(attr.format),
                .offset = attr.offset,
                .buffer_index = attr.buffer_index,
            };
        }

        const c_desc = c.PinePipelineDesc{
            .vertex_shader = desc.vertex_shader.handle,
            .fragment_shader = desc.fragment_shader.handle,
            .attributes = c_attrs.ptr,
            .attribute_count = desc.attributes.len,
            .vertex_stride = desc.vertex_stride,
        };

        const handle = context.backend.create_pipeline.?(context.handle, &c_desc);
        if (handle == null) return GraphicsError.PipelineCreationFailed;

        return Pipeline{
            .handle = handle.?,
            .context = context,
        };
    }

    pub fn destroy(self: *Pipeline) void {
        self.context.backend.destroy_pipeline.?(self.handle);
    }
};
