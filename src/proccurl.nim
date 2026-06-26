import std/[json,syncio,strutils]
import curly


const STDIO_JSONL_JSONRPC*         = "stdio-v1+jsonl-v1+json-rpc-v2"
const STDIO_JSONL_JSONRPC_HELP*    = staticRead "../PROTOCOLS/STDIO-v1_JSONL-v1_JSON-RPC-v2_OPEN-RPC-v1.md"
const STDIO_JSONL_JSONRPC_OPENRPC* = staticRead "../PROTOCOLS/STDIO-v1_JSONL-v1_JSON-RPC-v2_OPEN-RPC-v1.json"
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


iterator handleMethod*(curl: Curly; msg: JsonNode): JsonNode =
  var result = newJNull()
  if msg.kind != JObject:
    result = parseJson STDIO_JSONL_JSONRPC_ERR
    result["id"] = msg{"id"}
    result["error"]["code"]    = %(-32601)
    result["error"]["message"] = %"Method not found"
    result["error"]["data"]    = msg
    yield result
  else:
    let meth = msg["method"].getStr
    if msg["method"].getStr == "/_API/v1":
      var resp = parseJson STDIO_JSONL_JSONRPC_OPENRPC
      if msg.contains("id"): resp["id"] = msg["id"]
      yield resp
    elif meth == "/curl/v0/get":
      if not msg.contains("params"):
        yield buildError(msg, -32601, "Invalid method parameters, no params found")
      elif not msg["params"].contains("url"):
        yield buildError(msg, -32601, "Invalid method parameters, no param url found")
      else: 
        let curled = curl.get(
            msg["params"]["url"].getStr,
            headers=msg["params"].getHeaders)
        yield buildSuccess(msg, curled.code, curled.url, curled.body, curled.headers)
    elif meth == "/curl/v0/post":
      if not msg.contains("params"):
        yield buildError(msg, -32601, "Invalid method parameters, no params found")
      elif not msg["params"].contains("url"):
        yield buildError(msg, -32601, "Invalid method parameters, no param url found")
      elif not msg["params"].contains("body"):
        yield buildError(msg, -32601, "Invalid method parameters, no param body found")
      elif msg["params"]["body"].kind != JString:
        yield buildError(msg, -32601, "Invalid method parameters, body should be a string")
      else:
        let curled = curl.post(
            msg["params"]["url"].getStr,
            body=msg["params"]["body"].getStr,
            headers=msg["params"].getHeaders)
        yield buildSuccess(msg, curled.code, curled.url, curled.body, curled.headers)
    elif meth == "/curl/v0/batch":
      if not msg.contains("params"):
        yield buildError(msg, -32601, "Invalid method parameters, no params found")
      elif not msg["params"].contains("requests"):
        yield buildError(msg, -32601, "Invalid method parameters, no param request found")
      elif msg["params"]["requests"].kind != JArray:
        yield buildError(msg, -32601, "Invalid method parameters, request should be an array")
      else:
        var batch: RequestBatch
        for req in msg["params"]["requests"].items:
          if req["method"].getStr == "/curl/v0/get":
            batch.get(
              req["url"].getStr,
              headers=req.getHeaders)
          if req["method"].getStr == "/curl/v0/post":
            batch.post(
              req["url"].getStr,
              body=req["body"].getStr,
              headers=req.getHeaders)
          for (curled, error) in curl.makeRequests(batch):
            yield buildSuccess(msg, curled.code, curled.url, curled.body, curled.headers)
    else:
      result = parseJson STDIO_JSONL_JSONRPC_ERR
      result["id"] = msg["id"]
      result["error"]["code"]    = %(-32601)
      result["error"]["message"] = %"Method not found"
      result["error"]["data"]    = msg
      yield result


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


iterator processJsonRpcLine*(curl: Curly; line: string): string =
  ## Process a single JSON-RPC line from a connect session.
  ## Returns the response string (no I/O).
  let msg = parseJson line
  for resp in handleMethod(curl, msg):
    yield $resp & "\n"


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
      for resp in processJsonRpcLine(curl, line):
        write sout, resp 
  of cakUnknown:
    write serr, UNKNOWN_COMMAND_OR_PROTOCOL
    quit 1
  quit 0


when isMainModule:
  import std/os
  var params = newSeq[string]()
  for i in 1..paramCount():
    params.add i.paramStr
  main stdin, stdout, stderr, params
