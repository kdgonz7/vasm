//! ## LR Assembly Lexer-Parser
//!
//! Lexing => Parsing => Stylist => Syntax Tree Generation => Linting => Codegen => Templating => Export
//! 1         2          3          4                         5          6          7             8
//!
//! Lexing is the first step in the simple VASM compiler pipeline.
//!
//! Turns LR Assembly input into a token stream
//! compliant with the following standards:
//!     - 1.0.0
//!     - 1.5.0
//!     - 1.16.0
//!
//! Vasm has dropped support for the `black` compiler syntax (metafunction macros)
//! in favor of more standard macro system.
//!
//! ```
//! [compatible(NexFUSE)] - black
//! [compat nexfuse]      - standard
//! ```
//!
//! VASM is planned to be the LR assembly reference compiler. The lexer contains 3 standart types: Literal, Number, and Identifier.
//! The parser can generate higher level structures based on these types, and not all types are represented here.
//!
//! See the LR Assembly standard for more information
//!

const std = @import("std");

const TokenStreamZig = @import("token_stream.zig");
const TokenStream = TokenStreamZig.TokenStream;
const Token = TokenStreamZig.Token;
const Span = TokenStreamZig.Span;

const Identifier = TokenStreamZig.Identifier;
const Number = TokenStreamZig.Number;
const Literal = TokenStreamZig.Literal;
const Operator = TokenStreamZig.Operator;
const OpKind = TokenStreamZig.OperatorKind;

pub const LexerError = error{
    /// Basic OOM without panicking
    OutOfMemory,

    /// error(1:3): Unexpected token `{S}'.
    UnexpectedToken,

    /// No input was given (can be an ignorable error)
    NoInput,

    /// Malformed number
    MalformedNumber,

    /// A char literal is more than one character
    LiteralTooLong,

    /// A char literal is never closed (EOF encountered)
    LiteralNeverClosed,
};

/// Contains rules for the lexer.
///
/// * identifierMatches matches an identifier character, if the character
///     does not conform to the function (the function returns false) then
///     the character isn't a part of an identifier. The identifier is already
///     starting at an A-Z a-z character, therefore, this is matching characters
///     after the first character
pub const LexerRules = struct {
    identifierMatches: *const fn (u8) bool,

    fn defaultIdMatcher(char: u8) bool {
        return std.ascii.isAlphanumeric(char) or char == '_' or char == '-';
    }

    pub fn initWithDefaultRules() LexerRules {
        return LexerRules{
            .identifierMatches = defaultIdMatcher,
        };
    }
};

pub const LexerArea = struct {
    line_number: usize,
    char_pos: usize,

    pub fn init() LexerArea {
        return LexerArea{
            .line_number = 1,
            .char_pos = 1,
        };
    }

    pub fn incrementCharacterPosition(self: *LexerArea) void {
        self.char_pos += 1;
    }

    pub fn incrementLineNumber(self: *LexerArea) void {
        self.line_number += 1;
    }

    pub fn decrementCharacterPosition(self: *LexerArea) void {
        self.char_pos -= 1;
    }

    pub fn resetCharacterPosition(self: *LexerArea) void {
        self.char_pos = 0;
    }

    pub fn resetLineNumber(self: *LexerArea) void {
        self.line_number = 0;
    }
};

pub const Lexer = struct {
    stream: TokenStream,
    input_text: []const u8,
    position: usize,

    area: LexerArea = LexerArea.init(),
    rules: LexerRules = LexerRules.initWithDefaultRules(),

    pub fn init(parent_allocator: std.mem.Allocator) Lexer {
        return Lexer{
            .stream = TokenStream.init(parent_allocator),
            .input_text = "",
            .position = 0,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.stream.deinit();
        self.position = 0;
    }

    pub fn incrementLineNumber(self: *Lexer) void {
        self.area.incrementLineNumber();
        self.area.resetCharacterPosition();
    }

    pub fn incrementCharacterPosition(self: *Lexer) void {
        self.area.incrementCharacterPosition();
        self.position += 1;
    }

    pub fn decrementCharacterPosition(self: *Lexer) void {
        self.area.decrementCharacterPosition();
        self.position -= 1;
    }

    pub fn getCurrentCharacter(self: *const Lexer) u8 {
        return self.input_text[self.getCurrentPosition()];
    }

    pub fn peekAtLastCharacter(self: *const Lexer) u8 {
        return self.input_text[self.getCurrentPosition() - 1];
    }

    pub fn getCurrentPosition(self: *const Lexer) usize {
        return self.position;
    }

    pub fn getLineNumber(self: *const Lexer) usize {
        return self.area.line_number;
    }

    pub fn getInputTextSlice(self: *const Lexer, begin: usize, end: usize) []const u8 {
        return self.input_text[begin..end];
    }

    pub fn isInRange(self: *const Lexer) bool {
        return self.position < self.input_text.len;
    }

    pub fn setInputText(self: *Lexer, given_text: []const u8) void {
        self.input_text = given_text;
    }

    /// Stage 1 of lexical analysis on singular tokens
    ///
    /// Takes every character at our current position (functions can modify our position) and
    /// runs it through `matchAndRedirect` to prevent heavy violations of the SRP and keep the code
    /// cleaner
    pub fn startLexingInputText(self: *Lexer) !void {
        if (self.atEndOfInput()) {
            return error.NoInput;
        }

        while (!self.atEndOfInput()) {
            const current_character = self.getCurrentCharacter();

            if (current_character == '\n') {
                self.incrementLineNumber();
            }

            try self.matchAndRedirect(current_character);

            self.incrementCharacterPosition();
        }
    }

    /// Stage 2 of lexical analysis on singular tokens
    ///
    /// This takes in the given character and, as the name suggests, redirects that character into a
    /// transformation function to add that to our token stream
    pub fn matchAndRedirect(self: *Lexer, character: u8) !void {
        // note: we hide this pattern matching because uncle bob said so.
        switch (character) {
            'A'...'Z', 'a'...'z', '_' => {
                try self.consumeIdentifierThenAdd();
                self.decrementCharacterPosition();
            },

            '0'...'9' => {
                try self.consumeNumberThenAdd();
                self.decrementCharacterPosition();
            },

            '\'' => {
                try self.consumeLiteral();
            },

            ';' => {
                self.incrementCharacterPosition();

                if (self.getCurrentPosition() < self.input_text.len and self.getCurrentCharacter() == ';') {
                    try self.consumeComment();
                } else {
                    try self.stream.addOne(Token{
                        .operator = Operator{
                            .kind = .semicolon,
                            .position = self.getCurrentPosition(),
                        },
                    });
                }
            },

            '\n' => {
                try self.stream.addOne(Token{
                    .operator = Operator{
                        .kind = .newline,
                        .position = self.getCurrentPosition(),
                    },
                });
            },

            ':' => {
                try self.stream.addOne(Token{
                    .operator = Operator{
                        .kind = .colon,
                        .position = self.getCurrentPosition(),
                    },
                });
            },

            '.' => {
                try self.stream.addOne(Token{
                    .operator = Operator{
                        .kind = .dot,
                        .position = self.getCurrentPosition(),
                    },
                });
            },

            '@' => {
                try self.stream.addOne(Token{
                    .operator = Operator{
                        .kind = .at_symbol,
                        .position = self.getCurrentPosition(),
                    },
                });
            },

            ',' => {
                try self.stream.addOne(Token{
                    .operator = Operator{
                        .kind = .comma,
                        .position = self.getCurrentPosition(),
                    },
                });
            },

            '[' => {
                try self.stream.addOne(Token{
                    .operator = Operator{
                        .kind = .bracket_open,
                        .position = self.getCurrentPosition(),
                    },
                });
            },

            ']' => {
                try self.stream.addOne(Token{
                    .operator = Operator{
                        .kind = .bracket_close,
                        .position = self.getCurrentPosition(),
                    },
                });
            },

            else => {
                if (!std.ascii.isWhitespace(character)) {
                    std.debug.print("{c}\n", .{character});
                    return error.UnexpectedToken;
                }
            },
        }
    }

    pub fn consumeIdentifierThenAdd(self: *Lexer) !void {
        const beginning_of_identifier = self.getCurrentPosition();

        while (self.isInRange() and self.rules.identifierMatches(self.getCurrentCharacter())) {
            self.incrementCharacterPosition();
        }

        const span = Span{
            .begin = beginning_of_identifier,
            .end = self.getCurrentPosition(),
        };

        const body = self.getInputTextSlice(span.begin, span.end);

        try self.stream.addOne(Token{
            .identifier = Identifier{
                .identifier_string = body,
            },
        });
    }

    pub fn consumeNumberThenAdd(self: *Lexer) !void {
        const beginning_number = self.getCurrentPosition();

        while (self.isInRange() and std.ascii.isAlphanumeric(self.getCurrentCharacter())) {
            self.incrementCharacterPosition();
        }

        const span = Span{
            .begin = beginning_number,
            .end = self.getCurrentPosition(),
        };

        const body = self.getInputTextSlice(span.begin, span.end);

        const number_token = Token{
            .number = Number{
                // TODO: parseInt can only ever return Invalid and Overflowed,
                // keeping this for now.
                .number = std.fmt.parseInt(i64, body, 0) catch {
                    return error.MalformedNumber;
                },
            },
        };

        try self.stream.addOne(number_token);
    }

    pub fn consumeLiteral(self: *Lexer) !void {
        const beginning_of_literal = self.getCurrentPosition();

        self.incrementCharacterPosition();

        while (self.isInRange() and self.getCurrentCharacter() != '\'') {
            if (self.getCurrentCharacter() == '\\') {
                // TODO: check for literal escape sequences like \x that have
                // multiple characters
                self.incrementCharacterPosition();
            }

            self.incrementCharacterPosition();
        }

        if (!self.isInRange()) return error.LiteralNeverClosed;

        const span = Span{
            .begin = beginning_of_literal,
            .end = self.getCurrentPosition(),
        };

        // we are here
        // 'a'
        //  ^ (beginning of literal + 1)
        const tok = Token{
            .literal = Literal{
                .character = self.input_text[beginning_of_literal + 1 .. self.getCurrentPosition()],
                .span = span,
            },
        };

        try self.stream.addOne(tok);
    }

    pub fn consumeComment(self: *Lexer) !void {
        while (self.isInRange() and self.getCurrentCharacter() != '\n') {
            self.incrementCharacterPosition();
        }

        self.incrementLineNumber();
    }

    pub fn splitInputTextIntoLines(self: *Lexer) std.mem.SplitIterator(u8, std.mem.DelimiterType.sequence) {
        const array = std.mem.splitSequence(u8, self.input_text, "\n");
        return array;
    }

    pub fn atEndOfInput(self: *const Lexer) bool {
        return self.position >= self.input_text.len;
    }
};

test "creating a lexer" {
    var lexer = Lexer.init(std.testing.allocator);
    defer lexer.deinit();

    try std.testing.expectEqual(0, lexer.stream.getSizeOfStream());
    try std.testing.expectEqual(true, lexer.atEndOfInput());
}

test "using a lexer to parse a string of three identifiers" {
    var lexer = Lexer.init(std.testing.allocator);
    defer lexer.deinit();

    lexer.setInputText("apples and banaenaes");

    try lexer.startLexingInputText();

    try std.testing.expectEqual(3, lexer.stream.getSizeOfStream());

    const apples = (try lexer.stream.getItemByReferenceOrError(0)).identifier.identifier_string;
    const middle_word = (try lexer.stream.getItemByReferenceOrError(1)).identifier.identifier_string;
    const banaenaes = (try lexer.stream.getItemByReferenceOrError(2)).identifier.identifier_string;

    try std.testing.expectEqualStrings(apples, "apples");
    try std.testing.expectEqualStrings(middle_word, "and");
    try std.testing.expectEqualStrings(banaenaes, "banaenaes");
}

test "using a lexer to parse two identical numbers in different formats" {
    var lexer = Lexer.init(std.testing.allocator);
    defer lexer.deinit();

    lexer.setInputText("123 0x7B");

    try lexer.startLexingInputText();
    try std.testing.expectEqual(2, lexer.stream.getSizeOfStream());

    const number1_token = try lexer.stream.getItemByReferenceOrError(0);
    const number1 = number1_token.number.getNumber();

    const number2_token = try lexer.stream.getItemByReferenceOrError(1);
    const number2 = number2_token.number.getNumber();

    try std.testing.expectEqual(number2, number1);
}

test "using a lexer and checking its stopping line" {
    var lexer = Lexer.init(std.testing.allocator);
    defer lexer.deinit();

    lexer.setInputText("123\n0x7B\n");

    try lexer.startLexingInputText();
    try std.testing.expectEqual(4, lexer.stream.getSizeOfStream());
    try std.testing.expectEqual(3, lexer.getLineNumber());
}

test "using a lexer to lex a simple operator (colon)" {
    var lexer = Lexer.init(std.testing.allocator);
    defer lexer.deinit();

    lexer.setInputText(":");

    try lexer.startLexingInputText();
    try std.testing.expectEqual(OpKind.colon, (try lexer.stream.getItemByReferenceOrError(0)).operator.kind);
}

test "using a lexer to lex multiple operators " {
    var lexer = Lexer.init(std.testing.allocator);
    defer lexer.deinit();

    lexer.setInputText(":@.");

    try lexer.startLexingInputText();
    try std.testing.expectEqual(OpKind.colon, (try lexer.stream.getItemByReferenceOrError(0)).operator.kind);
    try std.testing.expectEqual(OpKind.at_symbol, (try lexer.stream.getItemByReferenceOrError(1)).operator.kind);
    try std.testing.expectEqual(OpKind.dot, (try lexer.stream.getItemByReferenceOrError(2)).operator.kind);
}

test "using a lexer on somewhat applicable code" {
    var lexer = Lexer.init(std.testing.allocator);
    defer lexer.deinit();

    lexer.setInputText("@sub:");

    try lexer.startLexingInputText();

    try std.testing.expectEqual(1, lexer.area.line_number);
    try std.testing.expectEqual(5, lexer.area.char_pos - 1);
    try std.testing.expectEqual(3, lexer.stream.getSizeOfStream());
    try std.testing.expectEqual(OpKind.at_symbol, (try lexer.stream.getItemByReferenceOrError(0)).operator.kind);
    try std.testing.expectEqualStrings("sub", (try lexer.stream.getItemByReferenceOrError(1)).identifier.identifier_string);
    try std.testing.expectEqual(OpKind.colon, (try lexer.stream.getItemByReferenceOrError(2)).operator.kind);
}

test "using comments" {
    var lexer = Lexer.init(std.testing.allocator);
    defer lexer.deinit();

    lexer.setInputText(";; @sub:\nsub");
    try lexer.startLexingInputText();
    try std.testing.expectEqual(2, lexer.getLineNumber());
    try std.testing.expectEqual(1, lexer.stream.getSizeOfStream());
}

test "using literals in a simple expression" {
    var lexer = Lexer.init(std.testing.allocator);
    defer lexer.deinit();

    lexer.setInputText("'a'");
    try lexer.startLexingInputText();
    try std.testing.expectEqual(1, lexer.stream.getSizeOfStream());
    try std.testing.expectEqualStrings("a", (try lexer.stream.getItemByReferenceOrError(0)).literal.character);
}

test "erroneous literal" {
    var lexer = Lexer.init(std.testing.allocator);
    defer lexer.deinit();

    lexer.setInputText("'a");
    try std.testing.expectError(error.LiteralNeverClosed, lexer.startLexingInputText());
}

test "escape sequences" {
    var lexer = Lexer.init(std.testing.allocator);
    defer lexer.deinit();

    lexer.setInputText("'\\n'");
    try lexer.startLexingInputText();

    try std.testing.expectEqual(1, lexer.stream.getSizeOfStream());
    try std.testing.expectEqualStrings("\\n", (try lexer.stream.getItemByReferenceOrError(0)).literal.character);
}
