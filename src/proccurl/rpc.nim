import std/[cmdline, memfiles]
import boring

const PAGE_SIZE = 4096
const MAX_SIZE: uint =
  static:
    cast[uint](sizeOfQ[32, array[08 * 1024, uint8]]())

type
  QueueFormat* = enum
    qf00x00, # 00 slots of 00 KB each
    qf02x32, # 02 slots of 32  B each
    qf08x32, # 08 slots of 32 KB each
    qf16x16, # 16 slots of 16 KB each
    qf32x08, # 32 slots of 08 KB each

  Queue00x00* = Queue[00, MP[00], MC[00], array[00 * 1024, uint8]]
  Queue02x32* = Queue[02, MP[02], MC[02], array[32 * 0001, uint8]]
  Queue08x32* = Queue[08, MP[08], MC[08], array[32 * 1024, uint8]]
  Queue16x16* = Queue[16, MP[16], MC[16], array[16 * 1024, uint8]]
  Queue32x08* = Queue[32, MP[32], MC[32], array[08 * 1024, uint8]]

  QueueObj* = object
    case format*: QueueFormat
    of qf00x00:
      q00x00p*: ptr Queue00x00
    of qf02x32:
      q02x32p*: ptr Queue02x32
    of qf08x32:
      q08x32p*: ptr Queue08x32
    of qf16x16:
      q16x16p*: ptr Queue16x16
    of qf32x08:
      q32x08p*: ptr Queue32x08

  IpcInfo* = object
    headFormat*:  QueueFormat
    headSize*:    uint
    isMyFile*:    bool
    memFile*:     MemFile
    memFileName*: string
    tailFormat*:  QueueFormat
    tailSize*:    uint

  Ipc* = object
    info*:  IpcInfo
    headQ*: ref QueueObj
    tailQ*: ref QueueObj


proc qSize*(qFormat: QueueFormat): uint =
  case qFormat
    of qf02x32: static cast[uint](sizeOfQ[02, array[32 * 0001, uint8]]())
    of qf08x32: static cast[uint](sizeOfQ[08, array[32 * 1024, uint8]]())
    of qf16x16: static cast[uint](sizeOfQ[16, array[16 * 1024, uint8]]())
    of qf32x08: static cast[uint](sizeOfQ[32, array[08 * 1024, uint8]]())
    else:       static cast[uint](sizeOfQ[00, array[00 * 1024, uint8]]())


proc qFormat*(format: string): QueueFormat =
  result = case format
    of "02x32": qf02x32
    of "08x32": qf08x32
    of "16x16": qf16x16
    of "32x08": qf32x08
    else:       qf00x00


proc new00x00QueueObj(arena: pointer): ref QueueObj =
  result = new QueueObj
  result.format = qf00x00
  result.q00x00p = newQueue[00, MP[00], MC[00], array[00 * 1024, uint8]](arena)

proc new02x32QueueObj(arena: pointer): ref QueueObj =
  result = new QueueObj
  result.format = qf02x32
  result.q02x32p = newQueue[02, MP[02], MC[02], array[32 * 0001, uint8]](arena)

proc new08x32QueueObj(arena: pointer): ref QueueObj =
  result = new QueueObj
  result.format = qf08x32
  result.q08x32p = newQueue[08, MP[08], MC[08], array[32 * 1024, uint8]](arena)

proc new16x16QueueObj(arena: pointer): ref QueueObj =
  result = new  QueueObj
  result.format =  qf16x16
  result.q16x16p = newQueue[16, MP[16], MC[16], array[16 * 1024, uint8]](arena)

proc new32x08QueueObj(arena: pointer): ref QueueObj =
  result = new QueueObj
  result.format = qf32x08
  result.q32x08p = newQueue[32, MP[32], MC[32], array[08 * 1024, uint8]](arena)

proc newQueue*(mem: pointer; fmt: QueueFormat): ref QueueObj =
  case fmt
    of qf02x32: new02x32QueueObj mem
    of qf08x32: new08x32QueueObj mem
    of qf16x16: new16x16QueueObj mem
    of qf32x08: new32x08QueueObj mem
    else:       new00x00QueueObj mem


proc headArena*(ipcInfo: IpcInfo): pointer =
  ipcInfo.memFile.mem


proc tailArena*(ipcInfo: IpcInfo): pointer =
  cast[pointer](
    cast[pointer](
      cast[uint](ipcInfo.memFile.mem) + MAX_SIZE
    )
  )

proc createIPCInfo*(headFormat, tailFormat: QueueFormat; memFileName: string; isMyFile: bool): IpcInfo =
  let
    headSize = headFormat.qSize
    tailSize = tailFormat.qSize
    memFile  =
      if isMyFile:
        memfiles.open(
          memFileName,
          mode = fmReadWrite,
          newFileSize = (int(int(headSize + tailSize) / PAGE_SIZE) + 1) * PAGE_SIZE,
        )
      else:
        memfiles.open(
          memFileName,
          mode = fmWrite,
          mappedSize = (int(int(headSize + tailSize) / PAGE_SIZE) + 1) * PAGE_SIZE,
        )

  IpcInfo(
    headFormat:  headFormat,
    headSize:    headSize,
    isMyFile:    isMyFile,
    memFile:     memFile,
    memFileName: memFileName,
    tailFormat:  tailFormat,
    tailSize:    tailSize,
  )


iterator producer*[T](q: ref QueueObj; v: var T): bool {.closure.} =
  var vRD = RD
  case q.format
    of qf02x32:
      var cur = q.q02x32p.producer
      while true:
        while not q.q02x32p.enqueue(cur, v, vRD, sizeof(uint8).uint32):
          yield false
          vRD = RD
          cur = q.q02x32p.producer
        yield true
    else:
      yield false


iterator consumer*[T](q: ref QueueObj; v: var T): bool {.closure.} =
  var vWD = WD
  case q.format
    of qf02x32:
      var cur = q.q02x32p.consumer
      while true:
        while not q.q02x32p.dequeue(cur, v, vWD):
          yield false
          vWD = WD
          cur = q.q02x32p.consumer
        yield true
    else:
      yield false


when isMainModule:
  import std/os
  import std/[monotimes, times]

  proc qFormatFromParam(pos: int; isHead: bool): QueueFormat =
    let format =
      if paramCount() >= pos:
        paramStr pos
      else:
        "00x00"
  
    result = format.qFormat
  
    let name =
      if isHead:
        "Head"
      else:
        "Tail"
    let pos =
      if isHead:
        "first"
      else:
        "second"

    doAssert result != qf00x00,
      "Unknown " & name & "QueueFormat " &
      $format &
      "; inform " & name & "QueueFormat as " & pos & " parameter" &
      "; know formats: 08x32, 16x16, 32x08" &
      "; AxB means A Slots of B KB each"

  template createIPCInfo*(prefix = "/tmp/ipc-", suffix = "q.mmap"): IpcInfo =
    let
      headFormat  = 1.qFormatFromParam true
      tailFormat  = 2.qFormatFromParam false
      isMyFile    = paramCount() < 3
      memFileName =
        if isMyFile:
          prefix & suffix
        else:
          3.paramStr
  
    createIpcInfo(
      headFormat,
      tailFormat,
      memFileName,
      isMyFile,
    )

  proc main() =
    var info = createIpcInfo(suffix = $getCurrentProcessId() & "-main.mmap")
    defer:
      close info.memFile
      if not info.isMyFile:
        removeFile info.memFileName
  
    let ipc  = Ipc(
      info:  info,
      headQ: info.headArena.newQueue info.headFormat,
      tailQ: info.tailArena.newQueue info.tailFormat,
    )
  
    echo "{", '"', "main", '"', ": {",
        '"', "FileName",    '"', ':', '"', ipc.info.memFileName, '"', ',',
        '"', "HeadFormat",  '"', ':', '"', ipc.info.headFormat,  '"', ',',
        '"', "TailFormat",  '"', ':', '"', ipc.info.tailFormat,  '"', ',',
        '"', "HeadSize",    '"', ':', ' ', ipc.info.headSize,    ' ', ',',
        '"', "TailSize",    '"', ':', ' ', ipc.info.tailSize,    ' ', ',',
        '"', "IsMyFile",    '"', ':', '"', ipc.info.isMyFile,    '"', ' ',
      "}}"
  
    var p = producer[uint8]
    var c = consumer[uint8]
    var s = getMonoTime()
    var r = getMonoTime()
    var i: uint8 = 0
    if info.isMyFile:
      while not (finished(p) and finished(c)):
        if not finished(p) and p(ipc.headQ, i):
          echo 's', inNanoseconds(getMonoTime() - s)
          inc i
          s = getMonoTime()
        if not finished(c) and c(ipc.tailQ, i):
          echo 'r', inNanoseconds(getMonoTime() - r)
          r = getMonoTime()
    else:
      while not (finished(p) and finished(c)):
        if not finished(c) and c(ipc.headQ, i):
          discard
          echo 'r', inNanoseconds(getMonoTime() - r)
          r = getMonoTime()
        if not finished(p) and p(ipc.tailQ, i):
          echo 's', inNanoseconds(getMonoTime() - s)
          inc i
          s = getMonoTime()

  main()
