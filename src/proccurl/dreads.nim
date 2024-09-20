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
    let aren = createShared(ReqRes, MAX_ITEMS)
  
    let ctx =  initContext()
  
    for i in 0..<MAX_ITEMS:
      args[i][] = getMonoTime().ticks

      aren[i][] = ReqRes(
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



when defined debugDreads:
  var lastId: Atomic[int]
  lastId.store 0

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
    NEW,           ## ReqRes is new
    ENQUEUED,      ## ReqRes was sent to alt queue to be sent later
    SENT,          ## ReqRes was sent to thread to work
    WIP,           ## thread is working on ReqRes
    DONE,          ## thread completed ReqRes work

  ReqRes* = object
    stat*: Atomic[RStat]
    args*: pointer
    res*:  pointer
    req*:  proc (args, res: pointer) {.nimcall, gcsafe.}
 

  WorkerThread = object
    ## When we are unsure about the state of thread
    ## This object should be single thread
    ## but hold shared info like stat and task
    stat: Atomic[int]   ## thread status
    reqRes: Option[ptr ReqRes]  ## thread task/response

  SharedWorker = ptr WorkerThread

proc `=copy`(dest: var ReqRes; o: ReqRes) {.error.}=
  discard

using
  thr: ptr WorkerThread

proc initSharedWorker(thr): void =
  ## Create a new thread with unknown status
  thr[].stat.store TDONE.int.static


proc invoke(thr): int =
  ## Execute the task
  ## Return false if thread was available
  result = TTODO.int.static
  if thr[].stat.compareExchange(result, TWIP.int.static, moAcquire, moRelaxed):
    try:
      if thr[].reqRes.isSome:
        thr[].reqRes.get.stat.store(WIP)
        thr[].reqRes.get.req(
          thr[].reqRes.get.args,
          thr[].reqRes.get.res)
    finally:
      var expected = TWIP.int.static
      doAssert thr[].stat.compareExchange(expected, TDONE.int.static, moRelease, moRelaxed)
      if thr[].reqRes.isSome:
        thr[].reqRes.get.stat.store(DONE)


proc schedule(thr; reqRes: sink Option[ptr ReqRes]): Option[ptr ReqRes] =
  var expected = TDONE.int.static
  if not thr[].stat.compareExchange(expected, TTAKEN.int.static, moAcquire, moRelaxed):
    return reqRes

  result = none[ptr ReqRes]()
  try:
    reqRes.get.stat.store SENT
    thr.reqRes = reqRes
  finally:
    expected = TTAKEN.int.static
    const desired = TTODO.int.static
    doAssert thr[].stat.compareExchange(expected, desired, moRelease, moRelaxed)


proc scheduleDie(thr): bool =
  var expected = TDONE.int.static
  const desired = TTAKEN.int.static
  result = thr[].stat.compareExchange(expected, desired, moAcquire, moRelaxed)
  if result:
    thr[].stat.store TDIE.int.static


import ./lockedqueue


type
  WorkerQueue = SharedQueue[SharedWorker]
  TaskQueue = SharedQueue[ptr ReqRes]
  Context* = object
    t:   MonoTime
    q:   WorkerQueue
    tq:  TaskQueue
    thr: ptr Thread[ptr Context]
    numThreads: ptr Atomic[int]
    minThreads: int
    maxThreads: int


template whileJoin*(ctx: ptr Context; op: untyped): void =
  ctx.tq.stop
  while ctx.numThreads[].load > 0:
    op
  freeShared ctx.thr
  freeShared ctx.numThreads
  freeShared ctx.q
  freeShared ctx

converter threads(ctx: ptr Context): WorkerQueue = ctx.q

# converter thread(ctx: ptr Context): ptr Thread[ptr Context] = ctx.thr

converter tasks(ctx: ptr Context): TaskQueue = ctx.tq

proc dup(ctx: ptr Context; thr: ptr Thread[ptr Context]): ptr Context =
  result = createShared(Context)
  result.t = getMonoTime()
  result.q = ctx.q
  result.tq  = ctx.tq
  result.thr = thr
  result.numThreads = ctx.numThreads
  result.minThreads = ctx.minThreads
  result.maxThreads = ctx.maxThreads


proc schedule(q: WorkerQueue; reqRes: sink Option[ptr ReqRes]): Option[ptr ReqRes] =
  ## Because task cannot have copies
  ## Returns the reqRes if no thread is available
  ## Returns none(ReqRes) if operation succeed
  result = reqRes
  if result.isSome:
    if q.len > 0 and not q.isBusy:
      let optThr = q.dequeueLast
      if optThr.isSome:
        while result.isSome:
          result = optThr.get.schedule result
          if result.isSome:
            spin()


proc schedule(q: TaskQueue; reqRes: sink Option[ptr ReqRes]): Option[ptr ReqRes] =
  ## Because task cannot have copies
  ## Returns the reqRes if task queue is unavailable
  ## Returns none(ReqRes) if operation succeed
  result = reqRes
  if result.isSome:
    result.get.stat.store ENQUEUED
    result = q.enqueue result
    if result.isSome:
      result.get.stat.store NEW


proc schedule*(ctx: ptr Context; reqRes: sink Option[ptr ReqRes]): Option[ptr ReqRes] =
  result = ctx.threads.schedule reqRes
  if result.isSome:
    result = ctx.tasks.schedule result


proc schedule*(ctx: ptr Context; reqRes: ptr ReqRes): bool =
  ctx.schedule(reqRes.some).isNone


template whileSchedule*(ctx: ptr Context; v: sink Option[ptr ReqRes]; op: untyped): void =
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


proc taskRunner(ctx: ptr Context) {.thread.} =
  var myInit = getMonoTime()
  let myCost = (myInit - ctx.t).inNanoSeconds
  when defined debugDreads: debugEcho getThreadId(), " begin"

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
      myInit = getMonoTime()
      continue

    # spin my creation cost
    if (getMonoTime() - myInit).inNanoSeconds < myCost:
      spin()
      continue

    # spin more because someone is almost scheduling a task
    if oldStat == TTAKEN.int.static:
      spin()
      continue

    if oldStat == TDONE.int.static and ctx.tq.blocked and ctx.q.len == 0:
      break

    sleep()
    myInit = getMonoTime()

  when defined debugDreads: debugEcho getThreadId(), " end"

  defer:
    ctx.numThreads[].atomicDec
    ctx.thr.freeShared
    ctx.freeShared
    self.freeShared


proc threadManager(ctx: ptr Context) {.thread.} =
  var myInit = getMonoTime()
  let myCost = (myInit - ctx.t).inNanoSeconds
  var reqRes = none[ptr ReqRes]()
  while ctx.tasks.len > 0 or not(ctx.tasks.blocked):
    # Create more threads if resource len is too low
    if ctx.threads.len < ctx.minThreads and ctx.threads.len < ctx.maxThreads:
      ctx.numThreads[].atomicInc
      when defined debugDreads: debugEcho getThreadId(), " scaling up ", ctx.q[].len
      let t = createShared Thread[ptr Context]
      createThread t[], taskRunner, ctx.dup t

    if reqRes.isNone and ctx.tasks.len > 0 and not ctx.tq.isBusy:
      reqRes = ctx.tasks.dequeue
    
    if reqRes.isSome and ctx.threads.len > 0 and not ctx.q.isBusy:
      reqRes = ctx.schedule reqRes
      continue

    # too many threads, scaling down
    if ctx.tasks.len == 0 and ctx.threads.len > ctx.minThreads:
      # spin my creation cost
      if (getMonoTime() - myInit).inNanoSeconds < myCost:
        continue

      spin(20.us)
      myInit = getMonoTime()
      
      if ctx.tasks.len == 0 and ctx.threads.len > ctx.minThreads:
        discard ctx.q.scheduleDie
        when defined debugDreads: debugEcho getThreadId(), " scaling down ", ctx.q.len

    spin 100.ns


  while ctx.tasks.len > 0:
    if reqRes.isNone:
      reqRes = ctx.tasks.dequeue
  
    if reqRes.isSome:
      reqRes = ctx.threads.schedule reqRes
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
  result.t = getMonoTime()
  result.q = createShared(QueueResource[SharedWorker])
  result.tq = createShared(QueueResource[ptr ReqRes])
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

