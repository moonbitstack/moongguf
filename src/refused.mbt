///|
/// Why bytes are not a GGUF file this library can read, or why a file it holds
/// cannot be written.
///
/// The variants a caller is meant to act on carry the numbers that explain
/// them: a ceiling and what went past it, or the position something was
/// expected at and the position found.
#derive(Eq, Debug)
pub(all) suberror Refused {
  /// The bytes end before a field does. `at` is where the field starts.
  Truncated(at~ : Int64, want~ : Int32, got~ : Int32)
  /// The first four bytes are not `GGUF`.
  Magic(got~ : Bytes)
  /// A version number that is neither 1, 2 nor 3.
  Version(got~ : UInt32)
  /// A version 1 or 2 file asked to be written. Only version 3 is written.
  ReadOnly(version~ : Version)
  /// A value type number outside the thirteen.
  Untyped(got~ : UInt32)
  /// A tensor encoding number that is not in the table.
  Unencoded(got~ : UInt32)
  /// More metadata pairs than `limits.entries` allows.
  Entries(limit~ : Int32, got~ : Int32)
  /// More tensors than `limits.tensors` allows.
  Tensors(limit~ : Int32, got~ : Int32)
  /// A key, name or string longer than `limits.text` allows.
  Text(limit~ : Int32, got~ : Int32)
  /// More entries in one array than `limits.items` allows.
  Items(limit~ : Int32, got~ : Int32)
  /// Arrays nested deeper than `limits.depth` allows.
  Nesting(limit~ : Int32, got~ : Int32)
  /// `general.alignment` is not a `uint32` holding a power of two.
  Alignment(got~ : UInt32)
  /// Two metadata pairs, or two tensors, go by the same name.
  Duplicate(name~ : String)
  /// No tensor goes by that name.
  Missing(name~ : String)
  /// A tensor's row of values is not a whole number of blocks.
  Blocks(name~ : String, block~ : Int32, got~ : UInt64)
  /// A tensor has more dimensions than `ggml` holds.
  Dims(limit~ : Int32, got~ : Int32)
  /// A tensor's element count does not fit 64 bits.
  Volume(name~ : String)
  /// Text that is not UTF-8, starting at `at`. Repairing it would write back
  /// something the file did not hold.
  Malformed(at~ : Int64)
  /// A value that contradicts the kind declared for it: an array that declares
  /// its entries are arrays and holds something else, or `general.alignment`
  /// stored as something other than `uint32`.
  Mismatch(at~ : Int64, want~ : ValueType, got~ : ValueType)
  /// A tensor's recorded offset is not where the tensor before it ends.
  Offset(name~ : String, want~ : UInt64, got~ : UInt64)
  /// The bytes of a tensor are not at hand, so the file cannot be written.
  Absent(name~ : String)
  /// Fewer bytes were given for a tensor than it takes.
  Short(name~ : String, want~ : Int64, got~ : Int64)
  /// The whole file does not fit one `Bytes`.
  Large(limit~ : Int32, got~ : Int64)
  /// A metadata key is empty.
  Empty
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Truncated(at~, want~, got~) =>
      logger.write_string("\{want} bytes wanted at \{at}, \{got} left")
    Magic(_) => logger.write_string("not a GGUF file")
    Version(got~) =>
      logger.write_string("GGUF version \{got} is not one this reads")
    ReadOnly(version~) =>
      logger.write_string("version \{version.code()} is read-only")
    Untyped(got~) => logger.write_string("no value type is numbered \{got}")
    Unencoded(got~) =>
      logger.write_string("no tensor encoding is numbered \{got}")
    Entries(limit~, got~) =>
      logger.write_string("\{got} metadata pairs past \{limit}")
    Tensors(limit~, got~) => logger.write_string("\{got} tensors past \{limit}")
    Text(limit~, got~) => logger.write_string("\{got} characters past \{limit}")
    Items(limit~, got~) =>
      logger.write_string("\{got} array entries past \{limit}")
    Nesting(limit~, got~) =>
      logger.write_string("arrays nested \{got} deep past \{limit}")
    Alignment(got~) =>
      logger.write_string("alignment \{got} is not a power of two")
    Duplicate(name~) => logger.write_string("\{name} appears twice")
    Missing(name~) => logger.write_string("no tensor named \{name}")
    Blocks(name~, block~, got~) =>
      logger.write_string(
        "\{name} holds \{got} values per row, not a multiple of \{block}",
      )
    Dims(limit~, got~) => logger.write_string("\{got} dimensions past \{limit}")
    Volume(name~) =>
      logger.write_string("\{name} holds more values than fit 64 bits")
    Malformed(at~) => logger.write_string("text at \{at} is not UTF-8")
    Mismatch(at~, want~, got~) =>
      logger.write_string(
        "\{got.name()} at \{at} where \{want.name()} was declared",
      )
    Offset(name~, want~, got~) =>
      logger.write_string("\{name} starts at \{got}, not at \{want}")
    Absent(name~) => logger.write_string("the bytes of \{name} are not here")
    Short(name~, want~, got~) =>
      logger.write_string("\{name} takes \{want} bytes, \{got} given")
    Large(limit~, got~) =>
      logger.write_string("a file of \{got} bytes past \{limit}")
    Empty => logger.write_string("a metadata key is empty")
  }
}

///|
pub extend Refused with Show::{output, to_string}
