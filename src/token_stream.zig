//! ## Token Streaming
//!
//! Lexing => Parsing => Stylist => Syntax Tree Generation => Linting => Codegen => Templating => Export
//! 1         2          3          4                         5          6          7             8
//!
//! Token streaming is a part of the lexing step. Creates abstractions for working
//! with a list of tokens. Provides methods for managing the position in the token stream, creating one,
//! deleting one, and contains definitions for different kinds of tokens used by the lexer.
//!
//! Tokenstream contains a reader for tokens

const std = @import("std");
const ArrayList = std.ArrayList;

pub const TokenStreamError = error{
    /// When getItem protects an out of range and just returns an error
    IndexOutOfRangeForReference,

    /// An outofmemory so we don't panic
    OutOfMemory,
};

/// A span from point A to point B
pub const Span = struct {
    begin: usize,
    end: usize,
    char_begin: usize = 1,
    line_number: usize,
};

/// An identifier is from A-Z, a-z, 0-9, '_' or '.'
pub const Identifier = struct {
    identifier_string: []const u8,
    span: Span = Span{
        .begin = 0,
        .end = 0,
        .line_number = 0,
    },

    const Self = @This();

    pub fn toString(self: *Self) []const u8 {
        return self.identifier_string;
    }

    pub fn getSpan(self: *const Self) Span {
        return self.span;
    }
};

pub const Number = struct {
    number: i64,
    span: Span = Span{
        .begin = 0,
        .end = 0,
        .line_number = 0,
    },

    pub fn init(with_number: i64) Number {
        return Number{
            .number = with_number,
        };
    }

    pub fn getNumber(self: *const Number) i64 {
        return self.number;
    }
};

pub const OperatorKind = enum {
    plus,
    minus,
    multiply,
    division,
    dollar_sign,
    colon,
    dot,
    at_symbol,
    comma,
    semicolon,
    bracket_open,
    bracket_close,
    curly_open,
    curly_close,
    newline,
};

pub const Operator = struct {
    kind: OperatorKind,
    operator_string: []const u8 = "",
    position: usize,
};

pub const Literal = struct {
    character: []const u8,
    span: Span = Span{
        .begin = 0,
        .end = 0,
        .line_number = 0,
    },

    pub fn init(with_char: u8) Literal {
        return Literal{
            .character = with_char,
        };
    }

    pub fn toCharacter(self: *const Literal) u8 {
        switch (self.character[0]) {
            '\\' => {
                switch (self.character[1]) {
                    'n' => {
                        return '\n';
                    },
                    't' => {
                        return '\t';
                    },
                    'r' => {
                        return '\r';
                    },
                    else => {
                        @panic("add more escape sequences (TODO)");
                    },
                }
            },
            else => {
                return self.character[0];
            },
        }
    }
};

pub const TokenTag = enum {
    identifier, // abc
    number, // 123
    operator, // + - / * = [  ]
    literal, // 'A'
    unknown,
};

pub const Token = union(TokenTag) {
    identifier: Identifier,
    number: Number,
    operator: Operator,
    literal: Literal,
    unknown,

    pub fn getType(self: *const Token) TokenTag {
        return switch (self.*) {
            .identifier => TokenTag.identifier,
            .number => TokenTag.number,
            .operator => TokenTag.operator,
            .literal => TokenTag.literal,
            else => TokenTag.unknown,
        };
    }
};

/// methods or properties can be used to read from token stream. both methods
/// are standard. This can be safely freed using `defer stream.deinit()`
pub const TokenStream = struct {
    stream_pos: usize,
    internal_list: ArrayList(Token),
    parent_allocator: std.mem.Allocator,

    pub fn init(parent_allocator: std.mem.Allocator) TokenStream {
        return TokenStream{
            .stream_pos = 0,
            .internal_list = ArrayList(Token).init(parent_allocator),
            .parent_allocator = parent_allocator,
        };
    }

    pub fn deinit(self: *TokenStream) void {
        self.stream_pos = 0;
        self.internal_list.deinit();
    }

    pub fn getItemByReferenceOrError(self: *TokenStream, index: usize) TokenStreamError!*Token {
        if (self.isOutOfRange(index)) {
            return error.IndexOutOfRangeForReference;
        }

        return &self.internal_list.items[index];
    }

    /// The given [`token`] should outlive or die with the tokenstream. Adds a token into the stream.
    pub fn addOne(self: *TokenStream, token: Token) !void {
        try self.internal_list.append(token);
    }

    pub fn incrementPositionByOne(self: *TokenStream) void {
        self.stream_pos += 1;
    }

    pub fn getCurrentStreamPosition(self: *const TokenStream) usize {
        return self.stream_pos;
    }

    pub fn getSizeOfStream(self: *const TokenStream) usize {
        return self.internal_list.items.len;
    }

    pub fn isAtEnd(self: *const TokenStream) bool {
        return self.getCurrentStreamPosition() >= self.getSizeOfStream();
    }

    pub fn isOutOfRange(self: *const TokenStream, index: usize) bool {
        return index >= self.getSizeOfStream();
    }
};

test "creating a token stream" {
    var my_token_stream = TokenStream.init(std.testing.allocator);
    defer my_token_stream.deinit();

    try my_token_stream.addOne(Token{
        .number = Number.init(64),
    });

    try std.testing.expectEqual(1, my_token_stream.getSizeOfStream());
    try std.testing.expectEqual(64, (try my_token_stream.getItemByReferenceOrError(0)).number.getNumber());
}

test "iterating a token stream" {
    var my_token_stream = TokenStream.init(std.testing.allocator);
    defer my_token_stream.deinit();

    try my_token_stream.addOne(Token{
        .identifier = Identifier{
            .identifier_string = "hello, world!",
        },
    });

    try my_token_stream.addOne(Token{
        .identifier = Identifier{
            .identifier_string = "hello, world!",
        },
    });

    try std.testing.expectEqual(2, my_token_stream.getSizeOfStream());

    while (!my_token_stream.isAtEnd()) {
        const str = (try my_token_stream.getItemByReferenceOrError(my_token_stream.getCurrentStreamPosition())).identifier.identifier_string;

        try std.testing.expectEqualStrings("hello, world!", str);

        my_token_stream.incrementPositionByOne();
    }
}

test "checking if we're at the end of the stream" {
    var my_token_stream = TokenStream.init(std.testing.allocator);
    defer my_token_stream.deinit();

    try std.testing.expect(my_token_stream.isAtEnd());
    try std.testing.expect(my_token_stream.getSizeOfStream() == 0);
    try std.testing.expect(my_token_stream.isOutOfRange(5));
    try std.testing.expectError(error.IndexOutOfRangeForReference, my_token_stream.getItemByReferenceOrError(3));
    try std.testing.expectError(error.IndexOutOfRangeForReference, my_token_stream.getItemByReferenceOrError(0));
}

test "ensuring types" {
    const token = Token{
        .identifier = .{
            .identifier_string = "hello, world!",
        },
    };

    try std.testing.expectEqual(TokenTag.identifier, token.getType());
}
