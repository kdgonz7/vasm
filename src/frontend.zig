//! ## VASM
//!
//! VASM is a LR Assembly compiler designed to be the maintained standard for compiling into bytecode.
//!

const std = @import("std");
const drivers = @import("drivers.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const codegen = @import("codegen.zig");
const linker = @import("linker.zig");
const compiler = @import("compiler_main.zig");
const compiler_output = @import("compiler_output.zig");
const compiler_vendors = @import("compiler_vendors.zig");
const stylist = @import("stylist.zig");
const diagnostic = @import("stylist_diagnostic.zig");

const stringCompare = std.ascii.eqlIgnoreCase;

/// A binding to `compiler.extractOptions`,
///
/// Takes in an allocator and a reporter and passes those options into extractOptions, with the command
/// line arguments allocated by `std.process.argsAlloc`.
fn getOptions(allocator: anytype, reporter: *compiler_output.Reporter) compiler.Options {
    const args = std.process.argsAlloc(allocator) catch {
        reporter.errorMessage("failed to allocate a separate argument buffer. out of memory.", .{});
        std.process.exit(1);
    };

    return compiler.extractOptions(allocator, args, reporter);
}

/// Converts `str` into a `compiler_vendors.Tag`
fn vendorStringToVendor(str: []const u8) compiler_vendors.Tag {
    if (stringCompare(str, "openlud")) {
        return .openlud;
    }

    if (stringCompare(str, "nexfuse")) {
        return .nexfuse;
    }

    if (stringCompare(str, "mercury")) {
        return .mercury;
    }

    if (stringCompare(str, "solarisvm")) {
        return .solarisvm;
    }

    if (stringCompare(str, "jade")) {
        return .jade;
    }

    if (stringCompare(str, "siax")) {
        return .siax;
    }

    return .unknown;
}

fn generateMethod(format: anytype, ctx: anytype) !void {
    switch (format) {
        .openlud => {
            var gen = codegen.Vendor(i8).init(ctx.parent_allocator);
            var link = linker.Linker(i8).init(ctx.parent_allocator);

            try drivers.openlud.vendor(&gen);

            // generate the procedure map
            gen.generateBinary(ctx.tree) catch |err| ctx.report.genError(err, gen, ctx);

            // generate the optimized binary
            link.linkOptimizedWithContext(drivers.openlud.ctx, &gen, gen.procedure_map) catch |err| ctx.report.linkerError(err, link, ctx);
            link.writeToFile(ctx.outfile, ctx.endian) catch |err| ctx.report.linkerWriteError(err, link, ctx);
        },

        .nexfuse => {
            var gen = codegen.Vendor(u8).init(ctx.parent_allocator);
            var link = linker.Linker(u8).init(ctx.parent_allocator);

            try drivers.nexfuse.runtime(&gen);

            gen.generateBinary(ctx.tree) catch |err| ctx.report.genError(err, gen, ctx);

            // TODO: nexfuse binaries should be optimized, however
            // TODO: some instructions are lost when optimizations occur.

            if (ctx.optimization_level > 0) {
                link.linkOptimizedWithContext(drivers.nexfuse.ctx_no_folding, &gen, gen.procedure_map) catch |err| ctx.report.linkerError(err, link, ctx);
            } else {
                link.linkUnOptimizedWithContext(drivers.nexfuse.ctx_no_folding, gen.procedure_map) catch |err| ctx.report.linkerError(err, link, ctx);
            }
            link.writeToFile(ctx.outfile, ctx.endian) catch |err| ctx.report.linkerWriteError(err, link, ctx);
        },

        else => {
            if (format == .unknown) {
                ctx.report.errorMessage("you must select a format with `--format' before compiling.  (see --format in the OPTIONS section)", .{});
                std.process.exit(1);
            }

            ctx.report.errorMessage("format '{any}' is not currently supported.", .{format});
        },
    }
}

fn checkNumberSizeFor(vm: compiler_vendors.Tag) usize {
    switch (vm) {
        .openlud,
        => {
            return std.math.maxInt(i8);
        },

        .nexfuse,
        => {
            return std.math.maxInt(u8);
        },

        .siax => {
            return std.math.maxInt(i32);
        },

        .mercury => {
            // TODO: mercury has experimental 32-bit support,
            // however, the main support is 8-bit.
            return std.math.maxInt(u8);
        },

        .jade => {
            // TODO: jade has options for 32-bit and 8-bit mode.
            // this number is the greater half of the two.
            return std.math.maxInt(u32);
        },

        .solarisvm => {
            // solarisvm is 32-bit.
            return std.math.maxInt(u32);
        },

        else => @panic("unrecognized vm format"),
    }
}

test checkNumberSizeFor {
    try std.testing.expectEqual(checkNumberSizeFor(.openlud), std.math.maxInt(i8));
    try std.testing.expectEqual(checkNumberSizeFor(.nexfuse), std.math.maxInt(u8));
    try std.testing.expectEqual(checkNumberSizeFor(.jade), std.math.maxInt(u32));
    try std.testing.expectEqual(checkNumberSizeFor(.siax), std.math.maxInt(i32));
    try std.testing.expectEqual(checkNumberSizeFor(.solarisvm), std.math.maxInt(u32));
    try std.testing.expectEqual(checkNumberSizeFor(.mercury), std.math.maxInt(u8));
}

test vendorStringToVendor {
    try std.testing.expect(vendorStringToVendor("openlud") == .openlud);
    try std.testing.expect(vendorStringToVendor("nexfuse") == .nexfuse);
    try std.testing.expect(vendorStringToVendor("mercury") == .mercury);
    try std.testing.expect(vendorStringToVendor("solarisvm") == .solarisvm);
    try std.testing.expect(vendorStringToVendor("jade") == .jade);
    try std.testing.expect(vendorStringToVendor("siax") == .siax);
    try std.testing.expect(vendorStringToVendor("unknown") == .unknown);
}

/// Runs the standard VASM compiler.
pub fn runCompilerFrontend() !void {
    var report = compiler_output.Reporter.init();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // the command-line options.
    const opts = getOptions(allocator, &report);

    // if there's no files, then exit
    if (opts.files.items.len == 0) {
        report.errorMessage("no input files", .{});
        std.process.exit(1);
    }

    // for each file, compile it
    const file = opts.files.items[0];

    var lex = lexer.Lexer.init(allocator);
    var pars = parser.Parser.init(allocator, &lex.stream);

    const file_body = std.fs.cwd().readFileAlloc(allocator, file, std.math.maxInt(usize)) catch |err| {
        report.errorMessage("could not create buffer for file '{s}` ({any})", .{ file, err });
        std.process.exit(1);
    };

    lex.setInputText(file_body);

    if (opts.stylist) {
        diagnostic.reportStylist(allocator, &report, .{
            .filename = file,
            .body = file_body,
            .lexer = &lex,
            .options = opts,
        });
    }

    const selected_vm = vendorStringToVendor(opts.format.?);

    if (selected_vm == .unknown) {
        report.errorMessage("unknown format '{s}'", .{opts.format.?});
        report.leaveNote("format enumerated to '{s}'", .{@tagName(selected_vm)});
        std.process.exit(1);
    }

    lex.rules.max_number_size = checkNumberSizeFor(selected_vm);
    lex.rules.check_for_big_numbers = !opts.allow_big_numbers;

    lex.startLexingInputText() catch |err| report.printError(&lex, file, err);

    const ast = pars.createRootNode() catch |err| report.astError(err, lex);

    try generateMethod(selected_vm, .{
        .parent_allocator = allocator,
        .tree = ast,
        .outfile = opts.output,
        .file_name = file,
        .lexer = &lex,
        .report = &report,
        .endian = opts.endian,
        .optimization_level = opts.optimization_level,
    });
}

pub fn main() !void {
    try runCompilerFrontend();
}
