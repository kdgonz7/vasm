//! ## Compiler Preprocessor
//!
//! This is a preprocessor for the VASM compiler.
//!

const std = @import("std");
const preprocessor = @import("preprocessor.zig");

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const compiler_rt = @import("compiler-rt/directives.zig");
const compiler_main = @import("compiler_main.zig");

pub fn preprocessWithDefaultRuntime(allocator: std.mem.Allocator, options: *compiler_main.Options, ast_root: *parser.Node) !preprocessor.PreprocessorResult {
    var pp = preprocessor.Preprocessor.init(allocator, options);
    defer pp.deinit();

    try pp.addDirective("compat", &compiler_rt.compatDirective);
    try pp.addDirective("endian", &compiler_rt.endianDirective);
    try pp.addDirective("compile-if", &compiler_rt.compile_if);

    return try pp.handleAstDirectives(ast_root);
}
