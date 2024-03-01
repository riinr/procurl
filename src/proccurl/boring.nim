## This is a Ring Buffer implementation
##
## It has some advanteges
## - Works with Multiple Producer Multiple Consumer
## - Is reasonable simple:
##   - You can only write next if next is writable
##   - You can only read  next if next is readable
##   - Unwritable/Unreadable means full/empty or busy
##     taken by another thread/process
## - It doesn't apply pooling (async friendly):
##   - Instead of wait it returns to caller, to call again or reeschedule
##   - Only success blocks for copy
##   - Copy is done on len of msg (instead of full buffer size)
##   - My tests copies 4KB in ~100ns, 8KB in ~200ns, 12KB in ~350ns
## - I'm trying to make it work with mmap to use as IPC
##   - Most implementation can only be used with threads
##
## It has some flaws:
## - Memory copy, no clue how to do it with zero copy
## - latency is (copyOf(buff, len) x 2) + (copyOf(uint32) + reeschedules/calls)
## - Contention when used as Multiple Produces Multiple Consumer
## - Isn't the most space efficient solution
## - Size of buffer is bounded
##  - For dynamic size responses (like my case curl) you have
##    check if size fits, and slice msgs

when defined profiler:
  import nimprof


import std/[atomics, options]

const PAGE* {.intdefine: "boring.mempage".} = 4096 # 4 KB

type
  IStat* = enum  # STATE MACHINE RD -> WW -> WD -> RR -> RD
    RD,          # Reader Done    # can  push
    WW,          # Writer Writing # wait before shift
    WD,          # Writer Done    # can  shift
    RR           # Reader Reading # wait before push

  Idx*[SLOTS: static int] = distinct range[0..(SLOTS - 1)]

  ## Random Access Memory
  Ram*[SLOTS: static int, T] = object
    stat*:   array[SLOTS, Atomic[IStat]]
    sizes*:  array[SLOTS, Atomic[uint32]]
    data*:   array[SLOTS, T]


proc `$`[SLOTS: static int](idx: Idx[SLOTS]): string =
  $(cast[uint32](idx))


template `[]=`*[SLOTS: static int, T](a: var Ram[SLOTS, T]; i: Idx[SLOTS], v: T): void =
  a.data[i] = v

template `[]` *[SLOTS: static int, T](a: var Ram[SLOTS, T]; i: Idx[SLOTS]): T =
  a.data[i]


template open_reader* [SLOTS: static int, T](
    a:   var Ram[SLOTS, T];
    i:   Idx[SLOTS];
    vWD: var IStat;
): bool =
  a.stat[cast[uint32](i)].compareExchange(vWD, RR, moAcquire, moRelaxed)


template close_reader*[SLOTS: static int, T](
    a: var Ram[SLOTS, T];
    i: Idx[SLOTS];
): void =
  a.stat[cast[uint32](i)].store RD, moRelease


template open_writer* [SLOTS: static int, T](
    a:   var Ram[SLOTS, T];
    i:   Idx[SLOTS];
    vRD: var IStat
): bool =
  a.stat[cast[uint32](i)].compareExchange(vRD, WW, moAcquire, moRelaxed)


template close_writer*[SLOTS: static int, T](
  a: var Ram[SLOTS, T];
  i: Idx[SLOTS];
): void =
  a.stat[cast[uint32](i)].store WD, moRelease


type
  SC*[SLOTS: static int] = object
    reader*: Idx[SLOTS]

  SP*[SLOTS: static int] = object
    writer*: Idx[SLOTS]

  MC*[SLOTS: static int] = object
    reader*: Atomic[Idx[SLOTS]]

  MP*[SLOTS: static int] = object
    writer*: Atomic[Idx[SLOTS]]

  P*[SLOTS: static int] = SP[SLOTS]|MP[SLOTS]
  C*[SLOTS: static int] = SC[SLOTS]|MC[SLOTS]


template producer*[SLOTS: static int](p: SP[SLOTS]): Idx[SLOTS] =
  p.writer

template producer*[SLOTS: static int](p: MP[SLOTS]): Idx[SLOTS] =
  p.writer.load moRelaxed

template inc*     [SLOTS: static int](p: var SP[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  var writer = cast[uint32](prev) + 1
  if writer == SLOTS:
    writer = 0
  p.writer = cast[Idx[SLOTS]](writer)
  p.writer

template inc*     [SLOTS: static int](p: var MP[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  var writer = cast[uint32](prev) + 1
  if writer == SLOTS:
    writer = 0
  p.writer.store cast[Idx[SLOTS]](writer), moRelaxed
  cast[Idx[SLOTS]](writer)

template inc*     [SLOTS: static int](p: var P[SLOTS]): Idx[SLOTS] = p.inc p.producer

template consumer*[SLOTS: static int](c: SC[SLOTS]): Idx[SLOTS] =
  c.reader

template consumer*[SLOTS: static int](c: MC[SLOTS]): Idx[SLOTS] =
  c.reader.load moRelaxed

template dec*     [SLOTS: static int](c: var SC[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  var reader = cast[uint32](prev) + 1
  if reader == SLOTS:
    reader = 0
  c.reader = cast[Idx[SLOTS]](reader)
  c.reader

template dec*     [SLOTS: static int](c: var MC[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  var reader = cast[uint32](prev) + 1
  if reader == SLOTS:
    reader = 0
  c.reader.store cast[Idx[SLOTS]](reader), moRelaxed
  cast[Idx[SLOTS]](reader)



template dec*     [SLOTS: static int](c: var C[SLOTS]): Idx[SLOTS] = c.dec c.consumer


type
  Queue*[
    SLOTS: static int,
    P: P[SLOTS],
    C: C[SLOTS],
    T
  ] = object
    a*: Ram[SLOTS, T]
    p*: P
    c*: C


proc sizeOfQ*         [SLOTS: static int, T](): int = sizeof Queue[SLOTS, SP[SLOTS], SC[SLOTS], T]

template `$`*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): string =
  $type(q)

template `[]=`*       [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS], v: T): void =
  q.a.data[cast[uint32](i)] = v

template `[]`*        [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): T =
  q.a.data[cast[uint32](i)]

template `stats`*     [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS], v: IStat): void =
  q.a.stat[cast[uint32](i)].store cast[uint8](v), moRelaxed

template `stats`*     [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): IStat =
  cast[IStat](q.a.stat[cast[uint32](i)].load moRelaxed)

template `sizes`*     [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS], v: uint32): void =
  q.a.sizes[cast[uint32](i)].store v, moRelaxed

template `sizes`*     [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): uint32 =
  q.a.sizes[cast[uint32](i)].load moRelaxed

template open_reader* [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]; vWD: var IStat): bool =
  q.a.open_reader  i, vWD
template open_writer* [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]; vRD: var IStat): bool =
  q.a.open_writer  i, vRD
template close_reader*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): void =
  q.a.close_reader i
template close_writer*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): void =
  q.a.close_writer i

template inc*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; prev: Idx[SLOTS]): Idx[SLOTS] =
  q.p.inc prev
template dec*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; prev: Idx[SLOTS]): Idx[SLOTS] =
  q.c.dec prev
template inc*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  q.p.inc
template dec*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  q.c.dec

template producer*    [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  q.p.producer
template consumer*    [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  q.c.consumer


proc enqueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q:    ptr Queue[SLOTS, P, C, T];
    i:    var Idx[SLOTS];
    v:    var TT;
    vRD:  var IStat;
    s:    uint32;
): bool =
  if not q.open_writer(i, vRD):
    return false

  let old = i
  i = q.inc i
  q.sizes old, s
  copyMem q[old].addr, v.addr, s
  q.close_writer old
  return  true


template enqueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](
    q:    ptr Queue[SLOTS, P, C, T];
    i:    var Idx[SLOTS];
    v:    var T;
    vRD:  var IStat;
): bool =
  ## this version let you reuse vars
  ## BEWARE of side effects
  ##
  ## Not only in queue:
  ## - i    will be updated with next position when done
  ## - vRD  will change when FULL or BUSY (this happen very often)
  ##   - vRD == WD means FULL
  ##   - vRD == WW means BUSY i, other thread is writing
  ##     - try fetching wIdx again, it may be changed
  ##   - vRD == RR means BUSY i, other thread is reading
  ##     - In a single   consumer, try same i again, it may be completed 
  ##     - In a multiple consumer, fetch i again (order safe) or try the same (order unsafe)
  q.enqueue i, v, vRD, sizeof(T).uint32


template enqueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](
    q:    ptr Queue[SLOTS, P, C, T];
    v:    var T;
): bool =
  var i   = queue.producer
  var vRD = RD
  q.enqueue i, v, vRD, sizeof(T).uint32


proc dequeue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q:    ptr Queue[SLOTS, P, C, T];
    i:    var Idx[SLOTS];
    v:    var TT;
    vWD:  var IStat;
): bool =
  ## this version let you reuse vars
  ## BEWARE of side effects
  ##
  ## Not only in queue or buffer:
  ## - buff will change when SUCCEDED
  ## - vWD  will change when EMPTY or BUSY (this happen very often)
  ##   - vWD == RD means EMPTY
  ##   - vWD == RR means BUSY i, other thread is reading
  ##     - try fetching i again, it may be changed
  ##   - vWD == WW means BUSY i, other thread is writing
  ##     - In a single   consumer, try same i again, it may be completed 
  ##     - In a multiple consumer, fetch i again (order safe) or try the same (order unsafe)
  if not q.open_reader(i, vWD):
    return false

  let old = i
  i = q.dec i
  copyMem v.addr, q[old].addr, q.sizes old
  q.close_reader old
  return true


template dequeue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](
    q:    ptr Queue[SLOTS, P, C, T];
): Option[T] =
  var v: T;
  var i   = q.consumer;
  var vWD = WD;
  if q.enqueue(i, v, vWD):
    some(v)
  else:
    none(T)


proc newQueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](
    arena: var openarray[uint8]
): ptr Queue[SLOTS, P, C, T] =
  ## create newQueue
  ##
  ## - SLOTS: queue max length
  ## - P    : Single (SP) or Multiple (MP) producers
  ## - C    : Single (SC) or Multiple (MC) consumers
  ## - T    : object Type
  ##
  assert arena.len >= sizeof Queue[SLOTS, P, C, T]
  cast[ptr Queue[SLOTS, P, C, T]](arena.addr)


proc newQueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](): ptr Queue[SLOTS, P, C, T] =
  ## create newQueue
  ##
  ## - SLOTS: queue max length
  ## - P    : Single (SP) or Multiple (MP) producers
  ## - C    : Single (SC) or Multiple (MC) consumers
  ## - T    : object Type
  ##
  var arena = createShared(array[static sizeOfQ[SLOTS, T](), uint8])
  cast[ptr Queue[SLOTS, P, C, T]](arena)
