#!/usr/bin/env python3
"""Build the in-process nauty/Traces bridge used by gog_generate.py."""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "gog_nauty_bridge.c"


def default_output() -> Path:
    suffix = ".dylib" if platform.system() == "Darwin" else ".so"
    return ROOT / f"gog_nauty_bridge{suffix}"


def candidate_prefixes() -> list[Path]:
    prefixes: list[Path] = []
    env_prefix = os.environ.get("NAUTY_PREFIX")
    if env_prefix:
        prefixes.append(Path(env_prefix))
    prefixes.extend([Path("/opt/homebrew"), Path("/usr/local"), Path("/usr")])
    return prefixes


def find_nauty_prefix() -> Path:
    for prefix in candidate_prefixes():
        if (prefix / "include" / "nauty" / "nauty.h").exists() and (
            prefix / "lib" / "libnauty.dylib"
        ).exists():
            return prefix
        if (prefix / "include" / "nauty" / "nauty.h").exists() and (
            prefix / "lib" / "libnauty.so"
        ).exists():
            return prefix
        if (prefix / "include" / "nauty" / "nauty.h").exists() and (
            prefix / "lib" / "libnauty.a"
        ).exists():
            return prefix
    raise SystemExit(
        "Could not find nauty headers/libs. Set NAUTY_PREFIX to the install prefix."
    )


def build(output: Path, cc: str, prefix: Path, extra_cflags: list[str]) -> None:
    output = output.resolve()
    cmd = [
        cc,
        "-O3",
        "-fPIC",
        "-I",
        str(prefix / "include"),
        str(SOURCE),
        "-L",
        str(prefix / "lib"),
        "-lnauty",
        "-o",
        str(output),
    ]
    if platform.system() == "Darwin":
        cmd[1:1] = ["-dynamiclib"]
        cmd.extend(["-Wl,-rpath", f"-Wl,{prefix / 'lib'}"])
    else:
        cmd[1:1] = ["-shared"]
        cmd.extend(["-Wl,-rpath", str(prefix / "lib")])
    cmd[1:1] = extra_cflags

    print(" ".join(cmd))
    subprocess.run(cmd, check=True)
    print(f"wrote {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=default_output())
    parser.add_argument("--cc", default=os.environ.get("CC") or shutil.which("cc") or "cc")
    parser.add_argument("--nauty-prefix", type=Path, default=None)
    parser.add_argument("--cflag", action="append", default=[], help="extra C compiler flag")
    args = parser.parse_args()

    prefix = args.nauty_prefix or find_nauty_prefix()
    build(args.output, args.cc, prefix, args.cflag)


if __name__ == "__main__":
    main()
