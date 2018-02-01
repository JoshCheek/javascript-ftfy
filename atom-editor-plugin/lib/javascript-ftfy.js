'use babel'
import path from 'path'
import { spawn } from 'child_process'
import { CompositeDisposable, Point } from 'atom'
import { createInterface } from 'readline'

export default {
  subscriptions: null,

  activate(state) {
    this.subscriptions = new CompositeDisposable()
    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'JavaScript FTFY:annotate-document': () => this.annotate(),
      'JavaScript FTFY:clear-annotations': () => this.clear(),
    }))
  },

  deactivate() {
    this.subscriptions.dispose()
  },

  annotate() {
    const editor = atom.workspace.getActiveTextEditor()
    if(!editor) return
    const buffer = editor.buffer
    if(!buffer) return
    const js_path = path.resolve(__dirname, '../../bin/joshuascript')
    const js = spawn(js_path)
    buffer.replace(/ *\/\/ => .*$/g, '')

    const seen = []
    const rl = createInterface({input: js.stdout})
    rl.on('line', line => {
      const [lineno, result] = JSON.parse(line)
      const rowno = lineno-1
      const colno = buffer.lineLengthForRow(rowno)
      const text  = seen[rowno] ? `, ${result}` : `  // => ${result}`
      seen[rowno] = true
      buffer.insert(new Point(rowno, colno), text)
    })

    let stderr = ''
    js.stderr.on('data', output => stderr += output)
    js.on('close', status =>
      status && atom.notifications.addError(stderr) // to persist the errors, add: {dismissable: true}
    )
    js.stdin.write(editor.getText())
    js.stdin.end()
  },

  clear() {
    const editor = atom.workspace.getActiveTextEditor()
    const buffer = editor.buffer
    buffer && buffer.replace(/ *\/\/ => .*$/g, '')
  },
}
