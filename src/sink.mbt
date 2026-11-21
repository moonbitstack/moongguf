///|
/// Where a file is written to, one field at a time. The buffer grows as it
/// goes, so the length of the index need not be known before writing it.
priv struct Sink {
  buffer : Buffer
  order : ByteOrder
  /// Lengths and counts are 64 bits wide from version 2 on; version 1 stored
  /// them in 32.
  wide : Bool
}

///|
fn Sink::new(order : ByteOrder, wide : Bool) -> Sink {
  { buffer: Buffer(), order, wide, }
}

///|
fn Sink::length(self : Sink) -> Int32 {
  self.buffer.length()
}

///|
fn Sink::u8(self : Sink, n : UInt64) -> Unit {
  self.buffer.write_byte(n.to_byte())
}

///|
fn Sink::u16(self : Sink, n : UInt64) -> Unit {
  match self.order {
    Little => self.buffer.write_uint16_le(n.to_uint16())
    Big => self.buffer.write_uint16_be(n.to_uint16())
  }
}

///|
fn Sink::u32(self : Sink, n : UInt32) -> Unit {
  match self.order {
    Little => self.buffer.write_uint_le(n)
    Big => self.buffer.write_uint_be(n)
  }
}

///|
fn Sink::u64(self : Sink, n : UInt64) -> Unit {
  match self.order {
    Little => self.buffer.write_uint64_le(n)
    Big => self.buffer.write_uint64_be(n)
  }
}

///|
fn Sink::f32(self : Sink, x : Float) -> Unit {
  match self.order {
    Little => self.buffer.write_float_le(x)
    Big => self.buffer.write_float_be(x)
  }
}

///|
fn Sink::f64(self : Sink, x : Double) -> Unit {
  match self.order {
    Little => self.buffer.write_double_le(x)
    Big => self.buffer.write_double_be(x)
  }
}

///|
/// A count: 32 bits in version 1, 64 from version 2 on. Only version 3 is
/// written, so the wide form is what a file gets.
fn Sink::count(self : Sink, n : UInt64) -> Unit {
  if self.wide {
    self.u64(n)
  } else {
    self.u32(n.to_uint())
  }
}

///|
fn Sink::raw(self : Sink, bytes : BytesView) -> Unit {
  self.buffer.write_bytes(bytes)
}

///|
/// A length-prefixed run of bytes, the way strings and names are stored.
fn Sink::text(self : Sink, text : String) -> Unit {
  let bytes = @utf8.encode(text)
  self.count(bytes.length().to_uint64())
  self.buffer.write_bytes(bytes[:])
}

///|
/// Zeroes until the buffer is a multiple of the alignment. `alignment` is a
/// power of two, which the file's own reader has already checked.
fn Sink::pad(self : Sink, alignment : UInt32) -> Unit {
  let step = alignment.to_uint64().reinterpret_as_int64().to_int()
  let rest = self.length() % step
  if rest != 0 {
    for _ in 0..<(step - rest) {
      self.buffer.write_byte(b'\x00')
    }
  }
}

///|
fn Sink::to_bytes(self : Sink) -> Bytes {
  self.buffer.to_bytes()
}
