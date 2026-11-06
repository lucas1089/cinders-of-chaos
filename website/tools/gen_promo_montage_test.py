#!/usr/bin/env python3
"""Tests of gen_promo_montage.py without clips or ffmpeg: every plan has its music, every caption exists in pt-BR and en,
the seven classes are in the class short, every job names a plan.

    python3 -I website/tools/gen_promo_montage_test.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_promo_montage as m  # noqa: E402

FAILS = []


def eq(a, b, msg):
    if a != b:
        FAILS.append('%s: %r != %r' % (msg, a, b))


eq(m.check(False), [], 'plans check')
eq(len(m.CLASSES), 7, 'seven classes')
eq(sorted(m.CLASS_KEY.values()), sorted(m.CLASS_NAMES['en']), 'class keys')
eq(sorted(m.CLASS_NAMES['pt-BR']), sorted(m.CLASS_NAMES['en']), 'class names in both languages')
eq(sorted(m.EXTRA['pt-BR']), sorted(m.EXTRA['en']), 'extra captions in both languages')
eq([j for j in m.JOBS if j[0] not in m.PLANS], [], 'jobs name plans')
eq(len(m.JOBS), 14, 'job count')
for name, (_, plan) in m.PLANS.items():
    eq(plan[-1][0], 'end', name + ' ends on the end card')
eq('mystic_s' in m.clip_names(), True, 'clip names')

if FAILS:
    print('\n'.join(FAILS))
    sys.exit(1)
print('gen_promo_montage_test: ok')
