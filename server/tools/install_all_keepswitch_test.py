#!/usr/bin/env python3
"""Test of tools/install_all.py keep_switch: an update copies beta_mode_config.lua but keeps the installed `enabled` value
(chaos-ctl.sh beta-mode, the admin app), so a deploy never turns beta test mode off or on by itself.

Run: python3 -I server/tools/install_all_keepswitch_test.py (standard library only)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import install_all as I  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL ' + what)


KEY = 'scripts/chaos/beta_mode_config.lua'
repo = open(os.path.join(I.REPO_DATA, KEY), encoding='utf-8').read()
check(KEY in I.KEEP_SWITCH, 'the file is in KEEP_SWITCH')
check('\n\tenabled = false,' in repo, 'the repo file ships the switch off')
on = repo.replace('\tenabled = false,', '\tenabled = true,', 1)
check(I.keep_switch(KEY, repo, on) == on, 'installed on stays on after a copy of the repo file')
check(I.keep_switch(KEY, repo, repo) == repo, 'installed off stays off')
check(I.keep_switch(KEY, repo, None) == repo, 'first install: the repo value')
check(I.keep_switch(KEY, on, repo) == repo, 'the installed value wins over the repo value')
newer = repo + '-- a newer comment\n'
check(I.keep_switch(KEY, newer, on) == newer.replace('\tenabled = false,', '\tenabled = true,', 1),
      'new repo text with the installed switch')
check(I.keep_switch('scripts/chaos/other.lua', repo, on) == repo, 'other files are copied as they are')
if failed:
    sys.exit(1)
print('install_all_keepswitch_test: ok')
