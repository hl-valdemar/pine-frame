//! Pine Window - Cross-platform windowing library for Zig
//!
//! This library provides a simple, cross-platform windowing solution.
//! Currently supports macOS with plans for Windows and Linux.

//-- global settings --//

pub const std_options = std.Options{
    .logFn = log.logFn,
};

const std = @import("std");

//-- public exports --//

pub const log = @import("internal/log.zig");

pub const Window = platform.Window;
pub const WindowConfig = platform.WindowConfig;
pub const Platform = platform.Platform;

//-- private imports --//

const platform = @import("internal/platform.zig");
