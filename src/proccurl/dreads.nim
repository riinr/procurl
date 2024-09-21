import std/[atomics, monotimes, options, times, typedthreads]
import ./sleez

runnableExamples:
  import proccurl/[ptrmath]
  import std/[monotimes, options]

  const MAX_ITEMS = 10
  
  proc helloWorld(args, res: pointer): void =
    cast[ptr int64](res)[] = getMonoTime().ticks - cast[ptr int64](args)[]
  
  
  proc main(): void =
    let args = createShared(int64,  MAX_ITEMS)
    let resp = createShared(int64,  MAX_ITEMS)
    let aren = createShared(TaskObj, MAX_ITEMS)
  
    let ctx =  initContext()
  
    for i in 0..<MAX_ITEMS:
      args[i] = getMonoTime().ticks

      aren[i] = TaskObj(
        args: args[i],
        res:  resp[i],
        req:  helloWorld,
      )
  
      ctx.whileSchedule aren[i].some:
        cpuRelax()
  
    ctx.whileJoin:
      cpuRelax()

    for i in 0..<MAX_ITEMS:
      echo i, ": ", resp[0][]
  
  main()


type
  TStat = enum
    ## STATE MACHINE: DONE -> TAKEN -> TO DO -> RUNNING -> DONE
    TDONE,  ## thread is free to work
    TTAKEN, ## thread was taken by someone
    TTODO,  ## thread has task to run
    TWIP,   ## thread is running the task
    TDIE,   ## thread must be finished
   
  RStat* = enum
    ## STATE MACHINE: DONE -> TAKEN -> TO DO -> RUNNING -> DONE
    NEW,           ## Task is new
    ENQUEUED,      ## Task was sent to alt queue to be sent later
    SENT,          ## Task was sent to thread to work
    WIP,           ## thread is working on Task
    DONE,          ## thread completed Task work

  TaskObj* = object
    stat*: Atomic[RStat]
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
  Context* = object
    t:   int64
    q:   WorkerQueue
    tq:  TaskQueue
    thr: ptr Thread[ptr Context]
    numThreads: ptr Atomic[int]
    minThreads: int
    maxThreads: int

using ctx: ptr Context


template whileJoin*(ctx; op: untyped): void =
  ctx.tq.stop
  while ctx.numThreads[].load > 0:
    op
  freeShared ctx.thr
  freeShared ctx.numThreads
  freeShared ctx.q
  freeShared ctx

converter threads(ctx): WorkerQueue = ctx.q

converter tasks(ctx): TaskQueue = ctx.tq

proc dup(ctx; thr: ptr Thread[ptr Context]): ptr Context =
  result = createShared(Context)
  result.t = getMonoTime().ticks
  result.q = ctx.q
  result.tq  = ctx.tq
  result.thr = thr
  result.numThreads = ctx.numThreads
  result.minThreads = ctx.minThreads
  result.maxThreads = ctx.maxThreads


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


proc schedule*(ctx; task: sink Option[Task]): Option[Task] =
  result = ctx.threads.schedule task
  if result.isSome:
    result = ctx.tasks.schedule result


proc schedule*(ctx; task: Task): bool =
  ctx.schedule(task.some).isNone


template whileSchedule*(ctx; v: sink Option[Task]; op: untyped): void =
  var vv = v
  while vv.isSome and not ctx.tq.blocked:
    if not(ctx.q.isBusy) and not(ctx.threads.len == 0):
      vv = ctx.schedule vv
    if vv.isSome:
      op
      spin 10.ns

proc scheduleDie*(q: WorkerQueue): bool =
  let optT = q.dequeue
  result = optT.isSome
  if result:
    let thr = optT.get
    while not thr.scheduleDie:
      spin()


proc taskRunner(ctx) {.thread.} =
  var myInit = getMonoTime().ticks
  let myCost = myInit - ctx.t

  let self = createShared(WorkerThread)
  self.initSharedWorker

  # Enqueue this thread as resource
  ctx.q.whileEnqueue some self:
    spin()

  var oldStat = -1
  while true:
    cpuRelax()

    oldStat = self.invoke

    if oldStat == TDIE.int.static:
      break

    # Enequeue this thread back
    if oldStat == TTODO.int.static:
      ctx.q.whileEnqueue self.some:
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

    if oldStat == TDONE.int.static and ctx.tq.blocked and ctx.q.len == 0:
      break

    sleep()
    myInit = getMonoTime().ticks

  defer:
    ctx.numThreads[].atomicDec
    ctx.thr.freeShared
    ctx.freeShared
    self.freeShared


proc threadManager(ctx) {.thread.} =
  var myInit = getMonoTime().ticks
  let myCost = myInit - ctx.t
  var task = none[Task]()
  while ctx.tasks.len > 0 or not ctx.tasks.blocked:
    # Create more threads if resource len is too low
    if ctx.threads.len < ctx.minThreads and ctx.numThreads[].load(moRelaxed) < ctx.maxThreads:
      ctx.numThreads[].atomicInc
      let t = createShared Thread[ptr Context]
      createThread t[], taskRunner, ctx.dup t

    if task.isNone:
      task = ctx.tasks.dequeue
    
    if task.isSome:
      task = ctx.schedule task
      continue

    # too many threads, scaling down
    if ctx.tasks.len == 0 and ctx.threads.len > ctx.minThreads:
      # spin my creation cost
      if getMonoTime().ticks - myInit < myCost:
        continue

      spin(20.us)
      myInit = getMonoTime().ticks
      
      if ctx.tasks.len == 0 and ctx.threads.len > ctx.minThreads:
        discard ctx.q.scheduleDie

    spin 100.ns


  while ctx.tasks.len > 0:
    if task.isNone:
      task = ctx.tasks.dequeue
  
    if task.isSome:
      task = ctx.threads.schedule task
    spin()

  
  while ctx.numThreads[].load > 1:
    discard ctx.q.scheduleDie
    spin()

  ctx.numThreads[].atomicDec


proc initContext*(minThreads: int = 4; maxThreads: int = 6): ptr Context {.discardable.} =
  ## Init a thread pool of minThreads up to maxThreads
  ##
  ## `minThreads` is the minimum free threads system starts to creating a more thread.
  ##
  ## `maxThreads` is the maximum free threads system starts to finishing threads.
  ##
  ## Must be +1 greater than `minThreads`. 
  ##
  ## Usually it keeps `minThreads` running.


  assert minThreads + 1 < maxThreads, "maxThreads must be greater than minThreads + 1"
  result = createShared(Context)
  result.t = getMonoTime().ticks
  result.q = createShared(QueueResource[SharedWorker])
  result.tq = createShared(QueueResource[Task])
  result.thr = createShared(Thread[ptr Context])
  result.numThreads = createShared(Atomic[int])
  result.minThreads = minThreads
  result.maxThreads = maxThreads
  result.numThreads[].store 1
  createThread(
    result.thr[],
    threadManager,
    result,
  )

