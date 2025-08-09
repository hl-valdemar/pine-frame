const std = @import("std");
const zm = @import("zm");

const pg = @import("pine-graphics");
const pw = @import("pine-window");

pub const std_options = std.Options{
    .logFn = pw.log.logFn,
};

const Vertex = struct {
    position: [3]f32,
    color: [3]f32,
};

const UniformData = extern struct {
    mvp_matrix: [4][4]f32,
};

// metal shader for 3d rendering
const metal_shader_source =
    \\#include <metal_stdlib>
    \\using namespace metal;
    \\
    \\struct Uniforms {
    \\    float4x4 mvp_matrix;
    \\};
    \\
    \\struct Vertex {
    \\    float3 position [[attribute(0)]];
    \\    float3 color [[attribute(1)]];
    \\};
    \\
    \\struct VertexOut {
    \\    float4 position [[position]];
    \\    float3 color;
    \\};
    \\
    \\vertex VertexOut vertex_main(
    \\    Vertex in [[stage_in]],
    \\    constant Uniforms& uniforms [[buffer(1)]]
    \\) {
    \\    VertexOut out;
    \\    out.position = uniforms.mvp_matrix * float4(in.position, 1.0);
    \\    out.color = in.color;
    \\    return out;
    \\}
    \\
    \\fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    \\    return float4(in.color, 1.0);
    \\}
;

pub fn main() !void {
    std.log.info("initializing pine cube demo...", .{});

    // initialize platform and graphics
    var plt = try pw.Platform.init();
    defer plt.deinit();

    var graphics_ctx = try pg.GraphicsContext.init(.auto);
    defer graphics_ctx.deinit();

    // create window
    const default_width: f64 = 800;
    const default_height: f64 = 600;
    var window = try pw.Window.init(&plt, .{
        .width = default_width,
        .height = default_height,
        .position = .{ .center = true },
        .title = "Pine Engine - 3D Cube",
        .resizable = true,
        .visible = true,
    });
    defer window.deinit();

    // create swapchain
    var swapchain = try pg.Swapchain.init(&graphics_ctx, &window);
    defer swapchain.deinit();

    // create shaders
    var vertex_shader = try pg.Shader.init(&graphics_ctx, metal_shader_source, .vertex);
    defer vertex_shader.deinit();

    var fragment_shader = try pg.Shader.init(&graphics_ctx, metal_shader_source, .fragment);
    defer fragment_shader.deinit();

    // define vertex attributes for 3d positions
    const attributes = [_]pg.VertexAttribute{
        .{ .format = .float3, .offset = @offsetOf(Vertex, "position") },
        .{ .format = .float3, .offset = @offsetOf(Vertex, "color") },
    };

    // create pipeline
    var pipeline = try pg.Pipeline.init(&graphics_ctx, .{
        .vertex_shader = &vertex_shader,
        .fragment_shader = &fragment_shader,
        .attributes = &attributes,
        .vertex_stride = @sizeOf(Vertex),
    });
    defer pipeline.deinit();

    // define cube vertices (8 vertices)
    const vertices = [_]Vertex{
        // front face (red tints)
        .{ .position = .{ -0.5, -0.5, 0.5 }, .color = .{ 1.0, 0.0, 0.0 } },
        .{ .position = .{ 0.5, -0.5, 0.5 }, .color = .{ 1.0, 0.0, 0.0 } },
        .{ .position = .{ 0.5, 0.5, 0.5 }, .color = .{ 1.0, 0.0, 0.0 } },
        .{ .position = .{ -0.5, 0.5, 0.5 }, .color = .{ 1.0, 0.0, 0.0 } },

        // back face (blue tints)
        .{ .position = .{ -0.5, -0.5, -0.5 }, .color = .{ 0.0, 0.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, -0.5 }, .color = .{ 0.0, 0.0, 1.0 } },
        .{ .position = .{ 0.5, 0.5, -0.5 }, .color = .{ 0.0, 0.0, 1.0 } },
        .{ .position = .{ -0.5, 0.5, -0.5 }, .color = .{ 0.0, 0.0, 1.0 } },
    };

    // define cube indices (12 triangles, 2 per face)
    const indices = [_]u16{
        // front face
        0, 1, 2, 2, 3, 0,
        // back face
        4, 6, 5, 6, 4, 7,
        // left face
        4, 0, 3, 3, 7, 4,
        // right face
        1, 5, 6, 6, 2, 1,
        // top face
        3, 2, 6, 6, 7, 3,
        // bottom face
        4, 5, 1, 1, 0, 4,
    };

    // create vertex buffer
    const vertex_data = std.mem.sliceAsBytes(&vertices);
    var vertex_buffer = try pg.Buffer.init(&graphics_ctx, .{
        .data = vertex_data,
        .kind = .vertex,
    });
    defer vertex_buffer.deinit();

    // create index buffer
    const index_data = std.mem.sliceAsBytes(&indices);
    var index_buffer = try pg.Buffer.init(&graphics_ctx, .{
        .data = index_data,
        .kind = .index,
        .index_type = .U16,
    });
    defer index_buffer.deinit();

    var rotation: f32 = 0.0;

    std.log.info("entering render loop...", .{});

    // calculate aspect ratio
    var aspect_ratio = @as(f32, @floatCast(default_width / default_height));

    // main loop
    while (!try window.shouldClose()) {
        plt.pollEvents();

        // handle events
        while (try window.pollEvent()) |event| {
            switch (event) {
                .key_down => |key_event| {
                    if (key_event.key == .escape) {
                        window.requestClose();
                        break;
                    }
                },
                .window_resize => |resize_event| { // recompute aspect ratio
                    aspect_ratio = @as(f32, @floatCast(resize_event.width / resize_event.height));
                },
                else => {},
            }
        }

        // update rotation
        rotation += 0.01;

        // calculate transformation matrices
        const model = zm.Mat4f.rotation(zm.Vec3f{ 0, 1, 0 }, rotation);
        const view = zm.Mat4f.lookAt(
            zm.Vec3f{ 0, 0, 3 }, // eye position
            zm.Vec3f{ 0, 0, 0 }, // target
            zm.Vec3f{ 0, 1, 0 }, // up vector
        );
        const proj = zm.Mat4f.perspective(0.25 * std.math.pi, aspect_ratio, 0.1, 100);
        const mvp = proj.multiply(view).multiply(model);
        const mvp_transposed = mvp.transpose(); // metal uses column major order

        // create uniform data
        const uniform_data = UniformData{
            .mvp_matrix = @bitCast(mvp_transposed.data),
        };

        // create uniform buffer for this frame
        const uniform_bytes = std.mem.asBytes(&uniform_data);
        var uniform_buffer = try pg.Buffer.init(&graphics_ctx, .{
            .data = uniform_bytes,
            .kind = .uniform,
        });
        defer uniform_buffer.deinit();

        // begin render pass
        var render_pass = try pg.beginPass(&swapchain, .{
            .color = .{
                .action = .clear,
                .r = 0.0,
                .g = 0.0,
                .b = 0.0,
                .a = 1.0,
            },
            .depth_stencil = .{
                .action = .clear,
                .depth = 1,
                .stencil = 0,
            },
        });

        // draw cube
        render_pass.setPipeline(&pipeline);
        render_pass.setVertexBuffer(0, &vertex_buffer);
        render_pass.setUniformBuffer(1, &uniform_buffer);
        render_pass.drawIndexed(&index_buffer, 0, 0);

        // end render pass and present
        render_pass.end();
        swapchain.present();

        std.time.sleep(16 * std.time.ns_per_ms); // ~60 fps
    }

    std.log.info("shutting down...", .{});
}
