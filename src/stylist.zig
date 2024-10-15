//! ## Stylist
//!
//! Lexing => Parsing => Stylist => Syntax Tree Generation => Linting => Codegen => Templating => Export
//! 1         2          3          4                         5          6          7             8
//!
//! The Stylist is the THIRD step in the VASM compiler pipline.
//!
//! A separate facility from the lexer and parser which gives a simple analysis to
//! give a list of style recommendations following the LR Assembly standard. This is OPTIONAL
//! and a part of the compiler's internal processes.
//!
//! Stylist does NOT give advice on:
//! * compiler functions (halt being deprecated)
//! * inline comments
//! * unused registers
//! * writes never accessed
//!
//! Stylist is purely a quick and dirty solution to
//! provide a more strict writing system for LR Assembly.
//!

const std = @import("std");

/// A suggestion type. Essentially the severity of the subject matter.
pub const SuggestionType = enum {
    /// More of a "suggestion" and won't be pushed as something that NEEDS FIXING (aka. noncompliant)
    regular,

    /// Somewhere in the middle. The passive-aggresive type. NEEDS FIXING but
    /// WONT MIND if you don't.
    good_practice,

    /// A non-compliant suggestion. This is the NEEDS FIXING tag.
    non_compliant,

    /// A line may have undefined behavior or may be parsed incorrectly.
    undefined_behavior,
};

pub const SuggestionLocation = struct {
    line_number: usize,
    problematic_area_begin: usize,
    problematic_area_end: usize,
};

pub const Suggestion = struct {
    suggestion_type: SuggestionType,
    suggestion_message: []const u8,
    suggestion_location: SuggestionLocation,
};

pub const SuggestionList = std.ArrayList(Suggestion);

/// Analyzes input `source_text` and returns a `SuggestionList` with a list of suggestions
/// to make the code more standard compliant.
pub fn analyze(parent_allocator: std.mem.Allocator, source_text: []const u8) !SuggestionList {
    var returning_list = SuggestionList.init(parent_allocator);

    var line: usize = 1;
    var char: usize = 1;
    for (0..source_text.len - 1) |i| {
        if (source_text[i] == '\n') {
            line += 1;
            char = 1;
        }

        char += 1;

        switch (source_text[i]) {
            ',' => {
                if (source_text.len <= i + 1 or source_text[i + 1] == '\n') {
                    try returning_list.append(
                        Suggestion{
                            .suggestion_location = SuggestionLocation{
                                .line_number = line,
                                .problematic_area_begin = char,
                                .problematic_area_end = char + 1,
                            },

                            .suggestion_message = "trailing comma",
                            .suggestion_type = .good_practice,
                        },
                    );
                } else if (source_text[i + 1] == ' ') {
                    try returning_list.append(
                        Suggestion{
                            .suggestion_location = SuggestionLocation{
                                .line_number = line,
                                .problematic_area_begin = char,
                                .problematic_area_end = char + 1,
                            },

                            .suggestion_message = "behavior of this line may be undefined. try replacing the `,` with `;`. ",
                            .suggestion_type = .non_compliant,
                        },
                    );
                }
            },

            else => continue,
        }
    }

    if (source_text.len > 0) {
        if (source_text[source_text.len - 1] != '\n') {
            try returning_list.append(
                Suggestion{
                    .suggestion_location = SuggestionLocation{
                        .line_number = 0,
                        .problematic_area_begin = 0,
                        .problematic_area_end = 0 + 1,
                    },

                    .suggestion_message = "it's good to add a newline near EOF",
                    .suggestion_type = .good_practice,
                },
            );
        }
    }

    return returning_list;
}

test analyze {
    // you can use the analyze function as any other function.
    // stylist simply reports non-compliant token strings.
    // Like for example spaces after parameters
    const suggestions_for = try analyze(std.testing.allocator, "a: mov R1, 5");
    defer suggestions_for.deinit();

    try std.testing.expectEqual(2, suggestions_for.items.len);
    try std.testing.expectEqual(SuggestionType.non_compliant, suggestions_for.items[0].suggestion_type); // space after parameter
    try std.testing.expectEqual(SuggestionType.good_practice, suggestions_for.items[1].suggestion_type); // missing newline

    const more_suggestions = try analyze(std.testing.allocator, "a: mov R1");
    defer more_suggestions.deinit();

    try std.testing.expectEqual(1, more_suggestions.items.len);
    try std.testing.expectEqual(SuggestionType.good_practice, more_suggestions.items[0].suggestion_type); // missing newline
}

test "analyze lines" {
    const suggestions_for = try analyze(std.testing.allocator, "a: mov R1, 5");
    defer suggestions_for.deinit();

    try std.testing.expectEqual(2, suggestions_for.items.len);
    try std.testing.expectEqual(SuggestionType.non_compliant, suggestions_for.items[0].suggestion_type); // space after parameter
    try std.testing.expectEqual(SuggestionType.good_practice, suggestions_for.items[1].suggestion_type); // missing newline
    try std.testing.expectEqual(1, suggestions_for.items[0].suggestion_location.line_number); // missing newline

    const more_suggestions = try analyze(std.testing.allocator, "a: mov R1");
    defer more_suggestions.deinit();
}

test "trailing" {
    const suggestions_for = try analyze(std.testing.allocator, @embedFile("stylist-tests/trailing.asm"));
    defer suggestions_for.deinit();

    try std.testing.expectEqual(1, suggestions_for.items.len);
    try std.testing.expectEqual(SuggestionType.good_practice, suggestions_for.items[0].suggestion_type);
    try std.testing.expectEqual(4, suggestions_for.items[0].suggestion_location.line_number);
}
