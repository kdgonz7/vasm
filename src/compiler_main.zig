//! # Compiler Main Function
//!

const std = @import("std");
const builtin = @import("builtin");

const compiler_output = @import("compiler_output.zig");

const ArrayList = std.ArrayList;

pub const Options = struct {
    files: ArrayList([]const u8),
    output: []const u8 = "a.out",
    format: ?[]const u8 = null,
    stylist: bool = true,
    strict_stylist: bool = false,
    allow_big_numbers: bool = false,
};

pub fn runManPage(allocator: anytype, report: anytype) void {
    if (std.process.can_execv) {
        std.process.execv(allocator, &[_][]const u8{ "man", "vasm" }) catch {
            report.errorMessage("no man installed.", .{});
        };
    }
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
            } else {
                i += 1;
                return_opt.format = arg_slice[i];
            }
        } else if (std.mem.eql(u8, arg_slice[i], "--output") or std.mem.eql(u8, arg_slice[i], "-o")) {
            i += 1;
            if (i >= arg_slice.len) report.errorMessage("-o/output expects an OUTFILE argument.", .{});
            return_opt.output = arg_slice[i];
        } else if (std.mem.eql(u8, arg_slice[i], "--help") or std.mem.eql(u8, arg_slice[i], "-h")) {
            runManPage(allocator, report);
        } else if (std.mem.eql(u8, arg_slice[i], "--no-stylist")) {
            return_opt.stylist = false;
        } else if (std.mem.eql(u8, arg_slice[i], "--strict") or std.mem.eql(u8, arg_slice[i], "--enforce-stylist")) {
            return_opt.strict_stylist = true;
        } else if (std.mem.eql(u8, arg_slice[i], "--large-numbers") or std.mem.eql(u8, arg_slice[i], "-le")) {
            return_opt.allow_big_numbers = true;
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
