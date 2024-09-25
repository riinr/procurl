## The objective of this benchmark is following:
## 1. Calculate the thread pool creation overhead
## 2. Calculate how much time is required to send/schedule 1000 tasks
##   2.1 Calculate the avg per task
## 3. With a precision of +/-100ns calculate send/schedule top:
##   3.1 
## 1. Schdule 1000 tasks
##  1.1 The task is getMonoTime

import std/[atomics, tables, monotimes, options]
import proccurl/[dreads, ptrmath, sleez]

type
  Perc* = object
    tot: int
    part: int

  Pos* = object
    time: int64
    count: int
    perc: Perc

  Top* = tuple
    st1: Pos
    nd2: Pos
    rd3: Pos
    th4: Pos
    th5: Pos


proc `$`*(p: Perc): string =
  let i = (100 * p.part) div p.tot
  if i < 10:
     "0" & $i & "%"
  else:
    $i & "%"

proc tfv(i: int64): int64 =
  if i <= 250:
    250
  else:
    i div 250 * 250


proc top_items*(a, b: ptr int64; I: int): Top =
  var h = initTable[int64, int]()

  for i in 1..<I:
    let k = tfv(b[i][] - a[i][])
    discard h.hasKeyOrPut(k, 0)
    h[k].inc

  var st1: Pos
  var nd2: Pos
  var rd3: Pos
  var th4: Pos
  var th5: Pos

  for k, v in h.pairs():
    if v > st1.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = rd3.time
      th4.count = rd3.count
      rd3.time  = nd2.time
      rd3.count = nd2.count
      nd2.time  = st1.time
      nd2.count = st1.count
      st1.time  = k
      st1.count = v
    elif v > nd2.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = rd3.time
      th4.count = rd3.count
      rd3.time  = nd2.time
      rd3.count = nd2.count
      nd2.time  = k
      nd2.count = v
    elif v > rd3.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = rd3.time
      th4.count = rd3.count
      rd3.time  = k
      rd3.count = v
    elif v > th4.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = k
      th4.count = v
    elif v > th5.count:
      th5.time  = k
      th5.count = v
  st1.perc = Perc(tot: I, part: st1.count)
  nd2.perc = Perc(tot: I, part: nd2.count)
  rd3.perc = Perc(tot: I, part: rd3.count)
  th4.perc = Perc(tot: I, part: th4.count)
  th5.perc = Perc(tot: I, part: th5.count)
  (st1, nd2, rd3, th4, th5)


template zeroFill(t: int64): string =
  if   t < 010: "00" & $t
  elif t < 100:  "0" & $t
  else:                $t

when isMainModule:
  proc helloWorld(args, res: pointer): void =
    cast[ptr int64](res)[] = getMonoTime().ticks

  const MAX_ITEMS = 1000

  proc main(): void =
    ## Room for work
    let send  = createShared(int64,  MAX_ITEMS)
    let sent  = createShared(int64,  MAX_ITEMS)
    let args  = createShared(int64,  MAX_ITEMS)
    let res   = createShared(int64,  MAX_ITEMS)
    let tasks = createShared(TaskObj, MAX_ITEMS)

    let epoc = getMonoTime().ticks
    let ctx  =  initContext()

    for i in 0..<MAX_ITEMS:
      args[i] = 0
      tasks[i] = TaskObj(
        args: args[i],
        req:  helloWorld,
        res:  res[i],
      )

      send[i] = getMonoTime().ticks
      args[i] = getMonoTime().ticks
      ctx.whileSchedule tasks[i].some:
       args[i] = getMonoTime().ticks
      sent[i] = getMonoTime().ticks

    let ts = getMonoTime().ticks

    ctx.whileJoin:
      spin()

    let ta = getMonoTime().ticks

    let (st11, nd21, rd31, th41, th51) = top_items(sent, res, MAX_ITEMS)
    let (st12, nd22, rd32, th42, th52) = top_items(send, sent, MAX_ITEMS)

    echo "Tasks:    \t", MAX_ITEMS, "\t", tasks[MAX_ITEMS - 1].stat.load
    echo "Setup:    \t", (res[0][] - epoc).ns, "\t", "         \t", "Starting first thread"
    echo "Send:     \t", (ts - args[0][]).ns,   "\t", ((ts - args[0][]) div MAX_ITEMS).ns, "/task\t", "Sending tasks to threads"
    echo "Send  1st:\t", (st12.time).ns, "\t ", st12.count.zeroFill , " tasks\t", "Time scheduling tasks ", st12.perc, ", precision +/-250ns"
    echo "Send  2nd:\t", (nd22.time).ns, "\t ", nd22.count.zeroFill , " tasks\t", "Time scheduling tasks ", nd22.perc, ", precision +/-250ns"
    echo "Send  3rd:\t", (rd32.time).ns, "\t ", rd32.count.zeroFill , " tasks\t", "Time scheduling tasks ", rd32.perc, ", precision +/-250ns"
    echo "Send  4th:\t", (th42.time).ns, "\t ", th42.count.zeroFill , " tasks\t", "Time scheduling tasks ", th42.perc, ", precision +/-250ns"
    echo "Send  5th:\t", (th52.time).ns, "\t ", th52.count.zeroFill , " tasks\t", "Time scheduling tasks ", th52.perc, ", precision +/-250ns"
    echo "Delay 1st:\t", (st11.time).ns, "\t ", st11.count.zeroFill , " tasks\t", "Time between sent and start running task ", st11.perc, ", precision +/-250ns"
    echo "Delay 2nd:\t", (nd21.time).ns, "\t ", nd21.count.zeroFill , " tasks\t", "Time between sent and start running task ", nd21.perc, ", precision +/-250ns"
    echo "Delay 3rd:\t", (rd31.time).ns, "\t ", rd31.count.zeroFill , " tasks\t", "Time between sent and start running task ", rd31.perc, ", precision +/-250ns"
    echo "Delay 4th:\t", (th41.time).ns, "\t ", th41.count.zeroFill , " tasks\t", "Time between sent and start running task ", th41.perc, ", precision +/-250ns"
    echo "Delay 5th:\t", (th51.time).ns, "\t ", th51.count.zeroFill , " tasks\t", "Time between sent and start running task ", th51.perc, ", precision +/-250ns"
    echo "Join:     \t", (ta - ts).ns,          "\t", "         \t", "Waiting all tasks to complete"
    echo "Snd+Join: \t", (ta - args[0][]).ns,   "\t", ((ta - args[0][]) div MAX_ITEMS).ns, "/task\t", "Send + Join"
    echo "Total:    \t", (ta - epoc).ns
 

    freeShared res
    freeShared args
    freeShared sent
    freeShared tasks
    freeShared args

  main()
