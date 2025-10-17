import std/[os,json,syncio,strutils]
import curly


const STDIO_JSONL_JSONRPC = "stdio-v1+jsonl-v1+json-rpc-v2"
const STDIO_JSONL_JSONRPC_HELP = staticRead "../PROTOCOLS/STDIO-v1_JSONL-v1-JSON-RPC-v1-CURL.md"
const STDIO_JSONL_JSONRPC_OPENRPC = staticRead "../PROTOCOLS/STDIO-v1_JSONL-v1-JSON-RPC-v1-CURL-OPEN-RPC.json"

const STDIO_JSONL_JSONRPC_ERR = """
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

const STDIO_JSONL_JSONRPC_OK = """
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "code": 0,
    "url": "",
    "body": ""
  }
}
"""

const UNKNOWN_COMMAND_OR_PROTOCOL = """
Unknown command or protocol!!
List of protocols: `proccurl protocols`
Protocol details:  `proccurl protocols --protocol {protocol}`
Connect protocol:  `proccurl connect   --protocol {protocol}`
"""


when isMainModule:
  proc main(): void =
    let curl = newCurly()
    if paramCount() == 1 and 1.paramStr == "protocols":
      echo STDIO_JSONL_JSONRPC
      quit 0
    if paramCount() >= 2 and
      1.paramStr == "protocols" and
      2.paramStr == "--protocol" and
      3.paramStr == STDIO_JSONL_JSONRPC:
      echo STDIO_JSONL_JSONRPC_HELP
      quit 0
    elif paramCount() >= 3 and
      1.paramStr == "connect" and 
      2.paramStr == "--protocol" and
      3.paramStr == STDIO_JSONL_JSONRPC:
      var msg: JsonNode
      var line: string
      while readLine(stdin, line):
        if line.strip() == "": continue
        msg = parseJson line
        if msg["method"].getStr == "/_API/v1" and msg.contains("id"):
          var resp = parseJson STDIO_JSONL_JSONRPC_OPENRPC
          resp["id"] = msg["id"]
          echo resp
        elif msg["method"].getStr == "/curl/v0/get":
          if not msg.contains("params"):
            var resp = parseJson STDIO_JSONL_JSONRPC_ERR
            resp["id"] = msg["id"]
            resp["error"]["code"]    = %(-32601)
            resp["error"]["message"] = %"Invalid method parameters, no params found"
            resp["error"]["data"]    = msg
            echo resp
          elif not msg["params"].contains("url"):
            var resp = parseJson STDIO_JSONL_JSONRPC_ERR
            resp["id"] = msg["id"]
            resp["error"]["code"]    = %(-32601)
            resp["error"]["message"] = %"Invalid method parameters, no param url found"
            resp["error"]["data"]    = msg
            echo resp
          else:
            let curled = curl.get(msg["params"]["url"].getStr)
            var resp = parseJson STDIO_JSONL_JSONRPC_OK
            resp["id"] = msg["id"]
            resp["result"]["code"] = %curled.code
            resp["result"]["url"]  = %curled.url
            resp["result"]["body"] = %curled.body
            echo resp
        elif msg["method"].getStr == "/curl/v0/post":
          if not msg.contains("params"):
            var resp = parseJson STDIO_JSONL_JSONRPC_ERR
            resp["id"] = msg["id"]
            resp["error"]["code"]    = %(-32601)
            resp["error"]["message"] = %"Invalid method parameters, no params found"
            resp["error"]["data"]    = msg
            echo resp
          elif not msg["params"].contains("url"):
            var resp = parseJson STDIO_JSONL_JSONRPC_ERR
            resp["id"] = msg["id"]
            resp["error"]["code"]    = %(-32601)
            resp["error"]["message"] = %"Invalid method parameters, no param url found"
            resp["error"]["data"]    = msg
            echo resp
          elif not msg["params"].contains("body"):
            var resp = parseJson STDIO_JSONL_JSONRPC_ERR
            resp["id"] = msg["id"]
            resp["error"]["code"]    = %(-32601)
            resp["error"]["message"] = %"Invalid method parameters, no param body found"
            resp["error"]["data"]    = msg
            echo resp
          elif msg["params"]["body"].kind != JString:
            var resp = parseJson STDIO_JSONL_JSONRPC_ERR
            resp["id"] = msg["id"]
            resp["error"]["code"]    = %(-32601)
            resp["error"]["message"] = %"Invalid method parameters, body should be a string"
            resp["error"]["data"]    = msg
            echo resp
          else:
            let curled = curl.post(msg["params"]["url"].getStr, body=msg["params"]["body"].getStr)
            var resp = parseJson STDIO_JSONL_JSONRPC_OK
            resp["id"] = msg["id"]
            resp["result"]["code"] = %curled.code
            resp["result"]["url"]  = %curled.url
            resp["result"]["body"] = %curled.body
            echo resp
        else:
          var resp = parseJson STDIO_JSONL_JSONRPC_ERR
          resp["error"]["code"]    = %(-32601)
          resp["error"]["message"] = %"Method not found"
          resp["error"]["data"]    = msg
          echo resp
    else:
      write(stderr, UNKNOWN_COMMAND_OR_PROTOCOL)
      quit 1

  main()
