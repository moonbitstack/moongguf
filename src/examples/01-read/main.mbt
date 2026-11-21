// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A model file, in hex: one metadata pair and one tensor. A real one comes
/// from a disk or a network; this library only deals in the bytes.
let model : Bytes = b"\x47\x47\x55\x46\x03\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x14\x00\x00\x00\x00\x00\x00\x00\x67\x65\x6e\x65\x72\x61\x6c\x2e\x61\x72\x63\x68\x69\x74\x65\x63\x74\x75\x72\x65\x08\x00\x00\x00\x05\x00\x00\x00\x00\x00\x00\x00\x6c\x6c\x61\x6d\x61\x11\x00\x00\x00\x00\x00\x00\x00\x74\x6f\x6b\x65\x6e\x5f\x65\x6d\x62\x64\x2e\x77\x65\x69\x67\x68\x74\x01\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x47\x47\x55\x46\x0a\x14\x1e\x28\x32\x3c\x46\x50\x5a\x64\x6e\x78\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"

///|
/// What a file holds, without holding its weights: the header, the metadata
/// table and the tensor index are all a reader needs to answer questions about
/// a model.
///
///     moon run src/examples/01-read
#coverage.skip
fn main {
  show(model) catch {
    error => println("not a GGUF file: \{error}")
  }
}

///|
/// What the file holds: the version, the metadata, the tensor index, and the
/// first bytes of a tensor.
fn show(bytes : Bytes) -> Unit raise @moongguf.Refused {
  let file = @moongguf.File::parse(bytes[:])
  println("version \{file.version().code()}, \{file.tensor_count()} tensors")
  let arch = file.meta().text("general.architecture").unwrap_or("?")
  println("architecture \{arch}")
  for tensor in file.tensors() {
    println(
      "\{tensor.name()}: \{tensor.kind().name()} of \{tensor.n_elements()} values",
    )
  }
  let data = file.data("token_embd.weight").unwrap()
  println(
    "the first value's bytes: \{data[0]} \{data[1]} \{data[2]} \{data[3]}",
  )
}
