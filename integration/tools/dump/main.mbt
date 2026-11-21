// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The dump of one file, as JSON on standard output.
///
///     moon run integration/tools/dump -- path/to/file.gguf
fn main {
  let args = @env.args()
  if args.length() != 2 {
    println("usage: dump <file.gguf>")
    return
  }
  let bytes = @fs.read_file_to_bytes(args[1]) catch {
    _ => {
      println("cannot read \{args[1]}")
      return
    }
  }
  let file = @moongguf.File::parse(bytes[:]) catch {
    error => {
      println("not a GGUF file: \{error}")
      return
    }
  }
  println(file.to_json().stringify(indent=1))
}
