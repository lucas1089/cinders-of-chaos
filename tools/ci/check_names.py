#!/usr/bin/env python3
"""Fail if text files mention other servers or clients by name (project rule: no such references).
base-patches/ is skipped: its context lines are copied from the client tree and cannot be edited.
Art pack names (ART_PACKS) are allowed only in the credits (docs/CREDITS.md and the two files gen_credits.py makes
from it): the owner shows the packs' credits in the game and on the website (2026-10-15)."""
import os, re, subprocess, sys

DENY = re.compile(r'hellgrave|tenkaiser|drakantos|exodus|evolisca|black ?talon|magic ?heard|luminaris|zerion|fonticak|\bastra(?!l)|archlight|'
                  r'demolidores|crystalserver|fortibia|balrog|rubinot|medivia|ravendawn|otservbr|mordragor|'
                  r'jfranci|'
                  r'amon ?ot|albane|zainox|elythion|\btyron\b|oxygen ?ot|world ?of ?fragment|frontiers? ?of ?fantasy|'
                  r'grand ?line|\bgla\b|vision ?ot|boteq', re.I)
ART_PACKS = re.compile(r'\bwst(_|\b)|raven ?fantasy|pixel ?spellcraft|anime ?ki ?auras', re.I)
CREDITS_FILES = ('docs/CREDITS.md', 'client/overlay/modules/client_chaos_credits/credits_data.lua',
                 'website/overlay/plugins/chaos/credits/credits_data.json')
SKIP = ('client/base-patches/', 'tools/ci/check_names.py')
files = subprocess.check_output(['git', 'ls-files'], text=True).split('\n')
bad = 0
for f in files:
    if not f or f.startswith(SKIP) or f.endswith(('.png', '.jpg', '.dat', '.spr', '.ico')):
        continue
    try:
        text = open(f, encoding='utf-8').read()
    except (UnicodeDecodeError, FileNotFoundError):
        continue
    for i, line in enumerate(text.split('\n'), 1):
        if DENY.search(line) or (f not in CREDITS_FILES and ART_PACKS.search(line)):
            print(f'{f}:{i}: {line.strip()[:100]}'); bad += 1
    if DENY.search(f) or ART_PACKS.search(f):
        print(f'{f}: file name'); bad += 1
print('names check:', 'OK' if not bad else f'{bad} hit(s)')
sys.exit(1 if bad else 0)
