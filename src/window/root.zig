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

pub const log = @import("log.zig");

pub const Window = platform.Window;
pub const WindowID = platform.WindowID;
pub const WindowConfig = platform.WindowConfig;
pub const Platform = platform.Platform;

// event types
pub const Event = platform.Event;
pub const EventType = platform.EventType;
pub const KeyCode = platform.KeyCode;
pub const KeyModifiers = platform.KeyModifiers;
pub const KeyEvent = platform.KeyEvent;

//-- private imports --//

const platform = @import("platform.zig");
