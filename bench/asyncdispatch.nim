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
##   Tasks:    	1000
##   Setup:    	000s000ms000us385ns	         	Initializing
##   Send  100%:	000s000ms375us843ns	000s000ms000us375ns/task	To schedule tasks
##   Send   71%:	000s000ms000us150ns	 714 tasks	+/-050ns
##   Send   21%:	000s000ms000us200ns	 217 tasks	+/-050ns
##   Send   03%:	000s000ms000us250ns	 036 tasks	+/-050ns
##   Send   01%:	000s000ms000us300ns	 011 tasks	+/-050ns
##   Send   00%:	000s000ms009us300ns	 003 tasks	+/-050ns
##   Jitter 99%:	000s000ms000us002ns	 999 tasks	+/-002ns
##   Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
##   Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
##   Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
##   Jitter 00%:	000s000ms000us000ns	 000 tasks	+/-002ns
##   Join:     	000s000ms000us047ns	         	Waiting all tasks to complete
##   Snd+Join: 	000s000ms375us890ns	000s000ms000us375ns/task	Send + Join
##   Total:    	000s000ms376us332ns
##   

import std/[asyncfutures, asyncdispatch]
import std/[tables, monotimes, options]
import proccurl/[ptrmath, sleez]

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
  proc helloWorld(args, res: pointer): Future[void] {.async.} =
    cast[ptr int64](res)[] = getMonoTime().ticks

  const MAX_ITEMS = 1000

  proc main(): Future[void] {.async.} =
    ## Room for work
    let send  = createShared(int64,  MAX_ITEMS)
    let sent  = createShared(int64,  MAX_ITEMS)
    let args  = createShared(int64,  MAX_ITEMS)
    let res   = createShared(int64,  MAX_ITEMS)

    let epoc = getMonoTime().ticks

    for i in 0..<MAX_ITEMS:
      args[i] = 0

      send[i] = getMonoTime().ticks
      args[i] = getMonoTime().ticks
      await helloWorld(args[i], res[i])
      sent[i] = getMonoTime().ticks

    let tasksSent = getMonoTime().ticks


    let ta = getMonoTime().ticks

    let (st11, nd21, rd31, th41, th51) = top_items(sent, res, 2, MAX_ITEMS)
    let (st12, nd22, rd32, th42, th52) = top_items(send, sent, 50, MAX_ITEMS)

    echo "Tasks:    \t", MAX_ITEMS
    echo "Setup:    \t", (send[0][] - epoc).ns, "\t", "         \t", "Initializing"
    echo "Send  100%:\t", (tasksSent - args[0][]).ns,   "\t", ((tasksSent - args[0][]) div MAX_ITEMS).ns, "/task\t", "To schedule tasks"
    echo "Send   ", st12.perc, ":\t", (st12.time).ns, "\t ", st12.count.zeroFill , " tasks\t", "+/-050ns"
    echo "Send   ", nd22.perc, ":\t", (nd22.time).ns, "\t ", nd22.count.zeroFill , " tasks\t", "+/-050ns"
    echo "Send   ", rd32.perc, ":\t", (rd32.time).ns, "\t ", rd32.count.zeroFill , " tasks\t", "+/-050ns"
    echo "Send   ", th42.perc, ":\t", (th42.time).ns, "\t ", th42.count.zeroFill , " tasks\t", "+/-050ns"
    echo "Send   ", th52.perc, ":\t", (th52.time).ns, "\t ", th52.count.zeroFill , " tasks\t", "+/-050ns"
    echo "Jitter ", st11.perc, ":\t", (st11.time).ns, "\t ", st11.count.zeroFill , " tasks\t", "+/-002ns"
    echo "Jitter ", nd21.perc, ":\t", (nd21.time).ns, "\t ", nd21.count.zeroFill , " tasks\t", "+/-002ns"
    echo "Jitter ", rd31.perc, ":\t", (rd31.time).ns, "\t ", rd31.count.zeroFill , " tasks\t", "+/-002ns"
    echo "Jitter ", th41.perc, ":\t", (th41.time).ns, "\t ", th41.count.zeroFill , " tasks\t", "+/-002ns"
    echo "Jitter ", th51.perc, ":\t", (th51.time).ns, "\t ", th51.count.zeroFill , " tasks\t", "+/-002ns"
    echo "Join:     \t", (ta - tasksSent).ns, "\t", "         \t", "Waiting all tasks to complete"
    echo "Snd+Join: \t", (ta - args[0][]).ns, "\t", ((ta - args[0][]) div MAX_ITEMS).ns, "/task\t", "Send + Join"
    echo "Total:    \t", (ta - epoc).ns
 

    freeShared res
    freeShared args
    freeShared sent
    freeShared args

  waitFor main()
