//! ## Templating
//!
//! Lexing => Parsing => Stylist => Syntax Tree Generation => Linting => Codegen => Templating => Export
//! 1         2          3          4                         5          6          7             8
//!
//! Templating/Linking is the 7th step in the VASM compiler pipeline. Templating essentially creates a usable binary
//! from the provided procedure map created during the codegen stage.
//!
//! The procedure map runs instruction sets to generate bytecode using those functions, but it does not generate a
//! usable binary. Anything like end bytes and subroutine folding is executed here.
//!

const std = @import("std");
const codegen = @import("codegen.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const Vendor = codegen.Vendor;
const Instruction = codegen.Instruction;
const InstructionError = codegen.InstructionError;
const Generator = codegen.Generator;
const Lexer = lexer.Lexer;
const Parser = parser.Parser;
const Value = parser.Value;
const Node = parser.Node;

pub const Error = error{MissingStart};

/// ## Linking
///
/// The linker struct defines methods to create usable binaries. These methods include headers, VASM headers, VASM
/// metadata, etc.
///
/// ```zig
/// try vend1.generateBinary(root);
/// try link.linkUnOptimizedWithContext(.{ .start_definition = "_start" }, vend1.procedure_map);
/// ```
///
/// The linker is heavy on machine-specific contexts, therefore, some settings
/// many need to be applied to link functions in order for them to work and compile properly.
pub fn Linker(comptime binary_size: type) type {
    return struct {
        const Self = @This();
        const Binary = std.ArrayList(binary_size);

        /// The final generated binary.
        binary: Binary,

        /// The allocator used to allocate the entire binary.
        parent_allocator: std.mem.Allocator,

        pub fn init(parent_allocator: std.mem.Allocator) Self {
            return Self{
                .parent_allocator = parent_allocator,
                .binary = Binary.init(parent_allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.binary.deinit();
        }

        /// Populates the context's start function into the binary. `ctx` has to be a type
        /// that contains a `fold_procedures` boolean value, and a `start_definition` value.
        ///
        /// * `start_definition`
        ///     * The name of the start function. If this function isn't encountered and `compile` isn't true that is an error.
        /// * `compile`
        ///     * Should the binary have no usage?
        /// * `fold_procedures`
        ///     * Should procedures be folded or should they be traditional?
        ///         * **When disabling procedure folding, the first letter of the procedure name will be used. For faster and usable code, procedure folding should remain enabled.**
        pub fn linkUnOptimizedWithContext(self: *Self, ctx: anytype, proc_map: std.StringHashMap(std.ArrayList(binary_size))) !void {
            if (!ctx.fold_procedures) {
                try self.iterateAndLink(ctx, proc_map);
            }

            var entry_point_encountered: bool = false;

            if (proc_map.get(ctx.start_definition)) |start| {
                try self.appendBytes(start.items[0..]);
                entry_point_encountered = true;
            }

            if (!entry_point_encountered and ctx.compile == false) {
                return error.MissingStart;
            }
        }

        pub fn iterateAndLink(self: *Self, ctx: anytype, proc_map: std.StringHashMap(std.ArrayList(binary_size))) !void {
            var iterator_procedure_map = proc_map.iterator();

            while (iterator_procedure_map.next()) |item| {
                if (!std.mem.eql(u8, item.key_ptr.*, ctx.start_definition)) {
                    try self.appendByte(ctx.procedure_heading_byte);
                    try self.appendByte(@bitCast(item.key_ptr.*[0]));
                    try self.appendBytes(item.value_ptr.items[0..]); // body of function
                    try self.appendByte(ctx.procedure_closing_byte);
                }
            }
        }

        /// Populates the binary with the given bytes.
        pub fn appendBytes(self: *Self, bytes: []binary_size) !void {
            try self.binary.appendSlice(bytes);
        }

        /// Populates the binary with a given byte.
        pub fn appendByte(self: *Self, byte: binary_size) !void {
            try self.binary.append(byte);
        }
    };
}

fn movInstructionTest(generator: *Generator(i8), vendor: *Vendor(i8), args: []Value) InstructionError!void {
    _ = vendor;

    try generator.append(5);
    try std.testing.expectEqual(0, args.len);
}

fn createNodeFrom(alloc: std.mem.Allocator, text: []const u8) !Node {
    var lexer_st = Lexer.init(alloc);

    lexer_st.setInputText(text);
    try lexer_st.startLexingInputText();

    var parser_st = Parser.init(alloc, &lexer_st.stream);
    defer parser_st.deinit();

    return try parser_st.createRootNode();
}

test "creating and using a linker to create a usable binary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocatir = arena.allocator();

    var link = Linker(i8).init(std.testing.allocator);
    var vend1 = Vendor(i8).init(allocatir);
    var mov_ins = Instruction(i8).init("move", &movInstructionTest);

    defer link.deinit();
    defer arena.deinit();

    const root = try createNodeFrom(allocatir, "_start: move;");

    try vend1.implementInstruction("move", &mov_ins);
    try vend1.generateBinary(root);

    try link.linkUnOptimizedWithContext(.{
        .start_definition = "_start",
        .fold_procedures = false,
        .procedure_heading_byte = 10,
        .procedure_closing_byte = 22,
        .compile = false,
        .vasm_header = false,
    }, vend1.procedure_map);

    try std.testing.expectEqual(1, link.binary.items.len);
    try std.testing.expectEqual(5, link.binary.items[0]); // 5 is from the mov instruction
}
test "creating and using a linker to create a usable binary w/ procedures using folding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocatir = arena.allocator();

    var link = Linker(i8).init(std.testing.allocator);
    var vend1 = Vendor(i8).init(allocatir);
    var mov_ins = Instruction(i8).init("move", &movInstructionTest);

    defer link.deinit();
    defer arena.deinit();

    const root = try createNodeFrom(allocatir, "a: move;");

    try vend1.implementInstruction("move", &mov_ins);
    try vend1.generateBinary(root);

    try link.linkUnOptimizedWithContext(.{
        .start_definition = "_start",
        .fold_procedures = false,
        .procedure_heading_byte = 10,
        .procedure_closing_byte = 22,
        .compile = true,
        .vasm_header = false,
    }, vend1.procedure_map);

    try std.testing.expectEqual(4, link.binary.items.len);
    try std.testing.expectEqual(10, link.binary.items[0]);
    try std.testing.expectEqual(5, link.binary.items[2]);
    try std.testing.expectEqual(22, link.binary.items[3]);
}