"""Break the library on purpose, and check that a test notices.

A test suite that passes says nothing about what it would catch. Each mutation
below changes one line of the library in a way that a reader of the format would
call wrong, runs the tests, and expects at least one to fail. A mutation that no
test notices is a hole in the suite, and this script says which one.

    python scripts/mutation_check.py
    python scripts/mutation_check.py --only alignment

The file is put back the way it was, whatever happens.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class Mutation:
    name: str
    file: str
    before: str
    after: str
    why: str


MUTATIONS = [
    Mutation(
        name="alignment",
        file="src/number.mbt",
        before="    n + step - rest",
        after="    n - rest",
        why="rounds the data section and every tensor down instead of up",
    ),
    Mutation(
        name="nested-arrays",
        file="src/wire.mbt",
        before="    items.push(read_value(cur, kind, limits, depth + 1))",
        after="    items.push(read_value(cur, kind, limits, depth))",
        why="reads the entries of an array of arrays as arrays of the same shape",
    ),
    Mutation(
        name="tensor-offsets",
        file="src/file.mbt",
        before="    if offset != expected {",
        after="    if offset != expected && false {",
        why="accepts a tensor index whose offsets do not meet",
    ),
    Mutation(
        name="value-kinds",
        file="src/wire.mbt",
        before="    Int8 => Int8(signed8(cur.u8()))",
        after="    Int8 => Int8(cur.u8().reinterpret_as_int())",
        why="drops the sign of a negative `int8`",
    ),
    Mutation(
        name="array-element-kind",
        file="src/wire.mbt",
        before="      sink.u32(kind.code())",
        after="      sink.u32(ValueType::UInt8.code())",
        why="writes every array as if its entries were `uint8`",
    ),
    Mutation(
        name="string-length-width",
        file="src/sink.mbt",
        before="  self.count(bytes.length().to_uint64())",
        after="  self.u32(bytes.length().reinterpret_as_uint())",
        why="writes a version 3 string length as 32 bits",
    ),
    Mutation(
        name="tensor-byte-length",
        file="src/ggml.mbt",
        before='  { kind: Q6_K, code: 14, name: "Q6_K", block: 256, bytes: 210, },',
        after='  { kind: Q6_K, code: 14, name: "Q6_K", block: 256, bytes: 208, },',
        why="gives one encoding the wrong size in bytes",
    ),
    Mutation(
        name="shard-bounds",
        file="src/file.mbt",
        before="  let take = if bytes.length().to_int64() < room {",
        after="  let take = if bytes.length().to_int64() > 0 {",
        why="hands back more of a shard than belongs to the tensor",
    ),
]


def run_tests(moon: str) -> tuple[int, str, bool]:
    """The exit code, the output, and whether the suite ran at all — a mutation
    that does not compile says nothing about the tests."""
    done = subprocess.run([moon, "test", "--target", "native"],
                          cwd=ROOT, capture_output=True, text=True)
    output = done.stdout + done.stderr
    return done.returncode, output, "Total tests:" in output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--only", default=None)
    args = parser.parse_args()

    code, output, _ = run_tests(args.moon)
    if code != 0:
        print("the tests do not pass before any mutation:")
        print(output[-2000:])
        return 1
    print("the tests pass as they are")

    missed = []
    for mutation in MUTATIONS:
        if args.only is not None and mutation.name != args.only:
            continue
        path = ROOT / mutation.file
        original = path.read_text(encoding="utf-8")
        if mutation.before not in original:
            print(f"{mutation.name}: the line to break is not there any more")
            missed.append(mutation.name)
            continue
        path.write_text(original.replace(mutation.before, mutation.after, 1),
                        encoding="utf-8", newline="\n")
        try:
            code, output, ran = run_tests(args.moon)
            if "Error: [" in output:
                reason = next((line for line in output.splitlines()
                               if line.startswith("Error: [")), "it did not build")
                print(f"{mutation.name}: the library did not build — {reason}")
                missed.append(mutation.name)
            elif code != 0:
                caught = [line for line in output.splitlines()
                          if "failed:" in line or "FAILED" in line
                          or "panicked" in line.lower()]
                first = caught[0].strip() if caught else "the suite failed"
                print(f"{mutation.name}: caught by {first}")
            else:
                print(f"{mutation.name}: nothing noticed ({mutation.why})")
                missed.append(mutation.name)
        finally:
            path.write_text(original, encoding="utf-8", newline="\n")

    if missed:
        print(f"{len(missed)} of {len(MUTATIONS)} mutations went unnoticed")
        return 1
    print(f"all {len(MUTATIONS) - (0 if args.only else 0)} mutations were caught")
    return 0


if __name__ == "__main__":
    sys.exit(main())
