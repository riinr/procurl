import std/[atomics, deques, options]
import ./locked

type QueueResource*[T] = object
  size: Atomic[int]
  bloc: Atomic[bool]
  internal: Resource[Deque[Option[T]]]

type SharedQueue*[T] = ptr QueueResource[T]

converter toShared*[T](q: QueueResource[T]): SharedQueue[T] = q.addr


proc enqueue*[T](q: SharedQueue[T]; v: sink Option[T]): Option[T] =
  ## Return T.none if operation succeed
  ## Return v if operation fail

  if q[].bloc.load moRelaxed:
    return v

  q[].internal.getIt v:
    when defined debugLockedQueue: debugEcho getThreadId(), "Thr enqueue ", T
    it[].addLast v
    q[].size.atomicInc
    T.none


proc dequeueLast*[T](q: SharedQueue[T]): Option[T] =
  ## Return last T.some if operation succeed
  ## Return v if operation fail
  var prevLen = q[].size.load(moRelaxed)
  if prevLen == 0:
    return T.none

  q[].internal.getIt T.none:
    when defined debugLockedQueue: debugEcho getThreadId(), "Thr dequeue last ", T
    if q[].size.compareExchange(prevLen, prevLen - 1, moAcquire, moRelaxed):
      it[].popLast
    else:
      T.none


proc dequeue*[T](q: SharedQueue[T]): Option[T] =
  ## Return T.some if operation succeed
  ## Return v if operation fail
  var prevLen = q[].size.load(moRelaxed)
  if prevLen == 0:
    return T.none

  q[].internal.getIt T.none:
    when defined debugLockedQueue: debugEcho getThreadId(), "Thr dequeue ", T
    if q[].size.compareExchange(prevLen, prevLen - 1, moAcquire, moRelaxed):
      it[].popFirst
    else:
      T.none

proc isBusy*[T](q: SharedQueue[T]): bool =
  q[].internal.isBusy


template whileEnqueue*[T](q: SharedQueue[T]; v: sink Option[T]; op: untyped): void =
  var vv = v
  while vv.isSome and not q.blocked:
    if not q.isBusy:
      vv = q.enqueue(vv)

    if vv.isSome:
      op
      cpuRelax()


proc len*[T](q: SharedQueue[T]): int =
  q[].size.load(moRelaxed)


proc stop*[T](q: SharedQueue[T]): void =
  q[].bloc.store(true, moRelaxed)



proc blocked*[T](q: SharedQueue[T]): bool =
  q[].bloc.load(moRelaxed)


proc initLockedQueue*[T](q: SharedQueue): void =
  q[].size.store 0
  q[].internal.freeResource
  q[].bloc.store false


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
