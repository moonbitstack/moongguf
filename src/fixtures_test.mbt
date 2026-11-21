// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The bytes of a hex string, as `scripts/make_vectors.py` writes them.
fn hex(text : String) -> Bytes {
  let digits : Array[Byte] = []
  let mut high = -1
  for c in text {
    let digit = match c {
      '0'..<='9' => c.to_int() - '0'.to_int()
      'a'..<='f' => c.to_int() - 'a'.to_int() + 10
      _ => -1
    }
    if digit < 0 {
      continue
    }
    if high < 0 {
      high = digit
    } else {
      digits.push((high * 16 + digit).to_byte())
      high = -1
    }
  }
  Bytes::from_array(digits[:])
}

///|
/// The vector a case is called, so a failing case says which file it was.
fn vector(name : String) -> Bytes {
  for pair in vectors() {
    if pair.0 == name {
      return pair.1
    }
  }
  abort("no vector called " + name)
}

///|
test "the files the reference implementation wrote read back byte for byte" {
  for pair in vectors() {
    let (name, bytes) = pair
    match name {
      // Written by the packer rather than by `gguf-py`, and covered by the
      // tests below.
      "version-1" | "version-2" | "big-endian" => continue
      _ => ()
    }
    // A refusal is a failure the runner reports by test, not an error that
    // stops the run, so that a test reads whether the bytes still match.
    match (Ok(@moongguf.File::parse(bytes[:])) catch { error => Err(error) }) {
      Ok(file) =>
        assert_true(
          file.encode() == bytes,
          msg="reading and writing " + name + " gave other bytes",
        )
      Err(error) =>
        assert_true(false, msg=name + " was refused: " + error.to_string())
    }
  }
}

///|
test "the header of every vector says what it is" {
  assert_eq(vector("bare").length(), 32)
  let bare = @moongguf.File::parse(vector("bare")[:])
  assert_eq(bare.version(), @moongguf.V3)
  assert_eq(bare.header().tensors, 0)
  assert_eq(bare.header().entries, 0)
  assert_eq(bare.meta().count(), 0)
  assert_eq(bare.tensor_count(), 0)
  assert_eq(bare.alignment(), 32U)
  assert_eq(bare.data_start(), 32L)
}

///|
test "a version 1 file reads with its narrow lengths" {
  let file = @moongguf.File::parse(vector("version-1")[:])
  assert_eq(file.version(), @moongguf.V1)
  assert_eq(file.header().tensors, 2)
  assert_eq(file.header().entries, 3)
  assert_eq(file.meta().text("general.architecture"), Some("llama"))
  assert_eq(file.meta().uint("test.count"), Some(3UL))
  assert_eq(file.meta().items("test.array").unwrap().length(), 2)
  assert_eq(file.tensor_count(), 2)
  assert_eq(file.tensor("q.q4_0").unwrap().kind(), @moongguf.Q4_0)
}

///|
test "a version 2 file reads like a version 3 one" {
  let file = @moongguf.File::parse(vector("version-2")[:])
  assert_eq(file.version(), @moongguf.V2)
  assert_eq(file.header().tensors, 2)
  assert_eq(file.meta().uint("test.count"), Some(3UL))
  assert_eq(file.tensor("plain.f32").unwrap().byte_length(), 16L)
  assert_eq(file.tensor("q.q4_0").unwrap().byte_length(), 36L)
}

///|
test "a big-endian file reads the same numbers" {
  let file = @moongguf.File::parse(vector("big-endian")[:])
  assert_eq(file.order(), @moongguf.Big)
  assert_eq(file.meta().text("general.architecture"), Some("llama"))
  assert_eq(file.meta().int("test.int16"), Some(-300L))
  assert_eq(file.tensor("plain.f32").unwrap().byte_length(), 32L)
  assert_eq(file.data("plain.f32").unwrap().length(), 32)
}

///|
test "an alignment other than 32 moves the data section" {
  let file = @moongguf.File::parse(vector("alignment-64")[:])
  assert_eq(file.alignment(), 64U)
  assert_eq(file.data_start() % 64L, 0L)
  assert_eq(file.meta().uint("general.alignment"), Some(64UL))
  assert_eq(file.encode(), vector("alignment-64"))
}

///|
test "nested and empty arrays keep their shape" {
  let file = @moongguf.File::parse(vector("nested-arrays")[:])
  let meta = file.meta()
  let pairs = meta.get("test.array.of.pairs").unwrap()
  match pairs {
    @moongguf.Value::Array(kind, items) => {
      assert_eq(kind, @moongguf.ValueType::Array)
      assert_eq(items.length(), 3)
      assert_eq(
        items[0],
        @moongguf.Value::Array(@moongguf.ValueType::Int32, [
          @moongguf.Value::Int32(1),
          @moongguf.Value::Int32(2),
        ]),
      )
      assert_eq(
        items[1],
        @moongguf.Value::Array(@moongguf.ValueType::Int32, [
          @moongguf.Value::Int32(3),
        ]),
      )
      assert_eq(
        items[2],
        @moongguf.Value::Array(@moongguf.ValueType::Int32, []),
      )
    }
    _ => abort("the array was read as something else")
  }
  assert_eq(
    meta.get("test.array.empty.uint32"),
    Some(@moongguf.Value::Array(@moongguf.ValueType::UInt32, [])),
  )
  assert_eq(
    meta.get("test.array.empty.string"),
    Some(@moongguf.Value::Array(@moongguf.ValueType::String, [])),
  )
}

///|
test "one tensor of every encoding, at the offsets the format lays out" {
  let file = @moongguf.File::parse(vector("every-tensor-type")[:])
  let mut offset = 0L
  for tensor in file.tensors() {
    let length = tensor.byte_length()
    assert_eq(tensor.extent().at, offset)
    assert_eq(tensor.extent().length, length)
    offset = offset + (length + 31L) / 32L * 32L
  }
  assert_eq(file.tensor_count(), @moongguf.GgmlType::all().length() - 2)
}

///|
test "the two encodings newer than the reference writer" {
  let file = @moongguf.File::parse(vector("newest-encodings")[:])
  let q2 = file.tensor("t.Q2_0").unwrap()
  assert_eq(q2.kind(), @moongguf.Q2_0)
  assert_eq(q2.kind().block_size(), 64)
  assert_eq(q2.byte_length(), 108L)
  let f8 = file.tensor("t.F8_E4M3").unwrap()
  assert_eq(f8.kind(), @moongguf.F8_E4M3)
  assert_eq(f8.byte_length(), 32L)
  assert_eq(file.encode(), vector("newest-encodings"))
}
