const std = @import("std");
const preprocessor = @import("../preprocessor.zig");
const parser = @import("../parser.zig");

pub fn compatDirective(pp: *preprocessor.Preprocessor, args: []const parser.Value) anyerror!void {
    if (args.len != 1) {
        return error.InvalidArgumentCount;
    }

    if (args[0].getType() != .identifier) {
        return error.InvalidArgumentType;
    }

    pp.options.format = args[0].toIdentifier().identifier_string;
}

pub fn endianDirective(pp: *preprocessor.Preprocessor, args: []const parser.Value) anyerror!void {
    if (args.len != 1) {
        return error.InvalidArgumentCount;
    }

    if (args[0].getType() != .identifier) {
        return error.InvalidArgumentType;
    }

    const end = args[0].toIdentifier();

    if (std.mem.eql(u8, end.identifier_string, "little")) {
        pp.options.endian = .little;
    }

    if (std.mem.eql(u8, end.identifier_string, "big")) {
        pp.options.endian = .big;
    }
}

pub fn compile_if(pp: *preprocessor.Preprocessor, args: []const parser.Value) anyerror!void {
    if (args.len != 1) {
        return error.InvalidArgumentCount;
    }

    if (pp.options.format == null) {
        return;
    }

    if (args[0].getType() != .identifier) {
        return error.InvalidArgumentType;
    }

    if (!std.mem.eql(u8, args[0].toIdentifier().identifier_string, pp.options.format.?)) {
        std.log.err("compile-if: expected format '{s}' but found '{s}'.", .{
            args[0].toIdentifier().identifier_string,
            pp.options.format.?,
        });

        std.log.err("program will exit and compilation is over.", .{});

        std.process.exit(1);
    }
}
