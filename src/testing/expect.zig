//! ## Testing Utilities
//!
const std = @import("std");
const parser = @import("../parser.zig");
const codegen = @import("../codegen.zig");
const instruction_result = @import("../instruction_result.zig");
const linker = @import("../linker.zig");
const lexer = @import("../lexer.zig");

pub fn expectBin(comptime T: type, text: []const u8, bin: []const T, ctx: anytype, runtime: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var link = linker.Linker(T).init(allocator);
    var vend1 = codegen.Vendor(T).init(allocator);

    try runtime(&vend1);

    const root = try ast(allocator, text);

    try vend1.generateBinary(root);
    try link.linkUnOptimizedWithContext(ctx, vend1.procedure_map);

    for (0..link.binary.items.len) |i| {
        try std.testing.expectEqual(bin[i], link.binary.items[i]);
    }
}

fn ast(allocator: std.mem.Allocator, text: []const u8) !parser.Node {
    var lex = lexer.Lexer.init(allocator);

    lex.setInputText(text);
    try lex.startLexingInputText();

    var parse = parser.Parser.init(allocator, &lex.stream);
    defer parse.deinit();

    return try parse.createRootNode();
}
