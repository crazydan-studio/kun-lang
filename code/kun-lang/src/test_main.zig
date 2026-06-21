const std = @import("std");

const test_lexer = @import("lexer/test_lexer.zig");
const test_parser = @import("parser/test_parser.zig");

comptime {
    _ = test_lexer;
    _ = test_parser;
}
