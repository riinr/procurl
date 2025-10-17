# STDIO - JSONL - JSON-RPC


## ID

_stdio-v1+jsonl-v1+json-rpc-v2`_

ie: `proccurl connect --protocol stdio-v1+jsonl-v1+json-rpc-v2`

## Why

Is the easyest to be implemented, most languages knows how read and write from stdio also interpret json.

## References

- POSIX stdio
- [JSONL 1.0](https://jsonlines.org/)
- [JSON-RPC 2.0](https://www.jsonrpc.org/specification)
- [OpenRPC](https://open-rpc.org)




## Methods

### Introspection
- `/_API/v1`: JsonRpcResponseV2<OpenRpcV1>

#### Example:

__IN__:

```sh
echo '{ "jsonrpc": "2.0", "id": "1", "method": "/_API/v1"}'|proccurl connect --protocols stdio-v1+jsonl-v1+json-rpc-v2
```

__OUT__:

```json
{"jsonrpc": "2.0", "id": "1", "response": {"openrpc": "1.2.1", "info": {"version": "1.0.0","title": "Demo Petstore"},"methods": [{"name": "/pets/v1/listPets","description": "List all pets","result": {"name": "pets","description": "An array of pets","schema": {"type": "array","items": {"title": "Pet","type": "object","properties": {"uuid": {"type": "integer"},"name": {"type": "string"},"breed": {"type": "string"}}}}}}]}}
```
