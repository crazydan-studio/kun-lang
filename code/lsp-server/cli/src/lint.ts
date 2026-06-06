import * as fs from 'fs'
import {
  DEPRECATED_SYNTAX, GENERIC_RULES,
  DECLARATION_ORDER_RULES,
  isTypeName,
} from '@kun-lang/lsp-shared'
import {
  FORMAT_RULES, detectSemicolons, checkLineWidth,
  checkCommentStyle,
} from '@kun-lang/lsp-shared'
import {
  NILABLE_RULES, EARLY_RETURN_RULES, IO_RULES,
  NAMING_CONVENTIONS,
} from '@kun-lang/lsp-shared'

interface Diagnostic {
  line: number
  message: string
  severity: 'error' | 'warning'
}

function checkDeclarationOrderCLI(diagnostics: Diagnostic[], lines: string[]): void {
  let firstNonComment = -1
  let moduleOrCommandLine = -1
  let firstImportLine = -1
  let firstCapsLine = -1

  for (let i = 0; i < lines.length; i++) {
    const trimmed = lines[i].trim()
    if (trimmed.length === 0 || trimmed.startsWith('//')) continue

    if (firstNonComment === -1) firstNonComment = i

    if (DECLARATION_ORDER_RULES.modulePattern.test(trimmed) ||
        DECLARATION_ORDER_RULES.commandPattern.test(trimmed)) {
      if (moduleOrCommandLine === -1) moduleOrCommandLine = i
      continue
    }

    if (DECLARATION_ORDER_RULES.importPattern.test(trimmed)) {
      if (firstImportLine === -1) firstImportLine = i
      continue
    }

    if (DECLARATION_ORDER_RULES.capsPattern.test(lines[i])) {
      if (firstCapsLine === -1) firstCapsLine = i
      continue
    }
  }

  if (moduleOrCommandLine !== -1 && moduleOrCommandLine !== firstNonComment) {
    diagnostics.push({
      line: moduleOrCommandLine + 1,
      message: '`module` 或 `command` 声明必须是文件第一个非注释行',
      severity: 'error',
    })
  }

  if (moduleOrCommandLine !== -1 && firstImportLine !== -1 && firstImportLine < moduleOrCommandLine) {
    diagnostics.push({
      line: firstImportLine + 1,
      message: '`import` 语句必须在 `module`/`command` 声明之后',
      severity: 'error',
    })
  }

  if (firstCapsLine !== -1 && firstImportLine !== -1 && firstCapsLine < firstImportLine) {
    diagnostics.push({
      line: firstCapsLine + 1,
      message: '脚本级 `with caps` 必须在 `import` 语句之后',
      severity: 'error',
    })
  }

  if (firstCapsLine !== -1 && moduleOrCommandLine !== -1 && firstCapsLine < moduleOrCommandLine) {
    diagnostics.push({
      line: firstCapsLine + 1,
      message: '脚本级 `with caps` 必须在 `module`/`command` 声明之后',
      severity: 'error',
    })
  }
}

function runDiagnostics(content: string): Diagnostic[] {
  const diagnostics: Diagnostic[] = []
  const lines = content.split('\n')

  // 0. Declaration order check
  checkDeclarationOrderCLI(diagnostics, lines)

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const lineNum = i + 1

    // 1. Deprecated syntax patterns
    for (const rule of DEPRECATED_SYNTAX) {
      if (rule.pattern.test(line)) {
        diagnostics.push({ line: lineNum, message: rule.message, severity: 'error' })
      }
    }

    // 2. Comment style
    const commentCheck = checkCommentStyle(line)
    if (!commentCheck.valid && commentCheck.style) {
      diagnostics.push({
        line: lineNum,
        message: `Kun 仅支持 // 注释（当前使用了 ${commentCheck.style}）`,
        severity: 'error',
      })
    }

    // 3. Generics - forbid <>
    if (GENERIC_RULES.forbidden) {
      const match = line.match(GENERIC_RULES.forbidden)
      if (match) {
        diagnostics.push({
          line: lineNum,
          message: `泛型参数请使用空格分隔，禁止尖括号（如 "${match[0]}"）`,
          severity: 'error',
        })
      }
    }

    // 4. Semicolons — any semicolon in code (not in comments/strings)
    const codePart = line.replace(/\/\/.*$/, '').replace(/"[^"]*"/g, '')
    if (codePart.includes(';')) {
      diagnostics.push({
        line: lineNum,
        message: 'Kun 不支持分号；每条语句必须独占一行',
        severity: 'error',
      })
    }

    // 5. Line width
    if (checkLineWidth(line)) {
      diagnostics.push({
        line: lineNum,
        message: `超过 ${FORMAT_RULES.lineWidth} 字符限制（当前 ${line.length} 字符）`,
        severity: 'warning',
      })
    }

    // 6. Type naming
    const typeMatch = line.match(/^type\s+([A-Za-z_]\w*)/)
    if (typeMatch) {
      const name = typeMatch[1]
      if (!isTypeName(name)) {
        diagnostics.push({
          line: lineNum,
          message: `类型名 "${name}" 应以大写字母开头`,
          severity: 'error',
        })
      }
    }

    // 7. IO operators in non-do context
    const ioOperators = [IO_RULES.bindOperator, IO_RULES.bindWithEarlyReturn]
    const foundOp = ioOperators.find(op => line.includes(op))
    if (foundOp) {
      const doCount = lines.slice(0, i + 1).filter(l => l.trim().startsWith('do')).length
      const inCount = lines.slice(0, i + 1).filter(l => l.trim() === 'in' || l.trim().startsWith('in ')).length
      if (doCount <= inCount) {
        diagnostics.push({
          line: lineNum,
          message: `'${foundOp}' 应在 do 块内使用`,
          severity: 'warning',
        })
      }
    }
  }

  return diagnostics
}

function formatContent(content: string): string {
  let result = content

  result = result.split('\n').map(line => line.trimEnd()).join('\n')

  result = result.split('\n').map(line => {
    const trimmed = line.trimStart()
    const indent = line.slice(0, line.length - trimmed.length)
    if (trimmed.startsWith('--') && !trimmed.startsWith('-- ')) {
      return indent + '// ' + trimmed.slice(2).trimStart()
    }
    if (trimmed.startsWith('#')) {
      return indent + '// ' + trimmed.slice(1).trimStart()
    }
    return line
  }).join('\n')

  result = result.split('\n').map(line => {
    const commentIdx = line.indexOf('//')
    if (commentIdx >= 0) {
      const code = line.slice(0, commentIdx).replace(/;\s*$/, '')
      return code + line.slice(commentIdx)
    }
    return line.replace(/;\s*$/, '')
  }).join('\n')

  if (!result.endsWith('\n')) result += '\n'
  result = result.replace(/\n{3,}/g, '\n\n')

  return result
}

function printDiagnostics(diagnostics: Diagnostic[], fileLabel: string): number {
  const errors = diagnostics.filter(d => d.severity === 'error')
  const warnings = diagnostics.filter(d => d.severity === 'warning')

  if (diagnostics.length === 0) {
    console.log(`✅ ${fileLabel}: 无问题`)
    return 0
  }

  console.log(`\n📋 ${fileLabel}: ${errors.length} 错误, ${warnings.length} 警告\n`)

  for (const d of diagnostics) {
    const badge = d.severity === 'error' ? '✗' : '⚠'
    console.log(`  L${String(d.line).padStart(4)}  ${badge}  ${d.message}`)
  }
  console.log()

  return errors.length > 0 ? 1 : 0
}

function cmdCheck(files: string[]): number {
  let exitCode = 0
  for (const file of files) {
    try {
      const content = fs.readFileSync(file, 'utf-8')
      const diagnostics = runDiagnostics(content)
      if (printDiagnostics(diagnostics, file) > 0) exitCode = 1
    } catch (e: any) {
      console.error(`❌ ${file}: ${e.message}`)
      exitCode = 1
    }
  }
  return exitCode
}

function cmdFormat(files: string[]): number {
  let exitCode = 0
  for (const file of files) {
    try {
      const content = fs.readFileSync(file, 'utf-8')
      const formatted = formatContent(content)
      if (content !== formatted) {
        fs.writeFileSync(file, formatted, 'utf-8')
        console.log(`✏️  已格式化: ${file}`)
      } else {
        console.log(`✅ 已是最佳格式: ${file}`)
      }
    } catch (e: any) {
      console.error(`❌ ${file}: ${e.message}`)
      exitCode = 1
    }
  }
  return exitCode
}

function printUsage(): void {
  console.log(`
Kun 语言代码检查与格式化工具

用法:
  kun-lint check <file>...    检查语法/类型/过时模式
  kun-lint format <file>...   格式化代码

示例:
  kun-lint check app.kun lib.kun
  kun-lint format app.kun
`)
}

function main(): void {
  const args = process.argv.slice(2)
  if (args.length < 2) {
    printUsage()
    process.exit(1)
  }

  const cmd = args[0]
  const files = args.slice(1)

  switch (cmd) {
    case 'check':
      process.exit(cmdCheck(files))
    case 'format':
      process.exit(cmdFormat(files))
    default:
      console.error(`未知命令: ${cmd}`)
      printUsage()
      process.exit(1)
  }
}

main()
