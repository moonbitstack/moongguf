"""Check this library against two real models, field by field.

The models are pinned by URL and by digest, so a check either compares the same
bytes every time or fails. Each one is read twice: by this library, and by
`gguf-py`, the reference implementation — and the two dumps are compared pair by
pair and tensor by tensor. The file is then read again in pieces, the way a file
larger than one `Bytes` has to be, and the tensor bytes that come back are
counted against the index.

    python scripts/check_models.py
    python scripts/check_models.py --cache /somewhere/models

Needs `gguf` and `numpy` (see `scripts/requirements.txt`) and a MoonBit
toolchain. The files are cached, so the second run costs nothing.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import moon_tools  # noqa: E402
from gguf_reference import Checker, compare_dumps, reference_dump  # noqa: E402


@dataclass(frozen=True)
class Model:
    name: str
    repository: str
    file: str
    sha256: str
    size: int

    @property
    def urls(self) -> list[str]:
        # The public host, and the mirror that answers where it does not.
        return [f"https://huggingface.co/{self.repository}/resolve/main/{self.file}",
                f"https://hf-mirror.com/{self.repository}/resolve/main/{self.file}"]


MODELS = [
    Model(
        name="stories15M-q4_0",
        repository="ggml-org/models",
        file="tinyllamas/stories15M-q4_0.gguf",
        sha256="66967fbece6dbe97886593fdbb73589584927e29119ec31f08090732d1861739",
        size=19_077_344,
    ),
    Model(
        name="qwen2.5-0.5b-instruct-q2_k",
        repository="Qwen/Qwen2.5-0.5B-Instruct-GGUF",
        file="qwen2.5-0.5b-instruct-q2_k.gguf",
        sha256="",
        size=415_182_688,
    ),
]


def fetch(model: Model, cache: Path) -> Path:
    """The model on disk, downloaded once and checked against its digest."""
    target = cache / f"{model.name}.gguf"
    if target.exists() and target.stat().st_size == model.size:
        if not model.sha256 or digest(target) == model.sha256:
            return target
        print(f"{target} is not the file that was pinned; fetching it again")
        target.unlink()
    cache.mkdir(parents=True, exist_ok=True)
    for url in model.urls:
        print(f"fetching {model.name} from {url}")
        try:
            with urllib.request.urlopen(url, timeout=60) as response, \
                    open(target, "wb") as out:
                while chunk := response.read(1 << 20):
                    out.write(chunk)
        except (urllib.error.URLError, TimeoutError) as error:
            print(f"  {error}")
            continue
        if target.stat().st_size != model.size:
            print(f"  {target.stat().st_size} bytes, {model.size} expected")
            continue
        if model.sha256 and digest(target) != model.sha256:
            print("  the digest is not the one pinned")
            continue
        return target
    raise SystemExit(f"could not fetch {model.name}")


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with open(path, "rb") as handle:
        while chunk := handle.read(1 << 20):
            hasher.update(chunk)
    return hasher.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--cache", type=Path,
                        default=moon_tools.ROOT / "_build" / "models")
    parser.add_argument("--only", default=None,
                        help="one model by name, for a quicker run")
    args = parser.parse_args()

    tools = moon_tools.build(args.moon)
    check = Checker()
    models = [m for m in MODELS if args.only is None or m.name == args.only]
    if not models:
        raise SystemExit(f"no model called {args.only}")
    for model in models:
        path = fetch(model, args.cache)
        print(f"{model.name}: {path.stat().st_size} bytes")
        ours = json.loads(tools.run("dump", str(path)))
        compare_dumps(check, model.name, ours, reference_dump(path))
        # Reading it again in pieces, the way a file larger than one `Bytes`
        # has to be read, and counting the tensor bytes that come back.
        report = tools.run("read-chunks", str(path)).strip().splitlines()
        held = int(report[-1].split()[0])
        lengths = sum(extent_length(ours, name) for name in ours["tensors"])
        check.same(f"{model.name} tensor bytes read in shards", held, lengths)
        if model.size <= 32 << 20:
            # Writing a file back needs it whole in one `Bytes`; the small model
            # proves the round trip, and the large one is read here.
            again = args.cache / f"{model.name}.again.gguf"
            tools.run("rewrite", str(path), str(again))
            if again.read_bytes() != path.read_bytes():
                check.problems.append(f"{model.name}: reading and writing gave other bytes")
            compare_dumps(check, f"{model.name} written back",
                          json.loads(tools.run("dump", str(again))),
                          reference_dump(again))
            again.unlink()
    print(f"{len(models)} models, {check.fields} fields compared")
    for problem in check.problems:
        print("  " + problem)
    return 1 if check.problems else 0


def extent_length(dump: dict, name: str) -> int:
    """How many bytes a tensor takes, from the shape and the encoding, without
    reading the file again: the dump carries both."""
    tensor = dump["tensors"][name]
    shape = tensor["shape"]
    count = 1
    for dim in shape:
        count *= dim
    block, size = BLOCKS[tensor["type"]]
    return count // block * size


# Block size and bytes per block, the same table the library keeps.
BLOCKS = {
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


if __name__ == "__main__":
    sys.exit(main())
