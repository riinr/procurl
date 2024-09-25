import std/[monotimes, posix]

type
  NanoSeconds*  = distinct int64
  MicroSeconds* = distinct int64
  MiliSeconds*  = distinct int64
  Seconds*      = distinct int64


proc s* (t: int64): Seconds      = cast[Seconds](t)
proc ms*(t: int64): MiliSeconds  = cast[MiliSeconds](t)
proc us*(t: int64): MicroSeconds = cast[MicroSeconds](t)
proc ns*(t: int64): NanoSeconds  = cast[NanoSeconds](t)

converter ms*(t: Seconds):      MiliSeconds  = cast[MiliSeconds ](cast[int64](t) * 1000)
converter us*(t: MiliSeconds):  MicroSeconds = cast[MicroSeconds](cast[int64](t) * 1000)
converter us*(t: Seconds):      MicroSeconds = cast[MicroSeconds](cast[int64](t) * 1000_1000)
converter ns*(t: MicroSeconds): NanoSeconds  = cast[NanoSeconds ](cast[int64](t) * 1000)
converter ns*(t: MiliSeconds):  NanoSeconds  = cast[NanoSeconds ](cast[int64](t) * 1000_1000)
converter ns*(t: Seconds):      NanoSeconds  = cast[NanoSeconds ](cast[int64](t) * 1000_1000_1000)


converter ss* (t: NanoSeconds):  Seconds      = cast[Seconds     ](cast[int64](t) div 1000_1000_1000)
converter ss* (t: MicroSeconds): Seconds      = cast[Seconds     ](cast[int64](t) div 1000_1000)
converter ss* (t: MiliSeconds):  Seconds      = cast[Seconds     ](cast[int64](t) div 1000)
converter sm* (t: NanoSeconds):  MiliSeconds  = cast[MiliSeconds ](cast[int64](t) div 1000_1000)
converter sm* (t: MicroSeconds): MiliSeconds  = cast[MiliSeconds ](cast[int64](t) div 1000)
converter su* (t: NanoSeconds):  MicroSeconds = cast[MicroSeconds](cast[int64](t) div 1000)


template zeroFill(t: int64): string =
  if   t < 010: "00" & $t
  elif t < 100:  "0" & $t
  else:                $t

converter `$`*(t: Seconds):      string =
  result = if cast[int64](t) != 0: "\e[31m" else: "\e[30m"
  result = result & cast[int64](t).zeroFill & "s"
  result = result & "\e[0m"

converter `$`*(t: MiliSeconds):  string =
  result = $t.ss
  result = result & (if cast[int64](t) != 0: "\e[33m" else: "\e[30m")
  result = result & (cast[int64](t) - cast[int64](t.ss.ms)).zeroFill & "ms"
  result = result & "\e[0m"

converter `$`*(t: MicroSeconds): string =
  result = $t.sm
  result = result & (if cast[int64](t) != 0: "\e[34m" else: "\e[30m")
  result = result & (cast[int64](t) - cast[int64](t.sm.us)).zeroFill & "us"
  result = result & "\e[0m"

converter `$`*(t: NanoSeconds):  string =
  result = $t.su
  result = result & (if cast[int64](t) != 0: "\e[32m" else: "\e[30m")
  result = result & (cast[int64](t) - cast[int64](t.su.ns)).zeroFill & "ns"
  result = result & "\e[0m"


using 
  ns: NanoSeconds
  us: MicroSeconds
  ms: MiliSeconds
  ss: Seconds
  # other
  on: NanoSeconds
  ou: MicroSeconds
  om: MiliSeconds
  os: Seconds


proc `*`*(ms; ns): NanoSeconds  = cast[NanoSeconds ](cast[int64](ms.ns) * cast[int64](ns))
proc `*`*(ms; om): MiliSeconds  = cast[MiliSeconds ](cast[int64](ms)    * cast[int64](om))
proc `*`*(ms; us): MicroSeconds = cast[MicroSeconds](cast[int64](ms.us) * cast[int64](us))
proc `*`*(ns; on): NanoSeconds  = cast[NanoSeconds ](cast[int64](ns)    * cast[int64](on))
proc `*`*(ss; ms): MiliSeconds  = cast[MiliSeconds ](cast[int64](ss.ms) * cast[int64](ms))
proc `*`*(ss; ns): NanoSeconds  = cast[NanoSeconds ](cast[int64](ss.ns) * cast[int64](ns))
proc `*`*(ss; os): Seconds      = cast[Seconds     ](cast[int64](ss)    * cast[int64](os))
proc `*`*(ss; us): MicroSeconds = cast[MicroSeconds](cast[int64](ss.us) * cast[int64](us))
proc `*`*(us; ns): NanoSeconds  = cast[NanoSeconds ](cast[int64](us.ns) * cast[int64](ns))
proc `*`*(us; ou): MicroSeconds = cast[MicroSeconds](cast[int64](us)    * cast[int64](ou))

proc `+`*(ms; ns): NanoSeconds  = cast[NanoSeconds ](cast[int64](ms.ns) + cast[int64](ns))
proc `+`*(ms; om): MiliSeconds  = cast[MiliSeconds ](cast[int64](ms)    + cast[int64](om))
proc `+`*(ms; us): MicroSeconds = cast[MicroSeconds](cast[int64](ms.us) + cast[int64](us))
proc `+`*(ns; on): NanoSeconds  = cast[NanoSeconds ](cast[int64](ns)    + cast[int64](on))
proc `+`*(ss; ms): MiliSeconds  = cast[MiliSeconds ](cast[int64](ss.ms) + cast[int64](ms))
proc `+`*(ss; ns): NanoSeconds  = cast[NanoSeconds ](cast[int64](ss.ns) + cast[int64](ns))
proc `+`*(ss; os): Seconds      = cast[Seconds     ](cast[int64](ss)    + cast[int64](os))
proc `+`*(ss; us): MicroSeconds = cast[MicroSeconds](cast[int64](ss.us) + cast[int64](us))
proc `+`*(us; ns): NanoSeconds  = cast[NanoSeconds ](cast[int64](us.ns) + cast[int64](ns))
proc `+`*(us; ou): MicroSeconds = cast[MicroSeconds](cast[int64](us)    + cast[int64](ou))

proc `-`*(ms; ns): NanoSeconds  = cast[NanoSeconds ](cast[int64](ms.ns) - cast[int64](ns))
proc `-`*(ms; om): MiliSeconds  = cast[MiliSeconds ](cast[int64](ms)    - cast[int64](om))
proc `-`*(ms; us): MicroSeconds = cast[MicroSeconds](cast[int64](ms.us) - cast[int64](us))
proc `-`*(ns; on): NanoSeconds  = cast[NanoSeconds ](cast[int64](ns)    - cast[int64](on))
proc `-`*(ss; ms): MiliSeconds  = cast[MiliSeconds ](cast[int64](ss.ms) - cast[int64](ms))
proc `-`*(ss; ns): NanoSeconds  = cast[NanoSeconds ](cast[int64](ss.ns) - cast[int64](ns))
proc `-`*(ss; os): Seconds      = cast[Seconds     ](cast[int64](ss)    - cast[int64](os))
proc `-`*(ss; us): MicroSeconds = cast[MicroSeconds](cast[int64](ss.us) - cast[int64](us))
proc `-`*(us; ns): NanoSeconds  = cast[NanoSeconds ](cast[int64](us.ns) - cast[int64](ns))
proc `-`*(us; ou): MicroSeconds = cast[MicroSeconds](cast[int64](us)    - cast[int64](ou))

proc sleep*(ns = 1.ns; us = 0.us; ms = 0.ms; s = 0.s): void =
  ## Sleep for posix system, allow for ns precision
  ## while isn't granted it would take 1ns presion
  ## is better than 1ms default of `system.sleep`
  var a, b: Timespec
  a.tv_sec  = posix.Time s.int
  a.tv_nsec = cast[int64](ms + us + ns)
  b.tv_sec  = posix.Time 0
  b.tv_nsec = 0
  discard posix.nanosleep(a, b)

const SPIN_MAX  = 02_000
const SLEEP_MIN = 50_000

proc spin*(ns = 1.ns; us = 0.us; ms = 0.ms; s = 0.s): int64 {.discardable.}=
  ## Loose time doing something sily
  ## Unless it has to loose so much time that a sleep would be worth
  let t = cast[int64](s + ms + us + ns)
  let epch = getMonoTime().ticks
  result = 0
  while result < t:
    if t - result > SLEEP_MIN:  # SPIN as SLEEP 
      sleep ns, us, ms, s
    elif t - result > SPIN_MAX: # SPIN as SYSCALL
      var interval: Timeval
      interval.tv_sec  = posix.Time 0
      interval.tv_usec = cast[int64](su(us + ns))
      discard close 2147483647
    cpuRelax()
    result = getMonoTime().ticks - epch


when isMainModule:
  proc main: void =
    var epch = getMonoTime().ticks
    echo " nanoseconds ", getMonoTime().ticks - epch
    echo " nanoseconds ", spin 01.ns
    echo " nanoseconds ", spin 03.us
    echo " nanoseconds ", spin 04.us
    echo " nanoseconds ", spin 51.us

  main()
