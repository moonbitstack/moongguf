///|
/// A 64-bit count as an `Int`, or `None` when it does not fit one. Lengths and
/// counts arrive as 64 bits and every place that holds one in a `Bytes` has to
/// pass through here first.
fn narrow(n : UInt64) -> Int32? {
  if n > 0x7FFF_FFFFUL {
    None
  } else {
    Some(n.reinterpret_as_int64().to_int())
  }
}

///|
/// `n` rounded up to a multiple of an alignment that is a power of two.
fn pad_to(n : Int64, alignment : UInt32) -> Int64 {
  let step = alignment.to_uint64().reinterpret_as_int64()
  let rest = n % step
  if rest == 0L {
    n
  } else {
    n + step - rest
  }
}
