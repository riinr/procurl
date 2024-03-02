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
    1. Transports are any transport supported by [NNG](https://nng.nanomsg.org/man/tip/nng.7.html#protocols) like io (required), others (optional), libProcCurl may try to use the fastest.
    2. Serialization formats like JSONRPC (required), and others (optional), libProcCurl may try to use the fastest.
    3. Version is minor version in [SemVer](https://semver.org/), major version is defined by execuble name ie (procCurlI, procCurlII, etc), patch won't make sense to be exposed, libProcCurl may try use lastest available.
2. libProcCurl reads protocols json to form a URI `{transport}://({ip}|{dir}/{session}.{format}`
  1. Transport from --protocols json
  2. ip or dir depending on the transport
  3. session, a randon string to make it possible run multiple client instances wihtout conflict
  4. format, serialization format (ie. .jsonrpc, .grpc, etc)
3. libProcCurl starts procCurlI with URI as last parameter, libProcCurl should be flexible to accept URI from parameter and skip step 1.
  1. procCurlI uses URI to create a connection and wait for messages.
4. libProcCurl uses URI to create a connection and start sending messages.

### Protocols JSON:

Example

```json
{
  "transports": {
    "io": {
      "rate": 1
    },
    "ipc": {
      "rate": 5
    },
    "mmap": {
      "rate": 10
    }
  },
  "formats": {
    "jsonrpc": {
      "rate": 1
    },
    "capnproto": {
      "rate": 10
    }
  },
  "version": 2
}
```

libProcCurl should sort by `rate` as greatest is fastest and choose fastest it knows.

libProcCurl may accept or  minVersion parameter and compare with version, throwing an exception.


## TODO:

[ ] Define spec (almost completed)
[ ] Evaluate min requirements (ie: JSON or msgpack, mmap or FD, etc)
[ ] POC
