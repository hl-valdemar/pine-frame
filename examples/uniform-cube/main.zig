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
    mvp_matrix: [16]f32,
};

// Metal shader for 3D rendering
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

    // Initialize platform and graphics
    var plt = try pw.Platform.init();
    defer plt.deinit();

    var graphics_ctx = try pg.GraphicsContext.init(.auto);
    defer graphics_ctx.deinit();

    // Create window
    var window = try pw.Window.init(&plt, .{
        .width = 800,
        .height = 600,
        .position = .{ .center = true },
        .title = "Pine Engine - 3D Cube",
        .resizable = true,
        .visible = true,
    });
    defer window.deinit();

    // Create swapchain
    var swapchain = try pg.Swapchain.init(&graphics_ctx, &window);
    defer swapchain.deinit();

    // Create shaders
    var vertex_shader = try pg.Shader.init(&graphics_ctx, metal_shader_source, .vertex);
    defer vertex_shader.deinit();

    var fragment_shader = try pg.Shader.init(&graphics_ctx, metal_shader_source, .fragment);
    defer fragment_shader.deinit();

    // Define vertex attributes for 3D positions
    const attributes = [_]pg.VertexAttribute{
        .{ .format = .float3, .offset = @offsetOf(Vertex, "position") },
        .{ .format = .float3, .offset = @offsetOf(Vertex, "color") },
    };

    // Create pipeline
    var pipeline = try pg.Pipeline.init(&graphics_ctx, .{
        .vertex_shader = &vertex_shader,
        .fragment_shader = &fragment_shader,
        .attributes = &attributes,
        .vertex_stride = @sizeOf(Vertex),
    });
    defer pipeline.deinit();

    // Define cube vertices (8 vertices)
    const vertices = [_]Vertex{
        // Front face (red tints)
        .{ .position = .{ -0.5, -0.5, 0.5 }, .color = .{ 1.0, 0.0, 0.0 } },
        .{ .position = .{ 0.5, -0.5, 0.5 }, .color = .{ 1.0, 0.5, 0.0 } },
        .{ .position = .{ 0.5, 0.5, 0.5 }, .color = .{ 1.0, 0.0, 0.5 } },
        .{ .position = .{ -0.5, 0.5, 0.5 }, .color = .{ 0.5, 0.0, 0.0 } },

        // Back face (blue tints)
        .{ .position = .{ -0.5, -0.5, -0.5 }, .color = .{ 0.0, 0.0, 1.0 } },
        .{ .position = .{ 0.5, -0.5, -0.5 }, .color = .{ 0.0, 0.5, 1.0 } },
        .{ .position = .{ 0.5, 0.5, -0.5 }, .color = .{ 0.5, 0.0, 1.0 } },
        .{ .position = .{ -0.5, 0.5, -0.5 }, .color = .{ 0.0, 0.0, 0.5 } },
    };

    // Define cube indices (12 triangles, 2 per face)
    const indices = [_]u16{
        // Front face
        0, 1, 2, 2, 3, 0,
        // Back face
        4, 6, 5, 6, 4, 7,
        // Left face
        4, 0, 3, 3, 7, 4,
        // Right face
        1, 5, 6, 6, 2, 1,
        // Top face
        3, 2, 6, 6, 7, 3,
        // Bottom face
        4, 5, 1, 1, 0, 4,
    };

    // Create vertex buffer
    const vertex_data = std.mem.sliceAsBytes(&vertices);
    var vertex_buffer = try pg.Buffer.init(&graphics_ctx, .{
        .data = vertex_data,
        .kind = .vertex,
    });
    defer vertex_buffer.deinit();

    // Create index buffer
    const index_data = std.mem.sliceAsBytes(&indices);
    var index_buffer = try pg.Buffer.init(&graphics_ctx, .{
        .data = index_data,
        .kind = .index,
        .index_type = .U16,
    });
    defer index_buffer.deinit();

    // Setup matrices using zm
    const aspect_ratio = @as(f32, 800.0) / @as(f32, 600.0);
    var rotation: f32 = 0.0;

    std.log.info("entering render loop...", .{});

    // Main loop
    while (!try window.shouldClose()) {
        plt.pollEvents();

        // Handle events
        while (try window.pollEvent()) |event| {
            switch (event) {
                .key_down => |key_event| {
                    if (key_event.key == .escape) {
                        window.requestClose();
                        break;
                    }
                },
                else => {},
            }
        }

        // Update rotation
        rotation += 0.01;

        // Calculate transformation matrices
        const model = zm.Mat4f.rotation(zm.Vec3f{ 0, 1, 0 }, rotation);
        const view = zm.Mat4f.lookAt(
            zm.Vec3f{ 0, 0, 3 }, // eye position
            zm.Vec3f{ 0, 0, 0 }, // target
            zm.Vec3f{ 0, 1, 0 }, // up vector
        );
        const proj = zm.Mat4f.perspective(0.25 * std.math.pi, aspect_ratio, 0.1, 100);
        const mvp = model.multiply(view).multiply(proj);

        // Create uniform data
        const uniform_data = UniformData{ .mvp_matrix = mvp.data };

        // Create uniform buffer for this frame
        const uniform_bytes = std.mem.sliceAsBytes(&[_]UniformData{uniform_data});
        var uniform_buffer = try pg.Buffer.init(&graphics_ctx, .{
            .data = uniform_bytes,
            .kind = .uniform,
        });
        defer uniform_buffer.deinit();

        // Begin render pass
        var render_pass = try pg.beginPass(&swapchain, .{
            .color = .{
                .action = .clear,
                .r = 0.1,
                .g = 0.1,
                .b = 0.1,
                .a = 1.0,
            },
        });

        // Draw cube
        render_pass.setPipeline(&pipeline);
        render_pass.setVertexBuffer(0, &vertex_buffer);
        render_pass.setUniformBuffer(1, &uniform_buffer);
        render_pass.drawIndexed(&index_buffer, 0, 0);

        // End render pass and present
        render_pass.end();
        swapchain.present();

        std.time.sleep(16 * std.time.ns_per_ms); // ~60 fps
    }

    std.log.info("shutting down...", .{});
}
