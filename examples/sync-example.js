var TASKS = [
  ["task 1.1", "task 1.2"],
  ["task 2"],
  ["task 3"],
]

function forEach(array, cb) {
  for(var i=0; i<array.length; ++i)
    cb(array[i])
}

// this asynchronous task will run at ~75ms,
// even though the synchronous code below will be waiting on
setTimeout(showTime, 75)  // => 77 ms

forEach(TASKS, tasks =>
  forEach(tasks, task => {
    setTimeout(50) // represents some async work, such as IO
    showTime()  // => 52 ms, 102 ms, 154 ms, 206 ms
    console.log(task)  // => task 1.1, task 1.2, task 2, task 3
  })
)
