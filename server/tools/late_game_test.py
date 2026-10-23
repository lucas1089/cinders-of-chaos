#!/usr/bin/env python3
"""Tests of late_game.py's experience stages: python3 -I server/tools/late_game_test.py

The table is contiguous from level 1 to an explicit open end, steps by at most 8% from one row to the next (O135: smooth
progression; tools/progression_model.lua --check also measures the minutes per level), keeps its late game rows, and the
config.lua patch is idempotent and reversible."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import late_game  # noqa: E402

fails = []


def check(cond, msg):
    if not cond:
        fails.append(msg)


S = late_game.STAGES
check(S[0][0] == 1, 'starts at level 1')
check(S[-1][1] == late_game.OPEN_END, 'explicit open end')
for (lo, hi, m), (lo2, hi2, m2) in zip(S, S[1:]):
    check(lo2 == hi + 1, 'contiguous at %d' % hi)
    check(max(m, m2) / min(m, m2) <= 1.08, 'step %d -> %d at level %d is over 8%%' % (m, m2, lo2))
check(S[0][2] > 10 and S[0][2] <= 50, 'level 1 stage')
check(late_game.SMOOTH_STAGES[-1][1] == 700 and late_game.LATE_STAGES[0][0] == 701, 'the smooth table ends at 700')
# nothing above the stock x50 and the late game keeps its rows
check(max(m for _, _, m in S) <= 50, 'no stage above x50')
check([m for lo, _, m in late_game.LATE_STAGES] == [15, 15, 14, 14, 13, 13], 'late game rows')
# the stock table for --remove is the base one
check(late_game.STOCK_STAGES[:14] == late_game.BASE_STAGES, 'stock table keeps the base rows')

text = 'rateExp = 5\n' + late_game.stages_lua(late_game.STOCK_STAGES, None) + '\nafter = 1\n'
new, status = late_game.patch_config(text, False)
check(status == 'patched', 'patched: %s' % status)
again, status = late_game.patch_config(new, False)
check(status == 'already' and again == new, 'second run changes nothing')
back, status = late_game.patch_config(new, True)
check(status == 'restored' and back == text, 'remove restores the stock table')
old_patched = text.replace(late_game.stages_lua(late_game.STOCK_STAGES, None),
                           late_game.stages_lua(late_game.BASE_STAGES + late_game.LATE_STAGES, late_game.STAGES_MARK))
up, status = late_game.patch_config(old_patched, False)
check(status == 'patched' and late_game.stages_lua(S, late_game.STAGES_MARK) in up, 'an old Chaos table is replaced')

for f in fails:
    print('FAIL', f)
print('late_game_test: %d failures' % len(fails))
sys.exit(1 if fails else 0)
