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

pub const Window = window.Window;
pub const WindowID = window.WindowID;
pub const WindowDesc = window.WindowDesc;
pub const Platform = window.Platform;

// event types
pub const Event = window.Event;
pub const EventType = window.EventType;
pub const KeyCode = window.KeyCode;
pub const KeyModifiers = window.KeyModifiers;
pub const KeyEvent = window.KeyEvent;

//-- private imports --//

const window = @import("window.zig");
