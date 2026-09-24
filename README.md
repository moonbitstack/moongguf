# moongguf

GGUF files, read and written.

> **Status: planned.** The repository is set up; nothing is
> implemented yet.

A GGUF file is a header, a table of metadata and an index of tensors, and then
the tensor data itself. This reads all four and writes them back; it does not
run anything.

| Package | What it covers |
|:--|:--|
| `head` | The magic, the version and the two counts |
| `meta` | The key-value table, every value type the format defines |
| `index` | Tensor names, shapes, types and offsets |
| `data` | Reaching the tensor bytes without reading the file whole |

The reference is [the GGUF specification](https://github.com/ggml-org/ggml/blob/master/docs/gguf.md).

## What is deliberately elsewhere

Quantisation formats and what to do with a tensor once it is read belong to
[`moonggml`](https://github.com/moonbitstack/moonggml). A file format library
that also did arithmetic would be two libraries.

## Install

```bash
moon add moonbitstack/moongguf
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
