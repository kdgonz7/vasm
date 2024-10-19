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

    var commented_out: bool = false;

    for (0..source_text.len - 1) |i| {
        if (source_text[i] == '\n') {
            line += 1;
            char = 1;
        }

        char += 1;

        switch (source_text[i]) {
            ';' => {
                commented_out = true;
            },

            '\n' => {
                commented_out = false;
            },

            ',' => {
                if (commented_out) {
                    continue;
                }
                if (source_text.len <= i + 1 or source_text[i + 1] == '\n' or (source_text[i + 1] == '\r' and source_text[i + 2] == '\n')) {
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
                } else if (source_text[i + 1] != ' ') {
                    try returning_list.append(
                        Suggestion{
                            .suggestion_location = SuggestionLocation{
                                .line_number = line,
                                .problematic_area_begin = char,
                                .problematic_area_end = char + 1,
                            },

                            .suggestion_message = "add a space after the comma",
                            .suggestion_type = .non_compliant,
                        },
                    );
                }
            },
            'j' => {
                if (commented_out) {
                    continue;
                }

                // checking if `jmp` label argument has more than one letter
                // reason being that if jmp is called, folding is off, which means
                // that the subroutine label names are just a single letter. Multiple letters
                // are allowed, but will not yield the expected result.
                // if (source_text.len < i + 2) {
                //     continue;
                // }

                if (source_text[i + 1] == 'm' and source_text[i + 2] == 'p') {
                    // jmp
                    //    ^
                    // we are here
                    var proc_chars: usize = 0;
                    var m: usize = i + 4;

                    while (m < source_text.len and source_text[m] != '\n' and source_text[m] != '\r' and source_text[m] != ' ' and source_text[m] != 'j' and std.ascii.isAlphanumeric(source_text[m])) : (m += 1) {
                        proc_chars += 1;
                    }

                    char += 5;

                    if (proc_chars > 1) {
                        try returning_list.append(
                            Suggestion{
                                .suggestion_location = SuggestionLocation{
                                    .line_number = line,
                                    .problematic_area_begin = char,
                                    .problematic_area_end = char + proc_chars - 1,
                                },

                                .suggestion_message = "procedure with multiple letters",
                                .suggestion_type = .good_practice,
                            },
                        );
                    }

                    char -= 4; // put us back at the `jmp`
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

    try std.testing.expectEqual(1, suggestions_for.items.len);
    try std.testing.expectEqual(SuggestionType.good_practice, suggestions_for.items[0].suggestion_type); // missing newline

    const more_suggestions = try analyze(std.testing.allocator, "a: mov R1");
    defer more_suggestions.deinit();

    try std.testing.expectEqual(1, more_suggestions.items.len);
    try std.testing.expectEqual(SuggestionType.good_practice, more_suggestions.items[0].suggestion_type); // missing newline
}

test "analyze lines" {
    const suggestions_for = try analyze(std.testing.allocator, "a: mov R1, 5\n");
    defer suggestions_for.deinit();

    try std.testing.expectEqual(0, suggestions_for.items.len);

    const more_suggestions = try analyze(std.testing.allocator, "a: mov R1");
    defer more_suggestions.deinit();
}

test "trailing" {
    const suggestions_for = try analyze(std.testing.allocator, @embedFile("stylist-tests/trailing.asm"));
    defer suggestions_for.deinit();

    try std.testing.expectEqual(1, suggestions_for.items.len);
    try std.testing.expectEqual(SuggestionType.good_practice, suggestions_for.items[0].suggestion_type);
    try std.testing.expectEqual(5, suggestions_for.items[0].suggestion_location.line_number);
}

test {
    const suggestions = try analyze(std.testing.allocator, @embedFile("stylist-tests/jmp-non-folding.asm"));
    defer suggestions.deinit();

    try std.testing.expectEqual(2, suggestions.items.len);
    try std.testing.expectEqual(2, suggestions.items[0].suggestion_location.line_number);
    try std.testing.expectEqual(12, suggestions.items[0].suggestion_location.problematic_area_begin);
}
