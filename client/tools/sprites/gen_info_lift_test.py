#!/usr/bin/env python3
"""Tests of gen_info_lift.py on small synthetic figures (no pair needed; numpy).

python3 -I client/tools/sprites/gen_info_lift_test.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_info_lift as gil  # noqa: E402

fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def figure(head_row):
    """a 64x64 canvas: a body 12 wide from head_row down to row 59"""
    a = np.zeros((64, 64), np.uint8)
    a[head_row:60, 40:52] = 255
    return a


# the body's top row; a raised staff (2 px wide) above the head does not count
check(gil.body_top(figure(30)) == 30, 'top of a plain body')
staff = figure(30)
staff[2:30, 36:38] = 255
check(gil.body_top(staff) == 30, 'a staff above the head left out: %s' % gil.body_top(staff))
check(gil.body_top(np.zeros((64, 64), np.uint8)) is None, 'nothing visible')
faint = figure(30)
faint[10:30, 40:52] = 20   # below the alpha threshold
check(gil.body_top(faint) == 30, 'faint pixels do not count')

# the gap: a stock 2x2 look, displacement 8, head at canvas row 30: top = 30 - 32 - 8 = -10, bar = -10, gap 0
check(gil.gap_of(30, 2, 8) == 0, 'stock look: head on the bar line')
# the same art with no displacement: the bar drops 8 with the picture, the gap stays
check(gil.gap_of(30, 2, 0) == 0, 'displacement cancels out')
# a figure drawn 20 px higher in its canvas: gap 20
check(gil.gap_of(10, 2, 0) == 20, 'a tall look: gap 20')
# a negative displacement: the bar keeps no displacement, the picture goes down by it
check(gil.gap_of(30, 2, -4, True) == -4, 'negative displacement: %s' % gil.gap_of(30, 2, -4, True))
check(gil.gap_of(30, 2, 8, True) == 8, 'negative x only: the bar keeps no displacement, the picture its dy')

# the lift: the largest direction's gap over ALLOW, from MIN_LIFT on, capped
check(gil.lift_of([]) == 0, 'no direction')
check(gil.lift_of([0, 2, gil.ALLOW]) == 0, 'stock gaps: no lift')
check(gil.lift_of([gil.ALLOW + gil.MIN_LIFT - 1]) == 0, 'below MIN_LIFT: none')
check(gil.lift_of([3, 20, 12]) == 20 - gil.ALLOW, 'the largest direction counts')
check(gil.lift_of([500]) == gil.MAX_LIFT, 'capped')

print('gen_info_lift_test:', 'OK' if not fails else '%d failure(s)' % fails)
sys.exit(1 if fails else 0)
