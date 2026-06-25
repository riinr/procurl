import std/[os,json,syncio,strutils]
import curly


const STDIO_JSONL_JSONRPC*         = "stdio-v1+jsonl-v1+json-rpc-v2"
const STDIO_JSONL_JSONRPC_HELP*    = staticRead "../PROTOCOLS/STDIO-v1_JSONL-v1-JSON-RPC-v1-CURL.md"
const STDIO_JSONL_JSONRPC_OPENRPC* = staticRead "../PROTOCOLS/STDIO-v1_JSONL-v1-JSON-RPC-v1-CURL-OPEN-RPC.json"
const STDIO_JSONL_JSONRPC_ERR      = """
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": 0,
    "message": "",
    "data": {}
  }
}
"""
const STDIO_JSONL_JSONRPC_OK       = """
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "code": 0,
    "url":  "",
    "body": ""
  }
}
"""
const UNKNOWN_COMMAND_OR_PROTOCOL  = """
Unknown command or protocol!!
List of protocols: `proccurl protocols`
Protocol details:  `proccurl protocols --protocol {protocol}`
Connect protocol:  `proccurl connect   --protocol {protocol}`
"""


proc buildError*(msg: JsonNode; code: int; message: string): JsonNode =
  result = parseJson STDIO_JSONL_JSONRPC_ERR
  result["id"] = msg["id"]
  result["error"]["code"]    = %code
  result["error"]["message"] = %message
  result["error"]["data"]    = msg


proc buildSuccess*(msg: JsonNode; code: int; url, body: string; headers: HttpHeaders = emptyHttpHeaders()): JsonNode =
  result = parseJson STDIO_JSONL_JSONRPC_OK
  result["id"] = msg["id"]
  result["result"]["code"]    = %code
  result["result"]["url"]     = %url
  result["result"]["body"]    = %body
  result["result"]["headers"] = block:
    var hdrs = %* {}
    for kv in headers.items:
      hdrs{kv[0]} = % kv[1]
    hdrs


proc getHeaders*(params: JsonNode): HttpHeaders =
  result = emptyHttpHeaders()
  if params.contains("headers") and
     params["headers"].kind == JObject:
    var hdrs = newSeq[(string, string)]()
    for k, n in params["headers"].pairs:
      hdrs.add((k, n.getStr))
    if hdrs.len > 0:
      result = hdrs.toWebby


proc handleMethod*(curl: Curly; msg: JsonNode): JsonNode =
  let meth = msg["method"].getStr
  if msg["method"].getStr == "/_API/v1":
    var resp = parseJson STDIO_JSONL_JSONRPC_OPENRPC
    if msg.contains("id"): resp["id"] = msg["id"]
    return resp
  elif meth == "/curl/v0/get":
    if not msg.contains("params"):
      return buildError(msg, -32601, "Invalid method parameters, no params found")
    if not msg["params"].contains("url"):
      return buildError(msg, -32601, "Invalid method parameters, no param url found")
    let curled = curl.get(
        msg["params"]["url"].getStr,
        headers=msg["params"].getHeaders)
    return buildSuccess(msg, curled.code, curled.url, curled.body, curled.headers)
  elif meth == "/curl/v0/post":
    if not msg.contains("params"):
      return buildError(msg, -32601, "Invalid method parameters, no params found")
    if not msg["params"].contains("url"):
      return buildError(msg, -32601, "Invalid method parameters, no param url found")
    if not msg["params"].contains("body"):
      return buildError(msg, -32601, "Invalid method parameters, no param body found")
    if msg["params"]["body"].kind != JString:
      return buildError(msg, -32601, "Invalid method parameters, body should be a string")
    let curled = curl.post(
        msg["params"]["url"].getStr,
        body=msg["params"]["body"].getStr,
        headers=msg["params"].getHeaders)
    return buildSuccess(msg, curled.code, curled.url, curled.body, curled.headers)
  else:
    result = parseJson STDIO_JSONL_JSONRPC_ERR
    result["id"] = msg["id"]
    result["error"]["code"]    = %(-32601)
    result["error"]["message"] = %"Method not found"
    result["error"]["data"]    = msg


type CliActionKind* = enum
  cakShowProtocols     ## Show Protocols list
  cakShowProtocolHelp  ## Show Protocols details
  cakConnect           ## Connect using protocol
  cakUnknown           ## Unknow args


proc parseCliArgs*(args: openArray[string]): CliActionKind =
  ## Pure function: parse CLI args into an action. No I/O, no quit.
  if args.len == 1 and args[0] == "protocols":
    return cakShowProtocols
  if args.len == 3 and
     args[0] == "protocols" and
     args[1] == "--protocol" and
     args[2] == STDIO_JSONL_JSONRPC:
    return cakShowProtocolHelp
  if args.len == 3 and
     args[0] == "connect" and
     args[1] == "--protocol" and
     args[2] == STDIO_JSONL_JSONRPC:
    return cakConnect
  return cakUnknown


proc processJsonRpcLine*(curl: Curly; line: string): string =
  ## Process a single JSON-RPC line from a connect session.
  ## Returns the response string (no I/O).
  let msg = parseJson line
  return $handleMethod(curl, msg) & "\n"


proc main*(sin, sout, serr: File; params: seq[string]): void =
  let curl = newCurly()
  case parseCliArgs(params)
  of cakShowProtocols:
    write sout, STDIO_JSONL_JSONRPC
  of cakShowProtocolHelp:
    write sout, STDIO_JSONL_JSONRPC_HELP
  of cakConnect:
    var line {.cursor.}: string
    while readLine(sin, line):
      if line.strip() == "": continue
      write sout, processJsonRpcLine(curl, line)
  of cakUnknown:
    write serr, UNKNOWN_COMMAND_OR_PROTOCOL
    quit 1
  quit 0


when isMainModule:
  var params = newSeq[string]()
  for i in 1..paramCount():
    params.add i.paramStr
  main stdin, stdout, stderr, params
