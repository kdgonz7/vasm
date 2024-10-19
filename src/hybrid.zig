//! Hybrid Vendor
//!
//! Generates a hybrid vendor from multiple other vendors that
//! provides a standard set of instructions. The "Standard Graph"
//!
//! E.g.
//!
//!     OpenLUD
//!         Has MOV
//!     NexFuse
//!         Has MOV
//!     Mercury
//!         Does NOT have MOV
//!
//! The standard graph would generate an 8-bit vendor that supports a MOV instruction.
//!
//! A con to using this method to generate standard-conforming code is that the instruction function used
//! in the intersecting instruction set will be unknown. If two instructions have the same name, the first one's
//! function will be used in the hybrid vendor.
//!
//! ```
//! vend1
//!     instruction b: a()
//!
//! vend2
//!     instruction b: b()
//!
//! hybrid
//!     instruction b: a() | And NOT b()
//! ```
//!
//! So this functionality is primarily for telling which implementations have the SAME functions, but
//! this does not mean that they have the same parameters or functionality.
//!

const std = @import("std");
const codegen = @import("codegen.zig");
const parser = @import("parser.zig");
const ir = @import("instruction_result.zig");

const Allocator = std.mem.Allocator;
const Vendor = codegen.Vendor;

pub fn generateHybridVendor(comptime T: type, vendor_list: std.ArrayList(Vendor(T)), allocator: Allocator) !Vendor(T) {
    var return_vendor = Vendor(T).init(allocator);

    for (vendor_list.items) |vendor| {
        var instruction_keyiter = vendor.instruction_set.keyIterator();

        while (instruction_keyiter.next()) |key| {
            var instruction_is_standard: bool = true;

            for (vendor_list.items) |other_vendor| {
                if (!other_vendor.instruction_set.contains(key.*)) {
                    instruction_is_standard = false;
                }
            }

            if (instruction_is_standard and return_vendor.instruction_set.get(key.*) == null) {
                try return_vendor.implementInstruction(
                    key.*,
                    vendor.instruction_set.getPtr(key.*).?,
                );
            }
        }
    }

    return return_vendor;
}

pub fn a(_: *codegen.Generator(i8), _: *codegen.Vendor(i8), _: []parser.Value) codegen.InstructionError!ir.InstructionResult {
    return .ok;
}

test {
    var vend1 = Vendor(i8).init(std.testing.allocator);
    var vend2 = Vendor(i8).init(std.testing.allocator);

    defer vend1.deinit();
    defer vend2.deinit();

    var vendors = std.ArrayList(Vendor(i8)).init(std.testing.allocator);
    defer vendors.deinit();

    try vend1.createAndImplementInstruction(i8, "hello", &a);
    try vend2.createAndImplementInstruction(i8, "hello", &a);
    try vend2.createAndImplementInstruction(i8, "world", &a);

    try vendors.append(vend1);
    try vendors.append(vend2);

    var hy = try generateHybridVendor(i8, vendors, std.testing.allocator);
    defer hy.deinit();

    try std.testing.expectEqual(1, hy.instruction_set.count());
}

test {
    var vend1 = Vendor(i8).init(std.testing.allocator);
    var vend2 = Vendor(i8).init(std.testing.allocator);

    defer vend1.deinit();
    defer vend2.deinit();

    var vendors = std.ArrayList(Vendor(i8)).init(std.testing.allocator);
    defer vendors.deinit();

    // vend 1 & vend 2 have hello
    try vend1.createAndImplementInstruction(i8, "hello", &a);
    try vend2.createAndImplementInstruction(i8, "hello", &a);

    // vend 1 & vend 2 have world
    try vend2.createAndImplementInstruction(i8, "world", &a);
    try vend1.createAndImplementInstruction(i8, "world", &a);

    try vendors.append(vend1);
    try vendors.append(vend2);

    var hy = try generateHybridVendor(i8, vendors, std.testing.allocator);
    defer hy.deinit();

    // the intersection has both hello and world instructions
    try std.testing.expectEqual(2, hy.instruction_set.count());
    try std.testing.expectEqual(true, hy.instruction_set.contains("hello"));
    try std.testing.expectEqual(true, hy.instruction_set.contains("world"));
}
