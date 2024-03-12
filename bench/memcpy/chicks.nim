# source
# https://github.com/timotheecour/Nim/blob/94a32119cb5eeeff2a825dc29cbbe60accb6432e/lib/std/cputicks.nim

##[
Experimental API, subject to change.
]##

#[
Future work:
* convert ticks to time; see some approaches here: https://quick-bench.com/q/WcbqUWBCoNBJvCP4n8h3kYfZDXU
* provide feature detection to test whether the CPU supports it (on linux, via /proc/cpuinfo)
* test on ARMv8-A, ARMv8-M, arm64

## js
* we use `window.performance.now()`

## nodejs
* we use `process.hrtime.bigint()`

## ARM
* The ARMv8-A architecture[1] manual explicitly states that two reads to the PMCCNTR_EL0 register may return the same value[1a].
  There is also the  CNTVCT_EL0[1b] register, however it's unclear whether that register is even monotonic (it's implied, but not stated explicitly).
  The ARMv8-M architecture[2] has the CYCCNT register, however all that's mentioned is that it is an "optional free-running 32-bit cycle counter"[2a].

## references
[1] https://documentation-service.arm.com/static/611fa684674a052ae36c7c91
[1a] See [1], PDF page 2852
[2] https://documentation-service.arm.com/static/60e6f8573d73a34b640e0cee
[2a] See [2]. PDF page 367

## further links
* https://www.intel.com/content/dam/www/public/us/en/documents/white-papers/ia-32-ia-64-benchmark-code-execution-paper.pdf
* https://gist.github.com/savanovich/f07eda9dba9300eb9ccf
* https://developers.redhat.com/blog/2016/03/11/practical-micro-benchmarking-with-ltrace-and-sched#
]#

when defined(js):
  proc getCpuTicksImpl(): int64 =
    ## Returns ticks in nanoseconds.
    # xxx consider returning JsBigInt instead of float
    when defined(nodejs):
      {.emit: """
      let process = require('process');
      `result` = Number(process.hrtime.bigint());
      """.}
    else:
      proc jsNow(): int64 {.importjs: "window.performance.now()".}
      result = jsNow() * 1_000_000
else:
  const header =
    when defined(posix): "<x86intrin.h>"
    else: "<intrin.h>"
  proc getCpuTicksImpl(): uint64 {.importc: "__rdtsc", header: header.}

template getCpuTicks*(): int64 =
  ## Returns number of CPU ticks as given by a platform specific timestamp counter,
  ## oftentimes the `RDTSC` instruction.
  ## Unlike `std/monotimes.ticks`, this gives a strictly monotonic counter at least
  ## on recent enough x86 platforms, and has higher resolution and lower overhead,
  ## allowing to measure individual instructions (corresponding to time offsets in
  ## the nanosecond range). A best effort implementation is provided when a timestamp
  ## counter is not available.
  ##
  ## Note that the CPU may reorder instructions.
  runnableExamples:
    for i in 0..<100:
      let t1 = getCpuTicks()
      # code to benchmark can go here
      let t2 = getCpuTicks()
      assert t2 > t1
  cast[int64](getCpuTicksImpl())

template toInt64(a, b): untyped =
  cast[int64](cast[uint64](a) or (cast[uint64](d) shl 32))

proc getCpuTicksStart*(): int64 {.inline.} =
  ## Variant of `getCpuTicks` which uses the `RDTSCP` instruction. Compared to
  ## `getCpuTicks`, this avoids introducing noise in the measurements caused by
  ## CPU instruction reordering, and can result in more deterministic results,
  ## at the expense of extra overhead and requiring asymetric start/stop APIs.
  ##
  ## A best effort implementation is provided for platforms where  `RDTSCP` is
  ## not available.
  runnableExamples:
    var a = 0
    for i in 0..<100:
      let t1 = getCpuTicksStart()
      # code to benchmark can go here
      let t2 = getCpuTicksEnd()
      assert t2 > t1, $(t1, t2)
  when nimvm: result = getCpuTicks()
  else:
    when defined(js): result = getCpuTicks()
    else:
      var a {.noinit.}: cuint
      var d {.noinit.}: cuint
      # See https://developers.redhat.com/blog/2016/03/11/practical-micro-benchmarking-with-ltrace-and-sched
      {.emit:"""
      asm volatile("cpuid" ::: "%rax", "%rbx", "%rcx", "%rdx");
      asm volatile("rdtsc" : "=a" (a), "=d" (d)); 
      """.}
      result = toInt64(a, b)

proc getCpuTicksEnd*(): int64 {.inline.} =
  ## See `getCpuTicksStart <#getCpuTicksStart>`_
  when nimvm: result = getCpuTicks()
  else:
    when defined(js): result = getCpuTicks()
    else:
      var a {.noinit.}: cuint
      var d {.noinit.}: cuint
      {.emit:"""
      asm volatile("rdtscp" : "=a" (a), "=d" (d)); 
      asm volatile("cpuid" ::: "%rax", "%rbx", "%rcx", "%rdx");
      """.}
      result = toInt64(a, b)
