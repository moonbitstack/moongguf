---
name: moongguf
description: "Read and write GGUF model files: the metadata table, the tensor index, and the weights behind it. Use it to inspect a model, convert one, or reach a tensor's bytes without copying them."
---

# moongguf

```bash
moon add moonbitstack/moongguf
```

```moonbit
import {
  "moonbitstack/moongguf",
}
```

The library deals in bytes: a caller reads a file, fetches a range, or maps a
buffer, and hands the bytes over. Nothing here opens a file.

## Build a file

A file is built in memory and written out in one call. Metadata goes in by key
and kind; tensors go in with their bytes, and each lands where the one before it
ends, rounded up to the alignment.

```moonbit
let made = @moongguf.File::new()
made.set("general.architecture", @moongguf.Value::String("llama"))
made.set("llama.block_count", @moongguf.Value::UInt32(1))
made.add(
  @moongguf.Tensor::new(name="weight", kind=@moongguf.F32, dims=[4UL]),
  Bytes::make(16, b'\x00')[:],
)
let bytes = made.encode()
debug_inspect(bytes.length() > 0, content="true")
```

## Ask what a file holds

The index of a file — the header, the metadata table and the tensor table — is
enough to answer most questions, and it is small next to the weights.

```moonbit
let file = @moongguf.File::parse(bytes[:])
let arch = file.meta().text("general.architecture").unwrap_or("?")
let blocks = file.meta().uint(arch + ".block_count").unwrap_or(0UL)
let tensors = file.tensors()
debug_inspect((arch, blocks, tensors.length()), content="(\"llama\", 1, 1)")
```

## Read a tensor's bytes

`data` returns a view into the bytes the file was parsed from: nothing is copied,
and the view lives as long as those bytes do. `extent` gives the same tensor's
offset in the data section and its length, for a reader that would rather fetch
it than hold it.

```moonbit
let weight = file.data("weight").unwrap()
let extent = file.extent("weight")
debug_inspect((weight.length().to_int64(), extent.length), content="(16, 16)")
```

## A file too large for one `Bytes`

One `Bytes` holds a gigabyte. The index is small even for a huge model, so it is
parsed from the head of the file, and each tensor's bytes are handed over as
they are read; `shard` checks the piece against the extent and returns the part
that belongs to the tensor.

```moonbit
let head = bytes.exact_view(end=made.data_start().to_int())
let index = @moongguf.File::parse(head)
let at = made.data_start() + extent.at
let piece = index.shard(
  "weight",
  bytes.exact_view(start=at.to_int(), end=(at + extent.length).to_int()),
  at=0L,
)
debug_inspect(piece.length().to_int64(), content="16")
```

## Rules that catch people out

- Versions 1 and 2 are read-only. Writing refuses them rather than upgrading
  silently; rebuild the file as version 3 if it has to be written.
- `general.alignment` must be a power of two, stored as `uint32`. It moves the
  data section, so set it before any tensor goes in.
- A tensor's row — its first dimension — must be a whole number of blocks for
  its encoding. `Q4_0` takes 32 values to a block, so a row of 100 values is
  refused, not padded.
- Tensor offsets are counted from the start of the data section, not from the
  start of the file; add `File::data_start` for a file offset.
- `File::tensor` and `File::data` return `None` for a name a file does not have;
  `File::extent` and `File::shard` refuse with `Refused::Missing` instead.
- A tensor view points into the bytes the file was parsed from, so those bytes
  have to outlive the views.
