##
## The objective of this benchmark is following:
## 1. Calculate the thread pool creation overhead
## 2. Calculate how much time is required to send/schedule 1000 tasks
##   2.1 Calculate the avg
##   2.2 Group in ranges of 250 and show 5 biggest clusters
## 3. Calculate how much time is lost after task was scheduled (jitter)
##   3.1 Group in ranges of 250 and show 5 biggest clusters
## 4. Calculate how much time it takes to wait all task to be completed after being scheduled
##
##
##   Tasks:    	1000	DONE
##   Setup:     	     092us873ns	         	Initializing
##   Send  100%:	     925us739ns	925ns/task	To schedule tasks
##   Send   28%:	     000us250ns	 282 tasks	+/-250ns
##   Send   23%:	     000us500ns	 238 tasks	+/-250ns
##   Send   23%:	     000us750ns	 237 tasks	+/-250ns
##   Send   11%:	     001us000ns	 116 tasks	+/-250ns
##   Send   05%:	     001us250ns	 055 tasks	+/-250ns
##   Latency 83%:	     000us250ns	 832 tasks	+/-250ns
##   Latency 03%:	     001us500ns	 030 tasks	+/-250ns
##   Latency 02%:	     001us250ns	 025 tasks	+/-250ns
##   Latency 01%:	     001us750ns	 018 tasks	+/-250ns
##   Latency 01%:	     001us000ns	 013 tasks	+/-250ns
##   Join:      	     040us748ns	         	Waiting all tasks to complete
##   Snd+Join:  	     966us487ns	966ns/task	Send + Join
##   Total:     	001ms245us195ns
##

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


proc cluster(i: int64; d: int): int64 =
  if i <= d:
    d
  else:
    i div d * d


proc top_items*(a, b: ptr int64; clstr, I: int): Top =
  var h = initTable[int64, int]()

  for i in 1..<I:
    let k = cluster(b[i][] - a[i][], clstr)
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
      st1.time  = k + clstr
      st1.count = v
    elif v > nd2.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = rd3.time
      th4.count = rd3.count
      rd3.time  = nd2.time
      rd3.count = nd2.count
      nd2.time  = k + clstr
      nd2.count = v
    elif v > rd3.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = rd3.time
      th4.count = rd3.count
      rd3.time  = k + clstr
      rd3.count = v
    elif v > th4.count:
      th5.time  = th4.time
      th5.count = th4.count
      th4.time  = k + clstr
      th4.count = v
    elif v > th5.count:
      th5.time  = k + clstr
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
    let pool  = newPool()

    for i in 0..<MAX_ITEMS:
      args[i] = 0
      tasks[i] = TaskObj(
        args: args[i],
        req:  helloWorld,
        res:  res[i],
      )

      send[i] = getMonoTime().ticks
      args[i] = getMonoTime().ticks
      pool.whileSchedule tasks[i].some:
       args[i] = getMonoTime().ticks
      sent[i] = getMonoTime().ticks

    let tasksSent = getMonoTime().ticks

    pool.whileJoin:
      spin()


    for i in 0..<MAX_ITEMS:
      assert tasks[i].isDone, "Task " & $i & " not DONE but " & $tasks[i].stat.load

    let ta = getMonoTime().ticks

    let (st11, nd21, rd31, th41, th51) = top_items(sent, res, 150, MAX_ITEMS)
    let (st12, nd22, rd32, th42, th52) = top_items(send, sent, 150, MAX_ITEMS)

    echo "Tasks:    \t", MAX_ITEMS
    echo "Setup:    \t", (send[0][] - epoc).ns, "\t", "         \t", "Initializing"
    echo "Send  100%:\t", (tasksSent - args[0][]).ns,   ((tasksSent - args[0][]) div MAX_ITEMS).ns, "/task\t", "To schedule tasks"
    echo "Send   ", st12.perc, ":\t", (st12.time - 149).ns, "~", st12.time, "ns", "\t", st12.count.zeroFill, " tasks\t"
    echo "Send   ", nd22.perc, ":\t", (nd22.time - 149).ns, "~", nd22.time, "ns", "\t", nd22.count.zeroFill, " tasks\t"
    echo "Send   ", rd32.perc, ":\t", (rd32.time - 149).ns, "~", rd32.time, "ns", "\t", rd32.count.zeroFill, " tasks\t"
    echo "Send   ", th42.perc, ":\t", (th42.time - 149).ns, "~", th42.time, "ns", "\t", th42.count.zeroFill, " tasks\t"
    echo "Send   ", th52.perc, ":\t", (th52.time - 149).ns, "~", th52.time, "ns", "\t", th52.count.zeroFill, " tasks\t"
    echo "Latency ", st11.perc, ":\t", (st11.time - 149).ns, "~", st11.time, "ns", "\t", st11.count.zeroFill, " tasks\t"
    echo "Latency ", nd21.perc, ":\t", (nd21.time - 149).ns, "~", nd21.time, "ns", "\t", nd21.count.zeroFill, " tasks\t"
    echo "Latency ", rd31.perc, ":\t", (rd31.time - 149).ns, "~", rd31.time, "ns", "\t", rd31.count.zeroFill, " tasks\t"
    echo "Latency ", th41.perc, ":\t", (th41.time - 149).ns, "~", th41.time, "ns", "\t", th41.count.zeroFill, " tasks\t"
    echo "Latency ", th51.perc, ":\t", (th51.time - 149).ns, "~", th51.time, "ns", "\t", th51.count.zeroFill, " tasks\t"
    echo "Join:     \t", (ta - tasksSent).ns, "\t", "         \t", "Waiting all tasks to complete"
    echo "Snd+Join: \t", (ta - args[0][]).ns, ((ta - args[0][]) div MAX_ITEMS).ns, "/task\t", "Send + Join"
    echo "Total:    \t", (ta - epoc).ns
 

    freeShared res
    freeShared args
    freeShared sent
    freeShared tasks
    freeShared args
    freePool pool

  main()
