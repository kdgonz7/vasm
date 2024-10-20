const std = @import("std");
const preprocessor = @import("../preprocessor.zig");
const parser = @import("../parser.zig");

pub fn compatDirective(pp: *preprocessor.Preprocessor, args: []const parser.Value) anyerror!void {
    if (args.len != 1) {
        return error.InvalidArgumentCount;
    }
    pp.options.format = args[0].toIdentifier().identifier_string;
}

pub fn endianDirective(pp: *preprocessor.Preprocessor, args: []const parser.Value) anyerror!void {
    if (args.len != 1) {
        return error.InvalidArgumentCount;
    }

    const end = args[0].toIdentifier();

    if (std.mem.eql(u8, end.identifier_string, "little")) {
        pp.options.endian = .little;
    }

    if (std.mem.eql(u8, end.identifier_string, "big")) {
        pp.options.endian = .big;
    }
}
