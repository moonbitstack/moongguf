// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read a model file the way a machine with a small buffer would: the index in
/// one growing window, then every tensor's bytes in shards, never holding the
/// whole file.
///
///     moon run integration/tools/read-chunks -- model.gguf
fn main {
  let args = @env.args()
  if args.length() != 2 {
    println("usage: read-chunks <file.gguf>")
    return
  }
  let file = @fs.open(args[1], mode=ReadOnly) catch {
    _ => {
      println("cannot open \{args[1]}")
      return
    }
  }
  let total = file.size() catch { _ => 0L }
  let index = match read_index(file, total) {
    Ok(index) => index
    Err(reason) => {
      println(reason)
      file.close()
      return
    }
  }
  println("version \{index.version().code()}, alignment \{index.alignment()}")
  println(
    "metadata pairs \{index.meta().count()}, tensors \{index.tensor_count()}",
  )
  match index.meta().text("general.architecture") {
    Some(arch) => println("architecture \{arch}")
    None => ()
  }
  let held = read_tensors(file, index) catch {
    error => {
      println("cannot read the tensors: \{error}")
      file.close()
      return
    }
  }
  println("\{held} bytes of tensor data, read in shards")
  file.close()
}

///|
/// The index, read into a window that doubles until the index fits inside it.
/// A file's tokenizer can run to megabytes, so the size is found rather than
/// guessed.
fn read_index(file : @fs.File, total : Int64) -> Result[@moongguf.File, String] {
  let mut span = 65_536
  for _ in 0..<64 {
    if span.to_int64() > total {
      span = total.to_int()
    }
    if span <= 0 {
      return Err("the file holds nothing")
    }
    let window = read_at(file, 0L, span)
    match parse(window) {
      Ok(index) => return Ok(index)
      Err(true) => ()
      Err(false) => return Err("not a GGUF file")
    }
    if span.to_int64() >= total {
      break
    }
    span = span * 2
  }
  Err("the index does not fit the file")
}

///|
/// The bytes from `at` to the end of the window, or as many as the file has
/// left.
fn read_at(file : @fs.File, at : Int64, want : Int32) -> Bytes {
  let buffer = FixedArray::make(want, b'\x00')
  let read = file.read_into_at(buffer.mut_view(), position=at) catch { _ => 0 }
  Bytes::from_array(buffer.exact_view(end=read))
}

///|
/// `Err(true)` says the window was too small for the index; `Err(false)` says
/// the bytes are not a GGUF file at all.
fn parse(bytes : Bytes) -> Result[@moongguf.File, Bool] {
  Ok(@moongguf.File::parse(bytes[:])) catch {
    @moongguf.Truncated(_) => Err(true)
    _ => Err(false)
  }
}

///|
/// Every tensor's bytes, read a megabyte at a time and checked against the
/// extent the index recorded. A file larger than one `Bytes` is read this way.
fn read_tensors(
  file : @fs.File,
  index : @moongguf.File,
) -> Int64 raise @moongguf.Refused {
  let mut held = 0L
  for tensor in index.tensors() {
    let extent = tensor.extent() catch { _ => continue }
    let mut at = 0L
    while at < extent.length {
      let want = if extent.length - at < 1_048_576L {
        (extent.length - at).to_int()
      } else {
        1_048_576
      }
      let shard = read_at(file, index.data_start() + extent.at + at, want)
      let piece = index.shard(tensor.name(), shard[:], at~) catch { _ => break }
      held = held + piece.length().to_int64()
      at = at + want.to_int64()
    }
  }
  held
}
