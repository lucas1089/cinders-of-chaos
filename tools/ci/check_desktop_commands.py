#!/usr/bin/env python3
"""Desktop admin app (O312, desktop/): its command table must name the same chaos-ctl.sh commands as the Android admin app.
Fails when
  - a chaos-ctl.sh command the Android app calls is missing from desktop/src/commands.rs (EXTRA_ANDROID lists the few
    that stay Android only, each with the reason),
  - a command of the table is not a command of server/deploy/chaos-ctl.sh.

  python3 -I tools/ci/check_desktop_commands.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TABLE = os.path.join(ROOT, 'desktop', 'src', 'commands.rs')
CTL = os.path.join(ROOT, 'server', 'deploy', 'chaos-ctl.sh')
JAVA = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'java', 'com', 'cindersofchaos', 'admin')

# Android only: live streams and pictures (phase 2 of O312), the in-game panel (the desktop has its own "Painel do
# jogo" page that calls catalog / panel), key and install helpers of the phone.
ANDROID_ONLY = {'spectate', 'cast', 'catalog', 'panel', 'install-admin'}
ACT = re.compile(r'^\s*act\(\s*\w+,\s*"[^"]*",\s*"[^"]*",\s*"([^"]+)"', re.M)
# a literal first word of a chaos-ctl.sh command in the Android sources: ctl("title", "word ...") / ctl("word ...")
JAVA_CMD = re.compile(r'\b(?:ctl|ctlq|runCtl)\(\s*(?:"[^"]*"\s*,\s*)?"([a-z][a-z-]+)[ "]')
JAVA_VAR = re.compile(r'\b(?:args|cmd|mode)\s*[=+]\s*\(?"([a-z][a-z-]+)[ "]')
CASE = re.compile(r'^  ([a-z][a-z|-]*)\)', re.M)


def desktop_words():
    return {t.split()[0] for t in ACT.findall(open(TABLE, encoding='utf-8').read())}


def ctl_words():
    out = set()
    for m in CASE.findall(open(CTL, encoding='utf-8').read()):
        out.update(m.split('|'))
    return out


def android_words():
    out = set()
    for f in os.listdir(JAVA):
        if f.endswith('.java'):
            t = open(os.path.join(JAVA, f), encoding='utf-8').read()
            out.update(JAVA_CMD.findall(t))
            out.update(JAVA_VAR.findall(t))
    return out


def main():
    d, c, a = desktop_words(), ctl_words(), android_words()
    bad = []
    if len(d) < 30:
        bad.append('desktop table read %d commands, expected 30 or more (format changed?)' % len(d))
    for w in sorted(d - c):
        bad.append('desktop command "%s" is not a command of chaos-ctl.sh' % w)
    for w in sorted((a & c) - d - ANDROID_ONLY):
        bad.append('Android calls "%s" but desktop/src/commands.rs has no action for it' % w)
    for w in sorted(ANDROID_ONLY & d):
        bad.append('ANDROID_ONLY lists "%s", which the desktop table has: remove it from the set' % w)
    for w in sorted(ANDROID_ONLY - c):
        bad.append('ANDROID_ONLY lists "%s", which chaos-ctl.sh does not have' % w)
    for b in bad:
        print('FAIL', b)
    if not bad:
        print('desktop commands ok: %d in the table, %d seen in the Android app' % (len(d), len(a)))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
