//! ## Instruction Result
//!
//! An instruction result (IR) is meant to define a way for instructions to return more
//! information than a simple error union. This allows for a lot of information to be passed
//! that otherwise would not have been possible.

const parser = @import("parser.zig");

const ValueType = parser.ValueTag;

pub const TypeMismatch = struct {
    expected: ValueType,
    got: ValueType,

    pub fn init(expected: ValueType, got: ValueType) TypeMismatch {
        return TypeMismatch{
            .expected = expected,
            .got = got,
        };
    }
};

pub const InstructionResult = union(enum) {
    ok: void,
    expected_parameter: []const u8,
    type_mismatch: TypeMismatch,
    other: []const u8,

    pub fn expectedParameter(parameter_name: []const u8) InstructionResult {
        return InstructionResult{
            .expected_parameter = parameter_name,
        };
    }

    pub fn otherError(message: []const u8) InstructionResult {
        return InstructionResult{
            .other = message,
        };
    }

    pub fn typeMismatch(expected: ValueType, got: ValueType) InstructionResult {
        return InstructionResult{
            .type_mismatch = TypeMismatch.init(expected, got),
        };
    }
};
