# procCurl

### What?

Linux command/lib POC to use libcurl without¹ linking


### Why?

Every time we have to make a http request, we have some options:

1. Dynamic link our application with some SSL lib
  - pros:
    - Small executable size
    - Easier to update SSL lib
  - cons:
    - Easy to have incompatibility problems, system version won't match;
    - Easy to have conflict problems when it tries to install same lib twice;

2. Static link our application with some SSL lib
  - pros:
    - Less conflict/incompatibility problems
    - Easier to install
  - cons:
    - Larger executable size
    - Harder to update SSL lib

We're trying to make a small size, easier to update, easier to install, less conflict prone application.


### How?

Dividing our application in two:

- One dynamic (or static)¹ linked with libcurl, lets call it "procCurlI"
- Other our actual application that will communicate with previous one, linked with a new lib called "libProcCurl".

This pattern isn't new, is called [UCSPI](https://cr.yp.to/proto/ucspi.txt), we may
differ a bit here on communication.


### What is the catch?

When someone offers something, there is always small letter at the end.
<small>
1. **¹** we are linking at libcurl, maybe not your main app but someone has to link it;
2. We are not only linking with libcurl, but now we have other lib to link;
3. Most important than provious points, we lose speed, not mesured yet, but there is no way to match dynamic/static linking [speed with IPC](https://github.com/goldsborough/ipc-bench).
<small>


### What about security?

In theory we can run "procCurlI" with less privilegies than our application linked with libProcCurl, it means if libCurl or [its dependêncies](https://curl.se/docs/libs.html) has any security issue they are isolated.

Future implementation may share memory for speed, in this case we are expecting same security of dynamic linked libs. The [idea is to use mmap](https://blog.cloudflare.com/scalable-machine-learning-at-cloudflare/) and share memory as must as possible to make it ~~fast~~ less slow.


### Why this is a POC?

Until completed we're not sure about speed loss.

It should be a lib not only for http, but lib for IPC with schema (like Cap'n Proto or Thrift) to make other integrations like DB, SSH, etc.


## More details

1. libProcCurl starts procCurlI with `--protocols`
  1. procCurlI returns a json with with transports, serialization formats and version to stdout.
    1. Transports are any transport supported by like io, tcp, unix, mmap, others, libProcCurl may try to use the fastest.
    2. Serialization formats like JSONRPC, grpc, msgpack-rpc and others, libProcCurl may try to use the fastest.
    3. Version is minor version in [SemVer](https://semver.org/), major version is defined by execuble name
        ie (procCurlI, procCurlII, etc), patch won't make sense to be exposed, libProcCurl may try use lastest available.
2. libProcCurl reads protocols json to form a URI `{transport}://({ip}|{dir}/{session}.{format}`
  1. Transport from --protocols json
  2. ip or dir depending on the transport
  3. session, a randon string to make it possible run multiple client instances wihtout conflict
  4. format, serialization format (ie. .jsonrpc, .grpc, etc)
3. libProcCurl starts procCurlI with URI as last parameter, libProcCurl should be flexible to accept URI from parameter and skip step 1.
  1. procCurlI uses URI to create a connection and wait for messages.
4. libProcCurl uses URI to create a connection and start sending messages.

### Protocols JSON:

Example:

```json5
{
  "transports": {
    "tcp": {
      "speedRate": 1
    },
    "io": {
      "speedRate": 5
    },
    "mmap_boring": {
      "rate": 10
    }
  },
  "formats": {
    "jsonrpc": {
      "rate": 1
    },
    "grpc": {
      "rate": 10
    }
    "msgpack-rpc": {
      "rate": 10
    }
    "raw": { // fast but imparity prone
      "rate": 20
    }
  },
  "version": 2
}
```

libProcCurl should sort by `rate` as greatest is fastest and choose fastest it knows.

libProcCurl may accept or  minVersion parameter and compare with version, throwing an exception.


## TODO:

- [ ] Define spec (almost completed)
- [ ] Evaluate min requirements (ie: JSON or msgpack, mmap or FD, etc)
- [ ] POC
  1. [x] RingBuffer
  2. [x] Inter Process Communication (IPC) with MMAP
  3. [ ] Serialization (or no serialization)
  4. [ ] Messages (IPC API)
  4. [ ] libProcCurl API

## Benchmarks:

### MemCopy

Tries to measure the most efficient size to copy, check [./memcpybench/memcopybench.sh](for more info) for mor info and results.

### Ring Buffer

Tries to measure two or more threads sending nanoseconds to each other.

- i5-1240P/LPDDR5 5200MHz 
- Linux T1 6.1.69 NixOS SMP PREEMPT DYNAMIC Dec 20 16:00:29 UTC 2023 x86-64


#### SCSP

Single Producer (1 thread), Single Consumer (1 thread)

|Sending NS|Receiving NS|Latency NS|Send Retries|Receiving Retries|
| -| -| -| -| -|
|24694|249|3951|0|0|
|84|156|4024|0|0|
|34|70|4052|0|0|
|35|126|4142|0|0|
|36|218|4325|0|0|
|132|310|883|109|0|
|180|314|1018|0|0|
|218|319|1119|0|0|
|190|313|1243|0|0|
|206|315|1351|0|0|
|197|253|1408|0|0|
|204|149|1355|0|0|
|93|214|1246|1|0|
|98|332|1272|1|0|
|77|320|1265|2|0|
|112|220|1293|1|0|
|227|316|1382|0|0|
|205|317|1492|0|0|
|78|315|1485|2|0|
|93|325|1484|2|0|
|219|316|1580|0|0|
|108|318|1582|1|0|
|87|319|1590|2|0|
|108|219|1483|1|0|
|93|319|1491|2|0|
|84|321|1494|2|0|
|85|313|1490|2|0|
|98|73|1237|2|0|
|221|279|1296|0|0|
|103|168|1151|1|0|
|83|212|1043|2|0|
|79|245|962|2|0|
|321|121|797|0|0|
|228|287|869|0|0|
|224|114|807|0|0|
|209|290|888|0|0|
|107|132|962|0|0|
|183|408|1191|0|0|
|80|338|1428|0|0|
|103|2518|3830|0|0|
|125|351|3851|2|0|
|122|358|4074|0|0|
|108|348|3898|4|0|
|130|244|3789|2|0|
|2502|350|1636|0|0|
|113|228|1506|2|0|
|127|190|1345|1|0|
|102|36|1034|2|0|
|242|83|875|0|0|
|98|100|633|2|0|


#### MCSP

Multiple Producer (2 threads), Single Consumer (1 thread).

|Sending NS|Receiving NS|Latency NS|Send Retries|Receiving Retries|
| -| -| -| -| -|
|1489|246|120717|0|0|
|74|287|120760|1|0|
|57|147|120850|0|0|
|47|358|121162|0|0|
|20582|92|101858|1|0|
|374|324|897|689|0|
|468|306|766|1152|0|
|309|116|798|1|0|
|491|309|608|0|0|
|446|254|570|2|0|
|354|306|626|1|0|
|498|420|575|1|0|
|305|231|765|1|0|
|211|262|810|0|0|
|393|454|872|0|0|
|362|95|607|0|0|
|548|501|706|4|0|
|436|270|760|1|0|
|379|288|663|0|0|
|466|115|504|2|0|
|425|302|599|1|0|
|451|302|456|1|0|
|291|518|938|1|0|
|551|270|651|0|0|
|438|303|664|2|0|
|154|302|901|1|0|
|423|257|728|0|0|
|456|82|513|2|0|
|331|252|514|1|0|
|360|354|502|0|0|
|528|310|391|2|0|
|411|232|411|1|0|
|367|278|316|0|0|
|544|268|192|2|0|
|475|274|207|1|0|
|491|297|64|1|0|
|474|255|57|1|0|
|420|366|306|1|1|
|368|290|304|1|0|
|443|88|10|1|0|
|494|204|62|1|1|
|418|93|5|1|1|
|530|298|166|1|2|
|437|121|99|1|0|
|302|157|109|0|1|
|308|244|46|0|0|
|341|98|63|0|2|
|247|156|113|0|1|
|245|243|111|0|0|
|243|248|117|0|0|


#### SCMP

Single Producer (1 thread), Multiple Consumer (2 threads)

|Sending NS|Receiving NS|Latency NS|Send Retries|Receiving Retries|
| -| -| -| -| -|
|809|280|8704|0|0|
|60|304|8955|0|0|
|43|287|9192|0|0|
|31|295|9454|0|0|
|30|283|9707|0|0|
|159|295|1494|287|0|
|281|304|1510|0|0|
|97|289|1505|1|0|
|281|288|1505|0|0|
|296|310|1515|0|0|
|303|282|1493|0|0|
|79|286|1495|1|0|
|76|295|1502|1|0|
|306|363|1559|0|0|
|77|289|1559|1|0|
|78|340|1614|1|0|
|91|296|1620|1|0|
|338|305|1585|0|0|
|81|303|1573|2|0|
|105|299|1558|1|0|
|89|293|1531|2|0|
|305|290|1514|0|0|
|104|298|1509|1|0|
|102|293|1502|1|0|
|87|290|1506|1|0|
|79|266|17895|1|0|
|305|322|17947|0|0|
|96|326|17988|1|0|
|86|338|18036|1|0|
|86|319|18064|1|0|
|148|323|1652|587|0|
|309|316|1660|0|0|
|106|346|1674|1|0|
|344|340|1671|0|0|
|325|339|1685|0|0|
|101|333|1707|1|0|
|339|343|1712|0|0|
|334|339|1716|0|0|
|337|333|1712|0|0|
|90|344|1720|2|0|
|115|333|1711|1|0|
|340|336|1706|0|0|
|116|331|1709|1|0|
|98|334|1696|2|0|
|338|335|1694|0|0|
|335|339|1699|0|0|
|114|70|1444|1|0|
|88|43|1151|2|0|
|330|70|893|0|0|
|344|68|618|0|0|


#### MCMP

Multiple Producer (2 threads), Multiple Consumer (2 threads)

|Sending NS|Receiving NS|Latency NS|Send Retries|Receiving Retries|
| -| -| -| -| -|
|1402|333|26486|0|0|
|89|164|26530|0|0|
|50|189|26650|0|0|
|49|252|26854|0|0|
|49|309|27116|0|0|
|361|250|935|390|0|
|247|331|1010|0|0|
|259|117|869|0|0|
|305|236|839|155|0|
|428|289|755|1|0|
|390|226|774|1|0|
|287|90|610|1|0|
|303|243|586|1|0|
|253|104|438|0|0|
|562|132|62|2|0|
|304|284|304|1|0|
|418|310|193|0|0|
|224|277|400|2|0|
|333|256|322|0|0|
|404|292|211|0|0|
|242|268|381|3|0|
|327|317|371|0|0|
|250|319|440|2|0|
|241|212|450|1|0|
|533|146|61|0|0|
|347|386|19561|2|0|
|254|132|19470|0|0|
|218|275|19541|2|0|
|230|309|19660|1|0|
|340|327|19677|1|0|
|255|326|1285|168|0|
|312|305|1384|166|0|
|241|255|1399|0|0|
|311|258|1345|0|0|
|502|257|1096|0|0|
|389|87|996|6|0|
|251|284|1022|0|0|
|255|366|1134|0|0|
|253|126|1006|0|0|
|193|142|636|1|0|
|599|86|635|4|0|
|250|210|703|0|0|
|223|96|518|1|0|
|190|246|574|0|0|
|371|249|451|0|0|
|243|95|303|0|0|
|230|88|160|0|0|
|246|150|65|0|0|
|250|204|196|0|1|
|365|83|96|0|1|
