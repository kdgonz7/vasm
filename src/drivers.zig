//! ## Drivers
//!
//! Implementations for different bytecode platforms.

const std = @import("std");
const codegen = @import("codegen.zig");
const linker = @import("linker.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

pub const openlud = @import("platforms/openlud.zig");
pub const nexfuse = @import("platforms/nexfuse.zig");

pub fn ast(allocator: std.mem.Allocator, text: []const u8) !parser.Node {
    var lex = lexer.Lexer.init(allocator);

    lex.setInputText(text);
    try lex.startLexingInputText();

    var parse = parser.Parser.init(allocator, &lex.stream);
    defer parse.deinit();

    return try parse.createRootNode();
}

test "populate vendor using openlud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var link = linker.Linker(i8).init(allocator);
    var vend1 = codegen.Vendor(i8).init(allocator);

    try openlud.vendor(&vend1);

    var root = try ast(allocator, "b: echo 'A'\n_start: b\n");

    try std.testing.expectEqual(2, root.asRoot().getChildrenAmount());

    try vend1.generateBinary(root);
    try link.linkUnOptimizedWithContext(openlud.ctx, vend1.procedure_map);

    const expected_bin: [4]i8 = .{ 40, 65, 0, 12 }; // ECHO 65 NUL prints 'A'

    try std.testing.expectEqual(expected_bin[0], link.binary.items[0]);
    try std.testing.expectEqual(expected_bin[1], link.binary.items[1]);
    try std.testing.expectEqual(expected_bin[2], link.binary.items[2]);
    try std.testing.expectEqual(expected_bin[3], link.binary.items[3]);
}

test "populate vendor using openlud program 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var link = linker.Linker(i8).init(allocator);
    var vend1 = codegen.Vendor(i8).init(allocator);

    try openlud.vendor(&vend1);

    var root = try ast(allocator, "_start: init R1\n mov R1,65\n each R1\n");

    try std.testing.expectEqual(1, root.asRoot().getChildrenAmount());

    try vend1.generateBinary(root);

    try link.linkUnOptimizedWithContext(openlud.ctx, vend1.procedure_map);

    const expected_bin: [11]i8 = .{ 100, 1, 0, 41, 1, 65, 0, 42, 1, 0, 12 };

    for (0..expected_bin.len) |i| {
        try std.testing.expectEqual(expected_bin[i], link.binary.items[i]);
    }

    try link.writeToFile("bin/populate_vendor_using_openlud_program_2-x86_64.ol", .little);
}

test "populate vendor using openlud program 3" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var link = linker.Linker(i8).init(allocator);
    var vend1 = codegen.Vendor(i8).init(allocator);

    try openlud.vendor(&vend1);

    var root = try ast(allocator, "_start: echo 'A';");

    try std.testing.expectEqual(1, root.asRoot().getChildrenAmount());

    try vend1.generateBinary(root);

    try link.linkUnOptimizedWithContext(openlud.ctx, vend1.procedure_map);

    const expected_bin: [4]i8 = .{ 40, 65, 0, 12 };

    for (0..expected_bin.len) |i| {
        try std.testing.expectEqual(expected_bin[i], link.binary.items[i]);
    }

    try link.writeToFile("bin/populate_vendor_using_openlud_program_3-x86_64.ol", .little);
}

test "populate vendor using openlud program 4" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var link = linker.Linker(i8).init(allocator);
    var vend1 = codegen.Vendor(i8).init(allocator);

    try openlud.vendor(&vend1);

    var root = try ast(allocator, "_start:\n    init R1;\n    put R1,65,1; ;; put 65 in register 1 at position 1\n    each R1;");

    try std.testing.expectEqual(1, root.asRoot().getChildrenAmount());

    try vend1.generateBinary(root);

    try link.linkUnOptimizedWithContext(openlud.ctx, vend1.procedure_map);

    const expected_bin: [12]i8 = .{
        100, // INITIALIZE
        1, // REGISTER 1
        0, // END STATEMENT
        45, // PUT
        1, // IN REGISTER ONE
        65, // THE BYTE 65
        1, // AT POSITION 1
        0, // END STATEMENT
        42,
        1,
        0,
        12, // END EXECUTABLE
    };

    for (0..expected_bin.len) |i| {
        try std.testing.expectEqual(expected_bin[i], link.binary.items[i]);
    }

    try link.writeToFile("bin/populate_vendor_using_openlud_program_4-x86_64.ol", .little);
}
