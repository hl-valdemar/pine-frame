//! Pine Graphics

//-- global settings --//

pub const std_options = std.Options{
    .logFn = log.logFn,
};

const std = @import("std");

//-- public exports --//

pub const log = @import("log.zig");

pub const beginPass = render.beginPass;
pub const endPass = render.endPass;
pub const commit = render.commit;

//-- private imports --//

const render = @import("render.zig");
