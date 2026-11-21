// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "each kind keeps the number the file stores" {
  assert_eq(@moongguf.ValueType::UInt8.code(), 0U)
  assert_eq(@moongguf.ValueType::Int8.code(), 1U)
  assert_eq(@moongguf.ValueType::UInt16.code(), 2U)
  assert_eq(@moongguf.ValueType::Int16.code(), 3U)
  assert_eq(@moongguf.ValueType::UInt32.code(), 4U)
  assert_eq(@moongguf.ValueType::Int32.code(), 5U)
  assert_eq(@moongguf.ValueType::Float32.code(), 6U)
  assert_eq(@moongguf.ValueType::Bool.code(), 7U)
  assert_eq(@moongguf.ValueType::String.code(), 8U)
  assert_eq(@moongguf.ValueType::Array.code(), 9U)
  assert_eq(@moongguf.ValueType::UInt64.code(), 10U)
  assert_eq(@moongguf.ValueType::Int64.code(), 11U)
  assert_eq(@moongguf.ValueType::Float64.code(), 12U)
  for code in 0..<13 {
    assert_eq(
      @moongguf.ValueType::of(code.reinterpret_as_uint()).unwrap().code(),
      code.reinterpret_as_uint(),
    )
  }
  assert_eq(@moongguf.ValueType::of(13U), None)
  assert_eq(@moongguf.ValueType::of(4294967295U), None)
}

///|
test "a kind names itself the way a dump prints it" {
  assert_eq(@moongguf.ValueType::UInt8.name(), "UINT8")
  assert_eq(@moongguf.ValueType::Float64.name(), "FLOAT64")
  assert_eq(@moongguf.ValueType::Array.name(), "ARRAY")
  assert_eq(@moongguf.ValueType::String.name(), "STRING")
}

///|
test "a value says which kind it is" {
  assert_eq(@moongguf.Value::UInt8(1).value_type(), @moongguf.ValueType::UInt8)
  assert_eq(@moongguf.Value::Bool(true).value_type(), @moongguf.ValueType::Bool)
  assert_eq(
    @moongguf.Value::Array(@moongguf.ValueType::Int32, []).value_type(),
    @moongguf.ValueType::Array,
  )
}

///|
test "a number reads back as an unsigned, a signed and a float" {
  assert_eq(@moongguf.Value::UInt8(200).as_uint(), Some(200UL))
  assert_eq(
    @moongguf.Value::UInt32(4_294_967_295).as_uint(),
    Some(4_294_967_295UL),
  )
  assert_eq(
    @moongguf.Value::UInt64(18_446_744_073_709_551_615UL).as_uint(),
    Some(18_446_744_073_709_551_615UL),
  )
  assert_eq(@moongguf.Value::Int8(-5).as_uint(), None)
  assert_eq(@moongguf.Value::Int16(-5).as_int(), Some(-5L))
  assert_eq(
    @moongguf.Value::Int32(-2_147_483_648).as_int(),
    Some(-2_147_483_648L),
  )
  assert_eq(
    @moongguf.Value::Int64(-9_223_372_036_854_775_808L).as_int(),
    Some(-9_223_372_036_854_775_808L),
  )
  assert_eq(
    @moongguf.Value::UInt64(18_446_744_073_709_551_615UL).as_int(),
    None,
  )
  assert_eq(@moongguf.Value::Float32(0.5).as_float(), Some(0.5))
  assert_eq(@moongguf.Value::Float64(-2.5).as_float(), Some(-2.5))
  assert_eq(@moongguf.Value::String("x").as_float(), None)
}

///|
test "text, a flag and entries come out as themselves" {
  assert_eq(@moongguf.Value::String("hi").as_text(), Some("hi"))
  assert_eq(@moongguf.Value::Bool(false).as_bool(), Some(false))
  assert_eq(@moongguf.Value::UInt32(1).as_bool(), None)
  let items = [@moongguf.Value::UInt32(1), @moongguf.Value::UInt32(2)]
  assert_eq(
    @moongguf.Value::Array(@moongguf.ValueType::UInt32, items)
    .as_items()
    .unwrap()
    .length(),
    2,
  )
  assert_eq(@moongguf.Value::UInt32(1).as_items(), None)
}

///|
test "a value written as JSON keeps its digits" {
  let big = @moongguf.Value::UInt64(18_446_744_073_709_551_615UL)
  assert_eq(big.to_json().stringify(), "18446744073709551615")
  let small = @moongguf.Value::Int8(-8)
  assert_eq(small.to_json().stringify(), "-8")
  assert_eq(@moongguf.Value::Float32(0.5).to_json().stringify(), "0.5")
  assert_eq(@moongguf.Value::Bool(true).to_json().stringify(), "true")
  assert_eq(@moongguf.Value::String("a\"b").to_json().stringify(), "\"a\\\"b\"")
  let list = @moongguf.Value::Array(@moongguf.ValueType::String, [
    @moongguf.Value::String("a"),
    @moongguf.Value::String("b"),
  ])
  assert_eq(list.to_json().stringify(), "[\"a\",\"b\"]")
}
