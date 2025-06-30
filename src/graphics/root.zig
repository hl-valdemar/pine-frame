//! Pine Graphics

//-- global settings --//

pub const std_options = std.Options{
    .logFn = log.logFn,
};

const std = @import("std");

//-- public exports --//

pub const log = @import("log.zig");

// pub const commit = render.commit;

pub const Context = context.Context;
pub const Swapchain = context.Swapchain;
pub const RenderPass = context.RenderPass;
pub const beginFrame = context.beginFrame;
pub const endFrame = context.endFrame;
pub const beginPass = context.beginPass;
pub const endPass = context.endPass;
pub const present = context.present;

//-- private imports --//

// const render = @import("render.zig");
const context = @import("context.zig");
