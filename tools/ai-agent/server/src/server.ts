import {
  createConnection,
  ProposedFeatures,
  TextDocuments,
  InitializeParams,
  InitializeResult,
  CompletionItem,
  CompletionItemKind,
  Hover,
  TextDocumentSyncKind,
  DocumentFormattingParams,
  TextEdit,
  Diagnostic,
  DiagnosticSeverity,
  Position,
} from 'vscode-languageserver/node'
import { TextDocument } from 'vscode-languageserver-textdocument'

import { DocumentManager, KunDocument } from './documents'
import { getDiagnostics } from './diagnostics'
import { getCompletions } from './completion'
import { getHoverInfo } from './hover'
import { formatDocument } from './formatting'

export function startServer(): void {
  const connection = createConnection(ProposedFeatures.all)
  const documents = new TextDocuments(TextDocument)
  const docManager = new DocumentManager()

  connection.onInitialize((params: InitializeParams): InitializeResult => {
    return {
      capabilities: {
        textDocumentSync: TextDocumentSyncKind.Incremental,
        completionProvider: {
          triggerCharacters: ['.', '/', '"'],
        },
        hoverProvider: true,
        documentFormattingProvider: true,
        diagnosticProvider: {
          interFileDependencies: false,
          workspaceDiagnostics: false,
        },
      },
    }
  })

  async function validate(document: TextDocument): Promise<void> {
    const kunDoc = docManager.updateDocument(document)
    if (!kunDoc) return
    const diagnostics = getDiagnostics(kunDoc)
    connection.sendDiagnostics({ uri: document.uri, diagnostics })
  }

  documents.onDidChangeContent(change => {
    void validate(change.document)
  })

  documents.onDidOpen(change => {
    void validate(change.document)
  })

  documents.onDidClose(change => {
    docManager.removeDocument(change.document.uri)
  })

  connection.onCompletion((params): CompletionItem[] => {
    const document = documents.get(params.textDocument.uri)
    if (!document) return []
    const kunDoc = docManager.getDocument(document.uri)
    if (!kunDoc) return []
    return getCompletions(kunDoc, params.position)
  })

  connection.onHover((params): Hover | null => {
    const document = documents.get(params.textDocument.uri)
    if (!document) return null
    const kunDoc = docManager.getDocument(document.uri)
    if (!kunDoc) return null
    return getHoverInfo(kunDoc, params.position)
  })

  connection.onDocumentFormatting((params: DocumentFormattingParams): TextEdit[] => {
    const document = documents.get(params.textDocument.uri)
    if (!document) return []
    return formatDocument(document)
  })

  documents.listen(connection)
  connection.listen()
}
