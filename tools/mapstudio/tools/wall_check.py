"""Wall and void check of finished areas (round 8): void_touch, wall_wrong, wall_missing (see gen/wallcheck.py).

python -B run.py tools/wall_check.py areas/asylum-review-02            # every seed folder of a batch
python -B run.py tools/wall_check.py areas/asylum-review-02/seed-801   # one area
Both counts that matter, `void_touch` and `wall_wrong + wall_missing`, must be 0. Exit code 1 when any is not.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gen"))

from common import ROOT, load_area, load_items, load_kit, water_ids  # noqa: E402
from lib import edge_pieces  # noqa: E402
import wallcheck  # noqa: E402


def check_area(path):
    meta, area = load_area(path)
    kit = load_kit(meta["kit"])
    z = meta.get("floor", kit.get("floor", 7))
    pools = {int(i) for i in (meta.get("pools") or {}).get("ids", [])}  # liquid pool grounds (header stat `pools`)
    no_walk = water_ids(kit) | pools | {int(i) for i in (kit.get("void_cover") or {}).get("ground", [])}
    res = wallcheck.check(area.get(z, {}), meta["size"], 1000, load_items(), kit, no_walk, edge_pieces, pool_ids=pools)
    return meta, res


def main():
    paths = []
    for a in sys.argv[1:] or ["."]:
        p = (ROOT / a) if not Path(a).is_absolute() else Path(a)
        paths += sorted(p.glob("seed-*/area.txt")) if (p / "area.txt").exists() is False else [p / "area.txt"]
    bad = 0
    for path in paths:
        meta, r = check_area(path)
        tag = f"{path.parent.parent.name}/{path.parent.name}"
        print(f"{tag}: void_touch {r['void_touch']} (floor {r['void_touch_floor']}, wall {r['void_touch_wall']}), "
              f"wall_wrong {r['wall_wrong']}, wall_missing {r['wall_missing']}, wall tiles {r['wall_tiles']}")
        if r["void_touch"] or r["wall_wrong"] or r["wall_missing"]:
            bad += 1
    print(f"{len(paths)} areas, {bad} with a count above 0")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
