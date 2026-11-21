///|
/// A GGUF file: the header, the metadata table, the tensor index, and — when
/// the bytes of the data section were handed over with the rest — the tensor
/// data itself.
///
/// Reading never copies the tensor bytes. `data` hands out a view into the
/// bytes the file was parsed from, so a gigabyte model costs its metadata and
/// no more. A file too large for one `Bytes` is read in two parts: the index
/// from the head of the file, and each tensor's bytes as they are needed,
/// which `shard` takes a view of.
pub struct File {
  priv bytes : BytesView
  priv mut header : Header
  priv meta : Meta
  priv tensors : Array[Tensor]
  priv order : ByteOrder
  priv mut alignment : UInt32
  priv data_start : Int64
}

///|
/// An empty version 3 file, ready for metadata and tensors to be put into it.
///
/// An alignment other than the format's 32 is recorded as `general.alignment`,
/// because a reader would otherwise lay the data section out at 32 and find
/// every tensor's bytes in the wrong place.
pub fn File::new(alignment~ : UInt32 = 32U) -> File {
  let meta = Meta::new()
  if alignment != 32U {
    if alignment == 0U || (alignment & (alignment - 1U)) != 0U {
      abort("an alignment is a power of two, not \{alignment}")
    }
    meta.set("general.alignment", UInt32(alignment))
  }
  {
    bytes: Bytes::make(0, b'\x00')[:],
    header: { version: V3, tensors: 0, entries: meta.count(), },
    meta,
    tensors: [],
    order: Little,
    alignment,
    data_start: -1L,
  }
}

///|
/// Read a file from its bytes.
///
/// The bytes may be the whole file, or just as much of it as holds the index —
/// the header, the metadata table and the tensor index. Tensor bytes are only
/// needed when something asks for them.
pub fn File::parse(
  bytes : BytesView,
  limits~ : Limits = limits,
) -> File raise Refused {
  if bytes.length() < 4 {
    raise Truncated(at=0L, want=4, got=bytes.length())
  }
  let head = bytes.exact_view(start=0, end=4)
  if head != magic[:] {
    raise Magic(got=Bytes::from_array(head.to_array()))
  }
  let cursor = Cursor::new(bytes, Little, false)
  let _ = cursor.take(4)
  // The version, and with it the byte order: a file converted for a
  // big-endian machine reads back as a number past anything the format has,
  // with its low half cleared.
  let stored = cursor.u32()
  let (code, order) = if stored > 0xFFFFU && (stored & 0xFFFFU) == 0U {
    (swap32(stored), Big)
  } else {
    (stored, Little)
  }
  let version = match Version::of(code) {
    Some(version) => version
    None => raise Version(got=code)
  }
  cursor.order = order
  cursor.wide = version != V1

  let declared_tensors = cursor.count()
  let tensor_count = match narrow(declared_tensors) {
    Some(count) => count
    None => raise Tensors(limit=limits.tensors, got=limits.tensors + 1)
  }
  if tensor_count > limits.tensors {
    raise Tensors(limit=limits.tensors, got=tensor_count)
  }
  let declared_entries = cursor.count()
  let entry_count = match narrow(declared_entries) {
    Some(count) => count
    None => raise Entries(limit=limits.entries, got=limits.entries + 1)
  }
  if entry_count > limits.entries {
    raise Entries(limit=limits.entries, got=entry_count)
  }

  let meta = Meta::new()
  for _ in 0..<entry_count {
    let at = cursor.at.to_int64()
    let key = cursor.text(limits)
    if key.is_empty() {
      raise Empty
    }
    if meta.contains(key) {
      raise Duplicate(name=key)
    }
    let code = cursor.u32()
    let kind = match ValueType::of(code) {
      Some(kind) => kind
      None => raise Untyped(got=code)
    }
    meta.push({ key, value: read_value(cursor, kind, limits, 1), at, })
  }

  let alignment = match meta.entry("general.alignment") {
    Some({ value: UInt32(n), .. }) =>
      if n == 0U || (n & (n - 1U)) != 0U {
        raise Alignment(got=n)
      } else {
        n
      }
    Some({ value, at, .. }) =>
      raise Mismatch(at~, want=UInt32, got=value.value_type())
    None => 32U
  }

  let tensors = []
  let seen : Map[String, Bool] = Map([])
  let mut expected = 0UL
  for _ in 0..<tensor_count {
    let at = cursor.at.to_int64()
    let name = cursor.text(limits)
    if seen.contains(name) {
      raise Duplicate(name~)
    }
    seen.set(name, true)
    let declared = cursor.u32()
    let dims = match narrow(declared.to_uint64()) {
      Some(count) =>
        if count > 4 {
          raise Dims(limit=4, got=count)
        } else {
          let dims = []
          for _ in 0..<count {
            dims.push(cursor.u64())
          }
          dims
        }
      None => raise Dims(limit=4, got=0x7FFF_FFFF)
    }
    let code = cursor.u32()
    let kind = match GgmlType::of(code) {
      Some(kind) => kind
      None => raise Unencoded(got=code)
    }
    let offset = cursor.count()
    let length = byte_length_of(name, kind, dims[:])
    if offset != expected {
      raise Offset(name~, want=expected, got=offset)
    }
    expected = expected + pad_to(length, alignment).reinterpret_as_uint64()
    tensors.push(Tensor::read(name, kind, dims, offset, at))
  }

  {
    bytes,
    header: { version, tensors: tensor_count, entries: entry_count, },
    meta,
    tensors,
    order,
    alignment,
    data_start: pad_to(cursor.at.to_int64(), alignment),
  }
}

///|
/// The magic, the version and the two counts.
pub fn File::header(self : File) -> Header {
  self.header
}

///|
/// The version the file is written in.
pub fn File::version(self : File) -> Version {
  self.header.version
}

///|
/// The byte order the file's numbers are stored in.
pub fn File::order(self : File) -> ByteOrder {
  self.order
}

///|
/// The alignment the data section starts on, from `general.alignment` or the
/// format's default of 32.
pub fn File::alignment(self : File) -> UInt32 {
  self.alignment
}

///|
/// The metadata table.
pub fn File::meta(self : File) -> Meta {
  self.meta
}

///|
/// The value under a metadata key.
pub fn File::get(self : File, key : StringView) -> Value? {
  self.meta.get(key)
}

///|
/// The tensor index, in file order.
pub fn File::tensors(self : File) -> ArrayView[Tensor] {
  self.tensors[:]
}

///|
/// One tensor's index entry.
pub fn File::tensor(self : File, name : StringView) -> Tensor? {
  for tensor in self.tensors {
    if tensor.name[:] == name {
      return Some(tensor)
    }
  }
  None
}

///|
/// How many tensors the index holds.
pub fn File::tensor_count(self : File) -> Int32 {
  self.tensors.length()
}

///|
/// Where the data section starts: the end of the index, rounded up to the
/// alignment.
///
/// A file that was read knows this from its own bytes. A file built here finds
/// it by writing its index, which is what a caller streaming a large file needs
/// before it can place the first tensor.
pub fn File::data_start(self : File) -> Int64 raise Refused {
  if self.data_start >= 0L {
    self.data_start
  } else {
    self.encode_index().length().to_int64()
  }
}

///|
/// Where a tensor's bytes sit and how far they run.
pub fn File::extent(self : File, name : StringView) -> Extent raise Refused {
  match self.tensor(name) {
    Some(tensor) => tensor.extent()
    None => raise Missing(name=name.to_owned())
  }
}

///|
/// The bytes of a tensor, as a view into the bytes the file was parsed from.
/// `None` when those bytes are not in hand — a file parsed from its index alone
/// still answers everything about the tensor except its data.
pub fn File::data(self : File, name : StringView) -> BytesView? {
  let tensor = match self.tensor(name) {
    Some(tensor) => tensor
    None => return None
  }
  match tensor.data {
    Some(data) => Some(data)
    None => {
      let length = tensor.byte_length() catch { _ => return None }
      let start = self.data_start + tensor.offset.reinterpret_as_int64()
      let end = start + length
      if end > self.bytes.length().to_int64() {
        None
      } else {
        Some(self.bytes.exact_view(start=start.to_int(), end=end.to_int()))
      }
    }
  }
}

///|
/// A view of a tensor's bytes read from somewhere else — the second half of
/// reading a file too large for one `Bytes`, where the caller holds the data
/// section in pieces.
///
/// `at` is how far into the tensor the piece starts, so a tensor larger than
/// one `Bytes` can be handed over in pieces of whatever size the caller can
/// hold. The piece is checked against the tensor's extent and the part that
/// belongs to the tensor is returned, padding and all dropped.
pub fn File::shard(
  self : File,
  name : StringView,
  bytes : BytesView,
  at~ : Int64 = 0L,
) -> BytesView raise Refused {
  let extent = self.extent(name)
  if at < 0L || at > extent.length {
    raise Short(name=name.to_owned(), want=extent.length, got=at)
  }
  let room = extent.length - at
  let take = if bytes.length().to_int64() < room {
    bytes.length()
  } else {
    room.to_int()
  }
  bytes.exact_view(start=0, end=take)
}

///|
/// Put a value under a metadata key, replacing one already there.
///
/// `general.alignment` is the one key with a meaning beyond its value: setting
/// it moves where the data section starts, so the tensors after it move too.
/// Only a power of two fits.
pub fn File::set(
  self : File,
  key : String,
  value : Value,
) -> Unit raise Refused {
  if key == "general.alignment" {
    match value {
      UInt32(n) =>
        if n == 0U || (n & (n - 1U)) != 0U {
          raise Alignment(got=n)
        } else {
          self.alignment = n
        }
      other => raise Mismatch(at=-1L, want=UInt32, got=other.value_type())
    }
  }
  self.meta.set(key, value)
  self.header = { ..self.header, entries: self.meta.count(), }
}

///|
/// Drop a metadata key. Dropping `general.alignment` puts the alignment back to
/// the format's 32.
pub fn File::remove(self : File, key : StringView) -> Unit {
  if key == "general.alignment" {
    self.alignment = 32U
  }
  self.meta.remove(key)
  self.header = { ..self.header, entries: self.meta.count(), }
}

///|
/// Put a tensor into the file, with its bytes. The bytes stay where the caller
/// put them: a file holds views, and writing it copies them out once.
///
/// The tensor lands at the end of the data section, where the one before it
/// ends and the alignment is satisfied.
pub fn File::add(
  self : File,
  tensor : Tensor,
  data : BytesView,
) -> Unit raise Refused {
  let length = tensor.byte_length()
  if data.length().to_int64() < length {
    raise Short(name=tensor.name, want=length, got=data.length().to_int64())
  }
  if self.tensor(tensor.name) is Some(_) {
    raise Duplicate(name=tensor.name)
  }
  let offset = self.next_offset()
  self.tensors.push(
    tensor
    .with_offset(offset)
    .with_data(data.exact_view(start=0, end=length.to_int())),
  )
  self.header = { ..self.header, tensors: self.tensors.length(), }
}

///|
/// Put a tensor into the file's index without its bytes, for a caller that
/// writes the data section itself.
pub fn File::add_index(self : File, tensor : Tensor) -> Unit raise Refused {
  if self.tensor(tensor.name) is Some(_) {
    raise Duplicate(name=tensor.name)
  }
  let _ = tensor.byte_length()
  self.tensors.push(tensor.with_offset(self.next_offset()))
  self.header = { ..self.header, tensors: self.tensors.length(), }
}

///|
/// Where the next tensor goes: the end of the last one, rounded up to the
/// alignment.
fn File::next_offset(self : File) -> UInt64 raise Refused {
  match self.tensors.length() {
    0 => 0UL
    n => {
      let last = self.tensors[n - 1]
      last.offset +
      pad_to(last.byte_length(), self.alignment).reinterpret_as_uint64()
    }
  }
}

///|
/// The index as bytes: the header, the metadata table, the tensor index, and
/// the zeroes that bring the length up to the alignment. This is the first part
/// of a file, and all of it a reader needs to answer what a model holds without
/// its weights.
pub fn File::encode_index(self : File) -> Bytes raise Refused {
  if self.header.version != V3 {
    raise ReadOnly(version=self.header.version)
  }
  let sink = Sink::new(self.order, true)
  self.write_to(sink)
  sink.pad(self.alignment)
  sink.to_bytes()
}

///|
/// The whole file: the index, then every tensor's bytes at the offset the index
/// recorded, each followed by the zeroes that reach the alignment.
///
/// One `Bytes` holds the result, so a file past what a `Bytes` can hold is
/// refused rather than truncated: `encode_index` and `add_index` are there for
/// writing such a file in pieces.
pub fn File::encode(self : File) -> Bytes raise Refused {
  if self.header.version != V3 {
    raise ReadOnly(version=self.header.version)
  }
  let sink = Sink::new(self.order, true)
  self.write_to(sink)
  sink.pad(self.alignment)
  let mut total = sink.length().to_int64()
  for tensor in self.tensors {
    total = total + pad_to(tensor.byte_length(), self.alignment)
    if total > 0x7FFF_FFFFL {
      raise Large(limit=0x7FFF_FFFF, got=total)
    }
  }
  for tensor in self.tensors {
    sink.raw(self.tensor_bytes(tensor))
    sink.pad(self.alignment)
  }
  sink.to_bytes()
}

///|
/// The header, the metadata table and the tensor index, up to the data section
/// but not including its padding.
fn File::write_to(self : File, sink : Sink) -> Unit raise Refused {
  sink.raw(magic[:])
  sink.u32(self.header.version.code())
  sink.count(self.header.tensors.to_uint64())
  sink.count(self.meta.count().to_uint64())
  for entry in self.meta.entries() {
    sink.text(entry.key)
    sink.u32(entry.value.value_type().code())
    write_value(sink, entry.value)
  }
  for tensor in self.tensors {
    sink.text(tensor.name)
    sink.u32(tensor.dims.length().reinterpret_as_uint())
    for dim in tensor.dims {
      sink.u64(dim)
    }
    sink.u32(tensor.kind.code())
    sink.count(tensor.offset)
  }
}

///|
/// The bytes of one tensor, whichever way it was come by: attached when the
/// tensor was put into a file made here, or borrowed from the bytes a file was
/// parsed from.
fn File::tensor_bytes(self : File, tensor : Tensor) -> BytesView raise Refused {
  let length = tensor.byte_length()
  match tensor.data {
    Some(data) =>
      if data.length().to_int64() < length {
        raise Short(name=tensor.name, want=length, got=data.length().to_int64())
      } else {
        data.exact_view(start=0, end=length.to_int())
      }
    None => {
      let start = self.data_start + tensor.offset.reinterpret_as_int64()
      let end = start + length
      if end > self.bytes.length().to_int64() {
        raise Absent(name=tensor.name)
      } else {
        self.bytes.exact_view(start=start.to_int(), end=end.to_int())
      }
    }
  }
}

///|
/// Four bytes with their order turned around, which is how a big-endian file's
/// version reaches a little-endian reader.
fn swap32(n : UInt32) -> UInt32 {
  ((n & 0xFFU) << 24) |
  ((n & 0xFF00U) << 8) |
  ((n >> 8) & 0xFF00U) |
  ((n >> 24) & 0xFFU)
}
