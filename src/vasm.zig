const std = @import("std");
pub const frontend = @import("frontend.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const codegen = @import("codegen.zig");
pub const linker = @import("linker.zig");
pub const ir = @import("instruction_result.zig");
pub const peephole = @import("peephole.zig");
pub const drivers = @import("drivers.zig");
pub const errors = @import("errors.zig");
pub const nexfuse = @import("platforms/nexfuse.zig");
pub const stylist = @import("stylist.zig");
pub const hybrid = @import("hybrid.zig");
pub const pp = @import("preprocessor.zig");

test {
    std.testing.refAllDecls(@This());
}
