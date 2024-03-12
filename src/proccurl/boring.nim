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
  IStat* = enum
    ## STATE MACHINE RD -> WW -> ( WD || LD) -> RR -> RD
    RD,          ## Reader Done:     can  push
    WW,          ## Writer Writing:  wait before shift
    WD,          ## Writer Done:     can  shift
    RR,          ## Reader Reading:  wait before push
    LD           ## Linker Done:     can  shift but only if you have link to it

  Idx*[SLOTS: static int] = distinct range[0..(SLOTS - 1)]

  Ram*[SLOTS: static int, T] = object
    ## Random Access Memory
    stat*:   array[SLOTS, Atomic[IStat]]   ## Slot status
    sizes*:  array[SLOTS, Atomic[uint32]]  ## Slot content len
    data*:   array[SLOTS, T]               ## Slot content bytes
    links*:  array[SLOTS, Idx[SLOTS]]      ## Link to other slot if one is not enough


proc `$`[SLOTS: static int](idx: Idx[SLOTS]): string =
  ## convert Idx[SLOTS] to string
  $(cast[uint32](idx))


template `[]=`*[SLOTS: static int, T](r: var Ram[SLOTS, T]; i: Idx[SLOTS], v: T): void =
  ## set data into RAM[i]
  r.data[i] = v

template `[]` *[SLOTS: static int, T](r: var Ram[SLOTS, T]; i: Idx[SLOTS]): T =
  ## get data from RAM[i]
  r.data[i]

template start_reading* [SLOTS: static int, T](
    r: var Ram[SLOTS, T];
    i: Idx[SLOTS];
    s: var IStat;
): bool =
  ## try to set RAM[i] as reading
  ##
  ## If false, returns false and changes `s` to reason, if reason is:
  ## - RR means other thread is already reading from RAM[i]
  ## - RD means it is empty shouldn't read from RAM[i]
  ## - LD means it is reserved to other thread with link to RAM[i]
  ## - WW means it is not ready to read RAM[i]
  ##
  ## If true, returns true and sets internal state to RR (reader reading)
  ##
  r.stat[cast[uint32](i)].compareExchangeWeak(s, RR, moRelaxed, moRelaxed)


template stop_reading*[SLOTS: static int, T](
    r: var Ram[SLOTS, T];
    i: Idx[SLOTS];
): void =
  ## set the internal state of RAM[i] to reader done
  ## freeing it so other threads can write
  r.stat[cast[uint32](i)].store RD, moRelaxed


template start_writing* [SLOTS: static int, T](
    r: var Ram[SLOTS, T];
    i: Idx[SLOTS];
    s: var IStat
): bool =
  ## try to set RAM[i] as writing
  ##
  ## If false, returns false and changes `s` to reason, if reason is:
  ## - WW means other thread is writing into RAM[i]
  ## - WD means it is full shouldn't overwrite RAM[i]
  ## - RR means is not ready to write in RAM[i]
  ## - LD means it is reserved to other thread with link to RAM[i]
  ##
  ## If true, returns true and sets internal state to WW (writer writing)
  ##
  r.stat[cast[uint32](i)].compareExchangeWeak(s, WW, moRelaxed, moRelaxed)


template stop_writing*[SLOTS: static int, T](
  r: var Ram[SLOTS, T];
  i: Idx[SLOTS];
): void =
  ## set the internal state of RAM[i] to writer done
  ## freeing it so other threads can read
  r.stat[cast[uint32](i)].store WD, moRelaxed


type
  SC*[SLOTS: static int] = object
    ## Single Consumer Reader
    reader*: Idx[SLOTS]

  SP*[SLOTS: static int] = object
    ## Single Producer Writer
    writer*: Idx[SLOTS]

  MC*[SLOTS: static int] = object
    ## Multi Consumer Reader
    reader*: Atomic[Idx[SLOTS]]

  MP*[SLOTS: static int] = object
    ## Multi Producer Writer
    writer*: Atomic[Idx[SLOTS]]

  P*[SLOTS: static int] = SP[SLOTS]|MP[SLOTS]  ## Generic Producer
  C*[SLOTS: static int] = SC[SLOTS]|MC[SLOTS]  ## Generic Consumer


template producer*[SLOTS: static int](p: SP[SLOTS]): Idx[SLOTS] =
  ## Get producer current positon
  p.writer

template producer*[SLOTS: static int](p: MP[SLOTS]): Idx[SLOTS] =
  ## Get producer current positon
  p.writer.load moRelaxed

template inc*     [SLOTS: static int](p: var SP[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move producer to next position
  var writer = cast[uint32](prev) + 1
  if writer == SLOTS:
    writer = 0
  p.writer = cast[Idx[SLOTS]](writer)
  p.writer

template inc*     [SLOTS: static int](p: var MP[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move producer to next position
  var writer = cast[uint32](prev) + 1
  if writer == SLOTS:
    writer = 0
  p.writer.store cast[Idx[SLOTS]](writer), moRelaxed
  cast[Idx[SLOTS]](writer)

template inc*     [SLOTS: static int](p: var P[SLOTS]): Idx[SLOTS] =
  ## Move producer to next position
  p.inc p.producer

template consumer*[SLOTS: static int](c: SC[SLOTS]): Idx[SLOTS] =
  ## Get consumer current positon
  c.reader

template consumer*[SLOTS: static int](c: MC[SLOTS]): Idx[SLOTS] =
  ## Get consumer current positon
  c.reader.load moRelaxed

template dec*     [SLOTS: static int](c: var SC[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move consumer to next positon
  var reader = cast[uint32](prev) + 1
  if reader == SLOTS:
    reader = 0
  c.reader = cast[Idx[SLOTS]](reader)
  c.reader

template dec*     [SLOTS: static int](c: var MC[SLOTS]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move consumer to next positon
  var reader = cast[uint32](prev) + 1
  if reader == SLOTS:
    reader = 0
  c.reader.store cast[Idx[SLOTS]](reader), moRelaxed
  cast[Idx[SLOTS]](reader)


template dec*     [SLOTS: static int](c: var C[SLOTS]): Idx[SLOTS] =
  ## Move consumer to next positon
  c.dec c.consumer


type
  Queue*[
    SLOTS: static int,
    P: P[SLOTS],
    C: C[SLOTS],
    T
  ] = object
    ## Your boring buffer queue with SLOTS available
    a*: Ram[SLOTS, T]  ## to store our data and position status
    p*: P              ## can be SP (single producer) or MP (multiple producers)
    c*: C              ## can be SC (single consumer) or SP (multiple consumers)


proc sizeOfQ*         [SLOTS: static int, T](): int =
  ## Total size of our Queue
  sizeof Queue[SLOTS, SP[SLOTS], SC[SLOTS], T]

template `$`*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): string =
  ## Convert our queue to string
  $type(q)

template `[]=`*       [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS], v: T): void =
  ## Set Queue[i] data
  q.a.data[cast[uint32](i)] = v

template `[]`*        [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): T =
  ## Get Queue[i] data
  q.a.data[cast[uint32](i)]

template `stats`*     [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS], v: IStat): void =
  ## Set Queue[i] stat
  q.a.stat[cast[uint32](i)].store cast[uint8](v), moRelaxed

template `stats`*     [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): IStat =
  ## Get Queue[i] stat
  cast[IStat](q.a.stat[cast[uint32](i)].load moRelaxed)

template `sizes`*     [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS], v: uint32): void =
  ## Set Queue[i] size
  q.a.sizes[cast[uint32](i)].store v, moRelaxed

template `sizes`*     [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): uint32 =
  ## Get Queue[i] size
  q.a.sizes[cast[uint32](i)].load moRelaxed

template start_enqueuing* [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]; s: var IStat): bool =
  ## Init an enqueue transation
  q.a.start_writing i, s

template start_dequeuing* [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]; s: var IStat): bool =
  ## Init an dequeue transation
  q.a.start_reading i, s

template stop_enqueuing*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): void =
  ## Commit an enqueue transation
  q.a.stop_writing i

template stop_dequeuing*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; i: Idx[SLOTS]): void =
  ## Commit an dequeue transation
  q.a.stop_reading i

template inc*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move Queue to next producer positon
  q.p.inc prev

template dec*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]; prev: Idx[SLOTS]): Idx[SLOTS] =
  ## Move Queue to next consumer positon
  q.c.dec prev

template inc*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  ## Move Queue to next producer positon
  q.p.inc

template dec*         [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  ## Move Queue to next consumer positon
  q.c.dec

template producer*    [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  ## Get Queue current producer position
  q.p.producer

template consumer*    [SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](q: ptr Queue[SLOTS, P, C, T]): Idx[SLOTS] =
  ## Get Queue current consumer position
  q.c.consumer


proc enqueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q: ptr Queue[SLOTS, P, C, T];
    i: var Idx[SLOTS];
    v: var TT;
    s: var IStat;
    l: uint32;
): bool =
  ## this version let you reuse vars
  ## BEWARE of side effects
  ##
  ## Not only in queue:
  ## - i    will be updated with next position only if done
  ## - s  will change when FULL or BUSY (this happen very often)
  ##   - s == WD means FULL
  ##   - s == WW means BUSY i, other thread is enqueuing
  ##     - try fetching i again, it may be changed
  ##   - s == RR means BUSY i, other thread is dequeuing
  ##     - In a single   consumer, try same i again, it may be completed 
  ##     - In a multiple consumer, fetch i again (order safe) or try the same (order unsafe)
  if not q.start_enqueuing(i, s):
    return false

  let old = i
  i = q.inc i
  q.sizes old, l
  copyMem q[old].addr, v.addr, l
  q.stop_enqueuing old
  return  true


template enqueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q: ptr Queue[SLOTS, P, C, T];
    i: var Idx[SLOTS];
    v: var TT;
    s: var IStat;
): bool =
  q.enqueue i, v, s, sizeof(TT).uint32


template enqueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q: ptr Queue[SLOTS, P, C, T];
    v: var TT;
): bool =
  var i = q.producer
  var s = RD
  q.enqueue i, v, s, sizeof(TT).uint32


proc dequeue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q: ptr Queue[SLOTS, P, C, T];
    i: var Idx[SLOTS];
    v: var TT;
    s: var IStat;
): bool =
  ## this version let you reuse vars
  ## BEWARE of side effects
  ##
  ## Not only in queue or buffer:
  ## - buff will change when SUCCEDED
  ## - s  will change when EMPTY or BUSY (this happen very often)
  ##   - s == RD means i position is EMPTY
  ##   - s == RR means i position is BUSY, other thread is dequeuing
  ##     - try fetching i again, it may be changed
  ##   - s == WW means i position is BUSY, other thread is enqueuing
  ##     - In a single   consumer, try same i again, it may be completed 
  ##     - In a multiple consumer, fetch i again (order safe) or try the same (order unsafe)
  if not q.start_dequeuing(i, s):
    return false

  let old = i
  i = q.dec i
  copyMem v.addr, q[old].addr, q.sizes old
  q.stop_dequeuing old
  return true


template dequeue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T, TT](
    q: ptr Queue[SLOTS, P, C, T];
    v: TT
): bool =
  var i = q.consumer;
  var s = WD;
  q.dequeue(i, v, s)


template dequeue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](
    q: ptr Queue[SLOTS, P, C, T];
    TT: typedesc
): Option[T] =
  var i = q.consumer;
  var s = WD;
  var v: TT;
  if q.dequeue(i, v, s):
    some(v)
  else:
    none(TT)


proc newQueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](
    arena: pointer
): ptr Queue[SLOTS, P, C, T] =
  ## create newQueue
  ##
  ## - SLOTS: queue max length
  ## - P    : Single (SP) or Multiple (MP) producers
  ## - C    : Single (SC) or Multiple (MC) consumers
  ## - T    : object Type
  ##
  cast[ptr Queue[SLOTS, P, C, T]](arena)


proc newQueue*[SLOTS: static int, P: P[SLOTS], C: C[SLOTS], T](): ptr Queue[SLOTS, P, C, T] =
  ## create newQueue
  ##
  ## - SLOTS: queue max length
  ## - P    : Single (SP) or Multiple (MP) producers
  ## - C    : Single (SC) or Multiple (MC) consumers
  ## - T    : object Type
  ##
  let arena = createShared(array[static sizeOfQ[SLOTS, T](), uint8])
  cast[ptr Queue[SLOTS, P, C, T]](arena.addr)
