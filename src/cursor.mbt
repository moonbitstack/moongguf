///|
/// A position in the bytes of a file, reading one field at a time. Every read
/// that would pass the end is refused with the position it wanted, so nothing
/// downstream has to check a length again.
priv struct Cursor {
  bytes : BytesView
  mut at : Int32
  mut order : ByteOrder
  /// Lengths and counts are 64 bits wide from version 2 on; version 1 stored
  /// them in 32.
  mut wide : Bool
}

///|
fn Cursor::new(bytes : BytesView, order : ByteOrder, wide : Bool) -> Cursor {
  { bytes, at: 0, order, wide, }
}

///|
fn Cursor::left(self : Cursor) -> Int32 {
  self.bytes.length() - self.at
}

///|
fn Cursor::take(self : Cursor, want : Int32) -> BytesView raise Refused {
  if self.left() < want {
    raise Truncated(at=self.at.to_int64(), want~, got=self.left())
  }
  let piece = self.bytes.exact_view(start=self.at, end=self.at + want)
  self.at = self.at + want
  piece
}

///|
fn Cursor::u8(self : Cursor) -> UInt32 raise Refused {
  self.take(1)[0].to_uint()
}

///|
fn Cursor::u16(self : Cursor) -> UInt32 raise Refused {
  let piece = self.take(2)
  match self.order {
    Little => piece[0].to_uint() | (piece[1].to_uint() << 8)
    Big => piece[1].to_uint() | (piece[0].to_uint() << 8)
  }
}

///|
fn Cursor::u32(self : Cursor) -> UInt32 raise Refused {
  let piece = self.take(4)
  let mut n = 0U
  match self.order {
    Little =>
      for i in 0..<4 {
        n = n | (piece[i].to_uint() << (i * 8))
      }
    Big =>
      for i in 0..<4 {
        n = n | (piece[i].to_uint() << ((3 - i) * 8))
      }
  }
  n
}

///|
fn Cursor::u64(self : Cursor) -> UInt64 raise Refused {
  let piece = self.take(8)
  let mut n = 0UL
  match self.order {
    Little =>
      for i in 0..<8 {
        n = n | (piece[i].to_uint64() << (i * 8))
      }
    Big =>
      for i in 0..<8 {
        n = n | (piece[i].to_uint64() << ((7 - i) * 8))
      }
  }
  n
}

///|
/// A count: 32 bits in version 1, 64 from version 2 on.
fn Cursor::count(self : Cursor) -> UInt64 raise Refused {
  if self.wide {
    self.u64()
  } else {
    self.u32().to_uint64()
  }
}

///|
/// A length-prefixed run of bytes, the way strings and names are stored. The
/// prefix is not part of the returned view.
fn Cursor::run(self : Cursor, limits : Limits) -> BytesView raise Refused {
  let start = self.at.to_int64()
  let length = self.count()
  let size = match narrow(length) {
    Some(size) => size
    None => raise Text(limit=limits.text, got=limits.text + 1)
  }
  if size > limits.text {
    raise Text(limit=limits.text, got=size)
  }
  if self.left() < size {
    raise Truncated(at=start, want=size, got=self.left())
  }
  self.take(size)
}

///|
/// A run of bytes read as text. A run that is not UTF-8 is refused rather than
/// repaired: a key or a name that does not round trip would be written back as
/// something else.
fn Cursor::text(self : Cursor, limits : Limits) -> String raise Refused {
  let at = self.at.to_int64()
  let run = self.run(limits)
  @utf8.decode(run) catch {
    @utf8.Malformed(_) => raise Malformed(at~)
  }
}
