const std = @import("std");

const test_lexer = @import("test_lexer.zig");
const test_parser = @import("test_parser.zig");

comptime {
    _ = test_lexer;
    _ = test_parser;
}
