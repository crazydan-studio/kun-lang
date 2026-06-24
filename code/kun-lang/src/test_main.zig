const std = @import("std");

const test_lexer = @import("lexer/test_lexer.zig");
const test_parser = @import("parser/test_parser.zig");
const test_typecheck_env = @import("typecheck/test_env.zig");
const test_typecheck_unify = @import("typecheck/test_unify.zig");
const test_typecheck_constraint = @import("typecheck/test_constraint.zig");
const test_typecheck_effect = @import("typecheck/test_effect.zig");
const test_typecheck_pattern = @import("typecheck/test_pattern.zig");
const test_typecheck_infer = @import("typecheck/test_infer.zig");
const test_typecheck_error = @import("typecheck/test_error.zig");
const test_typecheck_i18n = @import("typecheck/test_i18n.zig");
const test_runtime_env = @import("runtime/test_env.zig");
const test_runtime_eval = @import("runtime/test_eval.zig");
const test_runtime_defer = @import("runtime/test_defer.zig");
const test_primitive = @import("runtime/test_primitive.zig");
const test_cmd = @import("runtime/test_cmd.zig");
const test_stream = @import("runtime/test_stream.zig");
const test_crypto = @import("runtime/test_crypto.zig");
const test_hash_map = @import("runtime/test_hash_map.zig");
const test_glob = @import("runtime/test_glob_engine.zig");
const test_integration = @import("tests/test_integration.zig");

comptime {
    _ = test_lexer;
    _ = test_parser;
    _ = test_typecheck_env;
    _ = test_typecheck_unify;
    _ = test_typecheck_constraint;
    _ = test_typecheck_effect;
    _ = test_typecheck_pattern;
    _ = test_typecheck_infer;
    _ = test_typecheck_error;
    _ = test_typecheck_i18n;
    _ = test_runtime_env;
    _ = test_runtime_eval;
    _ = test_runtime_defer;
    _ = test_primitive;
    _ = test_cmd;
    _ = test_stream;
    _ = test_crypto;
    _ = test_hash_map;
    _ = test_glob;
    _ = test_integration;
}
