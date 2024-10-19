//! # Compiler Main Function
//!

const std = @import("std");
const builtin = @import("builtin");

const compiler_output = @import("compiler_output.zig");

const ArrayList = std.ArrayList;

/// Manages the list of passed in compiler options.
pub const Options = struct {
    files: ArrayList([]const u8),
    output: []const u8 = "a.out",
    format: ?[]const u8 = null,
    stylist: bool = true,
    strict_stylist: bool = false,
    allow_big_numbers: bool = false,
    endian: std.builtin.Endian = .little,
};

pub fn printHelpClassic() void {
    const writer = std.io.getStdOut().writer();

    _ = writer.print(@embedFile("./cli/help.adoc"), .{}) catch unreachable;
}

pub fn runManPage(allocator: anytype, report: anytype) void {
    _ = report;
    if (std.process.can_execv) {
        std.process.execv(allocator, &[_][]const u8{ "man", "vasm" }) catch {
            printHelpClassic();
        };
    } else {
        printHelpClassic();
    }

    std.process.exit(0);
}

pub fn extractOptions(allocator: std.mem.Allocator, arg_slice: [][:0]u8, report: anytype) Options {
    var return_opt: Options = .{
        .output = "a.out",
        .format = "none",
        .files = std.ArrayList([]const u8).init(allocator),
    };

    // iterate over arguments and extract needed information
    var i: usize = 1;

    while (i < arg_slice.len) {
        if (std.mem.eql(u8, arg_slice[i], "--format") or std.mem.eql(u8, arg_slice[i], "-f")) {
            if (i + 1 >= arg_slice.len) {
                report.errorMessage("'--format' expects a format argument.", .{});
                std.process.exit(1);
            } else {
                i += 1;
                return_opt.format = arg_slice[i];
            }
        } else if (std.mem.eql(u8, arg_slice[i], "--output") or std.mem.eql(u8, arg_slice[i], "-o")) {
            i += 1;

            if (i >= arg_slice.len) {
                report.errorMessage("-o/output expects an OUTFILE argument.", .{});
                std.process.exit(1);
            }

            return_opt.output = arg_slice[i];
        } else if (std.mem.eql(u8, arg_slice[i], "--help") or std.mem.eql(u8, arg_slice[i], "-h")) {
            runManPage(allocator, report);
        } else if (std.mem.eql(u8, arg_slice[i], "--no-stylist")) {
            return_opt.stylist = false;
        } else if (std.mem.eql(u8, arg_slice[i], "--strict") or std.mem.eql(u8, arg_slice[i], "--enforce-stylist")) {
            return_opt.strict_stylist = true;
        } else if (std.mem.eql(u8, arg_slice[i], "--allow-large-numbers") or std.mem.eql(u8, arg_slice[i], "-ln")) {
            return_opt.allow_big_numbers = true;
        } else if (std.mem.eql(u8, arg_slice[i], "-be")) {
            return_opt.endian = .big;
        } else if (std.mem.eql(u8, arg_slice[i], "-le")) {
            return_opt.endian = .little;
        } else {
            if (arg_slice[i][0] == '-') {
                report.errorMessage("unrecognized flag '{s}'", .{arg_slice[i]});
            } else {
                return_opt.files.append(arg_slice[i]) catch {
                    report.errorMessage("Out of memory", .{});
                };
            }
        }

        i += 1;
    }

    return return_opt;
}
