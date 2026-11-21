///|
/// One metadata value as the file stores it: the bytes of the value itself,
/// with no type in front. The type came before it, in the pair's header or in
/// the header of the array it is an entry of. `depth` is how many arrays this
/// value sits inside, its own included.
fn read_value(
  cur : Cursor,
  kind : ValueType,
  limits : Limits,
  depth : Int32,
) -> Value raise Refused {
  match kind {
    UInt8 => UInt8(cur.u8())
    Int8 => Int8(signed8(cur.u8()))
    UInt16 => UInt16(cur.u16())
    Int16 => Int16(signed16(cur.u16()))
    UInt32 => UInt32(cur.u32())
    Int32 => Int32(cur.u32().reinterpret_as_int())
    Float32 => Float32(Float::reinterpret_from_uint(cur.u32()))
    Bool => Bool(cur.u8() != 0U)
    String => String(cur.text(limits))
    Array => read_array(cur, limits, depth)
    UInt64 => UInt64(cur.u64())
    Int64 => Int64(cur.u64().reinterpret_as_int64())
    Float64 => Float64(UInt64::reinterpret_as_double(cur.u64()))
  }
}

///|
/// An array value: the kind its entries share, then the entries themselves.
fn read_array(
  cur : Cursor,
  limits : Limits,
  depth : Int32,
) -> Value raise Refused {
  let code = cur.u32()
  let kind = match ValueType::of(code) {
    Some(kind) => kind
    None => raise Untyped(got=code)
  }
  Value::Array(kind, read_entries(cur, kind, limits, depth))
}

///|
/// The entries of an array whose entries are `kind`. An array of arrays repeats
/// the kind and the length for each entry, the way the reference reader expects
/// it: the entry says what its own entries are, and the array it sits in has
/// already said that it is an array.
fn read_entries(
  cur : Cursor,
  kind : ValueType,
  limits : Limits,
  depth : Int32,
) -> Array[Value] raise Refused {
  if depth > limits.depth {
    raise Nesting(limit=limits.depth, got=depth)
  }
  let declared = cur.count()
  let count = match narrow(declared) {
    Some(count) => count
    None => raise Items(limit=limits.items, got=limits.items + 1)
  }
  if count > limits.items {
    raise Items(limit=limits.items, got=count)
  }
  let items = []
  for _ in 0..<count {
    items.push(read_value(cur, kind, limits, depth + 1))
  }
  items
}

///|
/// One metadata value written out, without the type in front of it.
fn write_value(sink : Sink, value : Value) -> Unit raise Refused {
  match value {
    UInt8(n) => sink.u8(n.to_uint64())
    Int8(n) => sink.u8(n.to_uint64())
    UInt16(n) => sink.u16(n.to_uint64())
    Int16(n) => sink.u16(n.to_uint64())
    UInt32(n) => sink.u32(n)
    Int32(n) => sink.u32(n.reinterpret_as_uint())
    Float32(x) => sink.f32(x)
    Bool(flag) => sink.u8(if flag { 1UL } else { 0UL })
    String(text) => sink.text(text)
    Array(kind, items) => {
      sink.u32(kind.code())
      sink.count(items.length().to_uint64())
      for item in items {
        let actual = item.value_type()
        if actual != kind {
          raise Mismatch(at=-1L, want=kind, got=actual)
        }
        write_value(sink, item)
      }
    }
    UInt64(n) => sink.u64(n)
    Int64(n) => sink.u64(n.reinterpret_as_uint64())
    Float64(x) => sink.f64(x)
  }
}

///|
fn signed8(n : UInt32) -> Int32 {
  if n >= 0x80U {
    n.reinterpret_as_int() - 0x100
  } else {
    n.reinterpret_as_int()
  }
}

///|
fn signed16(n : UInt32) -> Int32 {
  if n >= 0x8000U {
    n.reinterpret_as_int() - 0x10000
  } else {
    n.reinterpret_as_int()
  }
}
