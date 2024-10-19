//! ## OpenLUD
//!
//! OpenLUD is an 8-bit virtual architecture designed for memory safety and stability. OpenLUD holds a maximum of
//! 65536 bytes of information, stored in registers. There was no compiler for OpenLUD originally until the LunarRED
//! legacy compiler came out designed to compile into this and the NexFUSE bytecode formats.
//!
//! The OpenLUD OBI is no longer maintained, however still used as a reference and withholds an old standard
//! with many practices still being used in modern programs.
//!
//! ### Architecture
//!
//! The instruction set is very small (standing around >11 instructions) and
//! limited, as it is a standard, it is meant to be used in more constrainted environments
//! with a less memory consuming program.
//!
//! VASM can compile headless OpenLUD files.
//!
//! ### Specs
//!
//! * 8-bit
//!
const std = @import("std");
const codegen = @import("../codegen.zig");
const parser = @import("../parser.zig");
const instruction_result = @import("../instruction_result.zig");

const InstructionResult = instruction_result.InstructionResult;

const NAME = "openlud";

/// The binary format size of this platform.
const SIZE = i8;

/// appends the given instructions and values into `vend`. Required for each VM platform driver.
pub fn vendor(vend: *codegen.Vendor(i8)) !void {
    vend.nul_after_sequence = true;
    vend.nul_byte = 0;

    try vend.createAndImplementInstruction(i8, "echo", &echoInstruction);
    try vend.createAndImplementInstruction(i8, "mov", &moveInstruction);
    try vend.createAndImplementInstruction(i8, "each", &eachInstruction);
    try vend.createAndImplementInstruction(i8, "init", &initInstruction);
    try vend.createAndImplementInstruction(i8, "put", &putInstruction);
    try vend.createAndImplementInstruction(i8, "clear", &clearInstruction);
    try vend.createAndImplementInstruction(i8, "reset", &resetInstruction);
    try vend.createAndImplementInstruction(i8, "get", &getInstruction);
}

/// OpenLUD-aware link configuration.
///
/// Follows a `_start` entry procedure, enables procedure folding which disables NexFUSE-style procedures,
/// adds the VASM header, and supports the end byte.
///
pub const ctx = .{
    .start_definition = "_start",
    .fold_procedures = true,
    .compile = true,
    .vasm_header = false,
    .use_end_byte = true,
    .end_byte = 12,
    .proc_end_byte = false,
};

/// *"ECHO will print out a byte as a character"*
/// - from <https://github.com/thekaigonzalez/openLUD-OBI/blob/main/obi/obirqlist.d>
pub fn echoInstruction(generator: *codegen.Generator(SIZE), vend: *codegen.Vendor(SIZE), args: []parser.Value) codegen.InstructionError!InstructionResult {
    _ = vend;

    if (args.len == 0) {
        return error.InstructionExpectsDifferentValue;
    }

    const byte = args[0];

    if (byte.getType() != .literal) {
        return InstructionResult{
            .expected_parameter = "byte",
        };
    }

    try generator.append(40);
    try generator.append(@intCast(byte.toLiteral().character[0]));

    return .ok;
}

/// MOVE [register] [byte]
pub fn moveInstruction(generator: *codegen.Generator(SIZE), vend: *codegen.Vendor(SIZE), args: []parser.Value) codegen.InstructionError!InstructionResult {
    _ = vend;

    if (args.len != 2) {
        return error.InstructionExpectsDifferentValue;
    }

    const register_arg = args[0];

    if (register_arg.getType() != .register) return InstructionResult.typeMismatch(.register, register_arg.getType());

    // [register] and [byte]
    const register_location: i8 = @intCast(register_arg.toRegister().getRegisterNumber());
    const byte: i8 = @intCast(args[1].toNumber().getNumber());

    // 41 is MOVE opcode
    try generator.append(41);
    try generator.append(register_location);
    try generator.append(byte);
    return .ok;
}

pub fn eachInstruction(generator: *codegen.Generator(SIZE), vend: *codegen.Vendor(SIZE), args: []parser.Value) codegen.InstructionError!InstructionResult {
    _ = vend;

    if (args.len != 1) {
        return error.InstructionExpectsDifferentValue;
    }

    const register = args[0];
    if (register.getType() != .register) return error.InstructionExpectsDifferentValue;
    try generator.append(42);
    try generator.append(@intCast(register.toRegister().getRegisterNumber()));
    return .ok;
}

pub fn initInstruction(generator: *codegen.Generator(SIZE), vend: *codegen.Vendor(SIZE), args: []parser.Value) codegen.InstructionError!InstructionResult {
    _ = vend;

    if (args.len == 0) {
        return error.InstructionExpectsDifferentValue;
    }

    if (args[0].getType() == .register) {
        try generator.append(100);
        try generator.append(@intCast(args[0].toRegister().getRegisterNumber()));
    }
    return .ok;
}

/// `RESET r | WIPE[r]`
pub fn resetInstruction(generator: *codegen.Generator(SIZE), vend: *codegen.Vendor(SIZE), args: []parser.Value) codegen.InstructionError!InstructionResult {
    _ = vend;

    if (args.len == 0) {
        return error.InstructionExpectsDifferentValue;
    }

    if (args[0].getType() == .register) {
        try generator.append(43);
        try generator.append(@intCast(args[0].toRegister().getRegisterNumber()));
    } else {
        return InstructionResult.typeMismatch(.register, args[0].getType());
    }

    return .ok;
}

/// `CLEAR r | WIPE all`
pub fn clearInstruction(generator: *codegen.Generator(SIZE), vend: *codegen.Vendor(SIZE), args: []parser.Value) codegen.InstructionError!InstructionResult {
    _ = vend;

    if (args.len != 0) {
        return error.InstructionExpectsDifferentValue;
    }

    try generator.append(44);

    return .ok;
}

/// `PUT r n p | r[n] := NUM[p]`
pub fn putInstruction(generator: *codegen.Generator(SIZE), vend: *codegen.Vendor(SIZE), args: []parser.Value) codegen.InstructionError!InstructionResult {
    _ = vend;

    const register_arg: i8 = @intCast(args[0].toRegister().getRegisterNumber());
    const byte_arg: i8 = @intCast(args[1].toNumber().getNumber());
    const position: i8 = @intCast(args[2].toNumber().getNumber());

    try generator.append(45);
    try generator.append(register_arg);
    try generator.append(byte_arg);
    try generator.append(position);

    return .ok;
}

/// `GET src pos dest | dest[dest.size++] := src[pos]`
pub fn getInstruction(generator: *codegen.Generator(SIZE), vend: *codegen.Vendor(SIZE), args: []parser.Value) codegen.InstructionError!InstructionResult {
    _ = vend;

    if (args.len == 0) {
        return InstructionResult.expectedParameter("SOURCE");
    }

    if (args.len == 1) {
        return InstructionResult.expectedParameter("POS");
    }

    if (args.len == 2) {
        return InstructionResult.expectedParameter("DEST");
    }

    if (args[0].getType() != .register) return InstructionResult.typeMismatch(.register, args[0].getType());
    if (args[1].getType() != .number) return InstructionResult.typeMismatch(.number, args[1].getType());
    if (args[2].getType() != .number) return InstructionResult.typeMismatch(.number, args[2].getType());

    const source: i8 = @intCast(args[0].toRegister().getRegisterNumber());
    const position: i8 = @intCast(args[1].toNumber().getNumber());
    const dest: i8 = @intCast(args[2].toNumber().getNumber());

    try generator.append(46);
    try generator.append(source);
    try generator.append(position);
    try generator.append(dest);

    return .ok;
}
