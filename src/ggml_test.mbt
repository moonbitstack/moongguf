// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "every encoding keeps the number the format gave it" {
  assert_eq(@moongguf.F32.code(), 0U)
  assert_eq(@moongguf.F16.code(), 1U)
  assert_eq(@moongguf.Q4_0.code(), 2U)
  assert_eq(@moongguf.Q4_1.code(), 3U)
  assert_eq(@moongguf.Q5_0.code(), 6U)
  assert_eq(@moongguf.Q5_1.code(), 7U)
  assert_eq(@moongguf.Q8_0.code(), 8U)
  assert_eq(@moongguf.Q8_1.code(), 9U)
  assert_eq(@moongguf.Q2_K.code(), 10U)
  assert_eq(@moongguf.Q8_K.code(), 15U)
  assert_eq(@moongguf.IQ4_XS.code(), 23U)
  assert_eq(@moongguf.I8.code(), 24U)
  assert_eq(@moongguf.F64.code(), 28U)
  assert_eq(@moongguf.IQ1_M.code(), 29U)
  assert_eq(@moongguf.BF16.code(), 30U)
  assert_eq(@moongguf.TQ1_0.code(), 34U)
  assert_eq(@moongguf.TQ2_0.code(), 35U)
  assert_eq(@moongguf.MXFP4.code(), 39U)
  assert_eq(@moongguf.NVFP4.code(), 40U)
  assert_eq(@moongguf.Q1_0.code(), 41U)
  assert_eq(@moongguf.Q2_0.code(), 42U)
  assert_eq(@moongguf.F8_E4M3.code(), 43U)
}

///|
test "a number names its encoding back, and the withdrawn ones name nothing" {
  assert_eq(@moongguf.GgmlType::of(14U), Some(@moongguf.Q6_K))
  assert_eq(@moongguf.GgmlType::of(43U), Some(@moongguf.F8_E4M3))
  // 4 and 5 were withdrawn, as were the repacked variants 31 to 33 and 36 to 38.
  for code in [4U, 5U, 31U, 32U, 33U, 36U, 37U, 38U, 44U, 99U] {
    assert_eq(@moongguf.GgmlType::of(code), None)
  }
}

///|
test "every encoding has a block size and a size in bytes" {
  assert_eq(@moongguf.F32.block_size(), 1)
  assert_eq(@moongguf.F32.bytes_per_block(), 4)
  assert_eq(@moongguf.F16.bytes_per_block(), 2)
  assert_eq(@moongguf.Q4_0.block_size(), 32)
  assert_eq(@moongguf.Q4_0.bytes_per_block(), 18)
  assert_eq(@moongguf.Q8_K.block_size(), 256)
  assert_eq(@moongguf.Q8_K.bytes_per_block(), 292)
  assert_eq(@moongguf.Q6_K.bytes_per_block(), 210)
  assert_eq(@moongguf.MXFP4.bytes_per_block(), 17)
  assert_eq(@moongguf.NVFP4.block_size(), 64)
  assert_eq(@moongguf.NVFP4.bytes_per_block(), 36)
  assert_eq(@moongguf.Q1_0.block_size(), 128)
  assert_eq(@moongguf.Q1_0.bytes_per_block(), 18)
  assert_eq(@moongguf.Q2_0.block_size(), 64)
  assert_eq(@moongguf.F8_E4M3.bytes_per_block(), 1)
  for kind in @moongguf.GgmlType::all() {
    assert_eq(kind.bytes_per_block() > 0, true)
    assert_eq(kind.block_size() > 0, true)
  }
}

///|
test "the name is the one a dump prints, and the one on the variant" {
  assert_eq(@moongguf.Q4_0.name(), "Q4_0")
  assert_eq(@moongguf.Q4_K.name(), "Q4_K")
  assert_eq(@moongguf.Q8_K.name(), "Q8_K")
  assert_eq(@moongguf.F8_E4M3.name(), "F8_E4M3")
  assert_eq(@moongguf.IQ1_S.name(), "IQ1_S")
}

///|
test "an encoding with one value per block is not a quantised one" {
  assert_eq(@moongguf.F32.is_quantized(), false)
  assert_eq(@moongguf.BF16.is_quantized(), false)
  assert_eq(@moongguf.F8_E4M3.is_quantized(), false)
  assert_eq(@moongguf.Q4_0.is_quantized(), true)
  assert_eq(@moongguf.MXFP4.is_quantized(), true)
  assert_eq(@moongguf.Q1_0.is_quantized(), true)
}

///|
test "the table holds every encoding once" {
  let all = @moongguf.GgmlType::all()
  assert_eq(all.length(), 36)
  let seen : Map[UInt32, Bool] = Map([])
  for kind in all {
    assert_eq(seen.contains(kind.code()), false)
    seen.set(kind.code(), true)
    assert_eq(@moongguf.GgmlType::of(kind.code()), Some(kind))
  }
}
