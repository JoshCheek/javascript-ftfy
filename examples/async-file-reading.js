import {readFile} from 'fs'                // => "fs"
let val = 0                                // => 0

setTimeout(() => ++val, 0)                 // => null

val                                        // => 0
const body = readFile("/tmp/hw", 'utf-8')  // => "hello world\n"
val                                        // => 1
body                                       // => "hello world\n"
