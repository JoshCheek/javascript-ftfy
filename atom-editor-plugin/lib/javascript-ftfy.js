'use babel'
import path from 'path'
import { spawn } from 'child_process'
import { CompositeDisposable, Point } from 'atom'

export default {
  subscriptions: null,

  activate(state) {
    this.subscriptions = new CompositeDisposable()
    this.subscriptions.add(atom.commands.add('atom-workspace', {
      'JavaScript FTFY:annotate-document': () => this.annotate()
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
    let stdout = ''
    let stderr = ''
    js.stdout.on('data', output => stdout += output)
    js.stderr.on('data', output => stderr += output)
    js.on('close', status => {
      buffer.replace(/ *\/\/ => .*$/g, '')
      if (status == 0)
        stdout.split("\n")
              .filter(line => line.length)
              .map(line => JSON.parse(line))
              .forEach(([lineno, result]) => {
                 const rowno = lineno-1
                 const colno = buffer.lineLengthForRow(rowno)
                 buffer.insert(new Point(rowno, colno), `  // => ${result}`)
              })
      else
        atom.notifications.addError(stderr) // to persist the errors, add: {dismissable: true}
    })
    js.stdin.write(editor.getText())
    js.stdin.end()
  },
}
