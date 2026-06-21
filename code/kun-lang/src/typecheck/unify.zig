const std = @import("std");
const typed = @import("../ast/typed.zig");
const env_mod = @import("env.zig");

const Type = typed.Type;
const TypeId = typed.TypeId;
const TypeEnv = env_mod.TypeEnv;
const int_type = env_mod.int_type;
const bool_type = env_mod.bool_type;
const unit_type = env_mod.unit_type;

pub const TypeError = enum {
    mismatch,
    nil_to_non_nilable,
    effect_fn_pure_mismatch,
    infinite_type,
    unknown_field,
    adt_name_mismatch,
    tuple_length_mismatch,
    record_field_mismatch,
};

pub fn unify(env: *TypeEnv, allocator: std.mem.Allocator, a: TypeId, b: TypeId) !void {
    const resolved_a = env.applySubst(a);
    const resolved_b = env.applySubst(b);
    if (resolved_a == resolved_b) return;

    const ta = env.getType(resolved_a);
    const tb = env.getType(resolved_b);

    if (ta == .variable) {
        const va = ta.variable;
        if (occursCheck(env, allocator, va.id, resolved_b)) return error.InfiniteType;
        try env.subst.put(allocator, resolved_a, resolved_b);
        return;
    }
    if (tb == .variable) {
        const vb = tb.variable;
        if (occursCheck(env, allocator, vb.id, resolved_a)) return error.InfiniteType;
        try env.subst.put(allocator, resolved_b, resolved_a);
        return;
    }

    if (isBaseType(ta) and isBaseType(tb)) {
        if (@intFromEnum(ta) != @intFromEnum(tb)) return error.Mismatch;
        return;
    }

    if (ta == .nilable and tb == .nilable) {
        return unify(env, allocator, ta.nilable, tb.nilable);
    }
    if (ta == .nilable and isBaseType(tb)) {
        return error.NilToNonNilable;
    }
    if (isBaseType(ta) and tb == .nilable) {
        return error.NilToNonNilable;
    }

    if (ta == .function and tb == .function) {
        try unify(env, allocator, ta.function.param, tb.function.param);
        return unify(env, allocator, ta.function.result, tb.function.result);
    }
    if (ta == .effect_fn and tb == .effect_fn) {
        try unify(env, allocator, ta.effect_fn.param, tb.effect_fn.param);
        return unify(env, allocator, ta.effect_fn.result, tb.effect_fn.result);
    }
    if ((ta == .effect_fn and tb == .function) or (ta == .function and tb == .effect_fn)) {
        return error.EffectFnPureMismatch;
    }

    if (ta == .list and tb == .list) {
        return unify(env, allocator, ta.list, tb.list);
    }
    if (ta == .set and tb == .set) {
        return unify(env, allocator, ta.set, tb.set);
    }
    if (ta == .stream and tb == .stream) {
        return unify(env, allocator, ta.stream, tb.stream);
    }

    if (ta == .map and tb == .map) {
        try unify(env, allocator, ta.map.key, tb.map.key);
        return unify(env, allocator, ta.map.value, tb.map.value);
    }

    if (ta == .tuple and tb == .tuple) {
        const as = ta.tuple;
        const bs = tb.tuple;
        if (as.len != bs.len) return error.TupleLengthMismatch;
        for (as, bs) |ai, bi| {
            try unify(env, allocator, ai, bi);
        }
        return;
    }

    if (ta == .record and tb == .record) {
        const fa = ta.record;
        const fb = tb.record;
        if (fa.len != fb.len) return error.RecordFieldMismatch;
        for (fa, fb) |fi, fj| {
            if (!std.mem.eql(u8, fi.name, fj.name)) return error.RecordFieldMismatch;
            try unify(env, allocator, fi.type_, fj.type_);
        }
        return;
    }

    if (ta == .adt and tb == .adt) {
        if (!std.mem.eql(u8, ta.adt.name, tb.adt.name)) return error.AdtNameMismatch;
        const va = ta.adt.variants;
        const vb = tb.adt.variants;
        if (va.len != vb.len) return error.Mismatch;
        for (va, vb) |vi, vj| {
            if (vi.payload.len != vj.payload.len) return error.Mismatch;
            for (vi.payload, vj.payload) |pi, pj| {
                try unify(env, allocator, pi, pj);
            }
        }
        return;
    }

    return error.Mismatch;
}

fn isBaseType(ty: Type) bool {
    return switch (ty) {
        .int, .float, .bool, .string, .char, .bytes, .unit,
        .path, .duration, .regex, .decimal_t, .command_t, .datetime_t,
        => true,
        else => false,
    };
}

fn occursCheck(env: *TypeEnv, allocator: std.mem.Allocator, var_id: u32, ty_id: TypeId) bool {
    const resolved = env.applySubst(ty_id);
    if (resolved == var_id) return true;

    const ty = env.getType(resolved);
    return switch (ty) {
        .variable => |v| v.id == var_id,
        .nilable => |n| occursCheck(env, allocator, var_id, n),
        .list => |l| occursCheck(env, allocator, var_id, l),
        .set => |s| occursCheck(env, allocator, var_id, s),
        .stream => |s| occursCheck(env, allocator, var_id, s),
        .map => |m| occursCheck(env, allocator, var_id, m.key) or occursCheck(env, allocator, var_id, m.value),
        .function => |f| occursCheck(env, allocator, var_id, f.param) or occursCheck(env, allocator, var_id, f.result),
        .effect_fn => |f| occursCheck(env, allocator, var_id, f.param) or occursCheck(env, allocator, var_id, f.result),
        .tuple => |t| {
            for (t) |ti| {
                if (occursCheck(env, allocator, var_id, ti)) return true;
            }
            return false;
        },
        .record => |r| {
            for (r) |fi| {
                if (occursCheck(env, allocator, var_id, fi.type_)) return true;
            }
            return false;
        },
        .adt => |a| {
            for (a.variants) |v| {
                for (v.payload) |p| {
                    if (occursCheck(env, allocator, var_id, p)) return true;
                }
            }
            return false;
        },
        else => false,
    };
}
