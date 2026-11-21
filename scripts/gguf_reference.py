"""What the reference implementation makes of a GGUF file, and how to compare.

`gguf-py` is the package llama.cpp publishes; its `gguf_dump.py --json` prints
every metadata pair with its kind, its position and its value, and every tensor
with its shape, kind and position. This module prints the same shape, and
compares two of them field by field, so that a difference is named.

Needs `gguf` and `numpy` (see `scripts/requirements.txt`).
"""

from __future__ import annotations

import json
from pathlib import Path

import gguf
import numpy as np
from gguf import GGUFValueType


def plain(value):
    """JSON holds Python's own numbers, not numpy's."""
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, (list, tuple)):
        return [plain(item) for item in value]
    if isinstance(value, dict):
        return {key: plain(item) for key, item in value.items()}
    return value


def reference_dump(path: Path) -> dict:
    """A file as `gguf-py` reads it, in the shape `gguf_dump.py --json` prints
    with `--json-array`."""
    reader = gguf.GGUFReader(str(path))
    metadata: dict[str, object] = {}
    for idx, field in enumerate(reader.fields.values()):
        described: dict[str, object] = {
            "index": idx,
            "type": field.types[0].name if field.types else "UNKNOWN",
            "offset": field.offset,
        }
        if field.types[:1] == [GGUFValueType.ARRAY]:
            described["array_types"] = [t.name for t in field.types][1:]
        described["value"] = plain(field.contents())
        metadata[field.name] = described
    tensors: dict[str, object] = {}
    for idx, tensor in enumerate(reader.tensors):
        tensors[tensor.name] = {
            "index": idx,
            "shape": tensor.shape.tolist(),
            "type": tensor.tensor_type.name,
            "offset": tensor.field.offset,
        }
    return plain({
        "endian": "LITTLE" if reader.endianess == gguf.GGUFEndian.LITTLE else "BIG",
        "alignment": reader.alignment,
        "metadata": metadata,
        "tensors": tensors,
    })


class Checker:
    """A count of what was compared, and the fields that differ."""

    def __init__(self) -> None:
        self.fields = 0
        self.problems: list[str] = []

    def same(self, where: str, got, want) -> None:
        self.fields += 1
        if got != want:
            self.problems.append(f"{where}: {got!r} where the reference has {want!r}")

    @staticmethod
    def flatten(value):
        """`gguf-py` reads an array of arrays as one flat list with the kinds
        beside it; this library keeps the nesting."""
        if isinstance(value, list):
            out = []
            for item in value:
                out.extend(Checker.flatten(item))
            return out
        return [value]


def compare_dumps(check: Checker, name: str, ours: dict, theirs: dict) -> None:
    """Every field of two dumps, one by one."""
    check.same(f"{name} endian", ours.get("endian"), theirs["endian"])
    check.same(f"{name} alignment", ours.get("alignment"), theirs["alignment"])
    ours_meta = ours["metadata"]
    their_meta = theirs["metadata"]
    check.same(f"{name} metadata keys", sorted(ours_meta), sorted(their_meta))
    for key in sorted(set(ours_meta) & set(their_meta)):
        mine = ours_meta[key]
        other = their_meta[key]
        where = f"{name} {key}"
        check.same(f"{where} type", mine["type"], other["type"])
        check.same(f"{where} offset", mine["offset"], other["offset"])
        check.same(f"{where} index", mine["index"], other["index"])
        if "array_types" in other:
            check.same(f"{where} array_types", mine.get("array_types"),
                       other["array_types"])
            check.same(f"{where} value", check.flatten(mine["value"]),
                       check.flatten(other["value"]))
        else:
            check.same(f"{where} value", mine["value"], other["value"])
    ours_tensors = ours["tensors"]
    their_tensors = theirs["tensors"]
    check.same(f"{name} tensor names", sorted(ours_tensors), sorted(their_tensors))
    for key in sorted(set(ours_tensors) & set(their_tensors)):
        mine = ours_tensors[key]
        other = their_tensors[key]
        where = f"{name} {key}"
        check.same(f"{where} shape", mine["shape"], other["shape"])
        check.same(f"{where} type", mine["type"], other["type"])
        check.same(f"{where} offset", mine["offset"], other["offset"])


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))
