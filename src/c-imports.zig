const builtin = @import("builtin");

// single source of truth for all c imports
pub const c = @cImport({
    @cInclude("window-backend.h");
    @cInclude("graphics-backend.h");
});
