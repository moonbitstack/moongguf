"""Build the GGUF files the tests read, and the ones the interop check compares.

Most files here are written by the reference implementation: the `gguf` package
that llama.cpp publishes as `gguf-py`. That package cannot write everything the
format allows, so the rest is written by the small packer below, which follows
the specification in `docs/gguf.md` of ggml: version 1 and 2 headers, empty
arrays, arrays of arrays, and big-endian files. A file written by the packer is
still read back by `gguf-py` wherever that package supports the shape, so the
bytes are checked by a second implementation rather than only by us.

`src/vectors_test.mbt` is rewritten from the files, as hex, and is committed:
the tests read those bytes without touching the filesystem, which is what lets
them run on all four targets. `--out DIR` also writes the files themselves for
`scripts/check_interop.py`, and `--json DIR` the reference dump of each.

    python scripts/make_vectors.py
    python scripts/make_vectors.py --out build/vectors --json build/vectors/json

The version of `gguf` is pinned in `scripts/requirements.txt`.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

import numpy as np

import gguf
from gguf import GGUFValueType, GGMLQuantizationType, GGUFWriter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gguf_reference import reference_dump

ROOT = Path(__file__).resolve().parent.parent
VECTORS = ROOT / "src" / "vectors_test.mbt"

MAGIC = b"GGUF"

# The kinds of value, in the order the format numbers them.
VALUE_CODES = {
    "UINT8": 0, "INT8": 1, "UINT16": 2, "INT16": 3, "UINT32": 4, "INT32": 5,
    "FLOAT32": 6, "BOOL": 7, "STRING": 8, "ARRAY": 9, "UINT64": 10,
    "INT64": 11, "FLOAT64": 12,
}

# The numbers `ggml.h` gives the encodings, including the two that `gguf-py`
# has not caught up with.
TENSOR_CODES = {
    "F32": 0, "F16": 1, "Q4_0": 2, "Q4_1": 3, "Q5_0": 6, "Q5_1": 7,
    "Q8_0": 8, "Q8_1": 9, "Q2_K": 10, "Q3_K": 11, "Q4_K": 12, "Q5_K": 13,
    "Q6_K": 14, "Q8_K": 15, "IQ2_XXS": 16, "IQ2_XS": 17, "IQ3_XXS": 18,
    "IQ1_S": 19, "IQ4_NL": 20, "IQ3_S": 21, "IQ2_S": 22, "IQ4_XS": 23,
    "I8": 24, "I16": 25, "I32": 26, "I64": 27, "F64": 28, "IQ1_M": 29,
    "BF16": 30, "TQ1_0": 34, "TQ2_0": 35, "MXFP4": 39, "NVFP4": 40,
    "Q1_0": 41, "Q2_0": 42, "F8_E4M3": 43,
}

# Block size and bytes per block, from `ggml.h` and `ggml-common.h`.
TENSOR_SIZES = {
    "F32": (1, 4), "F16": (1, 2), "Q4_0": (32, 18), "Q4_1": (32, 20),
    "Q5_0": (32, 22), "Q5_1": (32, 24), "Q8_0": (32, 34), "Q8_1": (32, 40),
    "Q2_K": (256, 84), "Q3_K": (256, 110), "Q4_K": (256, 144),
    "Q5_K": (256, 176), "Q6_K": (256, 210), "Q8_K": (256, 292),
    "IQ2_XXS": (256, 66), "IQ2_XS": (256, 74), "IQ3_XXS": (256, 98),
    "IQ1_S": (256, 50), "IQ4_NL": (32, 18), "IQ3_S": (256, 110),
    "IQ2_S": (256, 82), "IQ4_XS": (256, 136), "I8": (1, 1), "I16": (1, 2),
    "I32": (1, 4), "I64": (1, 8), "F64": (1, 8), "IQ1_M": (256, 56),
    "BF16": (1, 2), "TQ1_0": (256, 54), "TQ2_0": (256, 66),
    "MXFP4": (32, 17), "NVFP4": (64, 36), "Q1_0": (128, 18), "Q2_0": (64, 18),
    "F8_E4M3": (1, 1),
}


class Value:
    """A metadata value with its kind spelt out, which JSON cannot do."""

    def __init__(self, kind: str, value):
        self.kind = kind
        self.value = value


def scalar(kind: str, value) -> Value:
    return Value(kind, value)


def array(elem: str, items: list) -> Value:
    return Value("ARRAY", (elem, items))


def pack_value(value: Value, version: int, order: str) -> bytes:
    """One value, its bytes. An array repeats the kind and the length of its
    entries, so an array of arrays repeats them once per entry."""
    out = bytearray()
    width = "I" if version == 1 else "Q"
    if value.kind == "ARRAY":
        elem, items = value.value
        out += struct.pack(order + "I", VALUE_CODES[elem])
        out += struct.pack(order + width, len(items))
        for item in items:
            out += pack_value(item, version, order)
        return bytes(out)
    code = VALUE_CODES[value.kind]
    v = value.value
    if value.kind == "STRING":
        raw = v.encode("utf-8")
        return struct.pack(order + width, len(raw)) + raw
    if value.kind == "BOOL":
        return struct.pack(order + "B", 1 if v else 0)
    return struct.pack(order + {
        "UINT8": "B", "INT8": "b", "UINT16": "H", "INT16": "h",
        "UINT32": "I", "INT32": "i", "FLOAT32": "f", "UINT64": "Q",
        "INT64": "q", "FLOAT64": "d",
    }[value.kind], v)


def pack(name: str, version: int, entries: list, tensors: list,
         alignment: int = 32, order: str = "<") -> bytes:
    """A whole file, byte for byte, the way the specification lays it out."""
    width = "I" if version == 1 else "Q"
    out = bytearray(MAGIC)
    out += struct.pack(order + "I", version)
    out += struct.pack(order + width, len(tensors))
    out += struct.pack(order + width, len(entries))
    for key, value in entries:
        raw = key.encode("utf-8")
        out += struct.pack(order + width, len(raw)) + raw
        out += struct.pack(order + "I", VALUE_CODES[value.kind])
        out += pack_value(value, version, order)
    offset = 0
    for tensor in tensors:
        raw = tensor["name"].encode("utf-8")
        out += struct.pack(order + width, len(raw)) + raw
        out += struct.pack(order + "I", len(tensor["dims"]))
        for dim in tensor["dims"]:
            out += struct.pack(order + "Q", dim)
        out += struct.pack(order + "I", tensor["code"])
        out += struct.pack(order + width, offset)
        block, size = TENSOR_SIZES[tensor["kind"]]
        n = 1
        for dim in tensor["dims"]:
            n *= dim
        length = n // block * size
        offset += (length + alignment - 1) // alignment * alignment
    while len(out) % alignment:
        out += b"\x00"
    for tensor in tensors:
        block, size = TENSOR_SIZES[tensor["kind"]]
        n = 1
        for dim in tensor["dims"]:
            n *= dim
        length = n // block * size
        out += tensor["data"][:length]
        while len(out) % alignment:
            out += b"\x00"
    return bytes(out)


def tensor(name: str, kind: str, dims: list, seed: int) -> dict:
    """A tensor whose bytes are a pattern rather than zeroes, so that a reader
    that fetched the wrong range would show it."""
    block, size = TENSOR_SIZES[kind]
    n = 1
    for dim in dims:
        n *= dim
    length = n // block * size
    data = bytes((seed + i * 7) % 251 + 1 for i in range(length))
    # Codes `gguf-py` has not learnt yet are taken from the format's own table.
    kind_code = int(getattr(GGMLQuantizationType, kind)) if hasattr(
        GGMLQuantizationType, kind) else TENSOR_CODES[kind]
    return {"name": name, "kind": kind, "code": kind_code, "dims": dims,
            "data": data, "length": length}


def write_reference(path: Path, arch: str | None, entries, tensors,
                    alignment: int = 32) -> None:
    """Write a file with `gguf-py`, which is the reference implementation."""
    writer = GGUFWriter(str(path), arch or "", use_temp_file=False)
    if alignment != 32:
        writer.add_custom_alignment(alignment)
    for key, value in entries:
        if key == "general.architecture":
            continue
        if value.kind == "ARRAY":
            elem, items = value.value
            # The kind is spelt out: read off the values, a list of Python
            # ints would be `int32` and lose the 64-bit ones.
            writer.add_key_value(
                key, [item.value for item in items], GGUFValueType.ARRAY,
                sub_type=GGUFValueType[elem])
        else:
            getattr(writer, "add_" + value.kind.lower())(key, value.value)
    for t in tensors:
        kind = getattr(GGMLQuantizationType, t["kind"])
        block, size = TENSOR_SIZES[t["kind"]]
        # `gguf-py` takes the bytes shaped the way numpy would hold them, and
        # reverses that shape into `ggml`'s when it writes, so the file ends up
        # with the dimensions asked for.
        row = t["dims"][0] // block * size
        shape = (*reversed(t["dims"][1:]), row)
        data = np.frombuffer(t["data"], dtype=np.uint8).reshape(shape)
        writer.add_tensor(t["name"], data, raw_dtype=kind)
    writer.write_header_to_file()
    writer.write_kv_data_to_file()
    writer.write_tensors_to_file()
    writer.close()


def every_type_entries() -> list:
    return [
        ("general.architecture", scalar("STRING", "llama")),
        ("general.name", scalar("STRING", "A file with one of everything")),
        ("general.alignment_note", scalar("STRING", "")),
        ("test.uint8", scalar("UINT8", 255)),
        ("test.int8", scalar("INT8", -128)),
        ("test.uint16", scalar("UINT16", 65535)),
        ("test.int16", scalar("INT16", -32768)),
        ("test.uint32", scalar("UINT32", 4294967295)),
        ("test.int32", scalar("INT32", -2147483648)),
        ("test.float32", scalar("FLOAT32", 0.1015625)),
        ("test.bool_true", scalar("BOOL", True)),
        ("test.bool_false", scalar("BOOL", False)),
        ("test.uint64", scalar("UINT64", 18446744073709551615)),
        ("test.int64", scalar("INT64", -9223372036854775808)),
        ("test.float64", scalar("FLOAT64", -2.2250738585072014e-308)),
        ("test.string", scalar("STRING", "a string with an \u00e9 and a \U0001f642")),
        ("test.array.uint8", array("UINT8", [scalar("UINT8", 0), scalar("UINT8", 255)])),
        ("test.array.int8", array("INT8", [scalar("INT8", -1), scalar("INT8", 1)])),
        ("test.array.uint16", array("UINT16", [scalar("UINT16", 0), scalar("UINT16", 65535)])),
        ("test.array.int16", array("INT16", [scalar("INT16", -2), scalar("INT16", 2)])),
        ("test.array.uint32", array("UINT32", [scalar("UINT32", 1), scalar("UINT32", 2), scalar("UINT32", 3)])),
        ("test.array.int32", array("INT32", [scalar("INT32", -3), scalar("INT32", -2)])),
        ("test.array.float32", array("FLOAT32", [scalar("FLOAT32", 0.5), scalar("FLOAT32", -0.25)])),
        ("test.array.bool", array("BOOL", [scalar("BOOL", True), scalar("BOOL", False)])),
        ("test.array.string", array("STRING", [scalar("STRING", "a"), scalar("STRING", "bc"), scalar("STRING", "\u4e2d\u6587")])),
        ("test.array.uint64", array("UINT64", [scalar("UINT64", 1), scalar("UINT64", 18446744073709551615)])),
        ("test.array.int64", array("INT64", [scalar("INT64", -9223372036854775808), scalar("INT64", 7)])),
        ("test.array.float64", array("FLOAT64", [scalar("FLOAT64", 1.5), scalar("FLOAT64", -1e300)])),
        ("test.array.single", array("INT32", [scalar("INT32", 42)])),
        ("tokenizer.ggml.tokens", array("STRING", [scalar("STRING", f"tok{i}") for i in range(64)])),
        ("geometry.dims", scalar("INT16", 2)),
    ]


def every_type_tensors() -> list:
    return [
        tensor("plain.f32", "F32", [8, 2], 1),
        tensor("plain.f16", "F16", [4, 3], 2),
    ]


def every_tensor_tensors() -> list:
    """One tensor per encoding `gguf-py` knows. The two encodings newer than
    that package go in a file the packer writes."""
    out = []
    for i, (name, (block, size)) in enumerate(TENSOR_SIZES.items()):
        if not hasattr(GGMLQuantizationType, name):
            continue
        out.append(tensor(f"t.{name}", name, [block * 2, 3], i + 1))
    return out


def build(out: Path, jsondir: Path | None) -> dict[str, bytes]:
    """Every file, name to bytes, and the reference dump of each where
    `gguf-py` can read it."""
    files: dict[str, bytes] = {}

    def reference(name: str, arch, entries, tensors, alignment: int = 32):
        path = out / f"{name}.gguf"
        write_reference(path, arch, entries, tensors, alignment)
        files[name] = path.read_bytes()
        if jsondir is not None:
            (jsondir / f"{name}.json").write_text(
                json.dumps(reference_dump(path), indent=1, sort_keys=True) + "\n",
                encoding="utf-8", newline="\n")

    out.mkdir(parents=True, exist_ok=True)
    if jsondir is not None:
        jsondir.mkdir(parents=True, exist_ok=True)

    reference("every-value-type", "llama", every_type_entries(), every_type_tensors())
    reference("every-tensor-type", "llama",
              [("general.architecture", scalar("STRING", "llama"))],
              every_tensor_tensors())
    reference("alignment-64", "llama",
              [("general.architecture", scalar("STRING", "llama"))],
              every_type_tensors(), alignment=64)
    reference("metadata-only", "llama", every_type_entries(), [])
    reference("bare", None, [], [])

    # Shapes the reference writer cannot produce. Each is read back by
    # `gguf-py` below, so the bytes answer to a second implementation.
    files["nested-arrays"] = pack(
        "nested-arrays", 3,
        [
            ("general.architecture", scalar("STRING", "llama")),
            ("test.array.of.pairs", array("ARRAY", [
                array("INT32", [scalar("INT32", 1), scalar("INT32", 2)]),
                array("INT32", [scalar("INT32", 3)]),
                array("INT32", []),
            ])),
            ("test.array.of.rows", array("ARRAY", [
                array("STRING", [scalar("STRING", "a")]),
                array("STRING", []),
            ])),
            ("test.array.empty.uint32", array("UINT32", [])),
            ("test.array.empty.string", array("STRING", [])),
            ("test.array.empty.float64", array("FLOAT64", [])),
        ],
        [tensor("plain.f32", "F32", [4], 3)],
    )
    files["version-2"] = pack(
        "version-2", 2,
        [("general.architecture", scalar("STRING", "llama")),
         ("test.count", scalar("UINT32", 3))],
        [tensor("plain.f32", "F32", [4], 4), tensor("q.q4_0", "Q4_0", [64], 5)],
    )
    files["version-1"] = pack(
        "version-1", 1,
        [("general.architecture", scalar("STRING", "llama")),
         ("test.count", scalar("UINT32", 3)),
         ("test.array", array("UINT32", [scalar("UINT32", 1), scalar("UINT32", 2)]))],
        [tensor("plain.f32", "F32", [4], 6), tensor("q.q4_0", "Q4_0", [64], 7)],
    )
    files["newest-encodings"] = pack(
        "newest-encodings", 3,
        [("general.architecture", scalar("STRING", "llama"))],
        [tensor("t.Q2_0", "Q2_0", [128, 3], 9),
         tensor("t.F8_E4M3", "F8_E4M3", [16, 2], 10)],
    )
    files["big-endian"] = pack(
        "big-endian", 3,
        [("general.architecture", scalar("STRING", "llama")),
         ("test.int16", scalar("INT16", -300))],
        [tensor("plain.f32", "F32", [8], 8)],
        order=">",
    )

    for name, raw in files.items():
        (out / f"{name}.gguf").write_bytes(raw)
    for name in ("nested-arrays", "version-2"):
        if jsondir is not None:
            (jsondir / f"{name}.json").write_text(
                json.dumps(reference_dump(out / f"{name}.gguf"), indent=1,
                           sort_keys=True) + "\n",
                encoding="utf-8", newline="\n")
    return files


def hex_literal(raw: bytes, indent: str = "    ") -> str:
    """Hex, split so that no line of the generated source is unwieldy."""
    text = raw.hex()
    chunk = 120
    parts = [text[i:i + chunk] for i in range(0, len(text), chunk)]
    return "\n".join(f'{indent}"{part}" +' for part in parts)[:-2]


def emit(files: dict[str, bytes]) -> None:
    names = sorted(files)
    lines = [
        "// Copyright 2026 Leo Cheng",
        "// SPDX-License-Identifier: Apache-2.0",
        "",
        "// Generated by `scripts/make_vectors.py`; edit that and run it again.",
        "",
        "///|",
        "/// The files the tests below read, as hex, keyed by the case they cover.",
        "fn vectors() -> Array[(String, Bytes)] {",
        "  [",
    ]
    for name in names:
        lines.append(f'    ("{name}", hex(')
        lines.append(hex_literal(files[name], indent="      "))
        lines.append("    )),")
    lines += ["  ]", "}", ""]
    VECTORS.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=None,
                        help="write the files here as well, for the interop check")
    parser.add_argument("--json", type=Path, default=None,
                        help="write the reference dump of each file here")
    parser.add_argument("--check", action="store_true",
                        help="fail if the generated source is out of date")
    args = parser.parse_args()
    out = args.out or Path(__file__).resolve().parent / ".." / "_build" / "vectors"
    files = build(out.resolve(), args.json)
    before = VECTORS.read_text(encoding="utf-8") if VECTORS.exists() else ""
    emit(files)
    after = VECTORS.read_text(encoding="utf-8")
    if args.check and before != after:
        print(f"{VECTORS.relative_to(ROOT)} is out of date", file=sys.stderr)
        VECTORS.write_text(before, encoding="utf-8", newline="\n")
        return 1
    print(f"{len(files)} files, {sum(len(v) for v in files.values())} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
