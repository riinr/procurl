import std/[atomics, monotimes, options, times, typedthreads]
import ./sleez

##
## This is a thread pool, managed by ThreadManager (a different thread).
##
## If pool has less threads than minThreads (default is 4), ThreadManager will 
## create new WorkerThread, unless there already maxThreads (default is 8) of 
## WorkerThreads.
##
## In most cases we dequeue a WorkerThread from pool and assign a task to it.
##
## If the pool is empty or busy, we add it to a task queue. The task will be later
## dequeued by the ThreadManager and assigned to a thread.
##
## If task queue is empty, and there are more threads in the pool than minThreads,
## ThreadManager will scale down to minThreads.
##
## The main objective of this scruture is reduce the amount of lock in shared
## objects per tasks, but it uses spin locks, spin locks are faster 
## 
## See the [diagram](https://coggle.it/diagram/ZtfGyMrvLIwlVhbU/t/main/2c837d2373a0dba51611b9ca5e2d1d687705477db3c60848b6519fe4dd430dae)
##
## See bench/dreads.nim for example.
##

runnableExamples:
  import proccurl/[ptrmath]
  import std/[monotimes, options]

  const MAX_ITEMS = 10
 
  # function to run in the thread
  proc helloWorld(args, res: pointer): void =
    # Read argument
    #              -- arg --        #
    let arg = cast[ptr int64](args)[]
    # Write to response
    #    -- res --                                   #
    cast[ptr int64](res)[] = getMonoTime().ticks - arg

  # Example with single schedule
  proc singleExample(pool: ptr Pool): void =
    # make room for shared data
    let arg:  ptr int64   = createShared(int64)
    let res:  ptr int64   = createShared(int64)
    let task: ptr TaskObj = createShared(TaskObj)

    # init argument 
    arg[] = getMonoTime().ticks

    # create a taskObj
    task[] = TaskObj(
      args: arg,
      res:  res,
      req:  helloWorld,
    )
 
    # schedule this task
    pool.whileSchedule task.some:
      # do something else if task isn't scheduled
      cpuRelax()

    # wait until the task complete
    waitTask task:
      # do something else if task isn't done
      cpuRelax()

    # do something with result
    assert task.isDone, "Task not DONE but " & $task.stat
    echo "Res: ", res[]

    # free resources before we left the function
    defer:
      freeShared res
      freeShared arg
      freeShared task
  
  # example with array 
  proc arrayExample(pool: ptr Pool): void =
    # make room for shared data
    let args = createShared(int64,   MAX_ITEMS)
    let resp = createShared(int64,   MAX_ITEMS)
    let tasks = createShared(TaskObj, MAX_ITEMS)

    # schedule the tasks
    for i in 0..<MAX_ITEMS:
      args[i] = getMonoTime().ticks

      tasks[i] = TaskObj(
        args: args[i],
        res:  resp[i],
        req:  helloWorld,
      )
  
      pool.whileSchedule tasks[i].some:
        cpuRelax()

    # wait all tasks to complete
    for i in 0..<MAX_ITEMS:
      waitTask tasks[i]:
        cpuRelax()
  
    # do something with result
    for i in 0..<MAX_ITEMS:
      assert tasks[i].isDone, "Task " & $i & " not DONE but " & $tasks[i].stat
      echo i, ": ", resp[0][]

    # free resources before we left the function
    defer:
      freeShared resp
      freeShared args
      freeShared tasks

  # async example
  import std/[asyncfutures, asyncdispatch]

  proc asyncExample(pool: ptr Pool): Future[int64] {.async.} =
    # make room for shared data
    let arg:  ptr int64   = createShared(int64)
    let res:  ptr int64   = createShared(int64)
    let task: ptr TaskObj = createShared(TaskObj)

    # free resources before we left the function
    defer:
      freeShared res
      freeShared arg
      freeShared task

    # init argument 
    arg[] = getMonoTime().ticks

    # create a taskObj
    task[] = TaskObj(
      args: arg,
      res:  res,
      req:  helloWorld,
    )
 
    # schedule this task
    pool.whileSchedule task.some:
      # return control to asyncdispatch
      await sleepAsync(0)

    # wait until the task complete
    waitTask task:
      # return control to asyncdispatch
      echo getMonoTime().ticks - arg[]
      await sleepAsync(0)
      echo getMonoTime().ticks - arg[]

    # do something with result
    return res[]

 
  proc main(): void =
    # init the pool
    let pool: ptr Pool =  newPool()

    arrayExample pool
    singleExample pool
    echo "Async: ", waitFor asyncExample(pool)

    # free resources before we left the function
    defer:
      # wait all threads to die
      pool.whileJoin:
        cpuRelax()
      freePool pool

  main()


type
  ThStat = enum
    ## STATE MACHINE: DONE -> TAKEN -> TO DO -> RUNNING -> DONE
    TDONE,  ## thread is free to work
    TTAKEN, ## thread was taken by someone
    TTODO,  ## thread has task to run
    TWIP,   ## thread is running the task
    TDIE,   ## thread must be finished
   
  Stat* = enum
    ## STATE MACHINE: DONE -> TAKEN -> TO DO -> RUNNING -> DONE
    NEW,           ## Task is new
    ENQUEUED,      ## Task was sent to alt queue to be sent later
    SENT,          ## Task was sent to thread to work
    WIP,           ## thread is working on Task
    DONE,          ## thread completed Task work

  TaskObj* = object
    stat*: Atomic[Stat]
    args*: pointer
    res*:  pointer
    req*:  proc (args, res: pointer) {.nimcall, gcsafe.}


  Task* = ptr TaskObj
 

  WorkerThread = object
    ## When we are unsure about the state of thread
    ## This object should be single thread
    ## but hold shared info like stat and task
    stat:   Atomic[int]         ## thread status
    task: Option[Task]  ## thread task/response

  SharedWorker = ptr WorkerThread

proc `=copy`(dest: var TaskObj; o: TaskObj) {.error.}= discard


proc isDone*(task: Task): bool =
  task.stat.load(moRelaxed) == DONE


template waitTask*(task: Task; op: untyped): void =
  var stat {.inject.} = task.stat.load(moRelaxed)
  while stat != DONE:
    op
    stat = task.stat.load(moRelaxed)


using
  thr: ptr WorkerThread

template initSharedWorker(thr): void = thr[].stat.store TDONE.int.static


proc invoke(thr): int =
  ## Execute the task
  ## Return false if thread was available
  result = TTODO.int.static
  if thr.stat.compareExchange(result, TWIP.int.static, moAcquire, moRelaxed):
    try:
      if thr.task.isSome:
        var expcted = SENT
        doAssert thr.task.get.stat.compareExchange(expcted, WIP, moAcquire, moRelaxed)
        thr.task.get.req thr.task.get.args, thr.task.get.res
    finally:
      if thr.task.isSome:
        var expcted = WIP
        doAssert thr.task.get.stat.compareExchange(expcted, DONE, moRelease, moRelaxed)
      var expected = TWIP.int.static
      doAssert thr.stat.compareExchange(expected, TDONE.int.static, moRelease, moRelaxed)


proc schedule(thr; task: sink Option[Task]): Option[Task] =
  var expected = TDONE.int.static
  if task.isNone or not thr.stat.compareExchange(expected, TTAKEN.int.static, moAcquire, moRelaxed):
    return task

  result = none[Task]()
  try:
    task.get.stat.store SENT
    thr.task = task
  finally:
    expected = TTAKEN.int.static
    const desired = TTODO.int.static
    doAssert thr.stat.compareExchange(expected, desired, moRelease, moRelaxed)


proc scheduleDie(thr): bool =
  var  expected = TDONE.int.static
  const desired = TTAKEN.int.static
  result = thr.stat.compareExchange(expected, desired, moAcquire, moRelaxed)
  if result:
    thr.stat.store TDIE.int.static


import ./lockedqueue


type
  WorkerQueue = SharedQueue[SharedWorker]
  TaskQueue = SharedQueue[Task]
  Pool* = object
    t:   int64
    q:   WorkerQueue
    tq:  TaskQueue
    thr: ptr Thread[ptr Pool]
    numThreads: ptr Atomic[int]
    minThreads: int
    maxThreads: int

using pool: ptr Pool

template freePool*(pool: ptr Pool): void =
  freeShared pool.q
  freeShared pool.tq
  freeShared pool.thr
  freeShared pool.numThreads
  freeShared pool

template whileJoin*(pool; op: untyped): void =
  pool.tq.stop
  while pool.numThreads[].load > 0:
    op

converter threads(pool): WorkerQueue = pool.q

converter tasks(pool): TaskQueue = pool.tq

proc dup(pool; thr: ptr Thread[ptr Pool]): ptr Pool =
  result = createShared(Pool)
  result.t = getMonoTime().ticks
  result.q = pool.q
  result.tq  = pool.tq
  result.thr = thr
  result.numThreads = pool.numThreads
  result.minThreads = pool.minThreads
  result.maxThreads = pool.maxThreads


proc schedule(q: WorkerQueue; task: sink Option[Task]): Option[Task] =
  ## Because task cannot have copies
  ## Returns the task if no thread is available
  ## Returns none(task) if operation succeed
  result = task
  if result.isSome:
    let optThr = q.dequeueLast
    if optThr.isSome:
      while result.isSome:
        result = optThr.get.schedule result
        if result.isSome:
          spin()


proc schedule(q: TaskQueue; task: sink Option[Task]): Option[Task] =
  ## Because task cannot have copies
  ## Returns the task if task queue is unavailable
  ## Returns none(task) if operation succeed
  result = task
  if result.isSome:
    result.get.stat.store ENQUEUED
    result = q.enqueue result
    if result.isSome:
      result.get.stat.store NEW


proc schedule*(pool; task: sink Option[Task]): Option[Task] =
  result = pool.threads.schedule task
  if result.isSome:
    result = pool.tasks.schedule result


proc schedule*(pool; task: Task): bool =
  pool.schedule(task.some).isNone


template whileSchedule*(pool; v: sink Option[Task]; op: untyped): void =
  var vv = v
  while vv.isSome and not pool.tq.blocked:
    if not(pool.q.isBusy) and not(pool.q.len == 0):
      vv = pool.schedule vv
    if vv.isSome:
      op

proc scheduleDie*(q: WorkerQueue): bool =
  let optT = q.dequeue
  result = optT.isSome
  if result:
    let thr = optT.get
    while not thr.scheduleDie:
      spin()


proc taskRunner(pool) {.thread.} =
  var myInit = getMonoTime().ticks
  let myCost = myInit - pool.t

  let self = createShared(WorkerThread)
  self.initSharedWorker

  # Enqueue this thread as resource
  pool.q.whileEnqueue some self:
    spin()

  var oldStat = -1
  while true:
    cpuRelax()

    oldStat = self.invoke

    if oldStat == TDIE.int.static:
      break

    # Enequeue this thread back
    if oldStat == TTODO.int.static:
      pool.q.whileEnqueue self.some:
        spin()
      myInit = getMonoTime().ticks
      continue

    # spin my creation cost
    if getMonoTime().ticks - myInit < myCost:
      spin()
      continue

    # spin more because someone is almost scheduling a task
    if oldStat == TTAKEN.int.static:
      spin()
      continue

    if oldStat == TDONE.int.static and pool.tq.blocked and pool.q.len == 0:
      break

    sleep()
    myInit = getMonoTime().ticks

  defer:
    pool.numThreads[].atomicDec
    pool.thr.freeShared
    pool.freeShared
    self.freeShared


proc threadManager(pool) {.thread.} =
  var myInit = getMonoTime().ticks
  let myCost = myInit - pool.t
  var task = none[Task]()
  while pool.tasks.len > 0 or not pool.tasks.blocked:
    # too fewer threads, scalling up
    if pool.threads.len < pool.minThreads and pool.numThreads[].load(moRelaxed) < pool.maxThreads:
      pool.numThreads[].atomicInc
      let t = createShared Thread[ptr Pool]
      createThread t[], taskRunner, pool.dup t
      myInit = getMonoTime().ticks

    if task.isNone:
      task = pool.tasks.dequeue
    
    if task.isSome:
      task = pool.q.schedule task
      continue

    # too many threads, scalling down
    if pool.tasks.len == 0 and pool.threads.len > pool.minThreads:
      # spin my creation cost
      if getMonoTime().ticks - myInit < myCost:
        continue

      spin(20.us)
      myInit = getMonoTime().ticks
      
      if pool.tasks.len == 0 and pool.threads.len > pool.minThreads:
        discard pool.q.scheduleDie

    spin 100.ns


  while pool.tasks.len > 0:
    if task.isNone:
      task = pool.tasks.dequeue
  
    if task.isSome:
      task = pool.threads.schedule task
    spin()

  
  while pool.numThreads[].load > 1:
    discard pool.q.scheduleDie
    spin()

  defer:
    pool.numThreads[].atomicDec


proc initPool*(
  pool: ptr Pool;
  threadQueue: ptr QueueResource[SharedWorker];
  taskQueue:   ptr QueueResource[Task];
  threadMngr:  ptr Thread[ptr Pool];
  numThreads:  ptr Atomic[int];
  minThreads: int = 4;
  maxThreads: int = 8): void =
  ## Init a thread pool of minThreads up to maxThreads
  ##
  ## `minThreads` is the minimum free threads system starts to creating a more thread.
  ##
  ## `maxThreads` is the maximum free threads system starts to finishing threads.
  ##
  ## Must be +2 greater than `minThreads`. 
  ##
  ## Usually it keeps `minThreads` running.


  assert minThreads + 2 < maxThreads, "maxThreads must be greater than minThreads + 2"
  pool.t = getMonoTime().ticks
  pool.q = threadQueue
  pool.tq = taskQueue
  pool.thr = threadMngr
  pool.numThreads = numThreads
  pool.minThreads = minThreads
  pool.maxThreads = maxThreads
  pool.numThreads[].store 1
  createThread(
    threadMngr[],
    threadManager,
    pool,
  )

proc newPool*(minThreads: int = 4; maxThreads: int = 8): ptr Pool {.discardable.} =
  ## Create a thread pool of minThreads up to maxThreads
  ##
  ## `minThreads` is the minimum free threads system starts to creating a more thread.
  ##
  ## `maxThreads` is the maximum free threads system starts to finishing threads.
  ##
  ## Must be +2 greater than `minThreads`. 
  ##
  ## Usually it keeps `minThreads` running.

  result = createShared(Pool)
  initPool(
    result,
    createShared(QueueResource[SharedWorker]),
    createShared(QueueResource[Task]),
    createShared(Thread[ptr Pool]),
    createShared(Atomic[int]),
    minThreads,
    maxThreads
  )


