///|
/// Where a tensor's bytes sit: `at` from the start of the data section, and how
/// many bytes they take. The data section itself starts at `File::data_start`.
#derive(Eq, Debug)
pub(all) struct Extent {
  /// Bytes from the start of the data section.
  at : Int64
  /// How many bytes the tensor takes.
  length : Int64
}

///|
/// One entry of a file's tensor index: what it is called, what it is stored as,
/// its dimensions, where its bytes start, and — when the file was read — where
/// the entry itself sits.
///
/// The dimensions are `ggml`'s order, the one the file stores: the first is the
/// row the innermost loop walks, so a matrix of 4096 rows of 11008 values is
/// `[11008, 4096]` and takes `11008 * 4096 * 2` bytes as `f16`.
#derive(Eq, Debug)
pub struct Tensor {
  priv name : String
  priv kind : GgmlType
  priv dims : Array[UInt64]
  priv offset : UInt64
  priv at : Int64
  priv data : BytesView?
}

///|
/// A tensor to put into a file, before its bytes are attached.
pub fn Tensor::new(
  name~ : String,
  kind~ : GgmlType,
  dims~ : Array[UInt64],
) -> Tensor {
  { name, kind, dims, offset: 0UL, at: -1L, data: None, }
}

///|
/// An index entry as it came out of a file: the data section's offset, and
/// where the entry itself sits.
fn Tensor::read(
  name : String,
  kind : GgmlType,
  dims : Array[UInt64],
  offset : UInt64,
  at : Int64,
) -> Tensor {
  { name, kind, dims, offset, at, data: None, }
}

///|
/// The same tensor, landed at another offset in the data section.
fn Tensor::with_offset(self : Tensor, offset : UInt64) -> Tensor {
  { ..self, offset, }
}

///|
/// The same tensor, carrying its bytes rather than borrowing a file's.
fn Tensor::with_data(self : Tensor, data : BytesView) -> Tensor {
  { ..self, data: Some(data), }
}

///|
/// The name the index gives it.
pub fn Tensor::name(self : Tensor) -> String {
  self.name
}

///|
/// The encoding its blocks are stored in.
pub fn Tensor::kind(self : Tensor) -> GgmlType {
  self.kind
}

///|
/// The dimensions in `ggml`'s order, the row first.
pub fn Tensor::dims(self : Tensor) -> ArrayView[UInt64] {
  self.dims[:]
}

///|
/// How many values the tensor holds.
pub fn Tensor::n_elements(self : Tensor) -> UInt64 raise Refused {
  let mut n = 1UL
  for dim in self.dims {
    if dim != 0UL && n > 0xFFFF_FFFF_FFFF_FFFFUL / dim {
      raise Volume(name=self.name)
    }
    n = n * dim
  }
  n
}

///|
/// How many bytes the tensor takes, blocks and all. `Refused` when its row is
/// not a whole number of blocks, which no reader could walk.
pub fn Tensor::byte_length(self : Tensor) -> Int64 raise Refused {
  byte_length_of(self.name, self.kind, self.dims[:])
}

///|
/// Where the bytes sit and how far they run.
pub fn Tensor::extent(self : Tensor) -> Extent raise Refused {
  { at: self.offset.reinterpret_as_int64(), length: self.byte_length(), }
}

///|
/// Where the entry sits in the file it was read from, or -1 for one made here.
pub fn Tensor::at(self : Tensor) -> Int64 {
  self.at
}

///|
/// The bytes attached to it, when it carries its own rather than borrowing the
/// file's.
pub fn Tensor::data(self : Tensor) -> BytesView? {
  self.data
}

///|
/// The bytes a tensor of this shape and encoding takes, with the two refusals
/// a shape can earn: a row that is not whole blocks, and a count too large to
/// compute.
fn byte_length_of(
  name : String,
  kind : GgmlType,
  dims : ArrayView[UInt64],
) -> Int64 raise Refused {
  let row = if dims.length() == 0 { 1UL } else { dims[0] }
  let mut n = 1UL
  for dim in dims {
    if dim != 0UL && n > 0xFFFF_FFFF_FFFF_FFFFUL / dim {
      raise Volume(name~)
    }
    n = n * dim
  }
  let block = kind.block_size().to_uint64()
  if row % block != 0UL {
    raise Blocks(name~, block=kind.block_size(), got=row)
  }
  let blocks = n / block
  let bytes = kind.bytes_per_block().to_uint64()
  if blocks != 0UL && bytes != 0UL && blocks > 0x7FFF_FFFF_FFFF_FFFFUL / bytes {
    raise Volume(name~)
  }
  (blocks * bytes).reinterpret_as_int64()
}
