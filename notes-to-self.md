Acorn: potential alternate parser
---------------------------------

So far, it looks like it has the same context sensitive nodes that Esprima has, though :(

```sh
node -e '
   const acorn = require("acorn")
   console.log(JSON.stringify(
     acorn.parse(
       `import fs from "fs"
       fs.readFile("someFile.whatev", "utf-8", (err, body) => console.log(body))
      `, {
        ecmaVersion: 9,
        allowImportExportEverywhere: true,
        // sourceFile: "myTest1.js",       // adds a "source" key to location
        // locations: true,                // same as esprima\'s
        // ranges: true,                   // useful for retrieving the source syntax of the node
        // directSourceFile: "myTest2.js", // adds a "sourceFile" key to the node, ie it\'s sourceFile, but without requiring "locations" to be set
     })
   ))'  | jq .body[0]
```

Tokenizing:

```sh
node -e '
   const acorn = require("acorn")
   for (let token of acorn.tokenizer("{a:1}; const b = 1 + getSomething()")) {
     console.log(JSON.stringify(token))
   }' | jq -c .
```

It has a lot of [tests](https://github.com/acornjs/acorn/blob/4570cc7d07ac850a24f4eec9a7d045ac3112d93a/test/tests.js)
that we could steal, if we wanted to write our own parser instead. Eg this would
allow us to fix stupid shit like `{a:1}` parsing to a label in a block.

