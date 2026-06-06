# Kun AI Agent LSP

Language Server Protocol (LSP) implementation for the Kun programming language, including a VS Code extension.

## Project Structure

```
tools/ai-agent/
├── package.json           # Workspace root
├── server/                # LSP server
│   ├── src/
│   │   ├── index.ts       # Entry point
│   │   ├── server.ts      # LSP server implementation
│   │   ├── documents.ts   # Document manager
│   │   ├── diagnostics.ts # Syntax & type diagnostics
│   │   ├── completion.ts  # Code completion
│   │   ├── hover.ts       # Hover information
│   │   └── formatting.ts  # Code formatting
│   ├── package.json
│   └── tsconfig.json
├── plugin/                # VS Code extension
│   ├── src/
│   │   ├── extension.ts   # Extension entry point
│   │   └── client.ts      # LSP client
│   ├── package.json
│   └── tsconfig.json
└── scripts/
    └── dev.sh             # Development build script

code/
└── lsp-shared/            # Shared library
    ├── src/
    │   ├── index.ts       # Exports
    │   ├── syntax.ts      # Syntax rules
    │   ├── types.ts       # Type system rules
    │   ├── formatter.ts   # Formatting rules
    │   └── ast.ts         # AST definitions
    ├── package.json
    └── tsconfig.json
```

## Features

### Diagnostics (Error Checking)
- **Comments**: Validates `//` style, flags `--`, `#`, `/* */`
- **Literals**: Validates `p"..."`, `r"..."`, `f"..."` prefixes
- **Generics**: Enforces space-separated generics, flags `<>`
- **Type naming**: Type names must start with uppercase
- **Semicolons**: Flags semicolons (not supported in Kun)
- **Deprecated syntax**: Flags `*rest`, `Just`, `Nothing`, `--`
- **Line length**: Warns on lines exceeding 100 characters
- **IO binding**: `<->` and `<-!` must be inside `do` blocks

### Code Formatting
- 2-space indentation
- Removes trailing whitespace
- Removes semicolons
- Fixes comment style (`--` → `//`, `#` → `//`)
- Normalizes indentation
- Ensures trailing newline

### Code Completion
- Keywords: `type`, `case`, `if`, `do`, `let`, `module`, `import`, `with`, `caps`, etc.
- Built-in types: `Int`, `String`, `Bool`, `Result`, `List`, `Stream`, `IO`, etc.
- Documentation comment templates (`///`)

### Hover Information
- Keyword documentation
- Type documentation
- Operator documentation (`=!`, `<-!`, `<-`)

## Development

### Prerequisites
- Node.js >= 18.0.0
- pnpm >= 8.0.0

### Setup

```bash
# Install dependencies
pnpm install

# Build all packages
pnpm build

# Type checking
pnpm typecheck
```

### VS Code Extension Development

1. Open the workspace root in VS Code
2. Press `F5` to launch the Extension Development Host
3. Open a `.kun` file to activate the LSP

### LSP Server (Standalone)

```bash
node tools/ai-agent/server/out/index.js
```

The server communicates over stdio using the LSP protocol.

## Package Overview

| Package | Description |
|---------|-------------|
| `@kun/lsp-shared` | Shared syntax rules, type definitions, AST structures |
| `@kun/lsp-server` | LSP server implementation |
| `@kun/vscode-plugin` | VS Code extension |

## Architecture

The LSP implementation follows a layered architecture:

1. **`@kun/lsp-shared`** — Core language rules and data structures, framework-agnostic
2. **LSP Server** — Implements the Language Server Protocol using `vscode-languageserver`
3. **VS Code Plugin** — Thin client connecting to the server via `vscode-languageclient`

This separation ensures the shared rules can be reused by other tools (e.g., a CLI linter, formatter, or code generator).
