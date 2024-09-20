import proccurl/[dreads, ptrmath, sleez]
import std/[atomics, tables, monotimes, options]


when isMainModule:
  proc helloWorld(args, res: pointer): void =
    cast[ptr int64](res)[] = getMonoTime().ticks

  const MAX_ITEMS = 1000

  proc main(): void =
    let args = createShared(int64,  MAX_ITEMS)
    let r    = createShared(int64,  MAX_ITEMS)
    let t    = createShared(ReqRes, MAX_ITEMS)

    let epoc = getMonoTime().ticks
    let ctx =  initContext()

    for i in 0..<MAX_ITEMS:
      args[i][] = getMonoTime().ticks
      t[i][] = ReqRes(
        args: args[i],
        req:  helloWorld,
        res:  r[i],
      )

      ctx.whileSchedule t[i].some:
        args[i][] = getMonoTime().ticks

    let ts = getMonoTime().ticks

    ctx.whileJoin:
      spin()

    let ta = getMonoTime().ticks

    proc zer(i: int64): int64 =
      if i < 10:
        i
      else:
        zer(i div 10) * 10
    
    var h = initTable[int64, int]()

    for i in 1..<MAX_ITEMS:
      let k = zer(r[i][] - args[i][])
      if h.hasKey(k):
        h[k].inc
      elif h.hasKey(k + 100):
        h[k + 100].inc
      elif h.hasKey(k - 100):
        h[k - 100].inc
      elif h.hasKey(k + 200):
        h[k + 200].inc
      elif h.hasKey(k - 200):
        h[k - 200].inc
      elif h.hasKey(k + 300):
        h[k + 300].inc
      elif h.hasKey(k - 300):
        h[k - 300].inc
      elif h.hasKey(k + 400):
        h[k + 400].inc
      elif h.hasKey(k - 400):
        h[k - 400].inc
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

    echo "Tasks:   \t", MAX_ITEMS, "\t", t[MAX_ITEMS - 1].stat.load
    echo "Setup:   \t", (args[0][] - epoc).ns, "\t", "         \t", "Starting first thread"
    echo "Send:    \t", (ts - args[0][]).ns,   "\t", ((ts - args[0][]) div MAX_ITEMS).ns, "/task\t", "Sending tasks to threads"
    echo "Delay 1st:\t", "     \t", (st[0]).ns, " +/-", 400.ns, "\t ", st[1] , " tasks\t", "Time between sent and start running task"
    echo "Delay 2nd:\t", "     \t", (nd[0]).ns, " +/-", 400.ns, "\t ", nd[1] , " tasks\t", "Time between sent and start running task"
    echo "Delay 3rd:\t", "     \t", (rd[0]).ns, " +/-", 400.ns, "\t ", rd[1] , " tasks\t", "Time between sent and start running task"
    echo "Join:    \t", (ta - ts).ns,          "\t", "         \t", "Waiting all tasks to complete"
    echo "Snd+Join:\t", (ta - args[0][]).ns,   "\t", ((ta - args[0][]) div MAX_ITEMS).ns, "/task\t", "Send + Join"
    echo "Total:   \t", (ta - epoc).ns
 

    freeShared r
    freeShared t
    freeShared args

  main()
