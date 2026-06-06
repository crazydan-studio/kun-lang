import {
  CompletionItem,
  CompletionItemKind,
  InsertTextFormat,
  Position,
} from 'vscode-languageserver'
import { KEYWORDS, BUILTIN_TYPES } from '@kun/lsp-shared'
import type { KunDocument } from './documents'

const KEYWORD_COMPLETIONS: CompletionItem[] = KEYWORDS.map(kw => {
  const snippets: Record<string, { snippet: string; doc: string }> = {
    type: {
      snippet: 'type ${1:Name} ${2:params}\n  = ${3:Variant}',
      doc: 'Define a custom type (ADT, Record, or Newtype)',
    },
    case: {
      snippet: 'case ${1:expr} of\n  ${2:pattern} -> ${3:result}',
      doc: 'Pattern matching expression',
    },
    if: {
      snippet: 'if ${1:condition} then\n  ${2:expr}\nelse\n  ${3:expr}',
      doc: 'Conditional expression',
    },
    let: {
      snippet: 'let\n  ${1:binding}\nin\n  ${2:expr}',
      doc: 'Local bindings with a return expression',
    },
    do: {
      snippet: 'do\n  ${1:step}',
      doc: 'Sequential IO execution block',
    },
    module: {
      snippet: 'module ${1:Name} export (${2:symbols})',
      doc: 'Module declaration with export list',
    },
    import: {
      snippet: 'import ${1:Module}',
      doc: 'Import a module',
    },
  }

  const entry = snippets[kw]
  if (entry) {
    return {
      label: kw,
      kind: CompletionItemKind.Keyword,
      insertText: entry.snippet,
      insertTextFormat: InsertTextFormat.Snippet,
      detail: entry.doc,
      data: kw,
    }
  }

  return {
    label: kw,
    kind: CompletionItemKind.Keyword,
    detail: getKeywordDoc(kw),
    data: kw,
  }
})

const BUILTIN_TYPE_COMPLETIONS: CompletionItem[] = BUILTIN_TYPES.map(t => ({
  label: t,
  kind: CompletionItemKind.TypeParameter,
  detail: getBuiltinTypeDoc(t),
  data: t,
}))

const COMMENT_SNIPPET: CompletionItem = {
  label: '///',
  kind: CompletionItemKind.Snippet,
  insertText: [
    '// ${1:description}',
    '//',
    '// ${2:details}',
  ].join('\n'),
  insertTextFormat: InsertTextFormat.Snippet,
  detail: 'Documentation comment template',
  data: 'doc-comment',
}

export function getCompletions(doc: KunDocument, position: Position): CompletionItem[] {
  const line = doc.lines[position.line] || ''
  const beforeCursor = line.slice(0, position.character)

  if (beforeCursor.trimStart().startsWith('//')) {
    return [COMMENT_SNIPPET]
  }

  const wordMatch = beforeCursor.match(/(\w+)$/)
  if (!wordMatch) {
    return [...KEYWORD_COMPLETIONS, ...BUILTIN_TYPE_COMPLETIONS]
  }

  const prefix = wordMatch[1].toLowerCase()

  return [
    ...KEYWORD_COMPLETIONS.filter(k => k.label.startsWith(prefix)),
    ...BUILTIN_TYPE_COMPLETIONS.filter(t => t.label.toLowerCase().startsWith(prefix)),
  ]
}

function getKeywordDoc(kw: string): string | undefined {
  const docs: Record<string, string> = {
    type: 'Define a custom type',
    case: 'Pattern matching expression',
    of: 'Part of case expression',
    if: 'Conditional expression',
    then: 'Then branch of if expression',
    else: 'Else branch of if expression',
    do: 'Sequential IO execution block',
    in: 'Return expression for let/do',
    let: 'Local bindings',
    module: 'Module declaration',
    import: 'Import a module',
    as: 'Module alias on import',
    with: 'Import specific symbols or declare capabilities',
    export: 'Declare exported symbols in module',
    caps: 'Capability declaration block',
    when: 'Guard clause in pattern matching',
    command: 'Declare a command module',
    for: 'Specify binary name in command declaration',
  }
  return docs[kw]
}

function getBuiltinTypeDoc(t: string): string | undefined {
  const docs: Record<string, string> = {
    Int: '64-bit signed integer',
    Nat: 'Non-negative integer',
    Float: 'Double-precision floating point',
    Bool: 'Boolean (true/false)',
    String: 'UTF-8 encoded text',
    Bytes: 'Binary data',
    Char: 'Unicode scalar value',
    Regex: 'Compiled regular expression',
    Duration: 'Time duration (nanosecond precision)',
    Unit: 'Unit type (void)',
    Path: 'File system path',
    Result: 'Result type for error handling (Ok | Err)',
    List: 'Linked list',
    Set: 'Set data structure',
    Map: 'Key-value map',
    Stream: 'Lazy pull-based sequence',
    IO: 'IO effect type',
  }
  return docs[t]
}
