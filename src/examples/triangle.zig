const std = @import("std");
const pw = @import("pine-window");
const pg = @import("pine-graphics");

pub const std_options = std.Options{
    .logFn = pw.log.logFn,
};

// simple vertex structure
const Vertex = struct {
    position: [2]f32,
    color: [3]f32,
};

// metal shader source
const metal_shader_source =
    \\#include <metal_stdlib>
    \\using namespace metal;
    \\
    \\struct Vertex {
    \\    float2 position [[attribute(0)]];
    \\    float3 color [[attribute(1)]];
    \\};
    \\
    \\struct VertexOut {
    \\    float4 position [[position]];
    \\    float3 color;
    \\};
    \\
    \\vertex VertexOut vertex_main(Vertex in [[stage_in]]) {
    \\    VertexOut out;
    \\    out.position = float4(in.position, 0.0, 1.0);
    \\    out.color = in.color;
    \\    return out;
    \\}
    \\
    \\fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    \\    return float4(in.color, 1.0);
    \\}
;

pub fn main() !void {
    std.log.info("initializing pine window platform...", .{});

    // initialize platform
    var plt = try pw.Platform.init();
    defer plt.deinit();

    std.log.info("creating graphics context...", .{});

    // create graphics context
    var graphics_ctx = try pg.GraphicsContext.create(.auto);
    defer graphics_ctx.destroy();

    std.log.info("creating window...", .{});

    // create window
    var window = try pw.Window.create(std.heap.page_allocator, .{
        .width = 800,
        .height = 600,
        .position = .{ .center = true },
        .title = "Pine Window # Triangle Example",
        .resizable = true,
        .visible = true,
    });
    defer window.destroy();

    std.log.info("creating swapchain...", .{});

    // create swapchain
    var swapchain = try pg.Swapchain.create(&graphics_ctx, &window);
    defer swapchain.destroy();

    std.log.info("creating shaders...", .{});

    // create shaders
    var vertex_shader = try pg.Shader.create(&graphics_ctx, metal_shader_source, .vertex);
    defer vertex_shader.destroy();

    var fragment_shader = try pg.Shader.create(&graphics_ctx, metal_shader_source, .fragment);
    defer fragment_shader.destroy();

    std.log.info("creating pipeline...", .{});

    // define vertex attributes
    const attributes = [_]pg.VertexAttribute{
        .{ .format = .float2, .offset = @offsetOf(Vertex, "position") },
        .{ .format = .float3, .offset = @offsetOf(Vertex, "color") },
    };

    // create pipeline
    var pipeline = try pg.Pipeline.create(
        &graphics_ctx,
        &vertex_shader,
        &fragment_shader,
        &attributes,
        @sizeOf(Vertex),
    );
    defer pipeline.destroy();

    std.log.info("creating vertex buffer...", .{});

    // define triangle vertices
    const vertices = [_]Vertex{
        .{ .position = .{ 0.0, 0.5 }, .color = .{ 1.0, 0.0, 0.0 } }, // top (red)
        .{ .position = .{ -0.5, -0.5 }, .color = .{ 0.0, 1.0, 0.0 } }, // bottom left (green)
        .{ .position = .{ 0.5, -0.5 }, .color = .{ 0.0, 0.0, 1.0 } }, // bottom right (blue)
    };

    // create vertex buffer
    const vertex_data = std.mem.sliceAsBytes(&vertices);
    var vertex_buffer = try pg.Buffer.create(&graphics_ctx, .{
        .data = vertex_data,
        .type = .vertex,
    });
    defer vertex_buffer.destroy();

    std.log.info("starting render loop...", .{});

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
                else => {},
            }
        }

        // begin render pass
        var render_pass = try pg.beginPass(&swapchain, .{
            .color = .{
                .action = .clear,
                .r = 0.1,
                .g = 0.1,
                .b = 0.1,
                .a = 1.0,
            },
        });

        // draw triangle
        render_pass.setPipeline(&pipeline);
        render_pass.setVertexBuffer(0, &vertex_buffer);
        render_pass.draw(3, 0);

        // end render pass and present frame
        render_pass.end();
        pg.present(&swapchain);
    }

    std.log.info("shutting down...", .{});
}
