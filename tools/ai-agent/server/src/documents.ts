import { TextDocument } from 'vscode-languageserver-textdocument'
import type { KunDocument } from '@kun/lsp-shared'

export type { KunDocument }

export class DocumentManager {
  private docs = new Map<string, KunDocument>()

  getDocument(uri: string): KunDocument | undefined {
    return this.docs.get(uri)
  }

  updateDocument(document: TextDocument): KunDocument {
    const text = document.getText()
    const kunDoc: KunDocument = {
      uri: document.uri,
      text,
      lines: text.split('\n'),
      declarations: [],
      comments: [],
    }
    this.docs.set(document.uri, kunDoc)
    return kunDoc
  }

  removeDocument(uri: string): void {
    this.docs.delete(uri)
  }
}
