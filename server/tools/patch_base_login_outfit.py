#!/usr/bin/env python3
"""No outfit window at a character's first login (O761, owner 2026-11-24: the first login shows the Daily Reward window only;
server/README.md "Quiet first login (O761)").

usage: python3 -I patch_base_login_outfit.py DATA_DIR [--dry-run]

The stock data/creaturescripts/scripts/login.lua opens the outfit window (the client's Customise Character window) when
player:getLastLoginSaved() is 0 and adds " Please choose your outfit." to the welcome line. Both lines of that first-login
branch are commented out, under a marker line; nothing else of the file changes (the else branch, the demotion fix of
patch_base_events.py, the events). The outfit window comes later, once, as an introduction (data/scripts/chaos/intros.lua,
intros_config.lua `outfit`). A file without the call is left alone. Idempotent; LF and CRLF. install_all.py step `loginoutfit`.
"""
import os
import re
import sys

MARKER = '-- Chaos: no outfit window at the first login, it comes later as an introduction (O761, patch_base_login_outfit.py)'
START = re.compile(r'if[ \t]+player:getLastLoginSaved\(\)[ \t]*(?:<=|==)[ \t]*0[ \t]+then[^\r\n]*\r?\n')
END = re.compile(r'^[ \t]*(?:else|elseif|end)\b', re.M)
HIT = re.compile(r'sendOutfitWindow\(\)|Please choose your outfit')


def patch(text):
    """(new text, status): status 'patched', 'already' or 'nothing' (no outfit window in a first-login branch)"""
    if MARKER in text:
        return text, 'already'
    m = START.search(text)
    if not m:
        return text, 'nothing'
    body_start = m.end()
    e = END.search(text, body_start)
    body_end = e.start() if e else len(text)
    body = text[body_start:body_end]
    lines = body.splitlines(True)
    out, hit, indent, eol = [], False, '\t', '\n'
    for line in lines:
        core = line.rstrip('\r\n')
        if HIT.search(core) and not core.lstrip().startswith('--'):
            lead = core[:len(core) - len(core.lstrip())]
            if not hit:
                indent, eol = lead, line[len(core):] or '\n'
                out.append(lead + MARKER + eol)
            hit = True
            out.append(lead + '-- ' + core.lstrip() + line[len(core):])
        else:
            out.append(line)
    if not hit:
        return text, 'nothing'
    return text[:body_start] + ''.join(out) + text[body_end:], 'patched'


def main(argv):
    args = list(argv)
    dry = '--dry-run' in args
    args = [a for a in args if a != '--dry-run']
    if len(args) != 1:
        print(__doc__)
        return 1
    path = os.path.join(args[0], 'creaturescripts', 'scripts', 'login.lua')
    if not os.path.isfile(path):
        print('%s: no creaturescripts/scripts/login.lua' % args[0])
        return 1
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, status = patch(text)
    if status == 'patched' and not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('login.lua: %s%s' % ({'patched': 'the first-login outfit window removed', 'already': 'already patched',
                                'nothing': 'no outfit window at the first login, nothing to do'}[status],
                               ' (dry run)' if dry and status == 'patched' else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
