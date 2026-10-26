"""Renders a review batch: 8 varied seeds into areas/<batch>/seed-NNN/ (area.txt, render.png, summary.txt), then
writes the review page areas/<batch>/index.html (tools/review_page.py).

python -B run.py tools/batch.py <batch> [--kit <name>] [--seeds 101,102] [--timeout 900]
Each map runs as its own process with a time limit, so one stuck run can't hang the batch.
"""
from __future__ import annotations

import argparse
import subprocess
import sys

from common import ROOT, kit_name

GENERATOR = "gen/generate.py"
VARIANTS = {  # seed: knobs; together they cover small/large, wet/dry, flat/high
    101: "--size 96",
    102: "--size 112 --rivers 1 --lakes 2",
    103: "--size 128 --rivers 2 --lakes 3 --mountains 25 --levels 3",
    104: "--size 112 --mountains 50 --levels 5 --hills 0",
    105: "--size 96 --mountains 15 --levels 2 --rivers 1 --vegetation 130",
    106: "--size 128 --rivers 1 --lakes 4 --mountains 30",
    107: "--size 112 --mountains 40 --levels 4 --sea-cliffs 30",
    108: "--size 112 --rivers 2 --roads 6 --sand 8",
}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("batch")
    p.add_argument("--kit")
    p.add_argument("--seeds", help="comma-separated subset of " + ",".join(map(str, VARIANTS)))
    p.add_argument("--timeout", type=int, default=900, help="seconds per map")
    a = p.parse_args()
    kit = kit_name(a.kit)
    seeds = [int(s) for s in a.seeds.split(",")] if a.seeds else list(VARIANTS)
    for seed in seeds:
        knobs = VARIANTS.get(seed, "")
        name = f"{a.batch}/seed-{seed}"
        out = ROOT / "areas" / a.batch / f"seed-{seed}"
        out.mkdir(parents=True, exist_ok=True)
        cmd = [sys.executable, "-B", str(ROOT / "run.py"), GENERATOR, "--kit", kit, "--name", name,
               "--seed", str(seed), *knobs.split()]
        try:
            run = subprocess.run(cmd, capture_output=True, text=True, timeout=a.timeout)
            text = run.stdout + run.stderr
        except subprocess.TimeoutExpired:
            text = f"TIMEOUT after {a.timeout} s"
        (out / "summary.txt").write_text(f"knobs: --kit {kit} --seed {seed} {knobs}\n{text}", encoding="utf-8")
        print(f"seed {seed}: {'ok' if 'access:' in text else 'FAILED, see summary.txt'}")
    subprocess.run([sys.executable, "-B", str(ROOT / "run.py"), "tools/review_page.py", a.batch], check=True)


if __name__ == "__main__":
    main()
