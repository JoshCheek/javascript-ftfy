var taskList = [
  ["task 1.1", "task 1.2"],
  ["task 2"],
  ["task 3"],
]

// These asynchronous task will run, b/c the synchronous code below is nonblocking
setTimeout(showTime,  75)  // => 79 ms
setTimeout(showTime, 150)  // => 155 ms
setTimeout(showTime, 250)  // => 251 ms

// A bunch of synchronous work that takes 200ms
taskList.forEach(tasks =>
  tasks.forEach(task => {
    setTimeout(50) // represents async task work, eg IO

    showTime()  // => 51 ms, 102 ms, 155 ms, 209 ms
    console.log(task)  // => task 1.1, task 1.2, task 2, task 3
  })
)

// This comes after the synchronous task processing code, so its time is after.
// But notice that this didn't block the thread, it was processing the timeouts
// from earlier, even while waiting on the synchronous setTimeout for each task.
//
// In other words: the callstack was paused, but it did not block the event queue.
showTime()  // => 209 ms
