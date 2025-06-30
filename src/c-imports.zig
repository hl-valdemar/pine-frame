const builtin = @import("builtin");

// single source of truth for all c imports
pub const c = switch (builtin.os.tag) {
    .macos => @cImport({
        @cInclude("window.h");
        @cInclude("graphics.h");
    }),
    // future platforms will include their headers here
    else => @compileError("unsupported platform"),
};
