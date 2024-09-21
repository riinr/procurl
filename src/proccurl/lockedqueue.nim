import std/[atomics, deques, options]
import ./locked

type QueueResource*[T] = object
  size: Atomic[int]
  bloc: Atomic[bool]
  internal: Resource[Deque[Option[T]]]

type SharedQueue*[T] = ptr QueueResource[T]

converter toShared*[T](q: QueueResource[T]): SharedQueue[T] = q.addr


template len*    [T](q: SharedQueue[T]): int  = q.size.load moRelaxed

template stop*   [T](q: SharedQueue[T]): void = q.bloc.store true, moRelaxed

template blocked*[T](q: SharedQueue[T]): bool = q.bloc.load moRelaxed

template isBusy* [T](q: SharedQueue[T]): bool = q.internal.isBusy

template isEmpty*[T](q: SharedQueue[T]): bool = q.len == 0


proc enqueue*[T](q: SharedQueue[T]; v: sink Option[T]): Option[T] =
  ## Return T.none if operation succeed
  ## Return v if operation fail
  if v.isNone or q.blocked or q.isBusy: return v

  q.internal.getIt v:
    when defined debugLockedQueue: debugEcho getThreadId(), "Thr enqueue ", T
    it[].addLast v
    q.size.atomicInc
    T.none


proc dequeueLast*[T](q: SharedQueue[T]): Option[T] =
  ## Return last T.some if operation succeed
  ## Return v if operation fail
  if q.isEmpty or q.isBusy: return T.none

  q.internal.getIt T.none:
    when defined debugLockedQueue: debugEcho getThreadId(), "Thr dequeue last ", T
    var prevLen = q.len
    if q.size.compareExchange(prevLen, prevLen - 1, moAcquire, moRelaxed):
      it[].popLast
    else:
      T.none


proc dequeue*[T](q: SharedQueue[T]): Option[T] =
  ## Return T.some if operation succeed
  ## Return v if operation fail
  if q.isEmpty or q.isBusy: return T.none

  q.internal.getIt T.none:
    when defined debugLockedQueue: debugEcho getThreadId(), "Thr dequeue ", T
    var prevLen = q.len
    if q.size.compareExchange(prevLen, prevLen - 1, moAcquire, moRelaxed):
      it[].popFirst
    else:
      T.none


template whileEnqueue*[T](q: SharedQueue[T]; v: sink Option[T]; op: untyped): void =
  var vv = v
  while vv.isSome and not q.blocked:
    vv = q.enqueue(vv)

    if vv.isSome:
      op
      cpuRelax()


proc initLockedQueue*[T](q: SharedQueue): void =
  q.bloc.store false
  q.size.store 0
  q.internal.freeResource


when isMainModule:
  proc main(): void =
    let q = createShared(QueueResource[int])
    echo "len ", q.len()
    if q.enqueue(1.some).isNone:
      echo "len ", q.len()

    if q.enqueue(2.some).isNone:
      echo "len ", q.len()

    echo "st  ", q.dequeue()
    echo "len ", q.len()

    echo "nd  ", q.dequeue()
    echo "len ", q.len()

  main()
