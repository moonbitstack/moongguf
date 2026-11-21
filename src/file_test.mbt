// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a file made here reads back" {
  let file = @moongguf.File::new()
  file.set("general.architecture", @moongguf.Value::String("llama"))
  file.set("llama.block_count", @moongguf.Value::UInt32(2))
  let data = Bytes::make(96, b'\x2A')
  file.add(
    @moongguf.Tensor::new(name="blk.0.weight", kind=@moongguf.F32, dims=[24UL]),
    data[:],
  )
  let bytes = file.encode()
  let back = @moongguf.File::parse(bytes[:])
  assert_eq(back.version(), @moongguf.V3)
  assert_eq(back.header().tensors, 1)
  assert_eq(back.meta().count(), 2)
  assert_eq(
    back.meta().get("general.architecture"),
    Some(@moongguf.Value::String("llama")),
  )
  let tensor = back.tensor("blk.0.weight").unwrap()
  assert_eq(tensor.kind(), @moongguf.F32)
  assert_eq(tensor.dims().length(), 1)
  assert_eq(tensor.dims()[0], 24UL)
  assert_eq(tensor.byte_length(), 96L)
  assert_eq(back.data("blk.0.weight").unwrap().length(), 96)
  assert_eq(back.encode(), bytes)
}
