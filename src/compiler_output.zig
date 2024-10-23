const std = @import("std");
const tty = std.io.tty;

const lexer = @import("lexer.zig");
const linker = @import("linker.zig");
const parser = @import("parser.zig");
const compiler_status = @import("compiler_status.zig");
const codegen = @import("codegen.zig");

const Result = codegen.Result;

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

        wri.print("error: ", .{}) catch unreachable;

        self.setStderrColor(.reset);
        self.setStderrColor(.bold);

        wri.print(format, args) catch unreachable;
        wri.print("\n", .{}) catch unreachable;

        self.setStderrColor(.reset);
    }

    pub fn preprocessErrorMessage(self: *Reporter, comptime format: []const u8, args: anytype) void {
        const wri = self.stderr.writer();

        wri.print("vasm: ", .{}) catch unreachable;
        self.setStderrColor(.cyan);
        self.setStderrColor(.magenta);

        wri.print("preprocessor error: ", .{}) catch unreachable;

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

            else => {
                self.errorMessage("{s}:{d}:{d}: {s}", .{
                    filename,
                    lex.getLineNumber(),
                    lex.area.char_pos,
                    @errorName(err),
                });

                std.process.exit(1);
            },
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

    pub fn genError(self: *Reporter, err: Result, gen: anytype, ctx: anytype) noreturn {
        _ = gen;
        switch (err) {
            .register_number_too_large => |reg| {
                self.errorMessage("{s}:{d}:{d}: {s}", .{
                    ctx.file_name,
                    reg.span.line_number,
                    reg.span.char_begin,
                    "register number too large",
                });

                ctx.lexer.area.char_pos = reg.span.char_begin;
                ctx.lexer.area.line_number = reg.span.line_number;

                self.getSourceLocation(ctx.lexer, .suggestion);
            },

            .instruction_doesnt_exist => |span| {
                self.errorMessage("{s}:{d}:{d}: {s}", .{
                    ctx.file_name,
                    span.line_number,
                    span.char_begin,
                    "instruction does not exist for this architecture",
                });

                ctx.lexer.area.char_pos = span.char_begin;
                ctx.lexer.area.line_number = span.line_number;

                self.getSourceLocation(ctx.lexer, .erroneous);
            },

            .params_to_instruction_are_wrong => |mismatch| {
                self.errorMessage("{s}:{d}:{d}: expected '{s}', got '{s}'", .{
                    ctx.file_name,
                    mismatch.span.line_number,
                    mismatch.span.char_begin,
                    @tagName(mismatch.expected),
                    @tagName(mismatch.actual),
                });

                ctx.lexer.area.char_pos = mismatch.span.char_begin;
                ctx.lexer.area.line_number = mismatch.span.line_number;

                self.getSourceLocation(ctx.lexer, .erroneous);
            },

            .too_little_params => |too_little_info| {
                const span = too_little_info.span;

                self.errorMessage("{s}:{d}:{d}: the parameters to this function are incorrect.", .{
                    ctx.file_name,
                    span.line_number,
                    span.char_begin,
                });

                ctx.lexer.area.char_pos = span.char_begin;
                ctx.lexer.area.line_number = span.line_number;

                self.getSourceLocation(ctx.lexer, .erroneous);

                var stderr = std.io.getStdErr().writer();

                stderr.print("help: function '{s}' has a type signature of: {s} ", .{ too_little_info.name, too_little_info.name }) catch unreachable;

                for (too_little_info.annotation.type_list.items) |annot| {
                    if (annot.getParamType() == .single_type) {
                        stderr.print("{{{s}}} ", .{@tagName(annot.asSingleType())}) catch unreachable;
                    }
                }
            },

            else => {
                self.errorMessage("{s}: {s}", .{
                    ctx.file_name,
                    @tagName(err),
                });
            },
        }

        std.process.exit(1);
    }

    pub fn printPreprocessError(self: *Reporter, err_result: anytype, lex: *lexer.Lexer) noreturn {
        switch (err_result) {
            .nonexistent_directive => {
                self.preprocessErrorMessage("unknown directive `{s}`", .{err_result.nonexistent_directive.identifier_string});

                lex.area.char_pos = err_result.nonexistent_directive.span.char_begin;
                lex.area.line_number = err_result.nonexistent_directive.span.line_number;

                self.getSourceLocation(lex, .suggestion);
            },

            else => {
                self.preprocessErrorMessage("preprocessor error: {s}", .{@tagName(err_result)});
            },
        }

        std.process.exit(1);
    }

    pub fn astError(self: *Reporter, err: anytype, ctx: anytype, lex: *lexer.Lexer, pars: *parser.Parser) noreturn {
        const last = pars.token_stream_internal.internal_list.items[pars.token_stream_internal.stream_pos - 1];

        switch (err) {
            error.RangeExpectsSeparator => {
                lex.area.char_pos = last.number.span.char_begin;
                lex.area.line_number = last.number.span.line_number;

                self.errorMessage("{s}:{d}:{d}: range expects separator", .{
                    ctx.file_name,
                    lex.area.line_number,
                    lex.area.char_pos,
                });
                self.getSourceLocation(lex, .suggestion);
            },

            error.RangeExpectsEnd => {
                lex.area.char_pos = last.number.span.char_begin;
                lex.area.line_number = last.number.span.line_number;

                self.errorMessage("{s}:{d}:{d}: range expects '{c}'", .{
                    ctx.file_name,
                    lex.area.line_number,
                    lex.area.char_pos,
                    '}',
                });
                self.getSourceLocation(lex, .suggestion);
            },

            error.RangeStartsAfterEnd => {
                lex.area.char_pos = last.getSpan().char_begin;
                lex.area.line_number = last.getSpan().line_number;

                self.errorMessage("{s}:{d}:{d}: range starts after end (syntax is start:end)", .{
                    ctx.file_name,
                    lex.area.line_number,
                    lex.area.char_pos,
                });

                self.getSourceLocation(lex, .suggestion);
            },

            error.InvalidTokenValue => {
                lex.area.char_pos = last.getSpan().char_begin;
                lex.area.line_number = last.getSpan().line_number;

                self.errorMessage("{s}:{d}:{d}: range expects '{c}'", .{
                    ctx.file_name,
                    lex.area.line_number,
                    lex.area.char_pos,
                    '}',
                });
                self.getSourceLocation(lex, .suggestion);
            },

            else => {
                self.errorMessage("other ast error: {s}", .{
                    @errorName(err),
                });
                self.getSourceLocation(lex, .erroneous);
            },
        }
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
