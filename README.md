<div align="center">

<h1>moongguf</h1>

<p><b>GGUF files for MoonBit.</b><br>
The header, the metadata table, the tensor index, and the weights behind them —<br>
read from bytes, written back byte for byte, handed over without a copy.</p>

<p>
<a href="https://moonbitstack.github.io/moongguf/"><b>Home</b></a>
&nbsp;·&nbsp;
<a href="https://moonbitstack.github.io/moongguf/guide.html"><b>Guide</b></a>
&nbsp;·&nbsp;
<a href="https://moonbitstack.github.io/moongguf/api.html"><b>API</b></a>
&nbsp;·&nbsp;
<a href="https://moonbitstack.github.io/moongguf/anatomy.html"><b>Anatomy</b></a>
&nbsp;·&nbsp;
<a href="https://mooncakes.io/docs/moonbitstack/moongguf"><b>mooncakes</b></a>
</p>

<table>
  <tr>
    <td align="center"><b>1 · 2 · 3</b><br><sub>versions read; 3 written</sub></td>
    <td align="center"><b>13</b><br><sub>value kinds, arrays nested</sub></td>
    <td align="center"><b>every</b><br><sub><code>ggml</code> encoding, one table</sub></td>
    <td align="center"><b>0</b><br><sub>copies of a tensor's bytes</sub></td>
  </tr>
</table>

</div>

A GGUF file is what a quantised language model looks like on disk: a header, a
table of key-value metadata, an index of the tensors, and then the weights, laid
out block by block in one of the encodings `ggml` defines. This library reads all
four parts, writes them back, and hands out a tensor's bytes without copying
them. It does no arithmetic on the weights: what a block of `q6_K` means belongs
to the arithmetic, not to the file.

- Every value kind the format defines, in arrays as well as on their own, nested
  arrays included.
- Every tensor encoding, with its block size and bytes per block, in one table.
- Versions 1 and 2 are read; version 3 is read and written.
- Files larger than one `Bytes` are read in two parts: the index from the head of
  the file, then each tensor's bytes as they arrive.
- Ceilings on counts and lengths are named, published, and refused past with the
  number that went past.

The format is specified in
[`gguf.md`](https://github.com/ggml-org/ggml/blob/master/docs/gguf.md).

## Install

```bash
moon add moonbitstack/moongguf
```

## Writing

A file is built in memory, given metadata and tensors, and written out. The data
section starts on the alignment the file records, and every tensor lands where
the one before it ends, rounded up to that boundary.

```moonbit
let file = @moongguf.File::new()
file.set("general.architecture", @moongguf.Value::String("llama"))
file.set("llama.block_count", @moongguf.Value::UInt32(1))
file.set(
  "tokenizer.ggml.tokens",
  @moongguf.Value::Array(@moongguf.ValueType::String, [
    @moongguf.Value::String("a"),
    @moongguf.Value::String("b"),
  ]),
)
file.add(
  @moongguf.Tensor::new(name="weight", kind=@moongguf.F32, dims=[4UL]),
  Bytes::make(16, b'\x00')[:],
)
let bytes = file.encode()
```

Reading those bytes back and writing them again gives the same bytes, and that
is the property the library is built around: an encoding is only right if it
survives the round trip.

## Reading

Those bytes are what a file is; this is what a reader does with them. The library
deals in bytes, not in files: a caller that has read a file, fetched a range, or
mapped a buffer hands the bytes over. A file is parsed in one call, and the tensor
data stays where it is — `data` returns a view into the bytes that were passed in.

```moonbit
let file = @moongguf.File::parse(bytes[:])
let architecture = file.meta().text("general.architecture").unwrap_or("?")
let blocks = file.meta().uint("llama.block_count")
let weight = file.tensor("weight")
debug_inspect((architecture, blocks, weight.is_some()), content="(\"llama\", Some(1), true)")
```

The tensor index is enough to answer what a model holds: `tensors` gives every
entry with its name, its encoding, its dimensions and where its bytes start, and
`extent` gives the offset and the length of one tensor's bytes.

## Files larger than a `Bytes`

One `Bytes` holds a gigabyte, so a four-gigabyte model does not fit. The index is
small even then — a few megabytes of vocabulary and tensor shapes — so it is read
from the head of the file, and each tensor's bytes are handed over as they are
read. `shard` takes a view of the piece it is given and checks it against the
extent the index recorded.

```moonbit
let head = bytes.exact_view(end=file.data_start().to_int())
let index = @moongguf.File::parse(head)
let extent = index.extent("weight")
let piece = bytes.exact_view(
  start=(file.data_start() + extent.at).to_int(),
  end=(file.data_start() + extent.at + extent.length).to_int(),
)
debug_inspect((extent.at, extent.length, index.shard("weight", piece, at=0L).length()), content="(0, 16, 16)")
```

`encode_index` writes the same head for a file being built, so a writer can place
the data section itself and stream each tensor out as it goes.

## A dump of a file

`to_json` describes a file the way the format's own tooling prints it: every
metadata pair with its kind, its position and its value, and every tensor with its
shape, its encoding and its position. Two dumps of the same file, taken by two
implementations, compare field by field.

```moonbit
let described = file.to_json().stringify(indent=1)
assert_eq(described.length() > 0, true)
```

## The pieces

| Type | What it is |
|:--|:--|
| `File` | A whole file: header, metadata, tensor index, and the bytes they came from |
| `Meta` | The metadata table, in file order, with a lookup by key |
| `Entry` | One metadata pair: its key, its value, and where it sits |
| `Value` | One metadata value of any of the thirteen kinds |
| `ValueType` | Which of the thirteen kinds a value is |
| `Tensor` | One index entry: name, encoding, dimensions, offset |
| `Extent` | Where a tensor's bytes sit and how far they run |
| `GgmlType` | A tensor encoding, with its block size and bytes per block |
| `Version` | 1, 2 or 3 |
| `ByteOrder` | Little or big |
| `Header` | The version and the two counts |
| `Limits` | The ceilings a reader works under |
| `Refused` | Why bytes are not a file this library can read, or cannot be written |

| Function | What it does |
|:--|:--|
| `File::parse` | Read a file from its bytes |
| `File::new` | An empty version 3 file |
| `File::encode` | The whole file as bytes |
| `File::encode_index` | The header, metadata and tensor index, up to the data section |
| `File::set`, `File::remove` | Put a metadata value in, take one out |
| `File::add`, `File::add_index` | Put a tensor in, with or without its bytes |
| `File::tensor`, `File::tensors` | One index entry, or all of them |
| `File::data`, `File::extent` | A tensor's bytes as a view, or where they are |
| `File::shard` | A view of a tensor's bytes read from somewhere else |
| `File::meta`, `File::header` | The metadata table, the header |
| `Meta::get`, `Meta::text`, `Meta::uint`, `Meta::int`, `Meta::float`, `Meta::flag`, `Meta::items` | One value, or one converted to the type wanted |
| `Tensor::new` | An index entry to put into a file |
| `GgmlType::of`, `GgmlType::all` | An encoding from its number, or all of them |
| `is_gguf` | Whether bytes start with the magic |

## Ceilings

A reader that trusted the counts in a corrupt file would allocate a gigabyte to
find nothing there. `Limits` puts a ceiling on the number of metadata pairs, the
number of tensors, the length of a key or a string, the number of entries in an
array, and how deeply arrays may nest. Each refusal names the ceiling it hit and
the number that hit it.

```moonbit
let small = { ..@moongguf.limits, entries: 64, text: 4096 }
let file = @moongguf.File::parse(bytes[:], limits=small)
debug_inspect(file.meta().count() <= 64, content="true")
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
