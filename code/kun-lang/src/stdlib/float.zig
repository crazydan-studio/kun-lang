const std = @import("std");
const value_mod = @import("../runtime/value.zig");
const Value = value_mod.Value;
const RuntimeEnv = @import("../runtime/primitive.zig").RuntimeEnv;

pub fn piImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .float = std.math.pi }; }
pub fn eImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .float = std.math.e }; }
pub fn absImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = @abs(args[0].float) }; }
pub fn floorImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = @floor(args[0].float) }; }
pub fn ceilImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = @ceil(args[0].float) }; }
pub fn roundImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = @round(args[0].float) }; }
pub fn sinImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = std.math.sin(args[0].float) }; }
pub fn cosImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = std.math.cos(args[0].float) }; }
pub fn tanImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = std.math.tan(args[0].float) }; }
pub fn expImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = std.math.exp(args[0].float) }; }
pub fn logImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = std.math.log(args[0].float) }; }
pub fn log2Impl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = std.math.log2(args[0].float) }; }
pub fn log10Impl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = std.math.log10(args[0].float) }; }
pub fn powImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 2) return Value{ .float = 1 }; return Value{ .float = std.math.pow(f64, args[0].float, args[1].float) }; }
pub fn sqrtImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .float = 0 }; return Value{ .float = std.math.sqrt(args[0].float) }; }
pub fn approxEqualImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 3) return Value{ .bool = false }; return Value{ .bool = @abs(args[0].float - args[1].float) < args[2].float }; }
pub fn minImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 2) return Value{ .float = 0 }; return Value{ .float = @min(args[0].float, args[1].float) }; }
pub fn maxImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 2) return Value{ .float = 0 }; return Value{ .float = @max(args[0].float, args[1].float) }; }
pub fn clampImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 3) return Value{ .float = 0 }; return Value{ .float = @min(@max(args[0].float, args[1].float), args[2].float) }; }
pub fn fromStringImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .nil = {} }; }
pub fn toIntImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; if (args.len < 1) return Value{ .int = 0 }; return Value{ .int = @intFromFloat(args[0].float) }; }
pub fn toStringImpl(env: *RuntimeEnv, args: []const Value) Value { _ = env; _ = args; return Value{ .string = .{ .ptr = "", .len = 0 } }; }
