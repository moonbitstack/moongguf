///|
/// The thirteen kinds of value a metadata entry can hold, numbered as the file
/// numbers them. The numbers are the format's, and one of them, `Array`, says
/// the value is a list whose own entries share a kind.
#derive(Eq, Debug)
pub(all) enum ValueType {
  UInt8
  Int8
  UInt16
  Int16
  UInt32
  Int32
  Float32
  Bool
  String
  Array
  UInt64
  Int64
  Float64
}

///|
/// The number the file stores for this kind of value.
pub fn ValueType::code(self : ValueType) -> UInt32 {
  match self {
    UInt8 => 0
    Int8 => 1
    UInt16 => 2
    Int16 => 3
    UInt32 => 4
    Int32 => 5
    Float32 => 6
    Bool => 7
    String => 8
    Array => 9
    UInt64 => 10
    Int64 => 11
    Float64 => 12
  }
}

///|
/// The kind a file's number names, or `None` past the thirteen.
pub fn ValueType::of(code : UInt32) -> ValueType? {
  match code {
    0 => Some(UInt8)
    1 => Some(Int8)
    2 => Some(UInt16)
    3 => Some(Int16)
    4 => Some(UInt32)
    5 => Some(Int32)
    6 => Some(Float32)
    7 => Some(Bool)
    8 => Some(String)
    9 => Some(Array)
    10 => Some(UInt64)
    11 => Some(Int64)
    12 => Some(Float64)
    _ => None
  }
}

///|
/// The name the format's own tooling prints for this kind, in the capital
/// letters a metadata dump carries. It is the name a dump compared against
/// another tool's has to agree on.
pub fn ValueType::name(self : ValueType) -> String {
  match self {
    UInt8 => "UINT8"
    Int8 => "INT8"
    UInt16 => "UINT16"
    Int16 => "INT16"
    UInt32 => "UINT32"
    Int32 => "INT32"
    Float32 => "FLOAT32"
    Bool => "BOOL"
    String => "STRING"
    Array => "ARRAY"
    UInt64 => "UINT64"
    Int64 => "INT64"
    Float64 => "FLOAT64"
  }
}

///|
/// One metadata value, as the file holds it.
///
/// The integer kinds keep their width: a count stored as `uint32` reads back
/// as `UInt32` and is written as `uint32` again, so a file survives a round
/// trip unchanged even where two widths could hold the same number. `Array`
/// carries the kind its entries share, which an empty list would otherwise
/// lose, and its entries may themselves be `Array`.
#derive(Eq, Debug)
pub(all) enum Value {
  UInt8(UInt32)
  Int8(Int32)
  UInt16(UInt32)
  Int16(Int32)
  UInt32(UInt32)
  Int32(Int32)
  Float32(Float)
  Bool(Bool)
  String(String)
  Array(ValueType, Array[Value])
  UInt64(UInt64)
  Int64(Int64)
  Float64(Double)
}

///|
/// Which of the thirteen kinds this value is.
pub fn Value::value_type(self : Value) -> ValueType {
  match self {
    UInt8(_) => UInt8
    Int8(_) => Int8
    UInt16(_) => UInt16
    Int16(_) => Int16
    UInt32(_) => UInt32
    Int32(_) => Int32
    Float32(_) => Float32
    Bool(_) => Bool
    String(_) => String
    Array(_) => Array
    UInt64(_) => UInt64
    Int64(_) => Int64
    Float64(_) => Float64
  }
}

///|
/// The number as an unsigned 64-bit integer, for the kinds that are numbers
/// without a fraction; `None` for the rest.
pub fn Value::as_uint(self : Value) -> UInt64? {
  match self {
    UInt8(n) => Some(n.to_uint64())
    UInt16(n) => Some(n.to_uint64())
    UInt32(n) => Some(n.to_uint64())
    UInt64(n) => Some(n)
    Int8(n) => if n < 0 { None } else { Some(n.to_uint64()) }
    Int16(n) => if n < 0 { None } else { Some(n.to_uint64()) }
    Int32(n) => if n < 0 { None } else { Some(n.to_uint64()) }
    Int64(n) => if n < 0L { None } else { Some(n.reinterpret_as_uint64()) }
    _ => None
  }
}

///|
/// The number as a signed 64-bit integer; `None` for the kinds that are not
/// numbers without a fraction, and for an unsigned one too large to hold.
pub fn Value::as_int(self : Value) -> Int64? {
  match self {
    Int8(n) => Some(n.to_int64())
    Int16(n) => Some(n.to_int64())
    Int32(n) => Some(n.to_int64())
    Int64(n) => Some(n)
    UInt8(n) => Some(n.to_uint64().reinterpret_as_int64())
    UInt16(n) => Some(n.to_uint64().reinterpret_as_int64())
    UInt32(n) => Some(n.to_uint64().reinterpret_as_int64())
    UInt64(n) =>
      if n > 0x7FFF_FFFF_FFFF_FFFFUL {
        None
      } else {
        Some(n.reinterpret_as_int64())
      }
    _ => None
  }
}

///|
/// The number as a double, widening whichever width it was stored in. A
/// `float64` comes back bit for bit.
pub fn Value::as_float(self : Value) -> Double? {
  match self {
    Float32(x) => Some(x.to_double())
    Float64(x) => Some(x)
    _ => None
  }
}

///|
/// The text of a `string` value.
pub fn Value::as_text(self : Value) -> String? {
  match self {
    String(text) => Some(text)
    _ => None
  }
}

///|
/// The truth of a `bool` value.
pub fn Value::as_bool(self : Value) -> Bool? {
  match self {
    Bool(flag) => Some(flag)
    _ => None
  }
}

///|
/// The entries of an `array` value, whatever kind they share.
pub fn Value::as_items(self : Value) -> Array[Value]? {
  match self {
    Array(_, items) => Some(items)
    _ => None
  }
}

///|
/// A `string` value.
pub fn Value::text(text : String) -> Value {
  String(text)
}

///|
/// An `array` value whose entries are `kind`; every entry must be of that
/// kind, which the writer checks.
pub fn Value::items(kind : ValueType, items : Array[Value]) -> Value {
  Array(kind, items)
}

///|
/// The value as JSON: numbers as numbers, text as text, a list as a list. The
/// kind is not in it — a dump of a file puts the kind beside the value, the
/// way the format's own dump does.
pub impl ToJson for Value with fn to_json(self) {
  match self {
    UInt8(n) | UInt16(n) | UInt32(n) =>
      Json::number(n.to_uint64().to_double(), repr=n.to_uint64().to_string())
    Int8(n) | Int16(n) | Int32(n) =>
      Json::number(n.to_int64().to_double(), repr=n.to_int64().to_string())
    UInt64(n) => Json::number(n.to_double(), repr=n.to_string())
    Int64(n) => Json::number(n.to_double(), repr=n.to_string())
    Float32(x) => Json::number(x.to_double())
    Float64(x) => Json::number(x)
    Bool(flag) => Json(flag)
    String(text) => Json(text)
    Array(_, items) => Json::array(items.map(fn(item) { item.to_json() }))
  }
}

///|
pub extend Value with ToJson::{to_json}
