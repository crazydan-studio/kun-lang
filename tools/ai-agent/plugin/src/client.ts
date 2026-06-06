import * as path from 'path'
import * as vscode from 'vscode'
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from 'vscode-languageclient/node'

let client: LanguageClient | null = null

export function startClient(context: vscode.ExtensionContext): LanguageClient {
  const serverModule = context.asAbsolutePath(
    path.join('..', 'server', 'out', 'index.js'),
  )

  const serverOptions: ServerOptions = {
    run: {
      module: serverModule,
      transport: TransportKind.ipc,
    },
    debug: {
      module: serverModule,
      transport: TransportKind.ipc,
      options: { execArgv: ['--nolazy', '--inspect=6009'] },
    },
  }

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: 'file', language: 'kun' }],
    synchronize: {
      fileEvents: vscode.workspace.createFileSystemWatcher('**/*.kun'),
    },
  }

  client = new LanguageClient(
    'kunLsp',
    'Kun Language Server',
    serverOptions,
    clientOptions,
  )

  client.start()
  return client
}
