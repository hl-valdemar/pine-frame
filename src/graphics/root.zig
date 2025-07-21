//! Pine Graphics

// global settings //

pub const std_options = std.Options{
    .logFn = log.logFn,
};

// public exports //

pub const log = @import("log.zig");

pub const GraphicsContext = graphics.Context;
pub const Swapchain = graphics.Swapchain;
pub const RenderPass = graphics.RenderPass;
pub const Pipeline = graphics.Pipeline;
pub const Shader = graphics.Shader;
pub const VertexAttribute = graphics.VertexAttribute;
pub const Buffer = graphics.Buffer;
pub const BufferDesc = graphics.BufferDesc;

// functions
pub const beginPass = graphics.beginPass;
pub const present = graphics.present;

// private imports //

const std = @import("std");
const graphics = @import("graphics.zig");
