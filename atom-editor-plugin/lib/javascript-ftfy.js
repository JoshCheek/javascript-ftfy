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
      'JavaScript FTFY:annotate-document': () => this.annotate(true),
      'JavaScript FTFY:clear-annotations': () => this.clear(),
      'JavaScript FTFY:annotate-printed':  () => this.annotate(false),
    }))
  },

  deactivate() {
    this.subscriptions.dispose()
  },

  annotate(allLines) {
    const editor = atom.workspace.getActiveTextEditor()
    if(!editor) return
    const buffer = editor.buffer
    if(!buffer) return
    const jsPath = path.resolve(__dirname, '../../bin/joshuascript')
    const args   = []
    if(allLines)
      args.push('-a')
    console.log("ARGS", args)
    const js = spawn(jsPath, args)
    buffer.replace(/ *\/\/ => .*$/g, '')

    const seen = []
    const rl = createInterface({input: js.stdout})
    let lineLen = buffer.getLines().map(l => l.length).reduce((a,b) => a < b ? b : a, 0)
    if(lineLen > 55)
      lineLen = 40 // don't put all the annotations after really long lines

    rl.on('line', line => {
      const [lineno, result] = JSON.parse(line)
      const rowno = lineno-1
      const colno = buffer.lineLengthForRow(rowno)
      let   text  = ''
      if (!seen[rowno]) {
        seen[rowno] = true
        const paddingSize = lineLen - buffer.lineLengthForRow(rowno)
        for(let i = 0; i < paddingSize; ++i)
          text += ' '
        text += `  // => ${result}`
      } else {
        text = `, ${result}`
      }
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
