import {
  Diagnostic,
  DiagnosticSeverity,
  Position,
  Range,
} from 'vscode-languageserver'
import type { KunDocument } from './documents'
import {
  COMMENT_RULES,
  DEPRECATED_SYNTAX,
  NAMING_RULES,
  isTypeName,
} from '@kun-lang/lsp-shared'
import { checkCommentStyle, detectSemicolons, checkLineWidth } from '@kun-lang/lsp-shared'
import { isTypeNameValid } from '@kun-lang/lsp-shared'
import { FORMAT_RULES } from '@kun-lang/lsp-shared'

function pos(line: number, character: number): Position {
  return { line, character }
}

function range(startLine: number, startChar: number, endLine: number, endChar: number): Range {
  return {
    start: pos(startLine, startChar),
    end: pos(endLine, endChar),
  }
}

function error(
  message: string,
  line: number,
  startChar: number,
  endChar: number,
): Diagnostic {
  return {
    range: range(line, startChar, line, endChar),
    message,
    severity: DiagnosticSeverity.Error,
    source: 'kun-lsp',
  }
}

function warning(
  message: string,
  line: number,
  startChar: number,
  endChar: number,
): Diagnostic {
  return {
    range: range(line, startChar, line, endChar),
    message,
    severity: DiagnosticSeverity.Warning,
    source: 'kun-lsp',
  }
}

export function getDiagnostics(doc: KunDocument): Diagnostic[] {
  const diagnostics: Diagnostic[] = []
  const { lines } = doc

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const trimmed = line.trim()

    if (trimmed.length === 0) continue

    checkSemicolons(diagnostics, line, i)
    checkComments(diagnostics, line, i)
    checkLineLength(diagnostics, line, i)
    checkDeprecatedSyntax(diagnostics, line, i)
    checkTypeNaming(diagnostics, line, i)
    checkGenericBrackets(diagnostics, line, i)
    checkFunctionApplication(diagnostics, line, i)
    checkDoBlockContext(diagnostics, line, i, lines)
  }

  return diagnostics
}

function checkSemicolons(diagnostics: Diagnostic[], line: string, lineNum: number): void {
  if (detectSemicolons(line)) {
    diagnostics.push(
      error('Semicolons are not supported in Kun. Each statement must be on its own line.', lineNum, line.length - 1, line.length),
    )
  }
}

function checkComments(diagnostics: Diagnostic[], line: string, lineNum: number): void {
  const result = checkCommentStyle(line)
  if (!result.valid) {
    const col = line.indexOf(result.style!)
    diagnostics.push(
      error(`Invalid comment style '${result.style}'. Use '//' for comments.`, lineNum, col, col + result.style!.length),
    )
  }
}

function checkLineLength(diagnostics: Diagnostic[], line: string, lineNum: number): void {
  if (checkLineWidth(line)) {
    diagnostics.push(
      warning(`Line exceeds ${FORMAT_RULES.lineWidth} characters (${line.length}).`, lineNum, FORMAT_RULES.lineWidth, line.length),
    )
  }
}

function checkDeprecatedSyntax(diagnostics: Diagnostic[], line: string, lineNum: number): void {
  for (const entry of DEPRECATED_SYNTAX) {
    const match = line.match(entry.pattern)
    if (match && match.index !== undefined) {
      diagnostics.push(
        warning(entry.message, lineNum, match.index, match.index + match[0].length),
      )
    }
  }
}

function checkTypeNaming(diagnostics: Diagnostic[], line: string, lineNum: number): void {
  const typeRe = /\btype\s+(\w+)/g
  let match: RegExpExecArray | null
  while ((match = typeRe.exec(line)) !== null) {
    if (!isTypeNameValid(match[1])) {
      diagnostics.push(
        error(`Type name '${match[1]}' must start with an uppercase letter.`, lineNum, match.index + 5, match.index + 5 + match[1].length),
      )
    }
  }
  const varRe = /(?<![A-Za-z0-9'])([a-z]\w*)\s*:\s+([A-Z]\w*)/g
  while ((match = varRe.exec(line)) !== null) {
    const typeName = match[2]
    if (!isTypeNameValid(typeName)) {
      diagnostics.push(
        error(`Type '${typeName}' in annotation must start with an uppercase letter.`, lineNum, match.index! + match[0].indexOf(typeName), match.index! + match[0].indexOf(typeName) + typeName.length),
      )
    }
  }
}

function checkGenericBrackets(diagnostics: Diagnostic[], line: string, lineNum: number): void {
  const angleGenericRe = /<([A-Z]\w*(?:\s*,\s*[A-Z]\w*)*)>/
  const match = line.match(angleGenericRe)
  if (match && match.index !== undefined) {
    diagnostics.push(
      error('Kun uses space-separated generics (e.g. List Int) instead of angle brackets <>.', lineNum, match.index, match.index + match[0].length),
    )
  }
}

function checkFunctionApplication(diagnostics: Diagnostic[], line: string, lineNum: number): void {
  const stripped = line.replace(/\/\/.*$/, '')
  const commaCallRe = /(\w+)\s*\(([^)]*,\s*[^)]*)\)/
  const match = stripped.match(commaCallRe)
  if (match) {
    diagnostics.push(
      warning('Function arguments are space-separated, not comma-separated.', lineNum, match.index!, match.index! + match[0].length),
    )
  }
}

function checkDoBlockContext(
  diagnostics: Diagnostic[],
  line: string,
  lineNum: number,
  allLines: string[],
): void {
  // Check that `<-` and `<-!` are inside do blocks
  const hasBind = /<-\!?\s/.test(line)
  if (hasBind) {
    let foundDo = false
    for (let j = lineNum; j >= 0; j--) {
      if (/^\s*do\b/.test(allLines[j])) {
        foundDo = true
        break
      }
    }
    if (!foundDo) {
      const bindIdx = line.search(/<-\!?\s/)
      diagnostics.push(
        error('IO bind operator (<- / <-!) can only be used inside a do block.', lineNum, bindIdx, bindIdx + 2),
      )
    }
  }
}
