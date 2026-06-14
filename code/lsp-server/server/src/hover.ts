import {
  Hover,
  Position,
  MarkupKind,
} from 'vscode-languageserver'
import type { KunDocument } from './documents'
import { KEYWORDS, BUILTIN_TYPES } from '@kun-lang/lsp-shared'

const KEYWORD_DOCS: Record<string, string> = {
  type: [
    '### `type` — Type Definition',
    '',
    'Defines a custom type (ADT, Record, or Newtype).',
    '',
    '```kun',
    'type Result t e',
    '  = Ok t',
    '  | Err e',
    '```',
    '',
    'Type names must start with an uppercase letter.',
    'Generic parameters are space-separated.',
  ].join('\n'),
  case: [
    '### `case` — Pattern Matching',
    '',
    'Pattern matching expression. Must be exhaustive for custom ADTs and Bool.',
    '',
    '```kun',
    'case value of',
    '  Ok v -> process v',
    '  Err _ -> handleError',
    '```',
  ].join('\n'),
  if: [
    '### `if/then/else` — Conditional Expression',
    '',
    '`if` is an expression and must have an `else` branch.',
    '',
    '```kun',
    'result =',
    '  if condition then',
    '    expr1',
    '  else',
    '    expr2',
    '```',
  ].join('\n'),
  do: [
    '### `do` / `do in` — Sequential Execution',
    '',
    'Sequentially executes operations. Use `do in` when a return value is needed.',
    'Effect functions (Cmd.*/IO.*/File.*/etc.) can only be called inside `do` blocks.',
    '',
    '```kun',
    'main = \\_ ->',
    '  do',
    '    IO.println "hello"',
    '    content = File.readString p"/tmp/foo"',
    '    case content of',
    '      Ok text -> IO.print text',
    '      Err _   -> IO.println "failed"',
    '',
    '// With return value:',
    'countFiles = \\dir ->',
    '  do',
    '    entries =',
    '      Cmd.ls { all = true } dir',
    '        |> Stream.lines',
    '        |> Stream.toList',
    '  in',
    '    List.length entries',
    '```',
  ].join('\n'),
  defer: [
    '### `defer` — Deferred Cleanup',
    '',
    'Registers an expression to execute when the enclosing `do` block exits.',
    'Multiple `defer` expressions execute in LIFO order.',
    '',
    '```kun',
    'do',
    '  case File.createTempFile of',
    '    Ok tmp ->',
    '      defer (File.remove tmp)',
    '      Cmd.ffmpeg {} "input.mp4" tmp',
    '    Err _ -> IO.println "failed to create temp file"',
    '```',
  ].join('\n'),
  let: [
    '### `let ... in` — Local Bindings',
    '',
    'Introduces local definitions with a return expression.',
    '',
    '```kun',
    'result =',
    '  let',
    '    x = 1',
    '    y = 2',
    '  in',
    '    x + y',
    '```',
  ].join('\n'),
  export: [
    '### `export` — Export Declaration',
    '',
    'Each library source file begins with an export declaration.',
    'File path determines the module name (e.g. `lib/File.kun` → module `File`).',
    'Executable scripts (with `main`) must not have an `export` declaration.',
    '',
    '```kun',
    'export (map, filter, fold)',
    'export (Result(..))',
    '```',
  ].join('\n'),
  import: [
    '### `import` — Module Import',
    '',
    'Three styles: module alias, selective import, or wildcard import.',
    '',
    '```kun',
    'import List                    // module alias',
    'import List as L               // short alias',
    'import List (map, filter)      // selective',
    'import List (..)               // wildcard',
    '```',
  ].join('\n'),
  as: [
    '### `as` — Module or Import Alias',
    '',
    'Used in imports to create a short alias or rename imported symbols.',
    '',
    '```kun',
    'import List as L              // module alias',
    'import List (map as m)       // symbol rename',
    '```',
  ].join('\n'),
  main: [
    '### `main` — Script Entry Point',
    '',
    'Defines the executable script entry point. Type annotation `List String -> Unit` is optional.',
    '',
    '```kun',
    '// With type annotation:',
    'main : List String -> Unit',
    'main = \\_ ->',
    '  do',
    '    IO.println "hello"',
    '',
    '// Without type annotation (defaults to List String -> Unit):',
    'main = \\_ ->',
    '  do',
    '    IO.println "hello"',
    '```',
  ].join('\n'),
}

const TYPE_DOCS: Record<string, string> = {
  Int: '`Int` — 64-bit signed integer. Supports `+`, `-`, `*`, `/`, `%`.',
  Float: '`Float` — IEEE 754 double-precision. Supports `+`, `-`, `*`, `/`, `sqrt`, `floor`, `ceil`, `round`.',
  Bool: '`Bool` — Boolean. Values: `true`, `false`. Supports `&&`, `||`, `not`.',
  String: '`String` — UTF-8 text. Supports `++`, `length`, `slice`, etc.',
  Bytes: '`Bytes` — Binary data. Distinct from `String`. Supports `++`, `length`, `slice`.',
  Char: '`Char` — Unicode scalar value. Single quotes: `\'A\'`.',
  Regex: '`Regex` — Compiled regex. Literal: `r"..."`.',
  Duration: '`Duration` — Nanosecond-precision time span. Literals: `5s`, `100ms`.',
  Path: '`Path` — File system path. Literal: `p"..."`. Supports `++`.',
  Result: '`Result t e` — Error handling type. Variants: `Ok t`, `Err e`.',
  List: '`List t` — Linked list. Literals: `[1, 2, 3]`, `[1..10]`.',
  Set: '`Set t` — Set data structure. Literal: `#[1, 2, 3]`.',
  Map: '`Map k v` — Key-value map. Literal: `#{ "a" = 1 }`.',
  Stream: '`Stream t` — Lazy pull-based sequence. Use `Stream` module to construct.',
  Unit: '`Unit` — Zero-width type (like void). Return type for functions with no meaningful value. Cannot be used as a parameter type.',
  Tuple: '`Tuple` — Fixed-length heterogeneous product type. Literal: `(1, "hello", true)`. Index access: `tuple.0`, `tuple.1`.',
}

const OPERATOR_DOCS: Record<string, string> = {
  '|>': [
    '`|>` — Pipe operator',
    '',
    'Passes the left-hand value as the last argument to the right-hand function.',
    '',
    '```kun',
    'list |> map (\\x -> x * 2) |> filter (\\x -> x > 10)',
    '```',
  ].join('\n'),
  '?.': [
    '`?.` — Optional chaining',
    '',
    'If the left operand is `Nil`, returns `Nil` without calling the right-hand function.',
    '',
    '```kun',
    'getConfig "port" ?. parseInt',
    '```',
  ].join('\n'),
  '??': [
    '`??` — Nil coalescing',
    '',
    'Returns the left-hand value if it is not `Nil`, otherwise returns the right-hand default.',
    '',
    '```kun',
    'name ?? "guest"',
    '```',
  ].join('\n'),
}

export function getHoverInfo(doc: KunDocument, position: Position): Hover | null {
  const line = doc.lines[position.line] || ''
  const wordMatch = line.match(/[\w!?=<>|\-:.]+/g)
  if (!wordMatch) return null

  const word = wordMatch.find((w: string) => {
    const idx = line.indexOf(w)
    return idx <= position.character && idx + w.length >= position.character
  })
  if (!word) return null

  const keywordDoc = KEYWORD_DOCS[word]
  if (keywordDoc) {
    return { contents: { kind: MarkupKind.Markdown, value: keywordDoc } }
  }

  const typeDoc = TYPE_DOCS[word]
  if (typeDoc) {
    return { contents: { kind: MarkupKind.Markdown, value: typeDoc } }
  }

  const operatorDoc = OPERATOR_DOCS[word]
  if (operatorDoc) {
    return { contents: { kind: MarkupKind.Markdown, value: operatorDoc } }
  }

  return null
}
