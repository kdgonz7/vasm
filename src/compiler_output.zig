const std = @import("std");
const lexer = @import("lexer.zig");
const compiler_status = @import("compiler_status.zig");

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

pub fn errorMessageWithExit(comptime format: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();

    stderr.print("vasm: \x1b[31;1mfatal error: \x1b[0;1m", .{}) catch unreachable;
    stderr.print(format, args) catch unreachable;
    stderr.print("\x1b[0m", .{}) catch unreachable;
    stderr.print("\n", .{}) catch unreachable;

    std.process.exit(1);
}

pub fn message(comptime format: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print(format, args) catch unreachable;
}

pub fn getSourceLocation(lexer_state: *lexer.Lexer, status: compiler_status.Status) void {
    var lines = lexer_state.splitInputTextIntoLines();
    var i: usize = 0;

    // try to find the line that the lexer stopped on
    while (lines.next()) |line| {
        if (i == lexer_state.getLineNumber() - 1) {
            // we get stderr
            const stderr = std.io.getStdErr().writer();

            // print the line number
            // 1        |     ...
            // + padding on the left
            stderr.print("{d: <8}| {s}\n", .{ lexer_state.getLineNumber(), line }) catch unreachable;
            stderr.print("          ", .{}) catch unreachable;

            // try to move to the stopped char pos
            for (0..lexer_state.area.char_pos - 1) |_| {
                stderr.print(" ", .{}) catch unreachable;
            }

            // try and match the color with status
            var color: []const u8 = "\x1b[31;1m";

            // TODO: scale this
            if (status == .suggestion) {
                color = "\x1b[33m";
            }

            // print a line where the error happens
            stderr.print("{s}^~~~~~~~~~\x1b[0m", .{color}) catch unreachable;
            stderr.print("\n", .{}) catch unreachable;

            break;
        }

        i += 1;
    }
}

pub fn getCustomarySourceLocationUsingLexer(existing_lexer: anytype, begin: anytype, end: anytype, line_number: anytype) void {
    var lines = existing_lexer.splitInputTextIntoLines();
    var i: usize = 0;

    while (lines.next()) |line| {
        if (i == line_number) {
            const stderr = std.io.getStdErr().writer();

            stderr.print("{d: <8}| {s}\n", .{ line_number, std.mem.trim(u8, line, " \t \n") }) catch unreachable;
            stderr.print("  ", .{}) catch unreachable;

            for (0..begin) |_| {
                stderr.print(" ", .{}) catch unreachable;
            }

            // try and match the color with status
            const color: []const u8 = "\x1b[33;1m";

            // print a line where the error happens
            stderr.print("{s}^", .{color}) catch unreachable;
            for (0..end - begin) |_| {
                stderr.print("~", .{}) catch unreachable;
            }
            stderr.print("\x1b[0m\n", .{}) catch unreachable;

            break;
        }

        i += 1;
    }
}

/// Prints error `err` and tries to get the source location using the lexer `lex`.
pub fn printError(lex: *lexer.Lexer, filename: []const u8, err: anyerror) noreturn {
    switch (err) {
        error.UnexpectedToken => {
            errorMessage("{s}:{d}:{d}: unexpected token `{c}'", .{
                filename,
                lex.getLineNumber(),
                lex.area.char_pos,
                lex.getCurrentCharacter(),
            });

            getSourceLocation(lex, .suggestion);
        },

        else => {},
    }

    std.process.exit(1);
}
