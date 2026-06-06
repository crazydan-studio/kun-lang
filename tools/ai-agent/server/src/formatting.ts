import { TextEdit, Position } from 'vscode-languageserver'
import { TextDocument } from 'vscode-languageserver-textdocument'
import {
  FORMAT_RULES,
  formatIndent,
  detectSemicolons,
  checkCommentStyle,
} from '@kun/lsp-shared'

export function formatDocument(document: TextDocument): TextEdit[] {
  const text = document.getText()
  const lines = text.split('\n')
  const formattedLines: string[] = []
  let blankCount = 0

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i]
    let line = raw

    line = removeTrailingWhitespace(line)
    line = removeSemicolons(line)
    line = fixCommentStyle(line)
    line = fixIndentation(line)

    if (line.trim() === '') {
      blankCount++
      if (blankCount <= FORMAT_RULES.maxConsecutiveBlankLines) {
        formattedLines.push('')
      }
    } else {
      blankCount = 0
      formattedLines.push(line)
    }
  }

  let formatted = formattedLines.join('\n')

  if (FORMAT_RULES.trailingNewline && !formatted.endsWith('\n')) {
    formatted += '\n'
  }

  const fullRange = {
    start: Position.create(0, 0),
    end: Position.create(lines.length, 0),
  }

  return [TextEdit.replace(fullRange, formatted)]
}

function removeTrailingWhitespace(line: string): string {
  return line.replace(/\s+$/, '')
}

function removeSemicolons(line: string): string {
  if (!detectSemicolons(line)) return line
  const commentIdx = line.indexOf('//')
  if (commentIdx >= 0) {
    const code = line.slice(0, commentIdx)
    const comment = line.slice(commentIdx)
    return code.replace(/;\s*$/, '') + comment
  }
  return line.replace(/;\s*$/, '')
}

function fixCommentStyle(line: string): string {
  const result = checkCommentStyle(line)
  if (result.valid) return line
  if (result.style === '--') {
    return line.replace(/^(\s*)--/, '$1//')
  }
  if (result.style === '#') {
    return line.replace(/^(\s*)#/, '$1//')
  }
  return line
}

function fixIndentation(line: string): string {
  const trimmed = line.trimStart()
  if (trimmed.length === 0) return ''

  const leadingSpaces = line.length - trimmed.length
  const indentLevel = Math.round(leadingSpaces / FORMAT_RULES.indentSize)
  const normalizedIndent = formatIndent(indentLevel)

  return normalizedIndent + trimmed
}
