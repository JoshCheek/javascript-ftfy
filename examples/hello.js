// No time has passed since we started
showTime()  // => 0 ms

setTimeout(() => {
  showTime()  // => 12 ms
  setTimeout(20)
  showTime()  // => 33 ms
}, 10)

showTime()  // => 0 ms
showVersion()  // => "JavaScript" version l.o.l aka "JoshuaScript" aka "JS... FTFY"
