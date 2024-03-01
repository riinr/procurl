import std/[cmdline, os, memfiles]
import boring

const PAGE_SIZE = 4096
const MAX_SIZE: uint =
  static:
    cast[uint](sizeOfQ[32, array[08 * 1024, uint8]]())

type
  QueueFormat* = enum
    qf00x00, # 00 slots of 00 KB each
    qf08x32, # 08 slots of 32 KB each
    qf16x16, # 16 slots of 16 KB each
    qf32x08, # 32 slots of 08 KB each

  Queue00x00* = Queue[00, MP[00], MC[00], array[00 * 1024, uint8]]
  Queue08x32* = Queue[08, MP[08], MC[08], array[32 * 1024, uint8]]
  Queue16x16* = Queue[16, MP[16], MC[16], array[16 * 1024, uint8]]
  Queue32x08* = Queue[32, MP[32], MC[32], array[08 * 1024, uint8]]
  
  QueueObj* = object
    case format*: QueueFormat
    of qf00x00:
      q00x00p*: ptr Queue00x00
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
    headQ*: QueueObj
    tailQ*: QueueObj


proc qSize(qFormat: QueueFormat): uint =
  case qFormat
    of qf08x32: static cast[uint](sizeOfQ[08, array[32 * 1024, uint8]]())
    of qf16x16: static cast[uint](sizeOfQ[16, array[16 * 1024, uint8]]())
    of qf32x08: static cast[uint](sizeOfQ[32, array[08 * 1024, uint8]]())
    else:       static cast[uint](sizeOfQ[00, array[00 * 1024, uint8]]())


proc qFormatFromParam(pos: int; isHead: bool): QueueFormat =
  let format =
    if paramCount() >= pos:
      paramStr pos
    else:
      "00x00"

  result = case format
    of "08x32": qf08x32
    of "16x16": qf16x16
    of "32x08": qf32x08
    else:       qf00x00

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


proc create00x00QueueObj*(arena: var openarray[uint8]): QueueObj =
  QueueObj(
    format:  qf00x00,
    q00x00p: newQueue[00, MP[00], MC[00], array[00 * 1024, uint8]](arena),
  )

proc create08x32QueueObj*(arena: var openarray[uint8]): QueueObj =
  QueueObj(
    format:  qf08x32,
    q08x32p: newQueue[08, MP[08], MC[08], array[32 * 1024, uint8]](arena),
  )

proc create16x16QueueObj*(arena: var openarray[uint8]): QueueObj =
  QueueObj(
    format:  qf16x16,
    q16x16p: newQueue[16, MP[16], MC[16], array[16 * 1024, uint8]](arena),
  )

proc create32x08QueueObj*(arena: var openarray[uint8]): QueueObj =
  QueueObj(
    format:  qf32x08,
    q32x08p: newQueue[32, MP[32], MC[32], array[08 * 1024, uint8]](arena),
  )


proc createQueue*(mem: var array[MAX_SIZE, uint8]; fmt: QueueFormat): QueueObj =
  case fmt
    of qf08x32: create08x32QueueObj mem
    of qf16x16: create16x16QueueObj mem
    of qf32x08: create32x08QueueObj mem
    else:       create00x00QueueObj mem


proc headArena(ipcInfo: IpcInfo): array[MAX_SIZE, uint8] =
  cast[var array[MAX_SIZE, uint8]](ipcInfo.memFile.mem)


proc tailArena(ipcInfo: IpcInfo): array[MAX_SIZE, uint8] =
  cast[var array[MAX_SIZE, uint8]](
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


iterator qProducer(q: QueueObj): uint8 {.closure.} =
  var queue   = q.q16x16p
  var cur     = queue.producer
  var vRD     = RD
  var i:uint8 = 0

  while true:
    var a = 0
    while not queue.enqueue(cur, i, vRD, sizeof(uint8).uint32):
      yield i
      vRD = RD
      cur = queue.producer
      echo "Attempt: ", a, " to insert value ", i
      if a > 200:
        break
      else:
        inc a

    yield i
    if i > 100:
      break
    else:
      inc i


iterator qConsumer(q: QueueObj): uint8 {.closure.} =
  var queue   = q.q16x16p
  var cur     = queue.consumer
  var vWD     = WD
  var i:uint8 = 0

  while true:
    var a = 0
    while not queue.dequeue(cur, i, vWD):
      yield i
      vWD = WD
      cur = queue.consumer
      echo "Attempt: ", a, " to read value, last value ", i
      if a > 200:
        break
      else:
        inc a

    yield i
    if i > 95:
      break


proc main() =
  var info = createIpcInfo(suffix = $getCurrentProcessId() & "-main.mmap")
  defer:
    close info.memFile
    if not info.isMyFile:
      removeFile info.memFileName

  var
    hArena = info.headArena
    tArena = info.tailArena

  let ipc  = Ipc(
    info:  info,
    headQ: hArena.createQueue info.headFormat,
    tailQ: tArena.createQueue info.tailFormat,
  )

  echo "[main]"
  echo "FileName = ",   '"', ipc.info.memFileName, '"'
  echo "HeadFormat = ", '"', ipc.info.headFormat,  '"'
  echo "TailFormat = ", '"', ipc.info.tailFormat,  '"'
  echo "HeadSize = ",        ipc.info.headSize
  echo "TailSize = ",        ipc.info.tailSize
  echo "IsMyFile = ",        ipc.info.isMyFile
  echo ""

  var p = qProducer
  var c = qConsumer
  if info.isMyFile:
    while not (finished(p) and finished(c)):
      sleep 500
      if not finished(p):
        discard p(ipc.headQ)
      if not finished(c):
        discard c(ipc.tailQ)
  else:
    while not (finished(p) and finished(c)):
      sleep 500
      if not finished(c):
        discard c(ipc.headQ)
      if not finished(p):
        discard p(ipc.tailQ)

when isMainModule:
  main()
