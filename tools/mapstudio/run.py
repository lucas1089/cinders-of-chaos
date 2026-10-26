"""Run a MapStudio Python tool with writes confined to this sandbox process.

Usage: python -B run.py tools/test_sides.py
This is a development guard, not OS isolation or a guard for child processes.
"""
from __future__ import annotations

import os
from pathlib import Path
import runpy
import sys

ROOT = Path(__file__).resolve().parent


def install_write_guard(root):
    root = Path(root).resolve()

    def check(path):
        if isinstance(path, (str, bytes, os.PathLike)):
            target = Path(os.fsdecode(path)).resolve()
            if not target.is_relative_to(root):
                raise PermissionError(f"Sandbox refuses write outside {root}: {target}")

    def guard(event, args):
        if event == "open":
            path, mode, flags = args
            if ((isinstance(mode, str) and any(c in mode for c in "wax+"))
                    or ((flags or 0) & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC))):
                check(path)
        elif event in ("os.mkdir", "os.remove", "os.rmdir", "os.chmod", "os.utime", "os.truncate"):
            check(args[0])
        elif event in ("os.rename", "os.replace"):
            check(args[0])
            check(args[1])
        elif event in ("os.symlink", "os.link"):
            raise PermissionError("Sandbox tools may not create filesystem links")

    sys.addaudithook(guard)


def main():
    if len(sys.argv) < 2:
        raise SystemExit("Usage: python -B run.py tools/<script>.py [arguments]")
    script = (ROOT / sys.argv[1]).resolve()
    if not script.is_relative_to(ROOT) or not script.is_file() or script.suffix != ".py":
        raise SystemExit("Choose an existing Python script inside this sandbox")
    sys.dont_write_bytecode = True
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    os.chdir(ROOT)
    install_write_guard(ROOT)
    sys.path[:0] = [str(script.parent), str(ROOT / "tools"), str(ROOT)]
    sys.argv = [str(script), *sys.argv[2:]]
    runpy.run_path(str(script), run_name="__main__")


if __name__ == "__main__":
    main()
