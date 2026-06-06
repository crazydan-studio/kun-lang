# Kun Language Server (LSP)

Language Server Protocol implementation for the Kun programming language, including a VS Code extension.

## Project Structure

```
code/lsp-server/
├── shared/                # @kun-lang/shared — Syntax rules, type definitions, AST
├── server/                # @kun-lang/lsp-server — LSP server
├── plugin/                # @kun-lang/vscode-plugin — VS Code extension
├── tsconfig.base.json
└── package.json
```

## Features

- **Diagnostics**: Comment validation, deprecated syntax detection, type naming, generics checking, IO binding context, semicolon detection
- **Formatting**: 2-space indent, comment style fixes, trailing whitespace, semicolon removal
- **Completion**: Keywords, built-in types, doc comment templates
- **Hover**: Keyword/type/operator documentation

## Development

```bash
# Install dependencies (from workspace root)
pnpm install

# Build all modules
cd code/lsp-server && pnpm build

# Type check
cd code/lsp-server && pnpm typecheck

# Start LSP server standalone
cd code/lsp-server && pnpm start
```

## Build Script

`tools/dev-lsp.sh` builds all modules in the correct order.
