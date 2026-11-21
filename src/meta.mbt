///|
/// One metadata pair as it sits in the file: its key, its value, and where the
/// pair starts. The position is what a dump of a file shows beside a pair, and
/// what tells two pairs with the same key apart when reading a file that has
/// them.
#derive(Eq, Debug)
pub(all) struct Entry {
  key : String
  value : Value
  /// Where the pair starts in the file, or -1 for a pair made here rather than
  /// read.
  at : Int64
}

///|
/// The metadata table: pairs in the order the file holds them, with a lookup
/// by key beside it.
///
/// Order is kept because writing the table back in another order would change
/// the file, and because the order often says something — a vocabulary and its
/// merges are easier to read in the order they were written.
pub struct Meta {
  priv entries : Array[Entry]
  priv index : Map[String, Int32]
}

///|
fn Meta::new() -> Meta {
  { entries: [], index: Map([]), }
}

///|
/// How many pairs the table holds.
pub fn Meta::count(self : Meta) -> Int32 {
  self.entries.length()
}

///|
/// The pairs, in file order.
pub fn Meta::entries(self : Meta) -> ArrayView[Entry] {
  self.entries[:]
}

///|
/// The value under a key.
pub fn Meta::get(self : Meta, key : StringView) -> Value? {
  match self.index.get(key.to_owned()) {
    Some(i) => Some(self.entries[i].value)
    None => None
  }
}

///|
/// The whole pair under a key, with the position it was read from.
pub fn Meta::entry(self : Meta, key : StringView) -> Entry? {
  match self.index.get(key.to_owned()) {
    Some(i) => Some(self.entries[i])
    None => None
  }
}

///|
/// Whether the table has that key.
pub fn Meta::contains(self : Meta, key : StringView) -> Bool {
  self.index.contains(key.to_owned())
}

///|
/// The text under a key, or `None` if it is absent or holds something else.
pub fn Meta::text(self : Meta, key : StringView) -> String? {
  match self.get(key) {
    Some(value) => value.as_text()
    None => None
  }
}

///|
/// The number under a key when it is stored as an unsigned kind; `None`
/// otherwise, a negative signed number included.
pub fn Meta::uint(self : Meta, key : StringView) -> UInt64? {
  match self.get(key) {
    Some(value) => value.as_uint()
    None => None
  }
}

///|
/// The number under a key when it is stored as a signed kind and fits 64 bits.
pub fn Meta::int(self : Meta, key : StringView) -> Int64? {
  match self.get(key) {
    Some(value) => value.as_int()
    None => None
  }
}

///|
/// The number under a key when it is stored as `float32` or `float64`.
pub fn Meta::float(self : Meta, key : StringView) -> Double? {
  match self.get(key) {
    Some(value) => value.as_float()
    None => None
  }
}

///|
/// The flag under a key when it is a `bool`.
pub fn Meta::flag(self : Meta, key : StringView) -> Bool? {
  match self.get(key) {
    Some(value) => value.as_bool()
    None => None
  }
}

///|
/// The entries under a key when it is an array.
pub fn Meta::items(self : Meta, key : StringView) -> Array[Value]? {
  match self.get(key) {
    Some(value) => value.as_items()
    None => None
  }
}

///|
/// Put a value under a key, replacing one already there. A pair made here has
/// no position in a file yet, so its `at` is -1.
fn Meta::set(self : Meta, key : String, value : Value) -> Unit {
  match self.index.get(key) {
    Some(i) => self.entries[i] = { key, value, at: -1L, }
    None => {
      self.index.set(key, self.entries.length())
      self.entries.push({ key, value, at: -1L, })
    }
  }
}

///|
/// Append a pair that came out of a file, keeping the position it was read
/// from. A file's own order is the order of its table.
fn Meta::push(self : Meta, entry : Entry) -> Unit {
  if !self.index.contains(entry.key) {
    self.index.set(entry.key, self.entries.length())
  }
  self.entries.push(entry)
}

///|
/// Drop a key if it is there.
fn Meta::remove(self : Meta, key : StringView) -> Unit {
  match self.index.get(key.to_owned()) {
    Some(i) => {
      let _ = self.entries.remove(i)
      self.index.remove(key.to_owned())
      for j in i..<self.entries.length() {
        self.index.set(self.entries[j].key, j)
      }
    }
    None => ()
  }
}
