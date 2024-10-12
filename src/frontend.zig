//! ## VASM
//!
//! VASM is a LR Assembly compiler designed to be the maintained standard for compiling into bytecode.
//!

const std = @import("std");

/// Prints a bolded message in `format` using the `Writer.print` method.
pub fn importantMessage(comptime format: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();

    stdout.print("\x1b[1m", .{}) catch unreachable;
    stdout.print(format, args) catch unreachable;
    stdout.print("\x1b[0m", .{}) catch unreachable;
    stdout.print("\n", .{}) catch unreachable;
}

/// Prints an error message also using the `stderr.writer().print` function.
pub fn errorMessage(comptime format: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();

    stderr.print("vasm: \x1b[31;1merror: \x1b[0;1m", .{}) catch unreachable;
    stderr.print(format, args) catch unreachable;
    stderr.print("\x1b[0m", .{}) catch unreachable;
    stderr.print("\n", .{}) catch unreachable;
}

pub fn main() !void {
    var prog_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const prog_allocator = prog_arena.allocator();
    const args = std.process.argsAlloc(prog_allocator) catch {
        errorMessage("failed to allocate a separate argument buffer. out of memory.", .{});
        std.process.exit(1);
    };
    var files = std.ArrayList([]const u8).init(prog_allocator);

    var format: []const u8 = undefined;

    var i: usize = 1;

    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "--format") or std.mem.eql(u8, args[i], "-f")) {
            if (i + 1 >= args.len) {
                errorMessage("'--format' expects a format argument.", .{});
                std.process.exit(1);
            } else {
                i += 1;
                format = args[i];
            }
        } else {
            if (args[i][0] == '-') {
                errorMessage("unrecognized flag '{s}'", .{args[i]});
                std.process.exit(1);
            } else {
                try files.append(args[i]);
            }
        }

        i += 1;
    }

    if (files.items.len == 0) {
        errorMessage("no input files.", .{});
        std.process.exit(1);
    }
}
