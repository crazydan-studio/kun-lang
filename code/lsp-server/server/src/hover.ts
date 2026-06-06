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
    '### `do` / `do in` — Sequential IO',
    '',
    'Sequentially executes IO operations. Use `do in` when a return value is needed.',
    '',
    '```kun',
    'main =',
    '  do',
    '    content <- readFile p"/tmp/foo"',
    '    print content',
    '',
    '// With return value:',
    'loadConfig = \\path ->',
    '  do',
    '    content <- readFile path',
    '  in',
    '    Config { content = content }',
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
  module: [
    '### `module` — Module Declaration',
    '',
    'Each source file begins with a module declaration.',
    '',
    '```kun',
    'module List export (map, filter, fold)',
    'module Result export (Result(..))',
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
    'import List with (map, filter) // selective',
    'import List with (..)          // wildcard',
    '```',
  ].join('\n'),
  with: [
    '### `with` — Import Selection / Capability Declaration',
    '',
    'Used in imports for selective symbol import, or in capability declarations.',
    '',
    '```kun',
    'import List with (map, filter)',
    'with caps',
    '  fs.read = [Path.cwd]',
    '```',
  ].join('\n'),
  caps: [
    '### `caps` — Capability Declaration',
    '',
    'Declares required capabilities for IO operations.',
    '',
    '```kun',
    'with caps',
    '  fs.read = [Path.cwd, p"/tmp/"]',
    '  fs.write = fs.read',
    '```',
  ].join('\n'),
}

const TYPE_DOCS: Record<string, string> = {
  Int: '`Int` — 64-bit signed integer. Supports `+`, `-`, `*`, `/`, `%`.',
  Nat: '`Nat` — Non-negative integer. Suffix: `42u`. Independent type from `Int`.',
  Float: '`Float` — IEEE 754 double-precision. Supports `+`, `-`, `*`, `/`.',
  Bool: '`Bool` — Boolean. Values: `true`, `false`. Supports `&&`, `||`, `not`.',
  String: '`String` — UTF-8 text. Supports `++`, `length`, `slice`, etc.',
  Bytes: '`Bytes` — Binary data. Distinct from `String`. Supports `++`, `length`, `slice`.',
  Char: '`Char` — Unicode scalar value. Single quotes: `\'A\'`.',
  Regex: '`Regex` — Compiled regex. Literal: `r"..."`.',
  Duration: '`Duration` — Nanosecond-precision time span. Literals: `5s`, `100ms`.',
  Unit: '`Unit` — Unit type. Only value: `()`.',
  Path: '`Path` — File system path. Literal: `p"..."`. Supports `++`.',
  Result: '`Result t e` — Error handling type. Variants: `Ok t`, `Err e`.',
  List: '`List t` — Linked list. Literals: `[1, 2, 3]`, `[1..10]`.',
  Set: '`Set t` — Set data structure. Literal: `#[1, 2, 3]`.',
  Map: '`Map k v` — Key-value map. Literal: `#{ "a" = 1 }`.',
  Stream: '`Stream t` — Lazy pull-based sequence. Use `Stream` module to construct.',
  IO: '`IO t` — IO effect type. Functions returning `IO t` have side effects.',
}

const OPERATOR_DOCS: Record<string, string> = {
  '=!': [
    '`=!` — Early-return Result binding',
    '',
    'Binds a Result value with early return on Err.',
    'Can only be used in variable binding context.',
    '',
    '```kun',
    'config =! readConfig p"/etc/app.toml"',
    '```',
  ].join('\n'),
  '<-!': [
    '`<-!` — IO Result early-return binding',
    '',
    'Binds an IO Result value with early return on Err.',
    'Can only be used inside a `do` block.',
    '',
    '```kun',
    'lines <-! Stream.readLines path',
    '```',
  ].join('\n'),
  '<-': [
    '`<-` — IO bind operator',
    '',
    'Extracts a value from an IO action inside a `do` block.',
    '',
    '```kun',
    'content <- readFile p"/tmp/foo"',
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
