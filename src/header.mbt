///|
/// The four bytes every GGUF file starts with.
pub let magic : Bytes = b"GGUF"

///|
/// The version of the format a file was written in. Versions 1 and 2 are read;
/// 3 is read and written.
#derive(Eq, Debug)
pub(all) enum Version {
  V1
  V2
  V3
}

///|
/// The number the file stores for this version.
pub fn Version::code(self : Version) -> UInt32 {
  match self {
    V1 => 1
    V2 => 2
    V3 => 3
  }
}

///|
/// The version a number names, or `None` for a number the format never had.
pub fn Version::of(code : UInt32) -> Version? {
  match code {
    1 => Some(V1)
    2 => Some(V2)
    3 => Some(V3)
    _ => None
  }
}

///|
/// The byte order a file's numbers are stored in. Files are little-endian; a
/// big-endian file is one converted for a machine that needs it, and reads and
/// writes the same way once this says which it is.
#derive(Eq, Debug)
pub(all) enum ByteOrder {
  Little
  Big
}

///|
/// The fixed part of a file: the magic, the version, and how many of the two
/// tables follow.
#derive(Eq, Debug)
pub(all) struct Header {
  /// The version the file was written in.
  version : Version
  /// How many tensors the file indexes.
  tensors : Int32
  /// How many metadata pairs the file carries.
  entries : Int32
}

///|
/// Whether bytes start with the magic, which is all that can be told without
/// reading the rest.
pub fn is_gguf(bytes : BytesView) -> Bool {
  bytes.length() >= 4 && bytes.exact_view(start=0, end=4) == magic[:]
}
