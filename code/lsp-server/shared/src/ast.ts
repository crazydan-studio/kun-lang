export type Position = {
  line: number
  character: number
}

export type Range = {
  start: Position
  end: Position
}

export type Comment = {
  range: Range
  text: string
  isDocComment: boolean
}

export type LiteralType =
  | 'Int' | 'Float' | 'Bool' | 'String'
  | 'Bytes' | 'Char' | 'Regex' | 'Duration'
  | 'Path'

export type Literal = {
  range: Range
  type: LiteralType
  prefix?: 'p' | 'r' | 'f' | 'f"""'
  value: string
}

export type TypeAnnotation = {
  range: Range
  name: string
  typeExpr: TypeExpr
}

export type TypeExpr =
  | { kind: 'name'; name: string; range: Range }
  | { kind: 'apply'; constructor: TypeExpr; args: TypeExpr[]; range: Range }
  | { kind: 'function'; param: TypeExpr; result: TypeExpr; range: Range }
  | { kind: 'record'; fields: RecordFieldType[]; range: Range }
  | { kind: 'nilable'; inner: TypeExpr; range: Range }
  | { kind: 'tuple'; elements: TypeExpr[]; range: Range }
  | { kind: 'paren'; inner: TypeExpr; range: Range }

export type RecordFieldType = {
  name: string
  typeExpr: TypeExpr
}

export type Pattern =
  | { kind: 'variable'; name: string; range: Range }
  | { kind: 'wildcard'; range: Range }
  | { kind: 'literal'; value: string; range: Range }
  | { kind: 'variant'; name: string; args: Pattern[]; range: Range }
  | { kind: 'tuple'; elements: Pattern[]; range: Range }
  | { kind: 'record'; fields: RecordPatternField[]; spread?: string; range: Range }
  | { kind: 'list'; elements: Pattern[]; rest?: string; range: Range }
  | { kind: 'alias'; pattern: Pattern; alias: string; range: Range }
  | { kind: 'guard'; pattern: Pattern; condition: string; range: Range }

export type RecordPatternField = {
  name: string
  alias?: string
  literal?: string
}

export type Expr =
  | { kind: 'literal'; literal: Literal; range: Range }
  | { kind: 'variable'; name: string; range: Range }
  | { kind: 'function'; name: string; params: string[]; body: Expr; range: Range }
  | { kind: 'lambda'; params: Pattern[]; body: Expr; range: Range }
  | { kind: 'apply'; func: Expr; arg: Expr; range: Range }
  | { kind: 'let'; bindings: Binding[]; body: Expr; range: Range }
  | { kind: 'case'; expr: Expr; branches: CaseBranch[]; range: Range }
  | { kind: 'if'; condition: Expr; thenBranch: Expr; elseBranch: Expr; range: Range }
  | { kind: 'do'; steps: DoStep[]; result?: Expr; range: Range }
  | { kind: 'defer'; expr: Expr; range: Range }
  | { kind: 'pipe'; expr: Expr; steps: PipeStep[]; range: Range }
  | { kind: 'record'; fields: RecordField[]; spread?: string; range: Range }
  | { kind: 'recordAccess'; record: Expr; field: string; range: Range }
  | { kind: 'recordUpdate'; record: Expr; fields: RecordField[]; range: Range }
  | { kind: 'list'; elements: ListElement[]; range: Range }
  | { kind: 'tuple'; elements: Expr[]; range: Range }
  | { kind: 'map'; entries: MapEntry[]; range: Range }
  | { kind: 'set'; elements: Expr[]; range: Range }
  | { kind: 'range'; start: Expr; end: Expr; range: Range }
  | { kind: 'binary'; operator: BinaryOp; left: Expr; right: Expr; range: Range }
  | { kind: 'unary'; operator: UnaryOp; operand: Expr; range: Range }
  | { kind: 'ternary'; condition: Expr; thenExpr: Expr; elseExpr: Expr; range: Range }
  | { kind: 'nilCoalesce'; left: Expr; right: Expr; range: Range }
  | { kind: 'optionalChain'; target: Expr; func: Expr; range: Range }
  | { kind: 'indexAccess'; target: Expr; index: Expr; range: Range }
  | { kind: 'fieldShorthand'; field: string; range: Range }
  | { kind: 'cmdBracket'; name: string; range: Range }
  | { kind: 'exportDecl'; symbols: string[]; range: Range }

export type Binding = {
  pattern: Pattern
  expr: Expr
  range: Range
  typeAnnotation?: TypeAnnotation
}

export type CaseBranch = {
  pattern: Pattern
  guard?: Expr
  body: Expr
  range: Range
}

export type DoStep =
  | { kind: 'bind'; pattern: Pattern; expr: Expr; range: Range }
  | { kind: 'expr'; expr: Expr; range: Range }
  | { kind: 'defer'; expr: Expr; range: Range }

export type PipeStep = {
  func: Expr
  range: Range
}

export type RecordField = {
  name: string
  value: Expr
  range: Range
}

export type MapEntry = {
  key: Expr
  value: Expr
  range: Range
}

export type ListElement =
  | { kind: 'expr'; expr: Expr; range: Range }
  | { kind: 'spread'; expr: Expr; range: Range }

export type BinaryOp =
  | '+' | '-' | '*' | '/' | '%' | '++'
  | '==' | '/=' | '<' | '>' | '<=' | '>='
  | '&&' | '||'
  | '>>' | '<<'

export type UnaryOp = '-' | 'not'

export type TopLevelDecl = {
  kind: 'typeDecl' | 'functionDecl'
  | 'importDecl' | 'exportDecl' | 'expression'
  range: Range
  name?: string
  typeAnnotation?: TypeAnnotation
  expr?: Expr
  exportSymbols?: string[]  // for exportDecl: exported symbol names
}

export type KunDocument = {
  uri: string
  declarations: TopLevelDecl[]
  comments: Comment[]
  text: string
  lines: string[]
}
