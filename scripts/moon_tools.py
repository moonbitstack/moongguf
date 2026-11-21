"""Building and running the small programs in `integration/tools`.

They are separate from the library because they read files, and the library
does not: the tools are what a caller of this library looks like, and they are
what the checks against another implementation drive.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = {"dump", "rewrite", "read-chunks"}


class Tools:
    """The built tools, by name, found wherever the toolchain put them."""

    def __init__(self, build: Path, output: str) -> None:
        self.build = build
        self.output = output
        self.suffix = ".exe" if os.name == "nt" else ""

    def path(self, name: str) -> Path:
        if name not in TOOLS:
            raise KeyError(name)
        found = sorted(self.build.rglob(f"{name}{self.suffix}"))
        if not found:
            raise SystemExit(
                f"{name} was not built; the build said:\n{self.output}")
        return found[-1]

    def run(self, name: str, *args: str) -> str:
        done = subprocess.run([str(self.path(name)), *args],
                              capture_output=True, text=True)
        if done.returncode != 0:
            raise SystemExit(f"{name} {' '.join(args)} failed:\n{done.stdout}{done.stderr}")
        return done.stdout


def build(moon: str = "moon") -> Tools:
    """Build the tools for the native target, and say where they landed."""
    done = subprocess.run(
        [moon, "build", "--target", "native",
         *[f"integration/tools/{name}" for name in sorted(TOOLS)]],
        cwd=ROOT, capture_output=True, text=True)
    output = done.stdout + done.stderr
    if done.returncode != 0:
        raise SystemExit("moon build failed:\n" + output)
    return Tools(ROOT / "_build", output)
