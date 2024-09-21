import proccurl/[dreads, ptrmath, sleez]
import std/[atomics, tables, monotimes, options]

type
  Pos* = tuple
    time: int64
    count: int

  Top* = tuple
    st: Pos
    nd: Pos
    rd: Pos


proc zer(i: int64): int64 =
  if i < 0:
    1
  elif i < 10:
    i
  else:
    zer(i div 10) * 10


proc top_items*(a, b: ptr int64; I: int): Top =
  var h = initTable[int64, int]()

  for i in 1..<I:
    let k = zer(b[i][] - a[i][])
    if h.hasKey(k):
      h[k].inc
    elif k < 100:
      if k < 50:
        discard h.hasKeyOrPut(50, 0)
        h[50].inc
      else:
        discard h.hasKeyOrPut(100, 0)
        h[100].inc
    elif h.hasKey(k + 100):
      h[k + 100].inc
    elif h.hasKey(k - 100):
      h[k - 100].inc
    else:
      discard h.hasKeyOrPut(k, 0)
      h[k].inc

  var st = (0.int64, 0)
  var nd = (0.int64, 0)
  var rd = (0.int64, 0)

  for k, v in h.pairs():
    if v > st[1]:
      rd[0] = nd[0]
      rd[1] = nd[1]
      nd[0] = st[0]
      nd[1] = st[1]
      st[0] = k
      st[1] = v
    elif v > nd[1]:
      rd[0] = nd[0]
      rd[1] = nd[1]
      nd[0] = k
      nd[1] = v
    elif v > rd[1]:
      rd[0] = k
      rd[1] = v
  (st, nd, rd)


when isMainModule:
  proc helloWorld(args, res: pointer): void =
    cast[ptr int64](res)[] = getMonoTime().ticks

  const MAX_ITEMS = 1000

  proc main(): void =
    let send = createShared(int64,  MAX_ITEMS)
    let sent = createShared(int64,  MAX_ITEMS)
    let args = createShared(int64,  MAX_ITEMS)
    let r    = createShared(int64,  MAX_ITEMS)
    let t    = createShared(TaskObj, MAX_ITEMS)

    let epoc = getMonoTime().ticks
    let ctx  =  initContext()

    for i in 0..<MAX_ITEMS:
      args[i] = 0
      t[i] = TaskObj(
        args: args[i],
        req:  helloWorld,
        res:  r[i],
      )

      send[i] = getMonoTime().ticks
      args[i] = getMonoTime().ticks
      ctx.whileSchedule t[i].some:
        args[i] = getMonoTime().ticks
      sent[i] = getMonoTime().ticks

    let ts = getMonoTime().ticks

    ctx.whileJoin:
      spin()

    let ta = getMonoTime().ticks

    let (st1, nd1, rd1) = top_items(args, r, MAX_ITEMS)
    let (st2, nd2, rd2) = top_items(send, sent, MAX_ITEMS)

    echo "Tasks:    \t", MAX_ITEMS, "\t", t[MAX_ITEMS - 1].stat.load
    echo "Setup:    \t", (args[0][] - epoc).ns, "\t", "         \t", "Starting first thread"
    echo "Send:     \t", (ts - args[0][]).ns,   "\t", ((ts - args[0][]) div MAX_ITEMS).ns, "/task\t", "Sending tasks to threads"
    echo "Send  1st:\t", "     \t", (st2[0]).ns, " +/-", 100.ns, "\t ", st2[1] , " tasks\t", "Time scheduling tasks"
    echo "Send  2nd:\t", "     \t", (nd2[0]).ns, " +/-", 100.ns, "\t ", nd2[1] , " tasks\t", "Time scheduling tasks"
    echo "Send  3rd:\t", "     \t", (rd2[0]).ns, " +/-", 100.ns, "\t ", rd2[1] , " tasks\t", "Time scheduling tasks"
    echo "Delay 1st:\t", "     \t", (st1[0]).ns, " +/-", 100.ns, "\t ", st1[1] , " tasks\t", "Time between sent and start running task"
    echo "Delay 2nd:\t", "     \t", (nd1[0]).ns, " +/-", 100.ns, "\t ", nd1[1] , " tasks\t", "Time between sent and start running task"
    echo "Delay 3rd:\t", "     \t", (rd1[0]).ns, " +/-", 100.ns, "\t ", rd1[1] , " tasks\t", "Time between sent and start running task"
    echo "Join:     \t", (ta - ts).ns,          "\t", "         \t", "Waiting all tasks to complete"
    echo "Snd+Join: \t", (ta - args[0][]).ns,   "\t", ((ta - args[0][]) div MAX_ITEMS).ns, "/task\t", "Send + Join"
    echo "Total:    \t", (ta - epoc).ns
 

    freeShared r
    freeShared t
    freeShared args

  main()
