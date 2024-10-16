const std = @import("std");
const tty = std.io.tty;

const lexer = @import("lexer.zig");
const compiler_status = @import("compiler_status.zig");

//TODO: lookie here pal, it's probably wednesday at the time you see this.
// it's almost 10:00 pm and im gonna stop working on this, it's burning me out for the night
// so far i've created this shiny new REPORTER class which manages the stdout and stderr configs to print
// colored messages to the console using std.io.tty.Config
// we've still got to migrate the lexer source location function into the reporter class and still have to
// rewrite the frontend to fit the new API. see the frontend.zig file if you don't know what I mean.

/// Manages standard error and standard output files. Prints in color cross platform.
pub const Reporter = struct {
    stdout: std.fs.File,
    stderr: std.fs.File,
    stdout_config: tty.Config = undefined,
    stderr_config: tty.Config = undefined,

    pub fn init() Reporter {
        var rep: Reporter = .{
            .stderr = std.io.getStdErr(),
            .stdout = std.io.getStdOut(),
        };

        rep.stdout_config = tty.detectConfig(rep.stdout);
        rep.stderr_config = tty.detectConfig(rep.stderr);

        return rep;
    }

    pub fn setStdoutColor(self: *Reporter, color: tty.Color) void {
        self.stdout_config.setColor(self.stdout.writer(), color) catch unreachable;
    }

    pub fn setStderrColor(self: *Reporter, color: tty.Color) void {
        self.stderr_config.setColor(self.stderr.writer(), color) catch unreachable;
    }

    pub fn importantMessage(self: *Reporter, comptime format: []const u8, args: anytype) void {
        var writer = self.stdout.writer();

        self.setStdoutColor(.bold);

        writer.print(format, args) catch unreachable;

        self.setStdoutColor(.reset);

        writer.print("\n", .{}) catch unreachable;
    }

    pub fn errorMessage(self: *Reporter, comptime format: []const u8, args: anytype) void {
        const wri = self.stderr.writer();

        wri.print("vasm: ", .{}) catch unreachable;
        self.setStderrColor(.bold);
        self.setStderrColor(.red);

        wri.print("fatal error: ", .{}) catch unreachable;

        self.setStderrColor(.reset);
        self.setStderrColor(.bold);

        wri.print(format, args) catch unreachable;
        wri.print("\n", .{}) catch unreachable;

        self.setStderrColor(.reset);
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

    pub fn astError(self: *Reporter, err: anytype, lex: lexer.Lexer) noreturn {
        _ = lex;

        self.errorMessage("ast error {any}", .{err});
        std.process.exit(1);
    }

    pub fn getCustomarySourceLocationUsingLexer(self: *Reporter, existing_lexer: anytype, begin: anytype, end: anytype, line_number: anytype) void {
        var lines = existing_lexer.*.splitInputTextIntoLines();
        var i: usize = 0;

        while (lines.next()) |line| {
            if (i == line_number) {
                const stderr = self.stderr.writer();

                stderr.print("{d: <8}| {s}\n", .{ line_number, std.mem.trim(u8, line, " \t \n") }) catch unreachable;
                stderr.print("  ", .{}) catch unreachable;

                for (0..begin) |_| {
                    stderr.print(" ", .{}) catch unreachable;
                }

                self.setStderrColor(.red);

                stderr.print("^", .{}) catch unreachable;

                for (0..end - begin) |_| {
                    stderr.print("~", .{}) catch unreachable;
                }

                self.setStderrColor(.reset);

                stderr.print("\n", .{}) catch unreachable;

                break;
            }

            i += 1;
        }
    }
};

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
