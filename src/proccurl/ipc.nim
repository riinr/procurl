import std/[cmdline, memfiles]
import boring

const PAGE_SIZE = 4096

type
  QueueFormat* = enum
    qf00x00, # 00 slots of 00 KB each
    qf02x32, # 02 slots of 32  B each
    qf08x32, # 08 slots of 32 KB each
    qf16x16, # 16 slots of 16 KB each
    qf32x08, # 32 slots of 08 KB each

  Queue00x00* = Queue[00, MP[00], MC[00], array[00 * 1024, uint8]]
  Queue08x32* = Queue[08, MP[08], MC[08], array[32 * 1024, uint8]]
  Queue16x16* = Queue[16, MP[16], MC[16], array[16 * 1024, uint8]]
  Queue32x08* = Queue[32, MP[32], MC[32], array[08 * 1024, uint8]]

  QueueObj* = ref object
    case format*: QueueFormat
    of qf08x32:
      q08x32p*: ptr Queue08x32
    of qf16x16:
      q16x16p*: ptr Queue16x16
    of qf32x08:
      q32x08p*: ptr Queue32x08
    else:
      q00x00p*: ptr Queue00x00

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
    headQ*: QueueObj
    tailQ*: QueueObj


proc qSize*(qFormat: QueueFormat): uint =
  case qFormat
    of qf08x32: static cast[uint](sizeOfQ[08, array[32 * 1024, uint8]]())
    of qf16x16: static cast[uint](sizeOfQ[16, array[16 * 1024, uint8]]())
    of qf32x08: static cast[uint](sizeOfQ[32, array[08 * 1024, uint8]]())
    else:       static cast[uint](sizeOfQ[00, array[00 * 1024, uint8]]())


proc qFormat*(format: string): QueueFormat =
  result = case format
    of "08x32": qf08x32
    of "16x16": qf16x16
    of "32x08": qf32x08
    else:       qf00x00


proc new00x00QueueObj(arena: pointer): QueueObj =
  QueueObj(
    format:  qf00x00,
    q00x00p: newQueue[00, MP[00], MC[00], array[00 * 1024, uint8]](arena)
  )

proc new08x32QueueObj(arena: pointer): QueueObj =
  QueueObj(
    format:  qf08x32,
    q08x32p: newQueue[08, MP[08], MC[08], array[32 * 1024, uint8]](arena)
  )

proc new16x16QueueObj(arena: pointer): QueueObj =
  QueueObj(
    format:  qf16x16,
    q16x16p: newQueue[16, MP[16], MC[16], array[16 * 1024, uint8]](arena)
  )

proc new32x08QueueObj(arena: pointer): QueueObj =
  QueueObj(
    format:  qf32x08,
    q32x08p: newQueue[32, MP[32], MC[32], array[08 * 1024, uint8]](arena)
  )

proc newQueue*(mem: pointer; fmt: QueueFormat): QueueObj =
  case fmt
    of qf08x32: new08x32QueueObj mem
    of qf16x16: new16x16QueueObj mem
    of qf32x08: new32x08QueueObj mem
    else:       new00x00QueueObj mem


proc headArena*(ipcInfo: IpcInfo): pointer =
  ipcInfo.memFile.mem


proc tailArena*(ipcInfo: IpcInfo): pointer =
  cast[pointer](
    cast[uint](ipcInfo.memFile.mem) + ipcInfo.headSize
  )

proc createIPCInfo*(headFormat, tailFormat: QueueFormat; memFileName: string; isMyFile: bool): IpcInfo =
  let
    # make sure we have multiples of page size
    headSize = (uint(headFormat.qSize.int / PAGE_SIZE) + 1) * PAGE_SIZE
    tailSize = (uint(tailFormat.qSize.int / PAGE_SIZE) + 1) * PAGE_SIZE
    fileSize = headSize + tailSize
    memFile  =
      if isMyFile:
        memfiles.open(
          memFileName,
          mode        = fmReadWrite,
          newFileSize = fileSize.int,
        )
      else:
        memfiles.open(
          memFileName,
          mode        = fmReadWrite,
          mappedSize  = fileSize.int,
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


iterator producer*[T](q: QueueObj; v: var T): bool {.closure.} =
  var vRD = RD
  case q.format
    of qf08x32:
      var cur = q.q08x32p.producer
      while true:
        while not q.q08x32p.enqueue(cur, v, vRD, sizeof(T).uint32):
          yield false
          vRD = RD
          cur = q.q08x32p.producer
        yield true
    of qf16x16:
      var cur = q.q16x16p.producer
      while true:
        while not q.q16x16p.enqueue(cur, v, vRD, sizeof(T).uint32):
          yield false
          vRD = RD
          cur = q.q16x16p.producer
        yield true
    of qf32x08:
      var cur = q.q32x08p.producer
      while true:
        while not q.q32x08p.enqueue(cur, v, vRD, sizeof(T).uint32):
          yield false
          vRD = RD
          cur = q.q32x08p.producer
        yield true
    else:
      yield false


iterator consumer*[T](q: QueueObj; v: var T): bool {.closure.} =
  var vWD = WD
  case q.format
    of qf08x32:
      var cur = q.q08x32p.consumer
      while true:
        while not q.q08x32p.dequeue(cur, v, vWD):
          yield false
          vWD = WD
          cur = q.q08x32p.consumer
        yield true
    of qf16x16:
      var cur = q.q16x16p.consumer
      while true:
        while not q.q16x16p.dequeue(cur, v, vWD):
          yield false
          vWD = WD
          cur = q.q16x16p.consumer
        yield true
    of qf32x08:
      var cur = q.q32x08p.consumer
      while true:
        while not q.q32x08p.dequeue(cur, v, vWD):
          yield false
          vWD = WD
          cur = q.q32x08p.consumer
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
  
    var write = producer[uint8]
    var read  = consumer[uint8]
    var s = getMonoTime()
    var r = getMonoTime()
    var i: uint8 = 0
    if info.isMyFile:
      while true:
        s = getMonoTime()
        if ipc.headQ.write i:
          echo 's', inNanoseconds(getMonoTime() - s)
          inc i
        r = getMonoTime()
        if ipc.tailQ.read i:
          echo 'r', inNanoseconds(getMonoTime() - r)
    else:
      while true:
        r = getMonoTime()
        if ipc.headQ.read i:
          discard
          echo 'r', inNanoseconds(getMonoTime() - r)
          echo 'v', i
        s = getMonoTime()
        if ipc.tailQ.write i:
          echo 's', inNanoseconds(getMonoTime() - s)
          inc i

  main()
