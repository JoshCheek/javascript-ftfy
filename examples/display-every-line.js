var a = {
  b:
   11,              // => 11
  c: function(b) {
    this.b = b      // => 2
  },                // => function(b) {\n    this.b = b\n  }
  d: "omg",         // => "omg"
  e: () => 1,       // => () => 1
}                   // => {b: 11, c: function(b) {\n    this.b = b\n  }, d: "omg", e: () => 1}

this.b = 10.1       // => 10.1
var c = a.c         // => function(b) {\n    this.b = b\n  }
this.b              // => 10.1
a.b                 // => 11
c(2)                // => 2
this.b              // => 10.1
a.b                 // => 2
"a"                 // => "a"
;[].forEach         // => function() { [native code] }
showTime            // => function() { [native code: JoshuaScript#show_time] }
