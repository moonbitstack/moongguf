// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a new file has no metadata, no tensors, and the format's alignment" {
  let file = @moongguf.File::new()
  assert_eq(file.version(), @moongguf.V3)
  assert_eq(file.alignment(), 32U)
  assert_eq(file.meta().count(), 0)
  assert_eq(file.tensor_count(), 0)
  let bytes = file.encode()
  // The magic, the version and two zero counts, up to the alignment.
  assert_eq(bytes.length(), 32)
  assert_eq(@moongguf.File::parse(bytes[:]).tensor_count(), 0)
}

///|
test "an alignment other than 32 is written down, and the data section obeys it" {
  let file = @moongguf.File::new(alignment=64U)
  assert_eq(file.alignment(), 64U)
  assert_eq(file.meta().uint("general.alignment"), Some(64UL))
  file.set("a", @moongguf.Value::UInt32(1))
  let bytes = file.encode()
  let back = @moongguf.File::parse(bytes[:])
  assert_eq(back.alignment(), 64U)
  assert_eq(back.data_start() % 64L, 0L)
}

///|
test "the index on its own is the head of the whole file" {
  let file = @moongguf.File::new()
  file.set("general.architecture", @moongguf.Value::String("llama"))
  file.add(
    @moongguf.Tensor::new(name="w", kind=@moongguf.F32, dims=[8UL]),
    Bytes::make(32, b'\x07')[:],
  )
  let whole = file.encode()
  let index = file.encode_index()
  assert_eq(index.length().to_int64(), file.data_start())
  assert_eq(whole.exact_view(end=index.length()), index[:])
  // The index parses, and knows the tensor without its bytes.
  let head = @moongguf.File::parse(index[:])
  assert_eq(head.tensor_count(), 1)
  assert_eq(head.tensor("w").unwrap().byte_length(), 32L)
  assert_eq(head.data("w"), None)
}

///|
test "a second tensor starts where the first ends, rounded to the alignment" {
  let file = @moongguf.File::new()
  file.add(
    @moongguf.Tensor::new(name="a", kind=@moongguf.F32, dims=[6UL]),
    Bytes::make(24, b'\x01')[:],
  )
  file.add(
    @moongguf.Tensor::new(name="b", kind=@moongguf.F16, dims=[2UL]),
    Bytes::make(4, b'\x02')[:],
  )
  let back = @moongguf.File::parse(file.encode()[:])
  assert_eq(back.extent("a"), { at: 0L, length: 24L, })
  assert_eq(back.extent("b"), { at: 32L, length: 4L, })
  assert_eq(back.data("a").unwrap()[0], b'\x01')
  assert_eq(back.data("b").unwrap()[0], b'\x02')
}

///|
test "a tensor whose name is taken is refused" {
  let file = @moongguf.File::new()
  let tensor = @moongguf.Tensor::new(name="t", kind=@moongguf.F32, dims=[2UL])
  file.add(tensor, Bytes::make(8, b'\x00')[:])
  let failure = try {
    file.add(tensor, Bytes::make(8, b'\x00')[:])
    None
  } catch {
    error => Some(error)
  }
  assert_eq(failure, Some(@moongguf.Duplicate(name="t")))
}

///|
test "a value set under a key replaces the one there" {
  let file = @moongguf.File::new()
  file.set("k", @moongguf.Value::UInt32(1))
  file.set("k", @moongguf.Value::String("two"))
  assert_eq(file.meta().count(), 1)
  assert_eq(file.meta().get("k"), Some(@moongguf.Value::String("two")))
  assert_eq(file.header().entries, 1)
  let back = @moongguf.File::parse(file.encode()[:])
  assert_eq(back.meta().text("k"), Some("two"))
}

///|
test "a key removed is gone from the table and from the bytes" {
  let file = @moongguf.File::new()
  file.set("keep", @moongguf.Value::UInt32(1))
  file.set("drop", @moongguf.Value::UInt32(2))
  file.remove("drop")
  assert_eq(file.meta().count(), 1)
  assert_eq(file.meta().contains("drop"), false)
  let back = @moongguf.File::parse(file.encode()[:])
  assert_eq(back.meta().count(), 1)
  assert_eq(back.header().entries, 1)
}

///|
test "removing the alignment puts it back to 32" {
  let file = @moongguf.File::new(alignment=64U)
  file.remove("general.alignment")
  assert_eq(file.alignment(), 32U)
  let back = @moongguf.File::parse(file.encode()[:])
  assert_eq(back.alignment(), 32U)
}

///|
test "an alignment that is not a power of two is refused when set" {
  let file = @moongguf.File::new()
  let failure = try {
    file.set("general.alignment", @moongguf.Value::UInt32(3))
    None
  } catch {
    error => Some(error)
  }
  assert_eq(failure, Some(@moongguf.Alignment(got=3U)))
  let wrong = try {
    file.set("general.alignment", @moongguf.Value::String("64"))
    None
  } catch {
    error => Some(error)
  }
  assert_eq(
    wrong,
    Some(
      @moongguf.Mismatch(
        at=-1L,
        want=@moongguf.ValueType::UInt32,
        got=@moongguf.ValueType::String,
      ),
    ),
  )
  assert_eq(file.alignment(), 32U)
}

///|
test "a tensor put into the index alone is written where the one before ends" {
  let file = @moongguf.File::new()
  file.add_index(
    @moongguf.Tensor::new(name="a", kind=@moongguf.F32, dims=[4UL]),
  )
  file.add_index(
    @moongguf.Tensor::new(name="b", kind=@moongguf.F32, dims=[4UL]),
  )
  let index = file.encode_index()
  let head = @moongguf.File::parse(index[:])
  assert_eq(head.extent("a"), { at: 0L, length: 16L, })
  assert_eq(head.extent("b"), { at: 32L, length: 16L, })
  assert_eq(head.tensor_count(), 2)
}

///|
test "a shard is checked against the extent and returns what belongs to it" {
  let file = @moongguf.File::parse(vector("every-value-type")[:])
  let extent = file.extent("plain.f32")
  let whole = Bytes::make(extent.length.to_int(), b'\x2A')
  assert_eq(file.shard("plain.f32", whole[:]).length(), extent.length.to_int())
  let half = Bytes::make(8, b'\x2A')
  assert_eq(file.shard("plain.f32", half[:], at=8L).length(), 8)
  // A shard running past the tensor keeps only what belongs to it.
  let long = Bytes::make(extent.length.to_int() + 40, b'\x2A')
  assert_eq(file.shard("plain.f32", long[:], at=extent.length - 4L).length(), 4)
}

///|
test "every kind of value survives being written and read again" {
  let file = @moongguf.File::new()
  let values = [
    ("u8", @moongguf.Value::UInt8(255)),
    ("i8", @moongguf.Value::Int8(-128)),
    ("u16", @moongguf.Value::UInt16(65535)),
    ("i16", @moongguf.Value::Int16(-32768)),
    ("u32", @moongguf.Value::UInt32(4294967295)),
    ("i32", @moongguf.Value::Int32(-2147483648)),
    ("f32", @moongguf.Value::Float32(0.5)),
    ("bool", @moongguf.Value::Bool(true)),
    ("text", @moongguf.Value::String("\u4e2d\u6587")),
    ("u64", @moongguf.Value::UInt64(18446744073709551615UL)),
    ("i64", @moongguf.Value::Int64(-9223372036854775808L)),
    ("f64", @moongguf.Value::Float64(-1.5)),
    (
      "array",
      @moongguf.Value::Array(@moongguf.ValueType::Int16, [
        @moongguf.Value::Int16(-1),
        @moongguf.Value::Int16(1),
      ]),
    ),
    (
      "nested",
      @moongguf.Value::Array(@moongguf.ValueType::Array, [
        @moongguf.Value::Array(@moongguf.ValueType::UInt8, [
          @moongguf.Value::UInt8(1),
        ]),
        @moongguf.Value::Array(@moongguf.ValueType::UInt8, []),
      ]),
    ),
  ]
  for pair in values {
    file.set(pair.0, pair.1)
  }
  let back = @moongguf.File::parse(file.encode()[:])
  for pair in values {
    assert_eq(back.meta().get(pair.0), Some(pair.1))
  }
  assert_eq(back.encode(), file.encode())
}

///|
test "a float that is not a number keeps its bits through a round trip" {
  let file = @moongguf.File::new()
  let one = Float::reinterpret_from_uint(0x7FC0_0001U)
  let two = UInt64::reinterpret_as_double(0x7FF8_0000_0000_0001UL)
  file.set("f32", @moongguf.Value::Float32(one))
  file.set("f64", @moongguf.Value::Float64(two))
  let back = @moongguf.File::parse(file.encode()[:])
  // A float that is not a number is not equal to itself, so its bits are what
  // a round trip is asked to keep.
  match back.meta().get("f32") {
    Some(@moongguf.Value::Float32(value)) =>
      assert_eq(value.reinterpret_as_uint(), 0x7FC0_0001U)
    _ => abort("the f32 came back as something else")
  }
  match back.meta().get("f64") {
    Some(@moongguf.Value::Float64(value)) =>
      assert_eq(value.reinterpret_as_uint64(), 0x7FF8_0000_0000_0001UL)
    _ => abort("the f64 came back as something else")
  }
  assert_eq(back.encode(), file.encode())
}
