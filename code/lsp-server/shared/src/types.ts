export const NILABLE_RULES = {
  prefix: '?',
  multiWordBracket: true,
  noSuffix: true,
} as const

export const NAMING_CONVENTIONS = {
  typeName: { pattern: /^[A-Z]/, description: 'Type names must start with uppercase' },
  typeVariable: { pattern: /^[a-z]/, description: 'Type variables must start with lowercase' },
  functionName: { pattern: /^[a-z_]/, description: 'Function names must start with lowercase or underscore' },
} as const

export function isNilableType(typeStr: string): boolean {
  return typeStr.startsWith('?')
}

export function wouldNeedBracketForNilable(typeStr: string): boolean {
  const content = typeStr.startsWith('?') ? typeStr.slice(1) : typeStr
  return content.includes(' ') && !content.startsWith('(')
}

export function isTypeNameValid(name: string): boolean {
  return NAMING_CONVENTIONS.typeName.pattern.test(name)
}

export function isTypeVariableValid(name: string): boolean {
  return NAMING_CONVENTIONS.typeVariable.pattern.test(name)
}

export type NilableType = `?${string}`
