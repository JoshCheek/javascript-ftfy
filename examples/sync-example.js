var TASKS = [
  ["task 1.1", "task 1.2"],
  ["task 2"],
  ["task 3"],
]

function asyncWork() {
  setTimeout(50)
}

function forEach(array, cb) {
  for(var i=0; i<array.length; ++i)
    cb(array[i])
}

// this asynchronous task will run at ~75ms,
// even though it will be in the middle of waiting for the asyncWork, below!
setTimeout(() => showTime(), 75)  // => 80 ms

forEach(TASKS, tasks =>
  forEach(tasks, task => {
    asyncWork()
    showTime()  // => 55 ms, 107 ms, 160 ms, 211 ms
    console.log(task)  // => task 1.1, task 1.2, task 2, task 3
  })
)
