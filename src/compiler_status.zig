const std = @import("std");

/// The status of the compiler.
pub const Status = enum {
    erroneous,
    suggestion,
};
