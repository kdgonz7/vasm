//! An Aside.
//!
//! Asides are values that are expanded into their respective values at runtime.
//!
//! ```asm
//! :set VAR_1 10
//!
//! ; somewhere else...
//! mov R1, VAR_1
//! ```
//!

const std = @import("std");
const token_stream = @import("../token_stream.zig");
const parser = @import("../parser.zig");

const Ident = token_stream.Identifier;
const Value = parser.Value;
const Span = token_stream.Span;

const Self = @This();

name: Ident,
parameters: std.ArrayList(Value),
span: Span,
