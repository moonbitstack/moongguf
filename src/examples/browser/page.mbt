// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Every encoding `ggml` defines, in the order of its number: the code, the
/// name a dump prints, the block size, and the bytes a block takes.
pub fn encodings() -> String {
  let rows = @moongguf.GgmlType::all().map(fn(kind) {
    Json::object({
      "code": Json(kind.code().reinterpret_as_int()),
      "name": Json(kind.name()),
      "block": Json(kind.block_size()),
      "bytes": Json(kind.bytes_per_block()),
      "quantized": Json(kind.is_quantized()),
    })
  })
  Json::array(rows).stringify()
}

///|
/// The thirteen kinds a metadata value can be, by number and by the name a dump
/// prints.
pub fn value_types() -> String {
  let rows = []
  for code in 0..<13 {
    let kind = @moongguf.ValueType::of(code.reinterpret_as_uint()).unwrap()
    rows.push(Json::object({ "code": Json(code), "name": Json(kind.name()) }))
  }
  Json::array(rows).stringify()
}

///|
/// A small file built here, as hex, so that the page has something to parse
/// before a reader pastes a file of their own. It holds six metadata pairs,
/// one of them an array of arrays, and three tensors of three encodings.
pub fn sample_file() -> String {
  build_sample() catch {
    _ => ""
  }
}

///|
/// The sample, kept apart so that the export above never raises into the page.
fn build_sample() -> String raise @moongguf.Refused {
  let file = @moongguf.File::new()
  file.set("general.architecture", @moongguf.Value::String("llama"))
  file.set("llama.block_count", @moongguf.Value::UInt32(1))
  file.set("llama.attention.head_count", @moongguf.Value::UInt32(8))
  file.set(
    "tokenizer.ggml.tokens",
    @moongguf.Value::Array(
      @moongguf.ValueType::String,
      [
        "a", "b", "c", "d", ".", ",", "the", "and", "of", "to", "in", "is", "it",
        "you", "that", "he", "was", "for", "on", "are",
      ].map(fn(word) { @moongguf.Value::String(word) }),
    ),
  )
  file.set(
    "llama.rope.scaling",
    @moongguf.Value::Array(@moongguf.ValueType::Array, [
      @moongguf.Value::Array(@moongguf.ValueType::Float32, [
        @moongguf.Value::Float32(1.0),
        @moongguf.Value::Float32(0.5),
      ]),
    ]),
  )
  file.set("llama.rope.freq_base", @moongguf.Value::Float32(10000.0))
  file.add(
    @moongguf.Tensor::new(name="token_embd.weight", kind=@moongguf.Q4_0, dims=[
      64UL, 2UL,
    ]),
    Bytes::make(128, b'\x11')[:],
  )
  file.add(
    @moongguf.Tensor::new(name="output_norm.weight", kind=@moongguf.F32, dims=[
      8UL,
    ]),
    Bytes::make(32, b'\x22')[:],
  )
  file.add(
    @moongguf.Tensor::new(name="blk.0.attn_q.weight", kind=@moongguf.Q8_0, dims=[
      32UL,
    ]),
    Bytes::make(34, b'\x33')[:],
  )
  hex_of(file.encode())
}

///|
/// A file read from the hex a reader pastes, described for the page: where each
/// part sits, what every metadata pair holds, and where each tensor's bytes
/// start. A refusal comes back as `{"ok": false, "error": "..."}` so the page
/// can show what went wrong rather than a blank panel.
pub fn inspect_hex(text : String) -> String {
  let bytes = match unhex(text) {
    Ok(bytes) => bytes
    Err(why) => return failure(why)
  }
  let file = @moongguf.File::parse(bytes[:]) catch {
    error => return failure(error.to_string())
  }
  let data_start = file.data_start() catch { _ => 0L }
  let entries = file.meta().entries()
  let tensors = file.tensors()
  let header_length = if file.version() == @moongguf.V1 { 16 } else { 24 }
  let index_start = if tensors.length() > 0 {
    tensors[0].at()
  } else {
    data_start
  }
  let metadata = []
  for i, entry in entries {
    // An entry's own span is not recorded, only where it starts: it runs until
    // the next one, and the last until the tensor index.
    let next = if i + 1 < entries.length() {
      entries[i + 1].at
    } else {
      index_start
    }
    let described : Map[String, Json] = Map([])
    described.set("key", Json(entry.key))
    described.set("type", Json(entry.value.value_type().name()))
    described.set("offset", json_int(entry.at))
    described.set(
      "length",
      json_int(if next > entry.at { next - entry.at } else { 0L }),
    )
    described.set("value", entry.value.to_json())
    match entry.value {
      @moongguf.Value::Array(kind, _) =>
        described.set("arrayType", Json(kind.name()))
      _ => ()
    }
    metadata.push(Json::object(described))
  }
  let rows = []
  for i, tensor in tensors {
    let extent = tensor.extent() catch { _ => { at: 0L, length: 0L, } }
    let next = if i + 1 < tensors.length() {
      tensors[i + 1].at()
    } else {
      data_start
    }
    let described : Map[String, Json] = Map([])
    described.set("name", Json(tensor.name()))
    described.set("type", Json(tensor.kind().name()))
    described.set(
      "dims",
      Json::array(
        tensor.dims().map(fn(dim) { json_int(dim.reinterpret_as_int64()) }),
      ),
    )
    described.set("infoAt", json_int(tensor.at()))
    described.set(
      "infoLength",
      json_int(if next > tensor.at() { next - tensor.at() } else { 0L }),
    )
    described.set("dataAt", json_int(data_start + extent.at))
    described.set("length", json_int(extent.length))
    described.set("block", Json(tensor.kind().block_size()))
    described.set("bytesPerBlock", Json(tensor.kind().bytes_per_block()))
    rows.push(Json::object(described))
  }
  let described : Map[String, Json] = Map([])
  described.set("ok", Json(true))
  described.set("bytes", json_int(bytes.length().to_int64()))
  described.set("version", Json(file.version().code().reinterpret_as_int()))
  described.set(
    "endian",
    Json(if file.order() == @moongguf.Little { "LITTLE" } else { "BIG" }),
  )
  described.set(
    "alignment",
    json_int(file.alignment().reinterpret_as_int().to_int64()),
  )
  described.set("dataStart", json_int(data_start))
  described.set("metadataCount", Json(entries.length()))
  described.set("tensorCount", Json(tensors.length()))
  described.set(
    "header",
    Json::object({ "at": Json(0), "length": json_int(header_length.to_int64()) }),
  )
  described.set("metadata", Json::array(metadata))
  described.set(
    "metadataSpan",
    Json::object({
      "at": json_int(header_length.to_int64()),
      "length": json_int(
        if index_start > header_length.to_int64() {
          index_start - header_length.to_int64()
        } else {
          0L
        },
      ),
    }),
  )
  described.set(
    "indexSpan",
    Json::object({
      "at": json_int(index_start),
      "length": json_int(data_start - index_start),
    }),
  )
  described.set("tensors", Json::array(rows))
  Json::object(described).stringify()
}

///|
/// The bytes a hex string names, with whitespace and separators ignored, so
/// that bytes copied out of a dump or a hex viewer go in as they are.
fn unhex(text : String) -> Result[Bytes, String] {
  let digits = []
  for char in text.to_lower() {
    let value = match char {
      '0'..<='9' => char.to_int() - '0'.to_int()
      'a'..<='f' => 10 + char.to_int() - 'a'.to_int()
      ' ' | '\n' | '\r' | '\t' | ',' | ':' | '-' | 'x' => continue
      _ => return Err("a hex string holds 0-9 and a-f, and this has \{char}")
    }
    digits.push(value)
  }
  if digits.length() % 2 != 0 {
    return Err(
      "a hex string needs an even number of digits; this one has \{digits.length()}",
    )
  }
  let out = []
  for i in 0..<(digits.length() / 2) {
    out.push((digits[i * 2] * 16 + digits[i * 2 + 1]).to_byte())
  }
  Ok(Bytes::from_array(out[:]))
}

///|
/// The bytes as hex, two digits each, no separators.
fn hex_of(bytes : BytesView) -> String {
  let digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let out = StringBuilder()
  for byte in bytes {
    let n = byte.to_int()
    out.write_char(digits[(n >> 4) & 0xF])
    out.write_char(digits[n & 0xF])
  }
  out.to_string()
}

///|
/// A count as a JSON number, its digits kept as written.
fn json_int(n : Int64) -> Json {
  Json::number(n.to_double(), repr=n.to_string())
}

///|
fn failure(why : String) -> String {
  Json::object({ "ok": Json(false), "error": Json(why) }).stringify()
}
