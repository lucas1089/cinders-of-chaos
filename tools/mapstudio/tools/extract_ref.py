"""Copies a reference area out of a map into refs/<name>/area.txt, and renders it with --render.

    python -B run.py tools/extract_ref.py <name> --from 3149,4743 --to 3405,4930 [--map <map>] [--floors 0-15]
        [--render [--floor 7] [--scale 0.5]]
The default map is the reference map. Underground windows: --floors 8-15 --render --floor 9.
"""
import argparse
import subprocess
import sys
from pathlib import Path

from common import REFERENCE_MAP, ROOT, read_area, save_area


def main():
    p = argparse.ArgumentParser()
    p.add_argument("name")
    p.add_argument("--map", default=REFERENCE_MAP)
    p.add_argument("--from", dest="start", required=True)
    p.add_argument("--to", dest="end", required=True)
    p.add_argument("--floors", default="0-15")
    p.add_argument("--render", action="store_true", help="also write refs/<name>/render.png")
    p.add_argument("--floor", type=int, default=7, help="the floor to render")
    p.add_argument("--scale", type=float, default=0.5)
    a = p.parse_args()
    x1, y1 = map(int, a.start.split(","))
    x2, y2 = map(int, a.end.split(","))
    lo, _, hi = a.floors.partition("-")
    floors = range(int(lo), int(hi or lo) + 1)
    area = read_area(a.map, x1, y1, x2, y2, floors)
    meta = {"name": a.name, "map": str(Path(a.map)) if a.map else "reference",
            "bounds": {"x1": x1, "y1": y1, "x2": x2, "y2": y2}, "floors": sorted(area)}
    out = ROOT / "refs" / a.name / "area.txt"
    save_area(out, area, meta)
    print(out, {z: len(layer) for z, layer in sorted(area.items())})
    if a.render:
        subprocess.run([sys.executable, "-B", str(ROOT / "run.py"), "tools/render.py", str(out), "--floor",
                        str(a.floor), "--upper", "--scale", str(a.scale), "--out", str(out.with_name("render.png"))],
                       check=True)


if __name__ == "__main__":
    main()
