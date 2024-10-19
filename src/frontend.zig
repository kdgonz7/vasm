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

fn getOptions(allocator: anytype, reporter: *compiler_output.Reporter) compiler.Options {
    const args = std.process.argsAlloc(allocator) catch {
        reporter.errorMessage("failed to allocate a separate argument buffer. out of memory.", .{});
        std.process.exit(1);
    };

    return compiler.extractOptions(allocator, args, reporter);
}

fn vendorStringToVendor(str: anytype) compiler_vendors.Tag {
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
            try drivers.openlud.vendor(&gen);

            gen.generateBinary(ctx.tree) catch |err| {
                switch (err) {
                    error.RegisterNumberTooLarge => {
                        ctx.report.errorMessage("{s}:{d}:{d}: {s}", .{
                            ctx.file_name,
                            gen.erroneous_token.toRegister().span.line_number,
                            gen.erroneous_token.toRegister().span.begin,
                            "register number too large",
                        });

                        ctx.report.getCustomarySourceLocationUsingLexer(
                            ctx.lexer,
                            gen.erroneous_token.toRegister().span.char_begin,
                            gen.erroneous_token.toRegister().span.end,
                            gen.erroneous_token.toRegister().span.line_number - 1,
                        );
                    },
                    else => {
                        return err;
                    },
                }
            };

            var link = linker.Linker(i8).init(ctx.parent_allocator);
            link.linkOptimizedWithContext(drivers.openlud.ctx, &gen, gen.procedure_map) catch {
                ctx.report.errorMessage("failed to link file '{s}'", .{ctx.file_name});
                std.process.exit(1);
            };

            link.writeToFile(ctx.outfile, .little) catch {
                ctx.report.errorMessage("error occured while writing to file `{s}'.", .{ctx.outfile});
                std.process.exit(1);
            };
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

// pub fn main() !void {
//     var prog_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     const prog_allocator = prog_arena.allocator();

//     const options = getOptions(prog_allocator);
//     const stdout = std.io.getStdOut();
//     const stderr = std.io.getStdErr();

//     const stdout_config = std.io.tty.detectConfig(stdout);
//     const stderr_config = std.io.tty.detectConfig(stderr);

//     // TODO: we need to also reserve room for the macro expander and runner
//     // TODO: as that's a very important part of the system. However, just not implemented YET (planned for v0.1.0)
//     var lex = lexer.Lexer.init(prog_allocator);
//     var pars = parser.Parser.init(prog_allocator, &lex.stream);

//     if (options.files.items.len == 0) {
//         compiler_output.errorMessageWithExit(stderr_config, "no input files. (see -h or --help for more information)", .{});
//     }

//     for (options.files.items) |filename| {
//         const file = std.fs.cwd().readFileAlloc(prog_allocator, filename, std.math.maxInt(usize)) catch |err| {
//             switch (err) {
//                 error.FileNotFound => {
//                     compiler_output.errorMessageWithExit(stderr_config, "could not locate file '{s}'", .{filename});
//                 },
//                 else => {
//                     compiler_output.errorMessageWithExit(stderr_config, "something went wrong when reading file '{s}'. ({any})", .{ filename, err });
//                 },
//             }
//         };

//         lex.setInputText(file);

//         // STYLIST

//         if (options.stylist) {
//             const report = stylist.analyze(prog_allocator, file) catch {
//                 compiler_output.errorMessageWithExit(stderr_config, "could not run stylist(if this continues failing, try running vasm with --no-stylist)", .{});
//             };

//             for (report.items) |ding| {
//                 compiler_output.importantMessage(stdout_config, "{s}:{d}:{d}: ({any}) {s}", .{
//                     filename,
//                     ding.suggestion_location.line_number,
//                     ding.suggestion_location.problematic_area_begin,
//                     ding.suggestion_type,
//                     ding.suggestion_message,
//                 });

//                 if (ding.suggestion_location.line_number > 0) {
//                     compiler_output.getCustomarySourceLocationUsingLexer(
//                         &lex,
//                         ding.suggestion_location.problematic_area_begin,
//                         ding.suggestion_location.problematic_area_end,
//                         ding.suggestion_location.line_number - 1,
//                     );
//                 }
//             }

//             if (report.items.len > 0 and options.strict_stylist) {
//                 compiler_output.errorMessageWithExit("too many stylist errors, can not continue. (--enforce-stylist)", .{});
//             }
//         }

//         lex.startLexingInputText() catch |err| compiler_output.printError(&lex, filename, err);

//         const ast = pars.createRootNode() catch |err| {
//             switch (err) {
//                 error.EmptySubroutine => {
//                     compiler_output.errorMessage("{s}:{d}: Empty Subroutine", .{
//                         filename,
//                         0,
//                     });

//                     std.process.exit(1);
//                 },
//                 else => {
//                     std.process.exit(1);
//                 },
//             }
//         };

//         const selected_vm = vendorStringToVendor(options.format.?);
//         try generateMethod(selected_vm, .{
//             .parent_allocator = prog_allocator,
//             .tree = ast,
//             .outfile = options.output,
//             .file_name = filename,
//             .lexer = &lex,
//         });
//     }
// }

// TODO: if you're here from the compiler output file i want you (future me) to know that
// this is looking pretty good, don't fuck up anything.
// we just need to reimplement the commented out code modularly, which means
// storing it all in functions and stuff. that makes the most sense. good luck.
pub fn main() !void {
    var report = compiler_output.Reporter.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const opts = getOptions(allocator, &report);

    if (opts.files.items.len == 0) {
        report.errorMessage("no input files", .{});
        std.process.cleanExit();
    }

    for (opts.files.items) |file| {
        var lex = lexer.Lexer.init(allocator);
        var pars = parser.Parser.init(allocator, &lex.stream);

        const file_body = std.fs.cwd().readFileAlloc(allocator, file, std.math.maxInt(usize)) catch {
            report.errorMessage("could not create buffer for file '{s}`", .{file});
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

        switch (selected_vm) {
            .openlud,
            => {
                lex.rules.max_number_size = std.math.maxInt(i8);
            },

            .nexfuse,
            => {
                lex.rules.max_number_size = std.math.maxInt(u8);
            },

            .siax => {
                lex.rules.max_number_size = std.math.maxInt(i32);
            },

            else => {},
        }

        lex.rules.check_for_big_numbers = !opts.allow_big_numbers;
        lex.startLexingInputText() catch |err| report.printError(&lex, file, err);

        const ast = pars.createRootNode() catch |err| {
            report.astError(err, lex);
        };

        try generateMethod(selected_vm, .{
            .parent_allocator = allocator,
            .tree = ast,
            .outfile = opts.output,
            .file_name = file,
            .lexer = &lex,
            .report = &report,
        });
    }
}
