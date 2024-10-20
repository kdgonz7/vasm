//! ## Preprocessor
//!
//! Takes in an AST and handles any preprocessor directives (e.g. [compat nexfuse])

const std = @import("std");
const compiler_main = @import("compiler_main.zig");

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const Options = compiler_main.Options;
const Value = parser.Value;
const ValueTag = parser.ValueTag;
const Parser = parser.Parser;
const Lexer = lexer.Lexer;

pub const Directive = struct {
    name: []const u8,
    function: *const fn (*Preprocessor, []const Value) anyerror!void,
};

pub const PreprocessorResult = union(Tag) {
    ok: u0,
    nonexistent_directive: []const u8,

    pub const Tag = enum {
        ok,
        nonexistent_directive,
    };

    pub fn getTag(self: *const PreprocessorResult) Tag {
        return switch (self.*) {
            .ok => Tag.ok,
            .nonexistent_directive => Tag.nonexistent_directive,
        };
    }
};

pub const Preprocessor = struct {
    parent_allocator: std.mem.Allocator,
    options: *Options,
    directives: std.StringHashMap(Directive),

    pub fn init(parent_allocator: std.mem.Allocator, options: *Options) Preprocessor {
        return Preprocessor{
            .parent_allocator = parent_allocator,
            .options = options,
            .directives = std.StringHashMap(Directive).init(parent_allocator),
        };
    }

    pub fn deinit(self: *Preprocessor) void {
        self.directives.deinit();
    }

    pub fn addDirective(self: *Preprocessor, name: []const u8, function: *const fn (*Preprocessor, []const Value) anyerror!void) !void {
        try self.directives.put(name, Directive{
            .name = name,
            .function = function,
        });
    }

    pub fn handleAstDirectives(self: *Preprocessor, ast_root: *parser.Node) !PreprocessorResult {
        switch (ast_root.*) {
            .root => |root| {
                for (root.children.items) |*node| {
                    const res = try self.handleAstDirectives(node);
                    switch (res) {
                        .ok => {},
                        else => {
                            return res;
                        },
                    }
                }
            },
            .procedure => |_| {},
            .macro => |mac| {
                if (self.directives.get(mac.name.identifier_string)) |directive| {
                    try directive.function(self, mac.parameters.items[0..]);
                } else {
                    return PreprocessorResult{
                        .nonexistent_directive = mac.name.identifier_string,
                    };
                }
            },

            else => {},
        }

        return PreprocessorResult{ .ok = 0 };
    }
};

fn testPrepValue(pp: *Preprocessor, args: []const Value) anyerror!void {
    _ = pp;

    try std.testing.expectEqual(1, args.len);
    try std.testing.expectEqualStrings("nexfuse", args[0].identifier.identifier_string);
}

test {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var lex = Lexer.init(allocator);

    lex.setInputText("[compat nexfuse]");
    try lex.startLexingInputText();

    var pars = Parser.init(allocator, &lex.stream);
    defer pars.deinit();

    var root = try pars.createRootNode();
    var opts1 = Options{
        .files = undefined,
    };
    var pp = Preprocessor.init(allocator, &opts1);
    defer pp.deinit();

    const res = try pp.handleAstDirectives(&root);

    if (res == .nonexistent_directive) {
        try std.testing.expectEqualStrings("compat", res.nonexistent_directive);
    } else {
        try std.testing.expect(false);
    }
}

test {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var lex = Lexer.init(allocator);

    lex.setInputText("[compat nexfuse]");
    try lex.startLexingInputText();

    var pars = Parser.init(allocator, &lex.stream);
    defer pars.deinit();

    var root = try pars.createRootNode();
    var opts1 = Options{
        .files = undefined,
    };
    var pp = Preprocessor.init(allocator, &opts1);
    defer pp.deinit();

    try pp.addDirective("compat", &testPrepValue);
    const res = try pp.handleAstDirectives(&root);

    try std.testing.expectEqual(res.getTag(), .ok);
}
test {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var lex = Lexer.init(allocator);

    lex.setInputText("[compat nexfuse]\n[compat nexfuse]");
    try lex.startLexingInputText();

    var pars = Parser.init(allocator, &lex.stream);
    defer pars.deinit();

    var root = try pars.createRootNode();
    var opts1 = Options{
        .files = undefined,
    };
    var pp = Preprocessor.init(allocator, &opts1);
    defer pp.deinit();

    try pp.addDirective("compat", &testPrepValue);
    const res = try pp.handleAstDirectives(&root);

    try std.testing.expectEqual(res.getTag(), .ok);
}
