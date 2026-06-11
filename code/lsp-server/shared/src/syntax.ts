export const KEYWORDS = [
  'type', 'case', 'if', 'then', 'else', 'do', 'in', 'let',
  'import', 'as', 'export', 'of',
  'when', 'defer',
] as const

export const BUILTIN_TYPES = [
  'Int', 'Float', 'Bool', 'String', 'Bytes', 'Char',
  'Regex', 'Duration', 'Path', 'Result', 'List', 'Set',
  'Map', 'Stream',
] as const

export const DEPRECATED_SYNTAX = [
  { pattern: /\*rest\b/, message: '*rest syntax is deprecated; use ..rest instead' },
  { pattern: /\bJust\b/, message: 'Just is deprecated; Kun uses ?T (Nilable) instead of Maybe' },
  { pattern: /\bNothing\b/, message: 'Nothing is deprecated; Kun uses Nil instead' },
  { pattern: /--/, message: '-- comments are deprecated; use // instead' },
  { pattern: /<-/, message: '<- bind operator is removed; use = instead' },
  { pattern: /<-!/, message: '<-! early-return operator is removed; use Cmd.<bin>? instead' },
  { pattern: /=!/, message: '=! early-return operator is removed; use Cmd.<bin>? instead' },
  { pattern: /\bwith\s+caps\b/, message: 'with caps is deprecated; use CLI --allow-path / --allow-net instead' },
  { pattern: /\bcommand\s+\w+\s+for\b/, message: 'command declaration is deprecated; use module declaration instead' },
] as const

export const COMMENT_RULES = {
  validPrefix: '//',
  invalidPrefixes: ['--', '#', '/*', '*/'],
  docCommentTriggers: ['type ', 'module ', /^\w+\s*:.*->/],
} as const

export const LITERAL_PREFIXES = ['p"', 'r"', 'f"', 'f"""'] as const

export const GENERIC_RULES = {
  separator: ' ',
  forbidden: /<[A-Z]\w*>/,
  nestedGrouping: '(',
} as const

export const FUNCTION_TYPE_RULES = {
  arrow: '->',
  curried: true,
  tupleParam: /^\(.*,\s*.*\).*->/,
} as const

export const LAMBDA_SYNTAX = {
  prefix: '\\',
  arrow: '->',
  paramsSeparator: ' ',
} as const

export const FUNCTION_APPLICATION = {
  separator: ' ',
  noCommas: true,
} as const

export const LET_IN_RULES = {
  letOnNewLine: true,
  inOnNewLine: true,
  notOnSameLineAsEquals: true,
} as const

export const CASE_OF_RULES = {
  ofOnNewLine: true,
  eachBranchOnNewLine: true,
} as const

export const IF_THEN_ELSE_RULES = {
  ifOnNewLine: true,
  elseOnNewLine: true,
  elseRequired: true,
  expression: true,
} as const

export const DO_RULES = {
  doOnNewLine: true,
  inOnNewLine: true,
  effectInDoBlock: true,
} as const

export const RECORD_RULES = {
  accessOperator: '.',
  updateSyntax: /^\s*\{\s*\w+\s*\|/,
  fieldSeparator: ',',
  spreadOperator: '..',
} as const

export const PIPE_RULES = {
  pipeOperator: '|>',
  reversePipe: '<|',
  eachOnNewLine: true,
} as const

export const IMPORT_EXPORT_RULES = {
  exportDeclaration: /^export\s*\([^)]*\)/,
  importStyles: ['as', '(..)', '(...)'],
} as const

export const EXECUTABLE_SCRIPT_RULES = {
  mainSignature: 'List String -> Unit',
  allowOmittedSignature: true,
  noModuleDeclaration: true,
} as const

export const NAMING_RULES = {
  typeNamePattern: /^[A-Z][a-zA-Z0-9']*$/,
  typeVariablePattern: /^[a-z][a-zA-Z0-9']*$/,
  functionPattern: /^[a-z_][a-zA-Z0-9_']*$/,
  modulePattern: /^[A-Z][a-zA-Z0-9']*$/,
} as const

export const DECLARATION_ORDER_RULES = {
  exportFirst: true,
  importAfterExport: true,
  exportPattern: /^export\s*\(/,
  importPattern: /^import\s+\w+/,
} as const

export function isTypeName(name: string): boolean {
  return NAMING_RULES.typeNamePattern.test(name)
}

export function isTypeVariable(name: string): boolean {
  return NAMING_RULES.typeVariablePattern.test(name)
}

export function isBuiltinType(name: string): boolean {
  return (BUILTIN_TYPES as readonly string[]).includes(name)
}

export type Keyword = (typeof KEYWORDS)[number]
export type BuiltinType = (typeof BUILTIN_TYPES)[number]
