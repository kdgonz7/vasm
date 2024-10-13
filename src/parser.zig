//! ## Parsing
//!
//! Lexing => Parsing => Stylist => Syntax Tree Generation => Linting => Codegen => Templating => Export
//! 1         2          3          4                         5          6          7             8
//!
//! Parsing is the second step in the VASM compiler pipeline. (AST Tree is 4th) Parsing takes the input token
//! stream from the lexer and generates two things:
//!
//! * Value artifacts
//!     * e.g. turning an "identifier" into a register type as well
//! * AST (Abstract Syntax Tree)
//!     * used to turn the given source code into a top-down representation
//!
//! The parser makes it much easier to work with the raw source code without the hassle of managing the environment, nested
//! calls, states, etc. It turns the source code into a bunch of memory structures.
//!

const std = @import("std");
const lexerl = @import("lexer.zig");
const token_stream_z = @import("token_stream.zig");

const Identifier = token_stream_z.Identifier;
const Number = token_stream_z.Number;
const TokenStream = token_stream_z.TokenStream;
const Operator = token_stream_z.Operator;
const Literal = token_stream_z.Literal;

const Lexer = lexerl.Lexer;
const LexerError = lexerl.LexerError;

const OpKind = token_stream_z.OperatorKind;

pub const ParseError = error{
    /// A simple notifier when the parser is at the end of its stream before parsing an input src.
    ParserHasNoInput,

    /// An unexpected or unmatched token was encountered
    UnexpectedToken,

    /// The expression is in the root scope and is NOT a procedure
    ExpressionIsNotSubroutine,

    /// The procedure has no text
    EmptySubroutine,

    /// Instruction took in a value that can not be represented
    InvalidTokenValue,

    /// A register (R<N>) is missing the number.
    RegisterMissingNumber,

    /// A token was expected
    ExpectedToken,

    /// A macro was never brought to its delimiter `]`
    MacroNeverClosed,
    Overflow,
    InvalidCharacter,
};

pub const ValueTag = enum {
    /// An identifier. See `token_stream.zig`
    /// TODO: could potentially be unused. Do
    /// a double take to make sure this has an actual use
    identifier,

    /// A number. See `token_stream.zig`
    number,

    /// The LR Assembly "Slice" type.
    /// References to a range between two values in a register.
    range,

    /// The LR Assembly "Register" type.
    /// A reference to a register on the CPU. Platform-dependent behaviour.
    register,

    /// The LR Assembly "Literal" type.
    /// A single character in the ASCII set.
    literal,
};

/// A value. Represents an LR assembly value. [compliant]
/// Implements builtin values from the lexer and token stream,
/// as well as a few others
pub const Value = union(ValueTag) {
    identifier: Identifier,
    number: Number,
    range: Range,
    register: Register,
    literal: Literal,

    pub fn toRegister(self: *const Value) Register {
        return self.register;
    }

    pub fn toRange(self: *const Value) Range {
        return self.range;
    }

    pub fn toIdentifier(self: *const Value) Register {
        return self.identifier;
    }

    pub fn toNumber(self: *const Value) Number {
        return self.number;
    }

    pub fn toLiteral(self: *const Value) Literal {
        return self.literal;
    }

    pub fn getType(self: *const Value) ValueTag {
        return switch (self.*) {
            ValueTag.identifier => ValueTag.identifier,
            ValueTag.number => ValueTag.number,
            ValueTag.range => ValueTag.range,
            ValueTag.register => ValueTag.register,
            ValueTag.literal => ValueTag.literal,
        };
    }
};

/// A register reference. E.g. R0, R1, R2
pub const Register = struct {
    register_number: usize,

    pub fn init(at_number: usize) Register {
        return Register{
            .register_number = at_number,
        };
    }

    pub fn getRegisterNumber(self: *Register) usize {
        return self.register_number;
    }
};

pub const Range = struct {
    starting_position: usize,
    ending_position: usize,
};

/// Possible types that a `Node` type can be.
pub const NodeTag = enum {
    /// Value is the result of an expression. The simplest form of node.
    /// Values have no children and withhold the `Value` type.
    value,

    /// Instruction calls hold the `instruction_name` which is an identifier and
    /// `parameters` which is a list of values that are called with the instruction.
    /// See [`Instruction`]
    instruction_call,

    /// Procedures hold children nodes which are all type `Node` and
    /// are all of the calls and expresions inside of the procedure.
    /// Due to their syntax there is no support for nesting procedures.
    /// Procedures can get cluttered and cause huge performance drops, therefore
    /// operations can be placed on procedures in order to make them easier to deal with.
    ///
    ///
    /// See [`Procedure`]
    procedure,

    /// Macros hold a `name` (identifier) and any `Value` parameters.
    macro,

    /// The root node. Holds all of the tree's children.
    root,
};

/// The `Node` encapsulates all possible values. Match and capture
/// statements are important when unwrapping nodes so use them
pub const Node = union(NodeTag) {
    value: Value,
    instruction_call: Instruction,
    procedure: Procedure,
    macro: Macro,
    root: Root,

    pub fn asRoot(self: *Node) *Root {
        return &self.root;
    }
};

/// An instruction.
///
/// ```
/// mov eax,123
/// ```
pub const Instruction = struct {
    name: Identifier,
    parameters: std.ArrayList(Value),
};

/// A procedure definition.
///
/// ```
/// _start:
/// ```
pub const Procedure = struct {
    /// The header of the procedure. `_start:` the header is `_start
    header: []const u8,

    /// The procedure's documentation. This may be unused.
    documentation: []const u8,

    /// The procedure's child calls. You will NOT encounter
    /// any sub-procedures.
    children: std.ArrayList(Node),
};

/// A macro call.
///
/// ```
/// [compat nexfuse]
/// ```
///
/// Historically, the macro syntax has had many revisions, this syntax is called the VOLT Macro Syntax and is
/// the more accepted version of the macro system.
pub const Macro = struct {
    /// The macro name e.g. `compat`
    name: Identifier,

    /// The macro's parameters. e.g. `nexfuse`
    parameters: std.ArrayList(Value),
};

/// The root node. Manages all of its children
pub const Root = struct {
    children: std.ArrayList(Node),

    /// Returns the amount of children in the given root node.
    pub fn getChildrenAmount(self: *Root) usize {
        return self.children.items.len;
    }

    pub fn getChildren(self: *Root) *[]Node {
        return &self.children.items;
    }

    /// Returns `true` if the root node has no children
    pub fn isEmpty(self: *Root) bool {
        return self.children.items.len == 0;
    }
};

/// The parser takes in an input list of tokens and spits out a node that
/// defines the tree of the source code. This is a separate mechanism from the stylist facility which
/// manages the styling of the source code
pub const Parser = struct {
    token_stream_internal: *TokenStream,
    parent_allocator: std.mem.Allocator,

    pub fn init(parent_allocator: std.mem.Allocator, token_stream: *TokenStream) Parser {
        return Parser{
            .token_stream_internal = token_stream,
            .parent_allocator = parent_allocator,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.token_stream_internal.*.deinit();
    }

    pub fn getInternalTokens(self: *Parser) *TokenStream {
        return self.token_stream_internal;
    }

    pub fn getCurrentToken(self: *Parser) !*token_stream_z.Token {
        var str = self.getInternalTokens();
        return try str.getItemByReferenceOrError(str.getCurrentStreamPosition());
    }

    pub fn getNextToken(self: *Parser) !*token_stream_z.Token {
        var str = self.getInternalTokens();
        return try str.getItemByReferenceOrError(str.getCurrentStreamPosition() + 1);
    }

    pub fn nextTokenExists(self: *Parser) bool {
        var str = self.getInternalTokens();
        return !(str.isOutOfRange(str.getCurrentStreamPosition() + 1));
    }

    pub fn streamIsAtEnd(self: *Parser) bool {
        return self.getInternalTokens().isAtEnd();
    }

    pub fn incrementCurrentPosition(self: *Parser) void {
        return self.getInternalTokens().incrementPositionByOne();
    }

    /// Creates a node based on `self.token_stream_internal`
    pub fn createRootNode(self: *Parser) !Node {
        if (self.streamIsAtEnd()) return error.ParserHasNoInput;

        // create the root node, this will be returned by the function
        var node = Node{
            .root = Root{
                .children = std.ArrayList(Node).init(self.parent_allocator),
            },
        };

        // while we're not at the end of the token stream
        while (!self.streamIsAtEnd()) {
            const current_token = try self.getCurrentToken();

            switch (current_token.*) {
                // if we've encountered an operator
                .operator => |op| {
                    var root = node.asRoot();

                    try root.children.append(try self.createNodeFromOperator(op));
                },

                // since this is the root node, we expect this to be a subroutine. Any
                // macros or calls where the delimiter is at the beginning of the statement are
                // already chewed up by the createNodeFromOperator() function.
                .identifier => |id| {
                    var root = node.asRoot();

                    // we now advance one
                    self.incrementCurrentPosition();

                    const next_token = try self.getCurrentToken();

                    // if our token type is an oeprator and the kind is a colon
                    // meaning that our statment looks like:
                    // <IDENT><COLON>
                    // 0       1
                    //         ^
                    //         our position here
                    if (next_token.getType() == .operator and next_token.operator.kind == OpKind.colon) {
                        self.incrementCurrentPosition();

                        if (self.streamIsAtEnd()) {
                            // and FTR: empty subroutines can be a error. they are not
                            // explicitly stated in the standard as an error/standard warning but
                            // this parser aims to provide as much information on the source code as possible.
                            //TODO: if issues arise with this line, change it to a more lenient rule
                            return error.EmptySubroutine;
                        }

                        // we then advance again, and we create a procedure body
                        try root.children.append(try self.createNodeFromProcedure(id));
                    } else {
                        // we expect a subroutine to kick our journey off,
                        // if the token isn't a subroutine then we can just throw an error,
                        // all the information is there to provide a logical and sensible error.
                        return error.ExpressionIsNotSubroutine;
                    }
                },

                else => {
                    return error.UnexpectedToken;
                },
            }

            // when everything else finished doing its magic,
            // move to the next token
            self.incrementCurrentPosition();
        }

        return node;
    }

    /// Parses the given operator
    pub fn createNodeFromOperator(self: *Parser, operator: Operator) !Node {
        // check the operator kind
        switch (operator.kind) {
            // if it's an @ symbol, we then check if the old syntax is enabled, which
            // is off by default. In this case we parse it like a procedure header.
            OpKind.at_symbol => {},
            OpKind.bracket_open => {
                // the opening of a macro.
                // this has the syntax of
                // [IDENT ...]

                return try self.createNodeFromMacro();
            },

            else => {
                return error.UnexpectedToken;
            },
        }

        return Node{
            .value = Value{
                .number = Number.init(56),
            },
        };
    }

    /// Creates a `Macro` node. From the LR Assembly standard:
    ///
    /// Macros can be defined as “code that runs without the VM’s knowledge.”
    /// Essentially being a way to specify how the program is meant to run or
    /// compile without any code being generated or any other memory construct
    /// overhead.
    pub fn createNodeFromMacro(self: *Parser) !Node {
        self.incrementCurrentPosition();

        if (self.streamIsAtEnd()) {
            return error.ExpectedToken;
        }

        const name = (try self.getCurrentToken()).identifier;

        var node = Node{
            .macro = Macro{
                .name = name,
                .parameters = std.ArrayList(Value).init(self.parent_allocator),
            },
        };

        // skip past the name
        self.incrementCurrentPosition();

        // while we're not at the end of the stream
        while (!self.streamIsAtEnd()) {
            const current = try self.getCurrentToken();

            // if the current token is a bracket close
            if (current.getType() == .operator and current.operator.kind == OpKind.bracket_close) {
                break;
            }

            // otherwise we've got an argument add it
            try node.macro.parameters.append(try self.createValueFromToken(current));

            // next token!
            self.incrementCurrentPosition();
        }

        if (self.streamIsAtEnd()) { // this function ends on the `]`. If that's not the case we can confidently say its an error
            return error.MacroNeverClose;
        }

        return node;
    }

    /// Creates a procedure node from the current node past the identifier `name`.
    ///
    /// The token this function starts at is anything after the `:` operator.
    pub fn createNodeFromProcedure(self: *Parser, name: Identifier) !Node {
        // create the procedure node, this is what will be returned
        var node = Node{
            .procedure = Procedure{
                .children = std.ArrayList(Node).init(self.parent_allocator),
                .documentation = "",
                .header = name.identifier_string,
            },
        };

        // we now parse the tokens in the procedure body
        while (!self.streamIsAtEnd()) {
            const token = try self.getCurrentToken();

            switch (token.*) {
                // if it's an identifier, we can parse this as an instruction
                .identifier => {
                    var stream = self.getInternalTokens();

                    // if there's a next token, check it against the colon OpKind
                    if (!stream.isOutOfRange(stream.getCurrentStreamPosition() + 1)) {
                        const potential_header_decl = try self.getNextToken();

                        if (potential_header_decl.getType() == .operator and potential_header_decl.operator.kind == OpKind.colon) {
                            self.getInternalTokens().stream_pos -= 1;
                            return node; // The root expression can then take control
                        }
                    }

                    // we can create an instruction with the current token's identifier( it should be an identifier )
                    self.incrementCurrentPosition();

                    var children = &node.procedure.children;

                    try children.append(try self.createNodeFromInstruction(token.*.identifier));
                },

                .number, .operator => {},

                else => {
                    return error.UnexpectedToken;
                },
            }

            self.incrementCurrentPosition();
        }

        return node;
    }

    pub fn createNodeFromInstruction(self: *Parser, name: Identifier) !Node {
        var node = Node{
            .instruction_call = Instruction{
                .name = name,
                .parameters = std.ArrayList(Value).init(self.parent_allocator),
            },
        };

        var instructions = &node.instruction_call.parameters;

        while (!self.streamIsAtEnd()) {
            const current = try self.getCurrentToken();

            // if there's a semicolon
            if ((current.getType() == .operator) and (current.operator.kind == .semicolon or current.operator.kind == .newline)) {
                // self.incrementCurrentPosition();
                return node;
            }

            // we append the token value as an instruction parameter
            try instructions.append(try self.createValueFromToken(try self.getCurrentToken()));

            if (self.nextTokenExists()) {
                const next_token = try self.getNextToken();

                if ((next_token).getType() != .operator or (next_token).operator.kind != OpKind.comma) {
                    break;
                }
            } else {
                break;
            }

            self.incrementCurrentPosition();
            self.incrementCurrentPosition();
        }

        return node;
    }

    pub fn createValueFromToken(self: *Parser, token: *token_stream_z.Token) !Value {
        _ = self;
        switch (token.*) {
            .number => {
                return Value{
                    .number = token.number,
                };
            },

            .identifier => {
                const ident = token.identifier;

                if (ident.identifier_string[0] == 'R') {
                    if (ident.identifier_string.len == 1) {
                        return error.RegisterMissingNumber;
                    }
                    const register_number = ident.identifier_string[1..];
                    const reg = Register{
                        .register_number = try std.fmt.parseInt(usize, register_number, 0),
                    };

                    return Value{
                        .register = reg,
                    };
                } else {
                    return Value{
                        .identifier = ident,
                    };
                }
            },

            .literal => |lit| {
                return Value{ .literal = lit };
            },

            else => {
                return error.InvalidTokenValue;
            },
        }

        return error.InvalidTokenValue;
    }
};

pub fn createTestArena() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(std.testing.allocator);
}

test "creating and using a parser for a single proc" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText("a:mov 1,1");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);
    defer parser.deinit();

    var root = try parser.createRootNode();

    try std.testing.expectEqual(1, root.asRoot().children.items.len);

    const proc1 = root.asRoot().children.items[0];

    try std.testing.expectEqualStrings("a", proc1.procedure.header);
}

test "creating and using a parser for a multiple proc" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText("a:mov 1,1 b: push 1,5");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);
    defer parser.deinit();

    var root = try parser.createRootNode();

    try std.testing.expectEqual(2, root.asRoot().children.items.len);

    const proc1 = root.asRoot().children.items[0];
    const proc2 = root.asRoot().children.items[1];

    try std.testing.expectEqualStrings("a", proc1.procedure.header);
    try std.testing.expectEqualStrings("b", proc2.procedure.header);
    try std.testing.expectEqualStrings("mov", proc1.procedure.children.items[0].instruction_call.name.identifier_string);
    try std.testing.expectEqual(2, proc1.procedure.children.items[0].instruction_call.parameters.items.len);
    try std.testing.expectEqual(1, proc1.procedure.children.items[0].instruction_call.parameters.items[0].number.number);
    try std.testing.expectEqual(1, proc1.procedure.children.items[0].instruction_call.parameters.items[1].number.number);

    try std.testing.expectEqualStrings("push", proc2.procedure.children.items[0].instruction_call.name.identifier_string);
    try std.testing.expectEqual(2, proc2.procedure.children.items[0].instruction_call.parameters.items.len);
    try std.testing.expectEqual(1, proc2.procedure.children.items[0].instruction_call.parameters.items[0].number.number);
    try std.testing.expectEqual(5, proc2.procedure.children.items[0].instruction_call.parameters.items[1].number.number);
}

test "creating and using a parser for a multiple procedures with register values" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText("a:mov R1");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);
    defer parser.deinit();

    var root = try parser.createRootNode();

    try std.testing.expectEqual(1, root.asRoot().children.items.len);

    const proc1 = root.asRoot().children.items[0];

    try std.testing.expectEqualStrings("a", proc1.procedure.header);
    try std.testing.expectEqualStrings("mov", proc1.procedure.children.items[0].instruction_call.name.identifier_string);
    try std.testing.expectEqual(1, proc1.procedure.children.items[0].instruction_call.parameters.items.len);
    try std.testing.expectEqual(1, proc1.procedure.children.items[0].instruction_call.parameters.items[0].register.register_number);
}

test "creating and using a parser for a multiple procedures with register values with whitespace" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText("a:\n    mov R1");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);
    defer parser.deinit();

    var root = try parser.createRootNode();

    try std.testing.expectEqual(1, root.asRoot().children.items.len);

    const proc1 = root.asRoot().children.items[0];

    try std.testing.expectEqualStrings("a", proc1.procedure.header);
    try std.testing.expectEqualStrings("mov", proc1.procedure.children.items[0].instruction_call.name.identifier_string);
    try std.testing.expectEqual(1, proc1.procedure.children.items[0].instruction_call.parameters.items.len);
    try std.testing.expectEqual(1, proc1.procedure.children.items[0].instruction_call.parameters.items[0].register.register_number);
}

test "creating and using a parser for a macro" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText("[a 1 2 3]");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);
    defer parser.deinit();

    var root = try parser.createRootNode();

    try std.testing.expectEqual(1, root.asRoot().children.items.len);

    const macro_call = root.asRoot().children.items[0];

    try std.testing.expectEqualStrings("a", macro_call.macro.name.identifier_string);

    try std.testing.expectEqual(3, macro_call.macro.parameters.items.len);
    try std.testing.expectEqual(1, macro_call.macro.parameters.items[0].number.getNumber());
    try std.testing.expectEqual(2, macro_call.macro.parameters.items[1].number.getNumber());
    try std.testing.expectEqual(3, macro_call.macro.parameters.items[2].number.getNumber());
}

test "creating and using a parser for multiple macros" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText("[compat nexfuse] [compat def]");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);
    defer parser.deinit();

    var root = try parser.createRootNode();

    try std.testing.expectEqual(2, root.asRoot().children.items.len);

    const macro_call_one = root.asRoot().children.items[0];
    const macro_call_two = root.asRoot().children.items[1];

    try std.testing.expectEqual(1, macro_call_one.macro.parameters.items.len);
    try std.testing.expectEqual(1, macro_call_two.macro.parameters.items.len);
    try std.testing.expectEqualStrings("compat", macro_call_one.macro.name.identifier_string);
    try std.testing.expectEqualStrings("compat", macro_call_two.macro.name.identifier_string);
    try std.testing.expectEqualStrings("nexfuse", macro_call_one.macro.parameters.items[0].identifier.identifier_string);
    try std.testing.expectEqualStrings("def", macro_call_two.macro.parameters.items[0].identifier.identifier_string);
}

test "creating and using a parser for niladic forms" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText("start:\n   halt");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);
    defer parser.deinit();

    var root = try parser.createRootNode();

    try std.testing.expectEqual(1, root.asRoot().children.items.len);

    const start = root.asRoot().children.items[0].procedure;

    try std.testing.expectEqual(1, start.children.items.len);
    try std.testing.expectEqual(0, start.children.items[0].instruction_call.parameters.items.len);
    try std.testing.expectEqualStrings("halt", start.children.items[0].instruction_call.name.identifier_string);
}

test "creating and using a parser with trailing commas" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText("start:\n   halt R1,");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);
    defer parser.deinit();

    var root = try parser.createRootNode();

    try std.testing.expectEqual(1, root.asRoot().children.items.len);

    const start = root.asRoot().children.items[0].procedure;

    try std.testing.expectEqual(1, start.children.items.len);
    try std.testing.expectEqual(1, start.children.items[0].instruction_call.parameters.items.len);
    try std.testing.expectEqualStrings("halt", start.children.items[0].instruction_call.name.identifier_string);
}

test "error test 1" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText("[compat nexfuse[[compat def]]");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);
    defer parser.deinit();

    try std.testing.expectError(error.InvalidTokenValue, parser.createRootNode());
}

test "error test 2" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText("A A: 22 1421 : 1");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);

    try std.testing.expectError(error.ExpressionIsNotSubroutine, parser.createRootNode());
    try std.testing.expectEqual(1, parser.getInternalTokens().stream_pos);
}

test "error test 3" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText("]]");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);

    try std.testing.expectError(error.UnexpectedToken, parser.createRootNode());
    try std.testing.expectEqual(0, parser.token_stream_internal.stream_pos);
}

test "error test 4" {
    var arena = createTestArena();
    const allocator = arena.allocator();
    defer arena.deinit();

    var lexer = Lexer.init(allocator);

    lexer.setInputText(":");
    try lexer.startLexingInputText();

    var parser = Parser.init(allocator, &lexer.stream);

    try std.testing.expectError(error.UnexpectedToken, parser.createRootNode());
    try std.testing.expectEqual(0, parser.token_stream_internal.stream_pos);
}
