const std = @import("std");
const value_mod = @import("value.zig");
const typed = @import("../ast/typed.zig");

const Value = value_mod.Value;
const StreamNode = value_mod.StreamNode;
const StreamFn = value_mod.StreamFn;
const Closure = value_mod.Closure;
const Frame = value_mod.Frame;
const PrimitiveFn = @import("primitive.zig").PrimitiveFn;

pub const EvalFn = *const fn (expr: *const typed.TypedExpr, frame: *Frame, allocator: std.mem.Allocator) (error{UnboundVariable, NotAFunction, TypeMismatch, DivisionByZero, UnknownField, NoMatch, Unimplemented, OutOfMemory, MissingArgument}!Value);

pub fn consumeNext(node: *StreamNode, allocator: std.mem.Allocator, eval_fn: ?EvalFn) !?Value {
    return switch (node.*) {
        .cmd => |*c| {
            const n = std.os.linux.read(c.fd, c.buf.ptr, c.buf.len);
            if (n == 0) {
                _ = std.os.linux.close(c.fd);
                if (c.pid > 0) { var status: i32 = 0; _ = std.os.linux.waitpid(c.pid, &status, 0); }
                return null;
            }
            return Value{ .bytes = c.buf[0..n] };
        },
        .mapped => |*m| {
            while (try consumeNext(m.upstream, allocator, eval_fn)) |elem| {
                const val = try applyStreamFn(allocator, eval_fn, m.f, elem);
                return val;
            }
            return null;
        },
        .filtered => |*f| {
            while (try consumeNext(f.upstream, allocator, eval_fn)) |elem| {
                const ok = try applyStreamFn(allocator, eval_fn, f.pred, elem);
                if (ok == .bool and ok.bool) return elem;
            }
            return null;
        },
        .taken => |*t| {
            if (t.remaining == 0) return null;
            t.remaining -= 1;
            return consumeNext(t.upstream, allocator, eval_fn);
        },
        .dropped => |*d| {
            while (d.remaining > 0) {
                _ = try consumeNext(d.upstream, allocator, eval_fn) orelse return null;
                d.remaining -= 1;
            }
            return consumeNext(d.upstream, allocator, eval_fn);
        },
        .lines => |*l| {
            while (true) {
                const chunk = try consumeNext(l.upstream, allocator, eval_fn) orelse {
                    if (l.pos > 0) {
                        const result = l.buf[0..l.pos];
                        l.pos = 0;
                        return Value{ .string = result };
                    }
                    return null;
                };
                if (chunk != .bytes) continue;
                const data = chunk.bytes;
                var start: usize = 0;
                for (data, 0..) |b, i| {
                    if (b == '\n') {
                        if (l.pos + i - start <= l.max_len) {
                            @memcpy(l.buf[l.pos..][0..(i - start)], data[start..i]);
                            l.pos += i - start;
                            const result = try allocator.dupe(u8, l.buf[0..l.pos]);
                            l.pos = 0;
                            return Value{ .string = result };
                        }
                        start = i + 1;
                    }
                }
                const remaining = data.len - start;
                if (l.pos + remaining <= l.buf.len) {
                    @memcpy(l.buf[l.pos..][0..remaining], data[start..]);
                    l.pos += remaining;
                }
            }
        },
        .parse_mapped => |*p| {
            while (try consumeNext(p.upstream, allocator, eval_fn)) |elem| {
                const result = try applyStreamFn(allocator, eval_fn, p.f, elem);
                if (result == .adt and result.adt.tag == 0) return result.adt.payload.*;
                if (result == .adt and result.adt.tag != 0) continue;
                return result;
            }
            return null;
        },
        .parse_mapped_keep => |*p| {
            while (try consumeNext(p.upstream, allocator, eval_fn)) |elem| {
                const val = try applyStreamFn(allocator, eval_fn, p.f, elem);
                return val;
            }
            return null;
        },
        .list_items => |*li| {
            if (li.index >= li.items.len) return null;
            const val = li.items[li.index];
            li.index += 1;
            return val;
        },
        .generate => |*g| {
            const val = g.seed;
            g.seed = try applyStreamFn(allocator, eval_fn, g.f, g.seed);
            g.count += 1;
            return val;
        },
    };
}

fn applyStreamFn(allocator: std.mem.Allocator, eval_fn: ?EvalFn, f: StreamFn, arg: Value) !Value {
    return switch (f) {
        .primitive => |p| {
            var env: @import("primitive.zig").RuntimeEnv = .{ .frame = undefined, .primitives = .{ .bindings = &.{} }, .allocator = allocator };
            const args = [_]Value{arg};
            return p(&env, &args);
        },
        .closure => |c| {
            const frame = try allocator.create(Frame);
            frame.* = Frame{ .bindings = .empty, .parent = c.env, .primitives = null };
            if (c.param_names.len == 1) {
                try frame.bindings.put(allocator, c.param_names[0], arg);
            }
            return (eval_fn orelse return error.NotAFunction)(c.body, frame, allocator);
        },
    };
}
