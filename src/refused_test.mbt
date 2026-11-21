// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Bytes put together field by field, so that a test can build a file the
/// writer would never produce.
struct Raw {
  bytes : Array[Byte]
}

///|
fn Raw::new() -> Raw {
  { bytes: [], }
}

///|
fn Raw::u8(self : Raw, n : Int32) -> Raw {
  self.bytes.push(n.to_byte())
  self
}

///|
fn Raw::u32(self : Raw, n : UInt32) -> Raw {
  for i in 0..<4 {
    let _ = self.u8((n.reinterpret_as_int() >> (i * 8)) & 0xFF)
  }
  self
}

///|
fn Raw::u64(self : Raw, n : UInt64) -> Raw {
  for i in 0..<8 {
    let _ = self.u8((n.reinterpret_as_int64() >> (i * 8)).to_int() & 0xFF)
  }
  self
}

///|
fn Raw::raw(self : Raw, bytes : BytesView) -> Raw {
  for byte in bytes {
    self.bytes.push(byte)
  }
  self
}

///|
fn Raw::text(self : Raw, text : String) -> Raw {
  let raw = @utf8.encode(text)
  let _ = self.u64(raw.length().to_uint64()).raw(raw[:])
  self
}

///|
fn Raw::done(self : Raw) -> Bytes {
  Bytes::from_array(self.bytes[:])
}

///|
/// A header with the given counts and nothing after it.
fn bare(tensors : UInt64, entries : UInt64) -> Raw {
  Raw::new().raw(b"GGUF"[:]).u32(3U).u64(tensors).u64(entries)
}

///|
/// The refusal a parse earns, or `None` when it reads.
fn refused(
  bytes : Bytes,
  limits~ : @moongguf.Limits = @moongguf.limits,
) -> @moongguf.Refused? {
  try {
    let _ = @moongguf.File::parse(bytes[:], limits~)
    None
  } catch {
    error => Some(error)
  }
}

///|
test "bytes that do not start with the magic are refused" {
  let near = Bytes::from_array([b'G', b'G', b'X', b'F', 3, 0, 0, 0])
  assert_eq(
    refused(near),
    Some(@moongguf.Magic(got=Bytes::from_array([0x47, 0x47, 0x58, 0x46]))),
  )
}

///|
test "a version the format never had is refused" {
  let bytes = Raw::new().raw(b"GGUF"[:]).u32(4U).u64(0UL).u64(0UL).done()
  assert_eq(refused(bytes), Some(@moongguf.Version(got=4U)))
  let zero = Raw::new().raw(b"GGUF"[:]).u32(0U).u64(0UL).u64(0UL).done()
  assert_eq(refused(zero), Some(@moongguf.Version(got=0U)))
}

///|
test "bytes that end inside a field are refused where the field starts" {
  let bytes = bare(0UL, 0UL).done()
  let head = bytes.exact_view(start=0, end=10)
  assert_eq(
    refused(Bytes::from_array(head.to_array())),
    Some(@moongguf.Truncated(at=8L, want=8, got=2)),
  )
  assert_eq(
    refused(Bytes::from_array([0x47, 0x47])),
    Some(@moongguf.Truncated(at=0L, want=4, got=2)),
  )
}

///|
test "a value type outside the thirteen is refused" {
  let bytes = bare(0UL, 1UL).text("key").u32(13U).done()
  assert_eq(refused(bytes), Some(@moongguf.Untyped(got=13U)))
}

///|
test "a tensor encoding outside the table is refused" {
  let bytes = bare(1UL, 0UL).text("t").u32(1U).u64(4UL).u32(44U).u64(0UL).done()
  assert_eq(refused(bytes), Some(@moongguf.Unencoded(got=44U)))
}

///|
test "a key that is empty, or present twice, is refused" {
  let empty = bare(0UL, 1UL).text("").u32(4U).u32(1U).done()
  assert_eq(refused(empty), Some(@moongguf.Empty))
  let twice = bare(0UL, 2UL)
    .text("key")
    .u32(4U)
    .u32(1U)
    .text("key")
    .u32(4U)
    .u32(2U)
    .done()
  assert_eq(refused(twice), Some(@moongguf.Duplicate(name="key")))
}

///|
test "a tensor named twice is refused" {
  let bytes = bare(2UL, 0UL)
    .text("t")
    .u32(1U)
    .u64(4UL)
    .u32(0U)
    .u64(0UL)
    .text("t")
    .u32(1U)
    .u64(4UL)
    .u32(0U)
    .u64(16UL)
    .done()
  assert_eq(refused(bytes), Some(@moongguf.Duplicate(name="t")))
}

///|
test "text that is not UTF-8 is refused rather than repaired" {
  let bytes = bare(0UL, 1UL).u64(2UL).u8(0xFF).u8(0xFE).u32(4U).u32(1U).done()
  assert_eq(refused(bytes), Some(@moongguf.Malformed(at=24L)))
}

///|
test "an alignment that is not a power of two is refused" {
  let odd = bare(0UL, 1UL).text("general.alignment").u32(4U).u32(3U).done()
  assert_eq(refused(odd), Some(@moongguf.Alignment(got=3U)))
  let zero = bare(0UL, 1UL).text("general.alignment").u32(4U).u32(0U).done()
  assert_eq(refused(zero), Some(@moongguf.Alignment(got=0U)))
}

///|
test "an alignment stored as something other than uint32 is refused" {
  let bytes = bare(0UL, 1UL).text("general.alignment").u32(0U).u8(64).done()
  assert_eq(
    refused(bytes),
    Some(
      @moongguf.Mismatch(
        at=24L,
        want=@moongguf.ValueType::UInt32,
        got=@moongguf.ValueType::UInt8,
      ),
    ),
  )
}

///|
test "a tensor row that is not whole blocks is refused" {
  // `q4_0` holds 32 values to a block; three is not a row it can walk.
  let bytes = bare(1UL, 0UL).text("t").u32(1U).u64(3UL).u32(2U).u64(0UL).done()
  assert_eq(refused(bytes), Some(@moongguf.Blocks(name="t", block=32, got=3UL)))
}

///|
test "more dimensions than ggml holds are refused" {
  let mut raw = bare(1UL, 0UL).text("t").u32(5U)
  for _ in 0..<5 {
    raw = raw.u64(2UL)
  }
  let bytes = raw.u32(0U).u64(0UL).done()
  assert_eq(refused(bytes), Some(@moongguf.Dims(limit=4, got=5)))
}

///|
test "a tensor count that does not fit 64 bits of values is refused" {
  let bytes = bare(1UL, 0UL)
    .text("t")
    .u32(2U)
    .u64(0x1_0000_0000UL)
    .u64(0x1_0000_0000UL)
    .u32(0U)
    .u64(0UL)
    .done()
  assert_eq(refused(bytes), Some(@moongguf.Volume(name="t")))
}

///|
test "a tensor that starts somewhere else than the one before it ends" {
  let bytes = bare(2UL, 0UL)
    .text("a")
    .u32(1U)
    .u64(4UL)
    .u32(0U)
    .u64(0UL)
    .text("b")
    .u32(1U)
    .u64(4UL)
    .u32(0U)
    .u64(64UL)
    .done()
  assert_eq(
    refused(bytes),
    Some(@moongguf.Offset(name="b", want=32UL, got=64UL)),
  )
}

///|
test "a ceiling is named, and names what went past it" {
  let bytes = vector("every-value-type")
  assert_eq(
    refused(bytes, limits={ ..@moongguf.limits, entries: 2, }),
    Some(@moongguf.Entries(limit=2, got=30)),
  )
  assert_eq(
    refused(bytes, limits={ ..@moongguf.limits, tensors: 1, }),
    Some(@moongguf.Tensors(limit=1, got=2)),
  )
  assert_eq(
    refused(bytes, limits={ ..@moongguf.limits, text: 4, }),
    Some(@moongguf.Text(limit=4, got=20)),
  )
  assert_eq(
    refused(bytes, limits={ ..@moongguf.limits, items: 2, }),
    Some(@moongguf.Items(limit=2, got=3)),
  )
  assert_eq(
    refused(vector("nested-arrays"), limits={ ..@moongguf.limits, depth: 1, }),
    Some(@moongguf.Nesting(limit=1, got=2)),
  )
}

///|
test "a tensor the file does not have is named" {
  let file = @moongguf.File::parse(vector("every-value-type")[:])
  assert_eq(file.tensor("nope"), None)
  assert_eq(file.data("nope"), None)
  let failure = try {
    let _ = file.extent("nope")
    None
  } catch {
    error => Some(error)
  }
  assert_eq(failure, Some(@moongguf.Missing(name="nope")))
}

///|
test "a version 1 or 2 file is read but not written" {
  for name in ["version-1", "version-2"] {
    let file = @moongguf.File::parse(vector(name)[:])
    let failure = try {
      let _ = file.encode()
      None
    } catch {
      error => Some(error)
    }
    assert_eq(failure, Some(@moongguf.ReadOnly(version=file.version())))
  }
}

///|
test "the bytes of a tensor that are not here are asked for by name" {
  let whole = vector("every-value-type")
  let complete = @moongguf.File::parse(whole[:])
  // The index is all there, and so is the first tensor; the second is cut off.
  let head = whole.exact_view(
    end=(complete.data_start() + complete.extent("plain.f32").length + 4L).to_int(),
  )
  let file = @moongguf.File::parse(head)
  assert_eq(file.data("plain.f32").unwrap().length(), 64)
  assert_eq(file.data("plain.f16"), None)
  let failure = try {
    let _ = file.encode()
    None
  } catch {
    error => Some(error)
  }
  assert_eq(failure, Some(@moongguf.Absent(name="plain.f16")))
}

///|
test "fewer bytes than a tensor takes are refused, both ways in" {
  let file = @moongguf.File::new()
  let failure = try {
    file.add(
      @moongguf.Tensor::new(name="t", kind=@moongguf.F32, dims=[8UL]),
      Bytes::make(4, b'\x00')[:],
    )
    None
  } catch {
    error => Some(error)
  }
  assert_eq(failure, Some(@moongguf.Short(name="t", want=32L, got=4L)))
  let parsed = @moongguf.File::parse(vector("every-value-type")[:])
  let shard = try {
    let _ = parsed.shard("plain.f32", Bytes::make(8, b'\x00')[:], at=1000L)
    None
  } catch {
    error => Some(error)
  }
  assert_eq(shard, Some(@moongguf.Short(name="plain.f32", want=64L, got=1000L)))
}

///|
test "a value that contradicts the kind declared for it is refused" {
  let file = @moongguf.File::new()
  file.set(
    "bad",
    @moongguf.Value::Array(@moongguf.ValueType::Int32, [
      @moongguf.Value::Int32(1),
      @moongguf.Value::String("two"),
    ]),
  )
  let failure = try {
    let _ = file.encode()
    None
  } catch {
    error => Some(error)
  }
  assert_eq(
    failure,
    Some(
      @moongguf.Mismatch(
        at=-1L,
        want=@moongguf.ValueType::Int32,
        got=@moongguf.ValueType::String,
      ),
    ),
  )
}

///|
test "the entries of an array of arrays say what they hold" {
  // The outer array says its entries are arrays; each entry then says what its
  // own entries are, so an entry is a whole array value without the marker.
  let bytes = bare(0UL, 1UL)
    .text("k")
    .u32(9U)
    .u32(9U)
    .u64(1UL)
    .u32(4U)
    .u64(2UL)
    .u32(7U)
    .u32(8U)
    .done()
  let file = @moongguf.File::parse(bytes[:])
  assert_eq(
    file.meta().get("k"),
    Some(
      @moongguf.Value::Array(@moongguf.ValueType::Array, [
        @moongguf.Value::Array(@moongguf.ValueType::UInt32, [
          @moongguf.Value::UInt32(7),
          @moongguf.Value::UInt32(8),
        ]),
      ]),
    ),
  )
}
