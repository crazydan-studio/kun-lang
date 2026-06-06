import {
  LET_IN_RULES, CASE_OF_RULES, IF_THEN_ELSE_RULES,
  DO_RULES, PIPE_RULES, RECORD_RULES,
} from './syntax'

export const FORMAT_RULES = {
  indentSize: 2,
  useTabs: false,
  lineWidth: 100,
  trailingNewline: true,
  maxConsecutiveBlankLines: 1,
  semicolonForbidden: true,
} as const

export function formatIndent(level: number): string {
  return ' '.repeat(level * FORMAT_RULES.indentSize)
}

export function detectSemicolons(line: string): boolean {
  const stripped = line.replace(/\/\/.*$/, '').trimEnd()
  return stripped.endsWith(';')
}

export function checkLineWidth(line: string): boolean {
  return line.length > FORMAT_RULES.lineWidth
}

export function checkCommentStyle(line: string): { valid: boolean; style?: string } {
  const trimmed = line.trimStart()
  if (!trimmed.startsWith('/') && !trimmed.startsWith('--') && !trimmed.startsWith('#')) {
    return { valid: true }
  }
  if (trimmed.startsWith('//')) return { valid: true }
  if (trimmed.startsWith('--')) return { valid: false, style: '--' }
  if (trimmed.startsWith('#')) return { valid: false, style: '#' }
  if (trimmed.startsWith('/*')) return { valid: false, style: '/*' }
  return { valid: true }
}

export function formatLetIn(body: string, indentLevel: number): string {
  const indent = formatIndent(indentLevel)
  const bodyIndent = formatIndent(indentLevel + 1)
  return `${indent}let\n${bodyIndent}${body}\n${indent}in`
}

export function formatCase(expr: string, branches: string[], indentLevel: number): string {
  const indent = formatIndent(indentLevel)
  const branchIndent = formatIndent(indentLevel + 1)
  const ofLine = `${indent}case ${expr} of`
  const branchLines = branches.map(b => `${branchIndent}${b}`)
  return [ofLine, ...branchLines].join('\n')
}

export function formatIfThenElse(
  condition: string,
  thenBody: string,
  elseBody: string,
  indentLevel: number,
): string {
  const indent = formatIndent(indentLevel)
  const bodyIndent = formatIndent(indentLevel + 1)
  return [
    `${indent}if ${condition} then`,
    `${bodyIndent}${thenBody}`,
    `${indent}else`,
    `${bodyIndent}${elseBody}`,
  ].join('\n')
}

export function formatDoBlock(
  steps: string[],
  indentLevel: number,
  result?: string,
): string {
  const indent = formatIndent(indentLevel)
  const stepIndent = formatIndent(indentLevel + 1)
  const lines: string[] = [`${indent}do`]
  for (const step of steps) {
    lines.push(`${stepIndent}${step}`)
  }
  if (result !== undefined) {
    lines.push(`${indent}in`)
    lines.push(`${stepIndent}${result}`)
  }
  return lines.join('\n')
}

export function formatPipe(expr: string, steps: string[], indentLevel: number): string {
  const indent = formatIndent(indentLevel)
  const pipeIndent = formatIndent(indentLevel + 1)
  const lines: string[] = [`${indent}${expr}`]
  for (const step of steps) {
    lines.push(`${pipeIndent}|> ${step}`)
  }
  return lines.join('\n')
}

export function formatRecordMultiline(
  fields: { name: string; value: string }[],
  indentLevel: number,
): string {
  const indent = formatIndent(indentLevel)
  const fieldIndent = formatIndent(indentLevel + 1)
  if (fields.length === 0) return `${indent}{}`
  const first = `${indent}{ ${fields[0].name} = ${fields[0].value}`
  const rest = fields.slice(1).map(f => `${fieldIndent}, ${f.name} = ${f.value}`)
  return [first, ...rest, `${indent}}`].join('\n')
}

export function formatFunctionDef(
  name: string,
  params: string[],
  body: string,
  indentLevel: number,
  typeAnnotation?: string,
): string {
  const indent = formatIndent(indentLevel)
  const bodyIndent = formatIndent(indentLevel + 1)
  const lines: string[] = []
  if (typeAnnotation) {
    lines.push(`${indent}${name} : ${typeAnnotation}`)
  }
  const paramStr = params.length > 0 ? ` ${params.join(' ')}` : ''
  lines.push(`${indent}${name} = \\${paramStr} ->`)
  lines.push(`${bodyIndent}${body}`)
  return lines.join('\n')
}

export function formatRecordUpdate(
  record: string,
  fields: { name: string; value: string }[],
  indentLevel: number,
): string {
  const indent = formatIndent(indentLevel)
  const fieldIndent = formatIndent(indentLevel + 1)
  if (fields.length <= 2) {
    const parts = fields.map(f => `${f.name} = ${f.value}`).join(', ')
    return `${indent}{ ${record} | ${parts} }`
  }
  const fieldLines = fields.map(f => `${fieldIndent}${f.name} = ${f.value}`)
  return [`${indent}{ ${record} |`, ...fieldLines, `${indent}}`].join('\n')
}

export function formatTypeAnnotation(
  name: string,
  typeStr: string,
  indentLevel: number,
): string {
  const indent = formatIndent(indentLevel)
  if (typeStr.length <= FORMAT_RULES.lineWidth - indent.length - name.length - 5) {
    return `${indent}${name} : ${typeStr}`
  }
  const parts = typeStr.split('->').map(s => s.trim())
  if (parts.length <= 1) return `${indent}${name} : ${typeStr}`
  const lines: string[] = [`${indent}${name}`]
  const contIndent = formatIndent(indentLevel + 1)
  for (let i = 0; i < parts.length; i++) {
    if (i < parts.length - 1) {
      lines.push(`${contIndent}-> ${parts[i]}`)
    } else {
      lines.push(`${contIndent}-> ${parts[i]}`)
    }
  }
  return lines.join('\n')
}
