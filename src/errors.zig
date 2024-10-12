//! Impelemnts LR Assembly compliant errors.
//!
//! See the LR Assembly standard for more information

const std = @import("std");

/// An error. Has a tag and message to define itself.
pub const Error = struct {
    /// The error's tag. Example E0001, E0002
    tag: []const u8,
    message: []const u8,

    pub fn init(tag: []const u8) Error {
        return Error{
            .tag = tag,
            .message = "",
        };
    }

    pub fn setMessage(self: *Error, message: []const u8) void {
        self.message = message;
    }
};

pub const ErrorMap = std.StringHashMap(Error);

test Error {
    var err0001 = Error.init("E0001");
    err0001.setMessage("Compiler out of memory");

    try std.testing.expectEqualStrings("E0001", err0001.tag);
    try std.testing.expectEqualStrings("Compiler out of memory", err0001.message);
}

test ErrorMap {
    var map = ErrorMap.init(std.testing.allocator);
    defer map.deinit();

    try map.put("E0001", Error.init("E0001"));
    try std.testing.expect(map.contains("E0001"));
}
