"""Check this library against the reference implementation, field by field.

Three things are checked for every file `scripts/make_vectors.py` can build:

* this library's dump of the file against `gguf-py`'s dump of the same file —
  every metadata pair with its kind, its position and its value, and every
  tensor with its shape, kind and position;
* this library's read written back out is the same bytes as the file it read;
* `gguf-py` reading that written file finds what it found in the original.

The dumps are the JSON `gguf-py`'s own `gguf_dump.py --json` prints, so a
difference is a field, not a phrase.

    python scripts/check_interop.py

Needs `gguf` (see `scripts/requirements.txt`) and a MoonBit toolchain.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_vectors  # noqa: E402
from gguf_reference import Checker, compare_dumps, reference_dump  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def run(binary: Path, *args: str) -> str:
    done = subprocess.run([str(binary), *args], capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(f"{binary.name} {' '.join(args)} failed:\n{done.stdout}{done.stderr}")
    return done.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--keep", action="store_true", help="leave the files behind")
    args = parser.parse_args()

    work = Path(tempfile.mkdtemp(prefix="moongguf-interop-"))
    print(f"building the tools in {work}")
    build = subprocess.run(
        [args.moon, "build", "--target", "native",
         "integration/tools/dump", "integration/tools/rewrite"],
        cwd=ROOT, capture_output=True, text=True)
    if build.returncode != 0:
        raise SystemExit("moon build failed:\n" + build.stdout + build.stderr)
    built = ROOT / "_build" / "native" / "debug" / "build" / "moonbitstack" / "moongguf-tools"
    suffix = ".exe" if os.name == "nt" else ""
    dump_tool = built / "dump" / f"dump{suffix}"
    rewrite_tool = built / "rewrite" / f"rewrite{suffix}"
    for tool in (dump_tool, rewrite_tool):
        if not tool.exists():
            raise SystemExit(f"{tool} was not built")

    vectors = make_vectors.build(work, work / "json")
    check = Checker()
    readable = 0
    rewritten = 0
    for name in sorted(vectors):
        path = work / f"{name}.gguf"
        reference = work / "json" / f"{name}.json"
        # `gguf-py` reads neither version 1 nor the two encodings newer than it.
        if reference.exists():
            readable += 1
            compare_dumps(check, name, json.loads(run(dump_tool, str(path))),
                          json.loads(reference.read_text(encoding="utf-8")))
        if name in ("version-1", "version-2"):
            # Versions 1 and 2 are read-only: only version 3 is written.
            continue
        again = work / f"{name}.again.gguf"
        run(rewrite_tool, str(path), str(again))
        if not again.exists():
            raise SystemExit(f"{name} was not written back")
        if again.read_bytes() != path.read_bytes():
            check.problems.append(f"{name}: reading and writing gave other bytes")
        if reference.exists():
            rewritten += 1
            compare_dumps(check, f"{name} written back",
                          json.loads(run(dump_tool, str(again))),
                          reference_dump(again))

    print(f"{len(vectors)} files, {readable} compared with gguf-py, "
          f"{rewritten} written back and read again by it, {check.fields} fields")
    for problem in check.problems:
        print("  " + problem)
    if not args.keep:
        import shutil
        shutil.rmtree(work, ignore_errors=True)
    return 1 if check.problems else 0


if __name__ == "__main__":
    sys.exit(main())
