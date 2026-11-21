///|
/// Ceilings on what a file may ask of a reader, so that a corrupt or hostile
/// length cannot ask for gigabytes before the bytes behind it turn up.
///
/// Each has a name and a published preset, so a caller reading files it did not
/// make can tighten one without guessing at the rest. Going past one is
/// `Refused`, carrying the ceiling and the number that went past it.
#derive(Eq, Debug)
pub(all) struct Limits {
  /// How many metadata pairs a file may hold. A large model carries a few
  /// hundred: the vocabulary goes in one array value, not one pair per token.
  entries : Int32
  /// How many tensors a file may index. A forty-billion-parameter model has
  /// some hundreds.
  tensors : Int32
  /// How long one key, tensor name or string value may be. The longest strings
  /// in real files are chat templates, a few kilobytes.
  text : Int32
  /// How many entries one array value may hold. A tokenizer's vocabulary for a
  /// million-token model is the largest array in the wild.
  items : Int32
  /// How deeply arrays may nest. Files seen so far nest one level; this leaves
  /// room for the format's allowance without letting a file recurse without
  /// end.
  depth : Int32
}

///|
/// The preset a reader starts from: roomy enough for every file published so
/// far, tight enough that a corrupt count is refused instead of allocated.
pub let limits : Limits = {
  entries: 65_536,
  tensors: 65_536,
  text: 1_048_576,
  items: 16_777_216,
  depth: 8,
}
