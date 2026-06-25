import std/[unittest, json, strutils]
import proccurl
import curly


# ---------------------------------------------------------------------------
# buildError — pure function tests
# ---------------------------------------------------------------------------

suite "buildError":

  test "returns jsonrpc 2.0":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildError(msg, -32000, "error msg")
    check resp["jsonrpc"].getStr == "2.0"

  test "id matches input msg id (integer)":
    let msg = %*{"jsonrpc": "2.0", "id": 42, "method": "test"}
    let resp = buildError(msg, -32000, "error msg")
    check resp["id"].getInt == 42

  test "id matches input msg id (string)":
    let msg = %*{"jsonrpc": "2.0", "id": "req-001", "method": "test"}
    let resp = buildError(msg, -32000, "error msg")
    check resp["id"].getStr == "req-001"

  test "id matches input msg id (null)":
    let msg = %*{"jsonrpc": "2.0", "id": nil, "method": "test"}
    let resp = buildError(msg, -32000, "error msg")
    check resp["id"].kind == JNull

  test "error.code matches code parameter":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildError(msg, -32601, "some error")
    check resp["error"]["code"].getInt == -32601

  test "error.code handles zero":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildError(msg, 0, "ok")
    check resp["error"]["code"].getInt == 0

  test "error.message matches message parameter":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildError(msg, -32000, "Invalid method parameters, no params found")
    check resp["error"]["message"].getStr == "Invalid method parameters, no params found"

  test "error.message handles empty string":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildError(msg, -32000, "")
    check resp["error"]["message"].getStr == ""

  test "error.data contains the original msg":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test", "params": {"url": "http://example.com"}}
    let resp = buildError(msg, -32000, "error")
    check resp["error"]["data"]["method"].getStr == "test"
    check resp["error"]["data"]["params"]["url"].getStr == "http://example.com"

  test "error.data preserves input id":
    let msg = %*{"jsonrpc": "2.0", "id": 99, "method": "test"}
    let resp = buildError(msg, -32000, "error")
    check resp["error"]["data"]["id"].getInt == 99


# ---------------------------------------------------------------------------
# buildSuccess — pure function tests
# ---------------------------------------------------------------------------

suite "buildSuccess":

  test "returns jsonrpc 2.0":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg, 200, "http://example.com", "ok")
    check resp["jsonrpc"].getStr == "2.0"

  test "id matches input msg id (integer)":
    let msg = %*{"jsonrpc": "2.0", "id": 42, "method": "test"}
    let resp = buildSuccess(msg, 200, "url", "body")
    check resp["id"].getInt == 42

  test "id matches input msg id (string)":
    let msg = %*{"jsonrpc": "2.0", "id": "req-002", "method": "test"}
    let resp = buildSuccess(msg, 200, "url", "body")
    check resp["id"].getStr == "req-002"

  test "id matches input msg id (null)":
    let msg = %*{"jsonrpc": "2.0", "id": nil, "method": "test"}
    let resp = buildSuccess(msg, 200, "url", "body")
    check resp["id"].kind == JNull

  test "result.code matches code parameter":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg, 200, "url", "body")
    check resp["result"]["code"].getInt == 200

  test "result.code handles zero":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg, 0, "url", "body")
    check resp["result"]["code"].getInt == 0

  test "result.url matches url parameter":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg, 200, "http://example.com/foo", "body")
    check resp["result"]["url"].getStr == "http://example.com/foo"

  test "result.url handles empty string":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg, 200, "", "body")
    check resp["result"]["url"].getStr == ""

  test "result.body matches body parameter":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg, 200, "url", "response body")
    check resp["result"]["body"].getStr == "response body"

  test "result.body handles empty string":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let resp = buildSuccess(msg, 200, "url", "")
    check resp["result"]["body"].getStr == ""

  test "result.body handles multi-line content":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "test"}
    let multiLine = "line1\nline2\nline3"
    let resp = buildSuccess(msg, 200, "url", multiLine)
    check resp["result"]["body"].getStr == "line1\nline2\nline3"


# ---------------------------------------------------------------------------
# Constants validation
# ---------------------------------------------------------------------------

suite "Constants":

  test "STDIO_JSONL_JSONRPC equals expected protocol string":
    check STDIO_JSONL_JSONRPC == "stdio-v1+jsonl-v1+json-rpc-v2"

  test "STDIO_JSONL_JSONRPC_HELP is non-empty":
    check STDIO_JSONL_JSONRPC_HELP.len > 0

  test "STDIO_JSONL_JSONRPC_HELP contains protocol keyword":
    check STDIO_JSONL_JSONRPC in STDIO_JSONL_JSONRPC_HELP

  test "STDIO_JSONL_JSONRPC_OPENRPC is non-empty":
    check STDIO_JSONL_JSONRPC_OPENRPC.len > 0

  test "STDIO_JSONL_JSONRPC_OPENRPC parses as valid JSON":
    let parsed = parseJson(STDIO_JSONL_JSONRPC_OPENRPC)
    check parsed.kind == JObject

  test "STDIO_JSONL_JSONRPC_OPENRPC contains openrpc field in result":
    let parsed = parseJson(STDIO_JSONL_JSONRPC_OPENRPC)
    check parsed["result"]["openrpc"].getStr == "1.2.1"


# ---------------------------------------------------------------------------
# handleMethod — validation paths (no HTTP calls made)
# ---------------------------------------------------------------------------

suite "handleMethod":

  let curl = newCurly()

  test "GET with missing params returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/get"}
    let resp = handleMethod(curl, msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, no params found"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/get"

  test "GET with params but no url returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/get", "params": {}}
    let resp = handleMethod(curl, msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, no param url found"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/get"

  test "POST with missing params returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/post"}
    let resp = handleMethod(curl, msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, no params found"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/post"

  test "POST with params but no url returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/post", "params": {}}
    let resp = handleMethod(curl, msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, no param url found"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/post"

  test "POST with url but no body returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/post",
                 "params": {"url": "http://example.com"}}
    let resp = handleMethod(curl, msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, no param body found"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/post"

  test "POST with non-string body returns error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/post",
                 "params": {"url": "http://example.com", "body": 123}}
    let resp = handleMethod(curl, msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Invalid method parameters, body should be a string"
    check resp["error"]["data"]["method"].getStr == "/curl/v0/post"

  test "Unknown method returns Method not found error":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/unknown/method"}
    let resp = handleMethod(curl, msg)
    check resp["error"]["code"].getInt == -32601
    check resp["error"]["message"].getStr == "Method not found"
    check resp["error"]["data"]["method"].getStr == "/unknown/method"

  test "Unknown method preserves input id":
    let msg = %*{"jsonrpc": "2.0", "id": 99, "method": "/does/not/exist"}
    let resp = handleMethod(curl, msg)
    check resp["id"].getInt == 99

  test "Error responses always return jsonrpc 2.0":
    let msg = %*{"jsonrpc": "2.0", "id": 1, "method": "/curl/v0/get"}
    let resp = handleMethod(curl, msg)
    check resp["jsonrpc"].getStr == "2.0"


# ---------------------------------------------------------------------------
# parseCliArgs — pure function tests
# ---------------------------------------------------------------------------

suite "parseCliArgs":

  test "protocols returns cakShowProtocols":
    check parseCliArgs(@["protocols"]) == cakShowProtocols

  test "protocols with help flag returns cakShowProtocolHelp":
    check parseCliArgs(@["protocols", "--protocol", STDIO_JSONL_JSONRPC]) == cakShowProtocolHelp

  test "connect with protocol returns cakConnect":
    check parseCliArgs(@["connect", "--protocol", STDIO_JSONL_JSONRPC]) == cakConnect

  test "empty args returns cakUnknown":
    check parseCliArgs(newSeq[string]()) == cakUnknown

  test "unknown command returns cakUnknown":
    check parseCliArgs(@["something"]) == cakUnknown

  test "protocols with extra args returns cakUnknown":
    check parseCliArgs(@["protocols", "extra"]) == cakUnknown

  test "connect without protocol returns cakUnknown":
    check parseCliArgs(@["connect"]) == cakUnknown

  test "protocols with wrong protocol returns cakUnknown":
    check parseCliArgs(@["protocols", "--protocol", "other"]) == cakUnknown

  test "connect with wrong protocol returns cakUnknown":
    check parseCliArgs(@["connect", "--protocol", "other"]) == cakUnknown


# ---------------------------------------------------------------------------
# processJsonRpcLine — validation paths (no HTTP calls made)
# ---------------------------------------------------------------------------

suite "processJsonRpcLine":

  let curl = newCurly()

  test "_API/v1 returns openrpc result":
    let line = """{"jsonrpc":"2.0","id":1,"method":"/_API/v1"}"""
    let resp = processJsonRpcLine(curl, line)
    let parsed = parseJson(resp)
    check parsed["result"]["openrpc"].getStr == "1.2.1"
    check resp.endsWith("\n")

  test "GET without params returns error":
    let line = """{"jsonrpc":"2.0","id":1,"method":"/curl/v0/get"}"""
    let resp = processJsonRpcLine(curl, line)
    let parsed = parseJson(resp)
    check parsed["error"]["code"].getInt == -32601
    check resp.endsWith("\n")

  test "POST without body returns error":
    let line = """{"jsonrpc":"2.0","id":1,"method":"/curl/v0/post","params":{"url":"http://example.com"}}"""
    let resp = processJsonRpcLine(curl, line)
    let parsed = parseJson(resp)
    check parsed["error"]["code"].getInt == -32601
    check parsed["error"]["message"].getStr == "Invalid method parameters, no param body found"
    check resp.endsWith("\n")

  test "POST with non-string body returns error":
    let line = """{"jsonrpc":"2.0","id":1,"method":"/curl/v0/post","params":{"url":"http://example.com","body":123}}"""
    let resp = processJsonRpcLine(curl, line)
    let parsed = parseJson(resp)
    check parsed["error"]["code"].getInt == -32601
    check parsed["error"]["message"].getStr == "Invalid method parameters, body should be a string"
    check resp.endsWith("\n")

  test "Unknown method returns error":
    let line = """{"jsonrpc":"2.0","id":1,"method":"/nothing"}"""
    let resp = processJsonRpcLine(curl, line)
    let parsed = parseJson(resp)
    check parsed["error"]["code"].getInt == -32601
    check parsed["error"]["message"].getStr == "Method not found"
    check resp.endsWith("\n")

  test "Response ends with newline":
    let line = """{"jsonrpc":"2.0","id":1,"method":"/_API/v1"}"""
    let resp = processJsonRpcLine(curl, line)
    check resp.endsWith("\n")
