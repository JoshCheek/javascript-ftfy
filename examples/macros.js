function macro$unless(bool, code) {
  console.log(`${bool}`)  // => 1 == 1, 1 == 2
  console.log(bool)       // => true, false
  console.log(`${code}`)  // => console.log("hello"), console.log("world")
  if(!bool) code
}

macro$unless(1 == 1,
  console.log("hello")
)

macro$unless(1 == 2,
  console.log("world")    // => "world"
)
