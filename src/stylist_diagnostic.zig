const std = @import("std");
const stylist = @import("stylist.zig");
const compiler_output = @import("compiler_output.zig");

pub fn reportStylist(allocator: anytype, reporter: *compiler_output.Reporter, ctx: anytype) void {
    const report = stylist.analyze(allocator, ctx.body) catch {
        reporter.errorMessage("failed to run stylist.", .{});
        std.process.exit(1);
    };

    for (report.items) |ding| {
        reporter.stylistMessage("{s}:{d}:{d}: ({s}) {s}", .{
            ctx.filename,
            ding.suggestion_location.line_number,
            ding.suggestion_location.problematic_area_begin,
            suggestionToStr(ding.suggestion_type),
            ding.suggestion_message,
        });

        if (ding.suggestion_location.line_number > 0) {
            reporter.getCustomarySourceLocationUsingLexer(
                &ctx.lexer,
                ding.suggestion_location.problematic_area_begin,
                ding.suggestion_location.problematic_area_end,
                ding.suggestion_location.line_number - 1,
            );
        }
    }

    if (report.items.len > 0 and ctx.options.strict_stylist) {
        reporter.errorMessage("too many stylist errors, can not continue. (--enforce-stylist)", .{});
        std.process.exit(1);
    }
}

pub fn suggestionToStr(suggestion: stylist.SuggestionType) []const u8 {
    return switch (suggestion) {
        .good_practice => "good practice",
        .undefined_behavior => "UB",
        .non_compliant => "non-compliant",
        .regular => "regular",
    };
}
