import * as vscode from 'vscode'
import { startClient } from './client'

let client: ReturnType<typeof startClient> | null = null

export function activate(context: vscode.ExtensionContext): void {
  client = startClient(context)

  const restartCommand = vscode.commands.registerCommand('kun.restartLsp', () => {
    if (client) {
      client.stop().then(() => {
        client = startClient(context)
      })
    }
  })

  context.subscriptions.push(restartCommand)
}

export function deactivate(): Thenable<void> | undefined {
  return client?.stop()
}
