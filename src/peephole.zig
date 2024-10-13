//! ## Peephole Optimizer
//!
const std = @import("std");

const codegen = @import("codegen.zig");

pub fn PeepholeOptimizer(comptime size: type) type {
    return struct {
        const Self = @This();

        used_instructions: std.StringHashMap(bool),

        pub fn init(parent_allocator: std.mem.Allocator) Self {
            return Self{ .used_instructions = std.StringHashMap(bool).init(parent_allocator) };
        }

        pub fn remember(self: *Self, name: []const u8) !void {
            if (self.used_instructions.get(name) != null) return;
            try self.used_instructions.put(name, true);
        }

        pub fn optimizeUsingKnownInstructions(self: *Self, proc_map: *std.StringHashMap(std.ArrayList(size))) !void {
            var it = proc_map.iterator();

            while (it.next()) |pair| {
                // if there's no used instruction with that name then remove it
                // it's dead code
                if (self.used_instructions.get(pair.key_ptr.*) == null) {
                    _ = proc_map.remove(pair.key_ptr.*);
                }
            }
        }

        pub fn deinit(self: *Self) void {
            self.used_instructions.deinit();
        }
    };
}
