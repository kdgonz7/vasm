//! LR Assembly codegen
//!
//! Lexing => Parsing => Stylist => Syntax Tree Generation => Linting => Codegen => Templating => Export
//! 1         2          3          4                         5          6          7             8
//!
//! Code generation is the 6th step in the simple LR assembly pipeline. This step
//! is meant to generate procedure maps for binaries. Code generation makes it easy to
//! define new systems by using the `Vendor` class. The Vendor class holds a hashmap from
//! instructions to raw instruction functions, and the vendor can generate bytes that are held
//! in the struct itself.
//!
//! This step does NOT generate usable binaries and therefore can not be written directly to files. The
//! Code generation stage is meant to generate actual byte code depending on the Vendor struct and the given
//! instruction set.
//!

const std = @import("std");
const peephole = @import("peephole.zig");
const instruction_result = @import("instruction_result.zig");

const Lexer = @import("lexer.zig").Lexer;
const LexerArea = @import("lexer.zig").LexerArea;

const Parser = @import("parser.zig").Parser;

const Node = @import("parser.zig").Node;
const NodeTag = @import("parser.zig").NodeTag;
const Value = @import("parser.zig").Value;
const Root = @import("parser.zig").Root;
const Procedure = @import("parser.zig").Procedure;

const InstructionResult = instruction_result.InstructionResult;

pub const InstructionError = error{
    OutOfMemory,
    InstructionExpectsDifferentValue,
    InstructionDoesntExist,
    TestExpectedEqual,
    InstructionError,
};

pub const CodegenError = error{
    /// an invalid root expression was encountered
    InvalidExpressionRoot,
    RegisterNumberTooLarge,
};

/// Instruction information for compiler debugging. Not meant for actual use in runtimes, etc.
pub fn Instruction(comptime format: type) type {
    return struct {
        /// The instruction's internal name (used for debugging)
        name: []const u8,

        /// The function ran from the instruction
        function: *const fn (*Generator(format), *Vendor(format), []Value) InstructionError!InstructionResult,

        pub fn init(name: []const u8, function: *const fn (*Generator(format), *Vendor(format), []Value) InstructionError!InstructionResult) Instruction(format) {
            return Instruction(format){
                .name = name,
                .function = function,
            };
        }
    };
}

/// The generator object holds the binary generated by an instruction.
///
/// Example:
///
/// ```
///
/// fn (generator: *Generator(i32), vendor: *Vendor(i32), args: []Value) !void {
///     // generator => the binary generator
///     // vendor    => The codegen vendor. Contains environment-specific information
///     // args      => arguments passed into this instruction.
///     try generator.append(0xAB);
///     try generator.append(args[0].number.getNumber());
/// }
/// ```
pub fn Generator(comptime T: type) type {
    return struct {
        binary: std.ArrayList(T),
        parent_allocator: std.mem.Allocator,

        pub fn init(parent_allocator: std.mem.Allocator) Generator(T) {
            return Generator(T){
                .parent_allocator = parent_allocator,
                .binary = std.ArrayList(T).init(parent_allocator),
            };
        }

        pub fn append(self: *Generator(T), byte: T) !void {
            try self.binary.append(byte);
        }
    };
}

/// Best to allocate with an arena.
///
/// A VENDOR for text -> instructions and macros. It is safest to run using an arena allocator, and parent to the desired
/// allocator. Reason being memory will become more complex and hard to manage as the data structure grows. So it's
/// best to just use an arena and save the trouble.
///
pub fn Vendor(comptime format_type: type) type {
    return struct {
        const Self = @This();

        /// The procedure map holds `name` -> `binary`. Essentially the .sections section in the file
        procedure_map: std.StringHashMap(std.ArrayList(format_type)),

        /// The list of strings to instructions. These
        /// are ran with their respective parameters.
        instruction_set: std.StringHashMap(Instruction(format_type)),

        /// The dead code eliminator
        peephole_optimizer: peephole.PeepholeOptimizer(format_type),

        /// the parent allocator.
        parent_allocator: std.mem.Allocator,

        /// Place a NULL byte at the end of an instruction binary?
        nul_after_sequence: bool = false,
        nul_byte: format_type = 0,

        /// A list of instruction results ran from each instruction.
        results: std.ArrayList(InstructionResult),

        erroneous_result: InstructionResult = undefined,

        pub fn init(parent_allocator: std.mem.Allocator) Self {
            return Self{
                .parent_allocator = parent_allocator,
                .procedure_map = std.StringHashMap(std.ArrayList(format_type)).init(parent_allocator),
                .instruction_set = std.StringHashMap(Instruction(format_type)).init(parent_allocator),
                .peephole_optimizer = peephole.PeepholeOptimizer(format_type).init(parent_allocator),
                .results = std.ArrayList(InstructionResult).init(parent_allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.procedure_map.deinit();
            self.instruction_set.deinit();
        }

        /// Puts `name` to `instruction`
        pub fn implementInstruction(self: *Self, name: []const u8, instruction: *Instruction(format_type)) !void {
            try self.instruction_set.put(name, instruction.*);
        }

        pub fn createAndImplementInstruction(self: *Self, comptime size: type, name: []const u8, function: *const fn (generator: *Generator(size), vendor: *Vendor(size), args: []Value) InstructionError!InstructionResult) !void {
            try self.instruction_set.put(name, Instruction(size){
                .function = function,
                .name = name,
            });
        }

        /// Populates the vendor's procedure map with instructions by running their
        /// respective functions.
        pub fn generateBinary(self: *Self, node: Node) !void {
            switch (node) {
                .root => |*root_node| {
                    for (root_node.children.items) |*child| {
                        switch (child.*) {
                            .procedure => |*proc| {
                                try self.generateBinaryProcedure(proc);
                            },
                            else => {
                                return error.InvalidExpressionRoot;
                            },
                        }
                    }
                },

                else => {},
            }
        }

        /// Generates the memory layout of a procedure. Iterates the instructions and runs them
        /// one by one in order, populating their space in the procedure map in the process.
        ///
        /// This function will also take into account instructions that are a part of the
        /// procedure map, and also run those accordingly. User-defined procedures have higher
        /// precedent over instruction set procedures.
        ///
        pub fn generateBinaryProcedure(self: *Self, child: *Procedure) !void {
            const procedure_name = child.header;
            var generator = Generator(format_type).init(self.parent_allocator);

            for (child.children.items[0..]) |call| {
                switch (call) {
                    // if its an instruction call
                    .instruction_call => |ins| {
                        if (self.procedure_map.get(ins.name.identifier_string)) |proc| {
                            for (proc.items) |byt| {
                                try generator.append(byt);
                            }

                            // that instruction has been expanded once and is in use
                            try self.peephole_optimizer.remember(ins.name.identifier_string);
                        } else {

                            // built in instruction
                            if (self.instruction_set.get(ins.name.identifier_string)) |map_item| {
                                for (ins.parameters.items) |it| {
                                    if (it.getType() == .register and it.toRegister().getRegisterNumber() > std.math.maxInt(format_type)) {
                                        return error.RegisterNumberTooLarge;
                                    }
                                }
                                const res = try map_item.function(&generator, self, ins.parameters.items);
                                switch (res) {
                                    .ok => {},
                                    else => {
                                        self.erroneous_result = res;
                                        return error.InstructionError;
                                    },
                                }
                            } else {
                                return error.InstructionDoesntExist;
                            }

                            if (self.nul_after_sequence) {
                                try generator.append(self.nul_byte);
                            }
                        }
                    },

                    else => {},
                }
            }

            try self.procedure_map.put(procedure_name, generator.binary);
        }

        pub fn peepholeOptimizeBinary(self: *Self) !void {
            try self.peephole_optimizer.optimizeUsingKnownInstructions(&self.procedure_map);
        }
    };
}

// =====- Tests -===== //

fn movInstructionTest(generator: *Generator(i32), vendor: *Vendor(i32), args: []Value) !InstructionResult {
    _ = vendor;
    try generator.append(5);
    if (args.len == 1) {
        std.debug.print("{any}\n", .{args[0]});
    }
    try std.testing.expectEqual(0, args.len);

    return .ok;
}

fn movInstructionTestError(generator: *Generator(i32), vendor: *Vendor(i32), args: []Value) !InstructionResult {
    _ = vendor;
    _ = args;
    _ = generator;
    return InstructionResult.typeMismatch(.literal, .register);
}

fn oneArgumentInstruction(generator: *Generator(i32), vendor: *Vendor(i32), args: []Value) !InstructionResult {
    _ = vendor;
    _ = generator;

    try std.testing.expectEqual(1, args.len);
    try std.testing.expectEqual(0x0A, args[0].toNumber().getNumber());

    return .ok;
}

fn registerSample(generator: *Generator(i8), vendor: *Vendor(i8), args: []Value) !InstructionResult {
    _ = vendor;
    _ = generator;

    try std.testing.expectEqual(1, args.len);

    return .ok;
}

fn oneArgumentInstructionWithPlacement(generator: *Generator(i32), vendor: *Vendor(i32), args: []Value) InstructionError!void {
    _ = vendor;
    try std.testing.expectEqual(1, args.len);
    try std.testing.expectEqual(0x0A, args[0].toNumber().getNumber());
    try generator.append(25);
}

fn createNodeFrom(alloc: std.mem.Allocator, text: []const u8) !Node {
    var lexer = Lexer.init(alloc);

    lexer.setInputText(text);
    try lexer.startLexingInputText();

    var parser = Parser.init(alloc, &lexer.stream);
    defer parser.deinit();

    return try parser.createRootNode();
}

test "creating and using a vendor with 0 argument function and one statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocatir = arena.allocator();
    defer arena.deinit();

    var sibc = Vendor(i32).init(allocatir);

    var mov_ins = Instruction(i32).init("mov", &movInstructionTest);
    try sibc.implementInstruction("mov", &mov_ins);

    const root = try createNodeFrom(allocatir, "a: mov");

    try sibc.generateBinary(root);
    try std.testing.expect(sibc.procedure_map.get("a") != null);
    try std.testing.expectEqual(1, sibc.procedure_map.get("a").?.items.len);
}

test "creating and using a vendor with 0 argument function and two statements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocatir = arena.allocator();
    defer arena.deinit();

    var sibc = Vendor(i32).init(allocatir);

    var mov_ins = Instruction(i32).init("mov", &movInstructionTest);
    try sibc.implementInstruction("mov", &mov_ins);

    const root = try createNodeFrom(allocatir, "a: mov; mov");

    try sibc.generateBinary(root);
    try std.testing.expect(sibc.procedure_map.get("a") != null);
    try std.testing.expectEqual(2, sibc.procedure_map.get("a").?.items.len);
}

test "creating and using a vendor with 0 argument functions, one calling the other for its instructions and folding it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocatir = arena.allocator();
    defer arena.deinit();

    var sibc = Vendor(i32).init(allocatir);

    var mov_ins = Instruction(i32).init("mov", &movInstructionTest);
    try sibc.implementInstruction("mov", &mov_ins);

    const root = try createNodeFrom(allocatir, "a: mov; mov;\nb: a;");

    try sibc.generateBinary(root);
    try std.testing.expect(sibc.procedure_map.get("a") != null);
    try std.testing.expectEqual(2, sibc.procedure_map.get("a").?.items.len);

    try std.testing.expect(sibc.procedure_map.get("b") != null);
    try std.testing.expectEqual(2, sibc.procedure_map.get("b").?.items.len);
}

test "creating and using a vendor with 0 argument functions but multiple subroutines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocatir = arena.allocator();
    defer arena.deinit();

    var sibc = Vendor(i32).init(allocatir);

    var mov_ins = Instruction(i32).init("mov", &movInstructionTest);
    try sibc.implementInstruction("mov", &mov_ins);

    const root = try createNodeFrom(allocatir, "a: mov\nb: a\n");

    try sibc.generateBinary(root);
    try std.testing.expect(sibc.procedure_map.get("a") != null);
    try std.testing.expectEqual(1, sibc.procedure_map.get("a").?.items.len);

    try std.testing.expect(sibc.procedure_map.get("b") != null);
    try std.testing.expectEqual(1, sibc.procedure_map.get("b").?.items.len);
}

test "creating and using a vendor with 1 argument function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocatir = arena.allocator();
    defer arena.deinit();

    var sample_vendor = Vendor(i32).init(allocatir);

    var one_ins = Instruction(i32).init("mov", &oneArgumentInstruction);
    try sample_vendor.implementInstruction("one", &one_ins);

    const root = try createNodeFrom(allocatir, "a: one 0x0A ;; runs the `one` instruction with `0x0A`");

    try sample_vendor.generateBinary(root);
    try std.testing.expect(sample_vendor.procedure_map.get("a") != null);
    try std.testing.expectEqual(0, sample_vendor.procedure_map.get("a").?.items.len);
}

test "dead code elimination" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocatir = arena.allocator();
    defer arena.deinit();

    var sample_vendor = Vendor(i32).init(allocatir);

    var one_ins = Instruction(i32).init("one", &oneArgumentInstruction);
    try sample_vendor.implementInstruction("one", &one_ins);

    const root = try createNodeFrom(allocatir, "a: one 0x0A; b: one 0x0A; _start: a; ");

    try sample_vendor.generateBinary(root);

    try sample_vendor.peephole_optimizer.remember("_start");
    try sample_vendor.peepholeOptimizeBinary();

    try std.testing.expect(sample_vendor.procedure_map.get("a") != null);
    try std.testing.expect(sample_vendor.procedure_map.get("_start") != null);
    try std.testing.expectEqual(0, sample_vendor.procedure_map.get("a").?.items.len);
    try std.testing.expect(sample_vendor.procedure_map.get("b") == null); // b exited, but got optimized away
}

test "creating and using a vendor with 0 argument functions that returns an error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocatir = arena.allocator();
    defer arena.deinit();

    var sibc = Vendor(i32).init(allocatir);

    var mov_ins = Instruction(i32).init("mov", &movInstructionTestError);
    try sibc.implementInstruction("mov", &mov_ins);

    const root = try createNodeFrom(allocatir, "a: mov\nb: a\n");

    try std.testing.expectError(error.InstructionError, sibc.generateBinary(root));
    try std.testing.expectEqual(.literal, sibc.erroneous_result.type_mismatch.expected);
    try std.testing.expectEqual(.register, sibc.erroneous_result.type_mismatch.got);
}

test "register too big" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocatir = arena.allocator();
    defer arena.deinit();

    var sample_vendor = Vendor(i8).init(allocatir);

    var one_ins = Instruction(i8).init("one", &registerSample);
    try sample_vendor.implementInstruction("one", &one_ins);

    const root = try createNodeFrom(allocatir, "_start: one R15353135");

    try std.testing.expectError(error.RegisterNumberTooLarge, sample_vendor.generateBinary(root));

    try sample_vendor.peephole_optimizer.remember("_start");
    try sample_vendor.peepholeOptimizeBinary();
}
