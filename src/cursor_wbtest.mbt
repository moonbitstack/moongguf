// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "counts and lengths are read at the width the version gives them" {
  let narrow = Bytes::from_array([
    0x2A, 0x00, 0x00, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x2A, 0x00, 0x00, 0x00,
  ])
  let small = Cursor::new(narrow[:], Little, false)
  assert_eq(small.count(), 42UL)
  assert_eq(small.count(), 42UL)
  assert_eq(small.at, 8)
  let wide = Cursor::new(narrow[:], Little, true)
  assert_eq(wide.count(), 0x2A0000002AUL)
  assert_eq(wide.at, 8)
}

///|
test "a big-endian count comes out the same number" {
  let bytes = Bytes::from_array([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02])
  let little = Cursor::new(bytes[:], Little, true)
  assert_eq(little.count(), 0x0201000000000000UL)
  let big = Cursor::new(bytes[:], Big, true)
  assert_eq(big.count(), 258UL)
}

///|
test "a field the bytes run out on is refused at its position" {
  let bytes = Bytes::from_array([0x01, 0x02])
  let cursor = Cursor::new(bytes[:], Little, true)
  let refused = try {
    let _ = cursor.u64()
    None
  } catch {
    error => Some(error)
  }
  assert_eq(refused, Some(Truncated(at=0L, want=8, got=2)))
}

///|
test "a string longer than the ceiling is refused before it is read" {
  let bytes = Bytes::from_array([
    0xFF, 0xFF, 0xFF, 0x7F, 0, 0, 0, 0, 0x41, 0x42, 0x43,
  ])
  let cursor = Cursor::new(bytes[:], Little, true)
  let refused = try {
    let _ = cursor.text({ ..limits, text: 4, })
    None
  } catch {
    error => Some(error)
  }
  assert_eq(refused, Some(Text(limit=4, got=0x7FFF_FFFF)))
}
