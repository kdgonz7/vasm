//! ## NexFUSE
//!
//! NexFUSE is a bytecode format designed to be efficient and a drop-in low memory replacement
//! for [OpenLUD](./openlud.zig) binaries. NexFUSE works by keeping an instruction pointer to
//! an instruction address and incrementing it, parsing each opcode and running its respective
//! functionality. NexFUSE would then be replaced by the brand-new "MercuryPIC" format, that supported
//! 8-bit to 32-bit architectures and cleaned up a lot of the procedural mess NexFUSE left behind.
//!
//! The NexFUSE novelty is to be usable, and to get to that point with as little steps and commands
//! as possible. That is why NexFUSE is manually managed, meaning that each free and create call is explicity stated
//! in the code instead of hidden behind different allocations and hidden frees.
//!
//! ### Architecture
//!
//! The NexFUSE instruction set contains around 20 instructions, each one performing either
//! a read or write on data, analysis, or clocking. NexFUSE, unlike OpenLUD, is more expansive,
//! and, albeit not Turing-complete, strives to provide as many abstractions and gates for logic
//! as possible with the knowledge at the time it was created.
//!
//! NexFUSE roughly has 65-70% of ABI compatibility with OpenLUD, meaning that a large portion of programs
//! can be ran with NexFUSE and OpenLUD, however, more comprehensive and non-standard programs need to be ran
//! with their respective interfaces.
//!
//! ### VASM Interface
//!
//! VASM compiles LR Assembly directly into NexFUSE with two context options:
//!
//! * Folded
//! * Non-Folded
//!
//! With folded programs, performance can be higher, however, a lot of the logical expansions of NexFUSE are limited due
//! to the compiler having no awareness of the program's state or processes. Non-Folded programs create procedure headers
//! for each instruction set with dead code elimination optimizations still in place. Those must forcefully be disabled
//! via flags and options that can be found in `frontend.zig` and `compiler_main.zig`.
//!

const std = @import("std");
const parser = @import("../parser.zig");
const codegen = @import("../codegen.zig");
const instruction_result = @import("../instruction_result.zig");
const linker = @import("../linker.zig");
const lexer = @import("../lexer.zig");
const testing = @import("../testing/expect.zig");

const Value = parser.Value;
const Result = instruction_result.InstructionResult;
const Return = codegen.InstructionError!Result;

const expectBin = testing.expectBin;

/// The NexFUSE bytecode context. This does not include procedural folding. NexFUSE programs
/// can not be compiled into object files.
pub const ctx_no_folding = .{
    .start_definition = "_start",
    .fold_procedures = false,
    .procedure_heading_byte = 10,
    .procedure_closing_byte = 128,
    .compile = false,
    .vasm_header = false,
    .use_end_byte = true,
    .end_byte = 22,
};

//// For tests.
pub const ctx_no_folding_compile = .{
    .start_definition = "_start",
    .fold_procedures = false,
    .procedure_heading_byte = 10,
    .procedure_closing_byte = 128,
    .compile = true,
    .vasm_header = false,
    .use_end_byte = true,
    .end_byte = 22,
};

pub const ctx_folding = .{
    .start_definition = "_start",
    .fold_procedures = true,
    .compile = false,
    .vasm_header = false,
    .use_end_byte = true,
    .end_byte = 22,
};

pub fn runtime(vend: *codegen.Vendor(u8)) !void {
    vend.nul_after_sequence = true;
    vend.nul_byte = 0;

    try vend.createAndImplementInstruction(u8, "echo", &echoIns);
    try vend.createAndImplementInstruction(u8, "mov", &moveIns);
    try vend.createAndImplementInstruction(u8, "each", &eachIns);
    try vend.createAndImplementInstruction(u8, "reset", &resetIns);
    try vend.createAndImplementInstruction(u8, "clear", &clearIns);
    try vend.createAndImplementInstruction(u8, "zeroall", &clearIns);
    try vend.createAndImplementInstruction(u8, "put", &putIns);
    try vend.createAndImplementInstruction(u8, "get", &getIns);
    try vend.createAndImplementInstruction(u8, "add", &addIns);
    try vend.createAndImplementInstruction(u8, "nop", &nopIns);
    try vend.createAndImplementInstruction(u8, "lar", &larIns);
    try vend.createAndImplementInstruction(u8, "lsl", &lslIns);
    try vend.createAndImplementInstruction(u8, "in", &inIns);
    try vend.createAndImplementInstruction(u8, "cmp", &cmpIns);
    try vend.createAndImplementInstruction(u8, "inc", &incIns);
    try vend.createAndImplementInstruction(u8, "rep", &repIns);
    try vend.createAndImplementInstruction(u8, "jmp", &gosubIns);
}

//TODO: add type checks for all of these instructions

/// Prints a byte to STDOUT.
///
/// `echo c: char -> void`
///
/// Internally this function uses C's printf() function to print the argument as a character.
/// in VASM this function ensures the type is representable by the charset
pub fn echoIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;

    if (args.len == 0) {
        return Result.expectedParameter("BYTE");
    }

    const byte: Value = args[0];

    if (byte.getType() != .literal) {
        return Result.typeMismatch(.literal, byte.getType());
    }

    try gen.append(40);
    try gen.append(@intCast(byte.toLiteral().toCharacter()));

    return .ok;
}

/// `r1 b | r1[TOP] := b`
pub fn moveIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;

    if (args.len < 2) {
        return Result.expectedParameter("either reg_num or reg_byte is missing");
    }

    const reg_num = args[0];
    const reg_byte = args[1];

    try gen.append(41);
    try gen.append(@intCast(reg_num.toRegister().getRegisterNumber()));
    try gen.append(@intCast(reg_byte.toNumber().getNumber()));

    return .ok;
}

/// Iterate and print each element in a register as a character. Uses C standard `printf` function.
pub fn eachIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;

    const reg_num = args[0];

    try gen.append(42);
    try gen.append(@intCast(reg_num.toRegister().getRegisterNumber()));

    return .ok;
}

pub fn resetIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;

    try gen.append(43);
    try gen.append(@intCast(args[0].toRegister().getRegisterNumber()));

    return .ok;
}

/// `REGISTERS := 0`
///
/// Zeroes every current register.
/// This function is also called `zeroall` in the VASM compiler. The standard
/// name for this function is `clear`.
pub fn clearIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;
    _ = args;

    try gen.append(44);

    return .ok;
}

/// `r1 b p | r1[p] := b`
pub fn putIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;
    const reg = args[0].toRegister();
    const byte = args[1].toNumber();
    const pos = args[2].toNumber();

    try gen.append(45);
    try gen.append(@intCast(reg.getRegisterNumber()));
    try gen.append(@intCast(byte.getNumber()));
    try gen.append(@intCast(pos.getNumber()));

    return .ok;
}

/// `r1 pos r2` | r2 := r1[pos]`
///
/// R2 owns a unique copy of `R1[POS]`
pub fn getIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;

    const src = args[0].toRegister();
    const pos = args[1].toNumber();
    const dest = args[2].toRegister();

    try gen.append(46);
    try gen.append(@intCast(src.getRegisterNumber()));
    try gen.append(@intCast(pos.getNumber()));
    try gen.append(@intCast(dest.getRegisterNumber()));

    return .ok;
}

/// `r1 r2 | r2[size++] := [SUM (r1[0..])]`
///
/// adds all of the values in r1 and puts it into r2. r2 is the address
/// of a big register, not a normal sized one. (See "Big Registers")
pub fn addIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;

    const register1 = args[0].toRegister();
    const register2 = args[1].toRegister();

    try gen.append(47);
    try gen.append(@intCast(register1.getRegisterNumber()));
    try gen.append(@intCast(register2.getRegisterNumber()));

    return .ok;
}

pub fn nopIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;
    _ = gen;
    _ = args;

    return .ok;
}

pub fn larIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;

    const register = args[0].toRegister();

    try gen.append(48);
    try gen.append(@intCast(register.getRegisterNumber()));

    return .ok;
}

pub fn lslIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;

    const register = args[0].toRegister();

    try gen.append(49);
    try gen.append(@intCast(register.getRegisterNumber()));

    // iterate past register arg
    for (1..args.len) |i| {
        switch (args[i]) {
            // add number and gen
            .number => |number| {
                try gen.append(@intCast(number.getNumber()));
            },

            .literal => |literal| {
                try gen.append(@intCast(literal.toCharacter()));
            },

            else => {
                return Result.otherError("object is not int-like");
            },
        }
    }

    return .ok;
}

pub fn inIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;
    const reg_num = args[0].toRegister();

    try gen.append(50);
    try gen.append(@intCast(reg_num.getRegisterNumber()));

    return .ok;
}

pub fn cmpIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    // CMP compares two registers and then jumps to a label
    // [reg1] [reg2] [label] | r1[..]==r[2] JUMP label

    _ = vend;

    const register1 = args[0].toRegister();
    const register2 = args[1].toRegister();
    const label = args[2].toIdentifier();

    try gen.append(51);
    try gen.append(@intCast(register1.getRegisterNumber()));
    try gen.append(@intCast(register2.getRegisterNumber()));
    try gen.append(@bitCast(label.identifier_string[0])); // use the first letter of label (assuming folding is off)

    return .ok;
}
pub fn incIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;

    const reg_num = args[0].toRegister();

    try gen.append(52);
    try gen.append(@intCast(reg_num.getRegisterNumber()));

    return .ok;
}
pub fn repIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;

    // repeats the procedure a certain number of times
    const proc_name = args[0].toIdentifier();
    const times = args[1].toNumber();

    try gen.append(53);
    try gen.append(@bitCast(proc_name.identifier_string[0]));
    try gen.append(@intCast(times.getNumber()));

    return .ok;
}

pub fn gosubIns(
    gen: *codegen.Generator(u8),
    vend: *codegen.Vendor(u8),
    args: []parser.Value,
) Return {
    _ = vend;

    const label = args[0].toIdentifier();

    // jmp to label
    try gen.append(15);
    try gen.append(@bitCast(label.identifier_string[0]));

    return .ok;
}

// wellness checks
// should compile in this exact form as
// they are read by the NexFUSE interpreter
test {
    try expectBin(
        u8,
        "_start: echo 'A'",
        &[_]u8{
            40, 65, 0, 22,
        },
        ctx_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start: nop",
        &[_]u8{
            0, 22,
        },
        ctx_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\necho 'A'\necho 'B'",
        &[_]u8{
            40, 65, 0,
            40, 66, 0,
            22,
        },
        ctx_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\necho '\\n'\necho 'B'",
        &[_]u8{
            40, 0x0a, 0,
            40, 66,   0,
            22,
        },
        ctx_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\nmov R1,81 ; add 81 to register 1",
        &[_]u8{
            41, 1, 81, 0,
            22,
        },
        ctx_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\neach R1",
        &[_]u8{
            42, 1, 0,
            22,
        },
        ctx_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\n   mov R1,0x0a\n   each R1",
        &[_]u8{
            41, 1, 0x0a, 0, // MOV R1 \n
            42, 1, 0, 22, // EACH R1 END
        },
        ctx_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\n   clear",
        &[_]u8{
            44, 0, 22,
        },
        ctx_folding,
        runtime,
    );
}

test {
    //alt syntax
    try expectBin(
        u8,
        "_start:\n   zeroall",
        &[_]u8{
            44, 0, 22,
        },
        ctx_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\n   reset R1,",
        &[_]u8{
            43, 1, 0,
            22,
        },
        ctx_folding,
        runtime,
    );
}

test {
    //alt syntax
    try expectBin(
        u8,
        "_start:\n   zeroall\nput R1,5,3",
        &[_]u8{
            44, 0,
            45, 1,
            5,  3,
            0,  22,
        },
        ctx_folding,
        runtime,
    );
}

test {
    //alt syntax
    try expectBin(
        u8,
        "_start:\n   zeroall\nadd R1,R2,\n",
        &[_]u8{
            44, 0,
            47, 1,
            2,  0,
            22,
        },
        ctx_folding,
        runtime,
    );
}

test {
    //alt syntax
    try expectBin(
        u8,
        "_start:\n   zeroall\n   put R1,65,3\n   get R1,5,R2\n   each R2",
        &[_]u8{
            44, 0, // zeroall
            45, 1, // put R1
            65, 3, // 65 3
            0, 46, // get
            1, 5, // R1 at 5
            2, 0, // put into register 2
            42, 2, // each 2
            0, 22, // end
        },
        ctx_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "a: echo 'A'",
        &[_]u8{
            10, 97, // SUB a
            40, 65, // ECHO A
            0, 0x80, // NUL ENDSUB
            22, // END
        },
        ctx_no_folding_compile,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\n   zeroall\n   put R1,65,3\n   lar R1,",
        &[_]u8{ 44, 0, 45, 1, 65, 3, 0, 48, 1, 0, 22 },
        ctx_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\n   lsl R1,'A','B','C',\n",
        &[_]u8{ 49, 1, 65, 66, 67, 0, 22 },
        ctx_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "a: echo 'A'\n_start:\n   cmp R1,R2,a\n",
        &[_]u8{ 10, 97, 40, 65, 0, 128, 51, 1, 2, 97, 0, 22 },
        ctx_no_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\n   in R1\n",
        &[_]u8{ 50, 1, 0, 22 },
        ctx_no_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\n   inc R1\n",
        &[_]u8{ 52, 1, 0, 22 },
        ctx_no_folding,
        runtime,
    );
}

test {
    try expectBin(
        u8,
        "_start:\n   jmp a\n",
        &[_]u8{ 15, 97, 0, 22 },
        ctx_no_folding,
        runtime,
    );
}

test {
    std.testing.refAllDecls(@This());
}
