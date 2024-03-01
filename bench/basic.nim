import std/[monotimes, options, strutils]
import proccurl/boring

const PAGES = 1
const SLOTS = 16
const ARENA_LEN = sizeof(BufferQueue[SLOTS, PAGES])


var arena: array[ARENA_LEN, uint8]

proc producer(): void {.thread.} =
  var queue = newBufferQueue[SLOTS, PAGES](arena)

  for i in 0..100:
    let buff = Buffer[PAGES](len: sizeof(MonoTime).uint32)
    let t  = getMonoTime()
    copyMem buff.addr, t.addr, buff.len
    while BUSY == queue.enqueue buff:
      cpuRelax()
    echo "send ", getMonoTime() - t, " ", $i


proc consumer(): void {.thread.} =
  var queue = newBufferQueue[SLOTS, PAGES](arena)
  var r = Buffer[PAGES].none
  var f = 0
  var t   = getMonoTime()
  var ttt = getMonoTime()
  while f < 10000:
    t   = getMonoTime()
    r   = queue.dequeue
    ttt = getMonoTime()
    if r.isNone:
      cpuRelax()
      f = f + 1
      continue
    f = 0
    let tt  = cast[ptr MonoTime](r.get().addr)[]
    echo "recv ", ttt - t, " ", ttt - tt
    assert r.isSome


proc main(): void =
  var
    thr: array[5, Thread[void]]
  createThread[void](thr[1], consumer)
  createThread[void](thr[2], consumer)
  createThread[void](thr[3], consumer)
  createThread[void](thr[4], consumer)
  #createThread[void](thr[5], consumer)
  createThread[void](thr[0], producer)
  joinThreads[void](thr)

main()
