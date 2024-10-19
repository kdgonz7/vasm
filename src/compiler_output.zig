const std = @import("std");
const tty = std.io.tty;

const lexer = @import("lexer.zig");
const linker = @import("linker.zig");
const compiler_status = @import("compiler_status.zig");

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

    pub fn leaveNote(self: *Reporter, comptime format: []const u8, args: anytype) void {
        const wri = self.stderr.writer();

        wri.print("vasm: ", .{}) catch unreachable;

        self.setStderrColor(.bright_magenta);

        wri.print("note: ", .{}) catch unreachable;

        self.setStderrColor(.reset);
        wri.print(format, args) catch unreachable;

        wri.print("\n", .{}) catch unreachable;
    }

    /// Prints error `err` and tries to get the source location using the lexer `lex`.
    pub fn printError(self: *Reporter, lex: *lexer.Lexer, filename: []const u8, err: anyerror) noreturn {
        switch (err) {
            error.UnexpectedToken => {
                self.errorMessage("{s}:{d}:{d}: unexpected token `{c}'", .{
                    filename,
                    lex.getLineNumber(),
                    lex.area.char_pos,
                    lex.getCurrentCharacter(),
                });

                self.getSourceLocation(lex, .suggestion);
            },

            error.NumberTooBig => {
                self.errorMessage("{s}:{d}:{d}: number too big (note that max size is {d})", .{
                    filename,
                    lex.getLineNumber(),
                    lex.area.char_pos,
                    lex.rules.max_number_size,
                });

                self.getSourceLocation(lex, .suggestion);
            },

            else => {},
        }

        std.process.exit(1);
    }

    pub fn getCustomarySourceLocationUsingLexer(self: *Reporter, existing_lexer: anytype, begin: anytype, end: anytype, line_number: anytype) void {
        var lines = existing_lexer.*.splitInputTextIntoLines();
        var i: usize = 0;

        while (lines.next()) |line| {
            if (i == line_number) {
                const stderr = self.stderr.writer();

                stderr.print("{d: <8}| {s}\n", .{ line_number + 1, std.mem.trim(u8, line, " \t \n") }) catch unreachable;
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

    pub fn getSourceLocation(self: *Reporter, lexer_state: *lexer.Lexer, status: compiler_status.Status) void {
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

                switch (status) {
                    .suggestion => {
                        self.setStderrColor(.bright_magenta);
                    },

                    .erroneous => {
                        self.setStderrColor(.bright_red);
                    },
                }

                // print a line where the error happens
                stderr.print("^", .{}) catch unreachable;
                stderr.print("\n", .{}) catch unreachable;

                self.setStderrColor(.reset);

                break;
            }

            i += 1;
        }
    }

    pub fn genError(self: *Reporter, err: anyerror, gen: anytype, ctx: anytype) noreturn {
        switch (err) {
            error.RegisterNumberTooLarge => {
                self.errorMessage("{s}:{d}:{d}: {s}", .{
                    ctx.file_name,
                    gen.erroneous_token.toRegister().span.line_number,
                    gen.erroneous_token.toRegister().span.begin,
                    "register number too large",
                });

                ctx.report.getCustomarySourceLocationUsingLexer(
                    ctx.lexer,
                    gen.erroneous_token.toRegister().span.char_begin,
                    gen.erroneous_token.toRegister().span.end,
                    gen.erroneous_token.toRegister().span.line_number - 1,
                );
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

    pub fn linkerError(self: *Reporter, err: anyerror, link: anytype, ctx: anytype) noreturn {
        _ = ctx;
        _ = link;

        self.leaveNote("linker error {any}", .{err});

        std.process.exit(1);
    }

    pub fn linkerWriteError(self: *Reporter, err: anyerror, link: anytype, ctx: anytype) noreturn {
        _ = ctx;
        _ = link;

        self.leaveNote("linker write error {any}", .{err});

        std.process.exit(1);
    }

    pub fn stylistMessage(self: *Reporter, comptime format: []const u8, args: anytype) void {
        const wri = self.stderr.writer();

        self.setStderrColor(.bright_cyan);

        wri.print("stylist error: ", .{}) catch unreachable;

        self.setStderrColor(.reset);

        wri.print(format, args) catch unreachable;
        wri.print("\n", .{}) catch unreachable;
    }
};
