
when isMainModule:
  import std/[os]
  proc main(): void =
    if paramCount() >= 1 and 1.paramStr == "--protocols":
      echo """
{
  "version": 0,
  "transports": {
    "mmap_boring": {
      "speedRate": 10,
      "options": {
        "tailFormat": ["00x00", "02x32", "08x32", "16x16", "32x08"]
        "headFormat": ["00x00", "02x32", "08x32", "16x16", "32x08"]
      }
    }
  },
  "formats": {
    "raw":    { "speedRate": 20 }
  }
}"""
      quit 0

  main()
