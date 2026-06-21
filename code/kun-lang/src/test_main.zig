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
const test_runtime_env = @import("runtime/test_env.zig");
const test_runtime_eval = @import("runtime/test_eval.zig");
const test_runtime_defer = @import("runtime/test_defer.zig");
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
    _ = test_runtime_env;
    _ = test_runtime_eval;
    _ = test_runtime_defer;
    _ = test_integration;
}
