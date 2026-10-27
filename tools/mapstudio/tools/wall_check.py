"""Wall and void check of finished areas (round 8): void_touch, wall_wrong, wall_missing (see gen/wallcheck.py).

python -B run.py tools/wall_check.py areas/asylum-review-02            # every seed folder of a batch
python -B run.py tools/wall_check.py areas/asylum-review-02/seed-801   # one area
Every count must be 0: void_touch, wall_wrong, wall_missing, wall_gaps, wall_bands, wall_spurs (round 10: corner caps, lone posts,
dead-end stubs, diagonal-only tiles; -v lists samples), fence_gaps (round 10: fence ends against lanterns, rock or void). Exit code 1 when any is not.
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
    res["wall_gaps"], res["samples_gaps"], res["wall_bands"], res["samples_bands"] = 0, [], 0, []
    res["wall_spurs"], res["samples_spurs"], res["kinds_spurs"] = 0, [], {}
    if kit.get("walls"):  # the two round 9 counts are for wall sets (cliff-edge cave kits and island kits have none)
        g = wallcheck.gaps(area.get(z, {}), meta["size"], 1000, load_items(), kit, no_walk)
        res["wall_gaps"], res["samples_gaps"] = g["wall_gaps"], g["samples"]
        b = wallcheck.bands(area.get(z, {}), meta["size"], 1000, load_items(), kit, no_walk)
        res["wall_bands"], res["samples_bands"] = b["wall_bands"], b["samples"]
        sp = wallcheck.spurs(area.get(z, {}), meta["size"], 1000, load_items(), kit, no_walk)  # round 10
        res["wall_spurs"], res["samples_spurs"], res["kinds_spurs"] = sp["wall_spurs"], sp["samples"], sp["kinds"]
    res["fence_gaps"], res["samples_fence"] = 0, []
    if wallcheck.fence_ids(kit):  # round 10: loose ends of fence and wall lines (stamp outlines, doors)
        f = wallcheck.fence_gaps(area.get(z, {}), meta["size"], 1000, load_items(), kit, no_walk)
        res["fence_gaps"], res["samples_fence"] = f["fence_gaps"], f["samples"]
    return meta, res


def main():
    paths = []
    for a in [a for a in sys.argv[1:] if not a.startswith('-')] or ["."]:
        p = (ROOT / a) if not Path(a).is_absolute() else Path(a)
        paths += sorted(p.glob("seed-*/area.txt")) if (p / "area.txt").exists() is False else [p / "area.txt"]
    bad = 0
    for path in paths:
        meta, r = check_area(path)
        tag = f"{path.parent.parent.name}/{path.parent.name}"
        print(f"{tag}: void_touch {r['void_touch']} (floor {r['void_touch_floor']}, wall {r['void_touch_wall']}), "
              f"wall_wrong {r['wall_wrong']}, wall_missing {r['wall_missing']}, wall_gaps {r['wall_gaps']}, wall_bands {r['wall_bands']}, wall_spurs {r['wall_spurs']}, fence_gaps {r['fence_gaps']}, wall tiles {r['wall_tiles']}")
        if "-v" in sys.argv or "--samples" in sys.argv:
            print("   gap samples (tile x, y, px):", r["samples_gaps"], "band samples (tile x, y):", r["samples_bands"],
                  "spur samples (tile x, y, kind):", r["samples_spurs"], r["kinds_spurs"], "fence samples:", r["samples_fence"])
        if r["void_touch"] or r["wall_wrong"] or r["wall_missing"] or r["wall_gaps"] or r["wall_bands"] or r["wall_spurs"] or r["fence_gaps"]:
            bad += 1
    print(f"{len(paths)} areas, {bad} with a count above 0")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
