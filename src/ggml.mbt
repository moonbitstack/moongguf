///|
/// The encodings a tensor's blocks can be stored in, numbered as `ggml`
/// numbers them. The number is what a file stores, so an encoding keeps its
/// number; a file that names a number outside this table is refused rather
/// than guessed at.
///
/// Reading a tensor's bytes is all this library does. Turning a block of
/// `q6_k` into floats is arithmetic, and lives elsewhere.
#derive(Eq, Debug)
pub(all) enum GgmlType {
  F32
  F16
  Q4_0
  Q4_1
  Q5_0
  Q5_1
  Q8_0
  Q8_1
  Q2_K
  Q3_K
  Q4_K
  Q5_K
  Q6_K
  Q8_K
  IQ2_XXS
  IQ2_XS
  IQ3_XXS
  IQ1_S
  IQ4_NL
  IQ3_S
  IQ2_S
  IQ4_XS
  I8
  I16
  I32
  I64
  F64
  IQ1_M
  BF16
  TQ1_0
  TQ2_0
  MXFP4
  NVFP4
  Q1_0
  Q2_0
  F8_E4M3
}

///|
/// One row of the table: what the file stores, what `ggml` calls it, and how
/// many values a block holds against how many bytes it takes.
priv struct Row {
  kind : GgmlType
  code : UInt32
  name : String
  block : Int32
  bytes : Int32
}

///|
/// Every encoding the format defines, in the order `ggml` added them. The
/// numbers are sparse: 4 and 5 were withdrawn, as were the repacked variants
/// 31 to 33 and 36 to 38, so nothing may be read off a position here.
let rows : Array[Row] = [
  { kind: F32, code: 0, name: "F32", block: 1, bytes: 4, },
  { kind: F16, code: 1, name: "F16", block: 1, bytes: 2, },
  { kind: Q4_0, code: 2, name: "Q4_0", block: 32, bytes: 18, },
  { kind: Q4_1, code: 3, name: "Q4_1", block: 32, bytes: 20, },
  { kind: Q5_0, code: 6, name: "Q5_0", block: 32, bytes: 22, },
  { kind: Q5_1, code: 7, name: "Q5_1", block: 32, bytes: 24, },
  { kind: Q8_0, code: 8, name: "Q8_0", block: 32, bytes: 34, },
  { kind: Q8_1, code: 9, name: "Q8_1", block: 32, bytes: 40, },
  { kind: Q2_K, code: 10, name: "Q2_K", block: 256, bytes: 84, },
  { kind: Q3_K, code: 11, name: "Q3_K", block: 256, bytes: 110, },
  { kind: Q4_K, code: 12, name: "Q4_K", block: 256, bytes: 144, },
  { kind: Q5_K, code: 13, name: "Q5_K", block: 256, bytes: 176, },
  { kind: Q6_K, code: 14, name: "Q6_K", block: 256, bytes: 210, },
  { kind: Q8_K, code: 15, name: "Q8_K", block: 256, bytes: 292, },
  { kind: IQ2_XXS, code: 16, name: "IQ2_XXS", block: 256, bytes: 66, },
  { kind: IQ2_XS, code: 17, name: "IQ2_XS", block: 256, bytes: 74, },
  { kind: IQ3_XXS, code: 18, name: "IQ3_XXS", block: 256, bytes: 98, },
  { kind: IQ1_S, code: 19, name: "IQ1_S", block: 256, bytes: 50, },
  { kind: IQ4_NL, code: 20, name: "IQ4_NL", block: 32, bytes: 18, },
  { kind: IQ3_S, code: 21, name: "IQ3_S", block: 256, bytes: 110, },
  { kind: IQ2_S, code: 22, name: "IQ2_S", block: 256, bytes: 82, },
  { kind: IQ4_XS, code: 23, name: "IQ4_XS", block: 256, bytes: 136, },
  { kind: I8, code: 24, name: "I8", block: 1, bytes: 1, },
  { kind: I16, code: 25, name: "I16", block: 1, bytes: 2, },
  { kind: I32, code: 26, name: "I32", block: 1, bytes: 4, },
  { kind: I64, code: 27, name: "I64", block: 1, bytes: 8, },
  { kind: F64, code: 28, name: "F64", block: 1, bytes: 8, },
  { kind: IQ1_M, code: 29, name: "IQ1_M", block: 256, bytes: 56, },
  { kind: BF16, code: 30, name: "BF16", block: 1, bytes: 2, },
  { kind: TQ1_0, code: 34, name: "TQ1_0", block: 256, bytes: 54, },
  { kind: TQ2_0, code: 35, name: "TQ2_0", block: 256, bytes: 66, },
  { kind: MXFP4, code: 39, name: "MXFP4", block: 32, bytes: 17, },
  { kind: NVFP4, code: 40, name: "NVFP4", block: 64, bytes: 36, },
  { kind: Q1_0, code: 41, name: "Q1_0", block: 128, bytes: 18, },
  { kind: Q2_0, code: 42, name: "Q2_0", block: 64, bytes: 18, },
  { kind: F8_E4M3, code: 43, name: "F8_E4M3", block: 1, bytes: 1, },
]

///|
fn GgmlType::row_of(self : GgmlType) -> Row {
  for row in rows {
    if row.kind == self {
      return row
    }
  }
  abort("every GgmlType has a row in the table")
}

///|
/// The number the file stores for this encoding.
pub fn GgmlType::code(self : GgmlType) -> UInt32 {
  self.row_of().code
}

///|
/// The name this encoding goes by in a dump, such as `Q4_K` — the spelling the
/// format's own tooling prints, and the one on the variant.
pub fn GgmlType::name(self : GgmlType) -> String {
  self.row_of().name
}

///|
/// How many values one block holds. Plain float and integer encodings hold
/// one value per block; the quantised ones hold a whole row chunk.
pub fn GgmlType::block_size(self : GgmlType) -> Int32 {
  self.row_of().block
}

///|
/// How many bytes one block takes.
pub fn GgmlType::bytes_per_block(self : GgmlType) -> Int32 {
  self.row_of().bytes
}

///|
/// Whether the encoding packs several values into a block, which is what
/// makes a block stand for scaled integers rather than the values themselves.
pub fn GgmlType::is_quantized(self : GgmlType) -> Bool {
  self.row_of().block > 1
}

///|
/// The encoding a file's number names, or `None` for a number this version of
/// the format does not define.
pub fn GgmlType::of(code : UInt32) -> GgmlType? {
  for row in rows {
    if row.code == code {
      return Some(row.kind)
    }
  }
  None
}

///|
/// Every encoding the table holds, in `ggml`'s order.
pub fn GgmlType::all() -> Array[GgmlType] {
  rows.map(fn(row) { row.kind })
}
