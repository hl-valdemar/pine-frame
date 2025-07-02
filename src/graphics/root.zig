//! Pine Graphics

//-- global settings --//

pub const std_options = std.Options{
    .logFn = log.logFn,
};

const std = @import("std");

//-- public exports --//

pub const log = @import("log.zig");

// pub const commit = render.commit;

pub const GraphicsContext = context.Context;
pub const Swapchain = context.Swapchain;
pub const RenderPass = context.RenderPass;
pub const Pipeline = context.Pipeline;
pub const Shader = context.Shader;
pub const VertexAttribute = context.VertexAttribute;
pub const Buffer = context.Buffer;

// functions
pub const beginPass = context.beginPass;
pub const present = context.present;

//-- private imports --//

const context = @import("context.zig");
