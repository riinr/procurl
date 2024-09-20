import std/[atomics, options]

type
  RStat* = enum
    ## STATE MACHINE: FREE -> BUSY -> FREE
    FREE, ## resource is free to work
    BUSY, ## resource was taken by someone

  Stat* = Atomic[int]

  Resource*[T] = object
    stat: Atomic[int] ## resource status
    rsc*: T           ## resource

  SharedResource*[T] = ptr Resource[T]


converter toShared*[T](r: Resource[T]): SharedResource[T] = r.addr


proc freeResource*[T](r: SharedResource[T]): void =
  r[].stat.store FREE.int.static


proc isBusy*[T](r: SharedResource[T]): bool =
  r[].stat.load(moRelaxed) == BUSY.int.static


template applyIt*[T](r: SharedResource[T]; op: untyped): typed =
  ## Return true if resource was free if and operation worked
  var expected = FREE.int.static
  result = r[].stat.compareExchange(expected, BUSY.int.static, moAcquire, moRelaxed)
  if result:
    try:
      var it {.inject.}: ptr T = r[].rsc.addr
      op
    finally:
      var expected = BUSY.int.static
      doAssert r[].stat.compareExchange(expected, FREE.int.static, moRelease, moRelaxed), $result


template getIt*[T](r: SharedResource[T]; otherwise, op: untyped): untyped =
  ## Return result of the `op` if resource is available, var `it[]` is actual value
  ## Return `otherwise` if resource isn't available, var `expected` is current State
  var expected {.inject.} = FREE.int.static
  if r[].stat.compareExchange(expected, BUSY.int.static, moAcquire, moRelaxed):
    try:
      var it {.inject.}: ptr T = r.rsc.addr
      op
    finally:
      var busy = BUSY.int.static
      doAssert r[].stat.compareExchange(busy, FREE.int.static, moRelease, moRelaxed)
  else:
    otherwise


type OpRes*[T] = Option[T]
  ## Shared resource operations return parameter to be reused
  ## This helps keep single reference to parameter

template sent*[T](r: OpRes[T]):     bool = r.isNone
template acquired*[T](r: OpRes[T]): bool = r.isSome
