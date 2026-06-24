const lexer = @import("lexer/lexer.zig");
const parser = @import("parser/parser.zig");
const ast = @import("ast/ast.zig");
const typed = @import("ast/typed.zig");
const typecheck = @import("typecheck/infer.zig");
const runtime = @import("runtime/eval.zig");

pub const Lexer = lexer;
pub const Parser = parser;
pub const Ast = ast;
pub const Typed = typed;
pub const TypeCheck = typecheck;
pub const Runtime = runtime;
pub const tokenize = lexer.tokenize;
pub const parseModule = parser.parseModule;
