// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Build a file from nothing and read it back, which is what a converter does
/// at the end of its work.
///
///     moon run src/examples/02-write
#coverage.skip
fn main {
  build() catch {
    error => println("cannot write the file: \{error}")
  }
}

///|
/// A file with two metadata pairs and one tensor, written and read back.
fn build() -> Unit raise @moongguf.Refused {
  let file = @moongguf.File::new()
  file.set("general.architecture", @moongguf.Value::String("llama"))
  file.set("llama.block_count", @moongguf.Value::UInt32(1))
  file.set(
    "tokenizer.ggml.tokens",
    @moongguf.Value::Array(@moongguf.String, [
      @moongguf.Value::String("a"),
      @moongguf.Value::String("b"),
    ]),
  )
  // 1.0 and 2.0, as `f32` sees them.
  let values = Bytes::from_array([
    0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x00, 0x40,
  ])
  file.add(
    @moongguf.Tensor::new(name="weight", kind=@moongguf.F32, dims=[2UL]),
    values[:],
  )
  let bytes = file.encode()
  println("\{bytes.length()} bytes, \{file.meta().count()} metadata pairs")
  let back = @moongguf.File::parse(bytes[:])
  println(
    "read back \{back.meta().count()} pairs and \{back.tensor_count()} tensors",
  )
  println("the same bytes: \{back.encode() == bytes}")
}
