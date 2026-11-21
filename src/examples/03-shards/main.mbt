// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read a file that does not fit one `Bytes`: the index is parsed from the
/// head of the file, and each tensor's bytes are handed over as they are read,
/// one shard at a time. This is what a reader of a four-gigabyte model does,
/// with the shards coming from `File::read_at` or from a `fetch` of a byte
/// range.
///
///     moon run src/examples/03-shards
#coverage.skip
fn main {
  walk() catch {
    error => println("cannot read the file: \{error}")
  }
}

///|
/// The tensor, shard by shard, out of the bytes of a whole file.
fn walk() -> Unit raise @moongguf.Refused {
  let whole = demo()
  // The index alone would be enough to answer what the file holds; parsing
  // the whole of it judges the tensor's dimensions against the bytes present.
  let index = @moongguf.File::parse(whole[:])
  let extent = index.extent("weight")
  println("the data section starts at \{index.data_start()}")
  println("the tensor sits at \{extent.at} and runs \{extent.length} bytes")
  let mut seen = 0
  let mut at = 0L
  while at < extent.length {
    let from = index.data_start() + extent.at + at
    let to = if extent.length - at < 1024L {
      from + extent.length - at
    } else {
      from + 1024L
    }
    // A shard of at most a kilobyte, the way a caller that can only hold so
    // much would hand the file over.
    let piece = whole.exact_view(start=from.to_int(), end=to.to_int())
    let view = index.shard("weight", piece, at~)
    seen = seen + view.length()
    at = at + 1024L
  }
  println("\{seen} bytes of the tensor seen, 1024 at a time")
}

///|
/// A file with one `f32` tensor of 1024 values, built here so the example runs
/// without a model on disk.
fn demo() -> Bytes {
  let file = @moongguf.File::new()
  let values = Bytes::make(4096, b'\x01')
  file.add(
    @moongguf.Tensor::new(name="weight", kind=@moongguf.F32, dims=[1024UL]),
    values[:],
  ) catch {
    error => {
      println("cannot build the file: \{error}")
      return Bytes::make(0, b'\x00')
    }
  }
  file.encode() catch {
    error => {
      println("cannot write the file: \{error}")
      Bytes::make(0, b'\x00')
    }
  }
}
