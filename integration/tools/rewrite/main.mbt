// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read a file and write it out again from what was read.
///
///     moon run integration/tools/rewrite -- in.gguf out.gguf
fn main {
  let args = @env.args()
  if args.length() != 3 {
    println("usage: rewrite <in.gguf> <out.gguf>")
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
  let again = file.encode() catch {
    error => {
      println("cannot write it back: \{error}")
      return
    }
  }
  @fs.write_bytes_to_file(args[2], again) catch {
    _ => println("cannot write \{args[2]}")
  }
}
