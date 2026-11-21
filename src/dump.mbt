///|
/// The file described as JSON: the header, every metadata pair with its kind
/// and position, and every tensor with its shape and kind.
///
/// The shape is the one the format's own dump tool prints, down to the three
/// header fields appearing as pairs named `GGUF.version`, `GGUF.tensor_count`
/// and `GGUF.kv_count`. A dump of a file and another tool's dump of the same
/// file therefore compare field by field, which is how this library is checked
/// against the reference implementation.
pub impl ToJson for File with fn to_json(self) {
  let metadata : Map[String, Json] = Map([])
  let wide = self.header.version != V1
  metadata.set(
    "GGUF.version",
    Json::object({
      "index": Json(0),
      "type": Json("UINT32"),
      "offset": Json(4),
      "value": json_of_uint(self.header.version.code().to_uint64()),
    }),
  )
  metadata.set(
    "GGUF.tensor_count",
    Json::object({
      "index": Json(1),
      "type": Json(if wide { "UINT64" } else { "UINT32" }),
      "offset": Json(8),
      "value": json_of_uint(self.header.tensors.to_uint64()),
    }),
  )
  metadata.set(
    "GGUF.kv_count",
    Json::object({
      "index": Json(2),
      "type": Json(if wide { "UINT64" } else { "UINT32" }),
      "offset": Json(if wide { 16 } else { 12 }),
      "value": json_of_uint(self.header.entries.to_uint64()),
    }),
  )
  let mut index = 3
  for entry in self.meta.entries() {
    let described : Map[String, Json] = Map([])
    described.set("index", Json(index))
    described.set("type", Json(entry.value.value_type().name()))
    described.set("offset", json_of_int(entry.at))
    described.set("value", entry.value.to_json())
    match entry.value {
      // The reference dump reads the kinds out of the entries, so an empty
      // array shows none; ours prints the same, though the file does name one.
      Value::Array(kind, items) =>
        described.set(
          "array_types",
          Json::array(if items.length() > 0 { chain(kind, items) } else { [] }),
        )
      _ => ()
    }
    metadata.set(entry.key, Json::object(described))
    index = index + 1
  }
  let tensors : Map[String, Json] = Map([])
  let mut order = 0
  for tensor in self.tensors {
    tensors.set(
      tensor.name,
      Json::object({
        "index": Json(order),
        "shape": Json::array(tensor.dims.map(fn(dim) { json_of_uint(dim) })),
        "type": Json(tensor.kind.name()),
        "offset": json_of_int(tensor.at),
      }),
    )
    order = order + 1
  }
  Json::object({
    "endian": Json(if self.order == Little { "LITTLE" } else { "BIG" }),
    "alignment": json_of_uint(self.alignment.to_uint64()),
    "metadata": Json::object(metadata),
    "tensors": Json::object(tensors),
  })
}

///|
pub extend File with ToJson::{to_json}

///|
/// How many kinds deep an array goes, innermost last, the way a dump spells an
/// array's type as `[UINT32]` or `[ARRAY, STRING]`.
fn chain(kind : ValueType, items : Array[Value]) -> Array[Json] {
  let kinds = [Json(kind.name())]
  if kind == ValueType::Array && items.length() > 0 {
    match items[0] {
      Value::Array(inner, deeper) => kinds.append(chain(inner, deeper))
      _ => ()
    }
  }
  kinds
}

///|
/// A number written as a number, with its digits kept as written so that a
/// count past what a double holds exactly does not come back rounded.
fn json_of_uint(n : UInt64) -> Json {
  Json::number(n.to_double(), repr=n.to_string())
}

///|
fn json_of_int(n : Int64) -> Json {
  Json::number(n.to_double(), repr=n.to_string())
}
