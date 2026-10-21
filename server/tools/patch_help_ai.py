#!/usr/bin/env python3
"""Ember, the Help channel assistant: the hook in the Help channel script (data/scripts/chaos/helpai.lua).

usage: python3 -I patch_help_ai.py DATA_DIR [--dry-run]

data/chatchannels/scripts/help.lua: onSpeak calls ChaosHelpAI.onHelpSpeak(player, type, message) right before its last
`return type`, so only lines that passed every base check (level 1, Help channel mute, tutor commands) and the other
Chaos hooks reach it. The hook never changes or holds back the player's line; it may queue it for the sidecar
(server/tools/helpai.py). Idempotent: the change carries a marker and is not made twice. Run it again after replacing
the base file.
"""
import os
import re
import sys

MARKER = '-- Chaos: Ember, the Help channel assistant (patch_help_ai.py)'
HOOK = (
    '\t' + MARKER + '\n'
    '\tif ChaosHelpAI and ChaosHelpAI.onHelpSpeak then ChaosHelpAI.onHelpSpeak(player, type, message) end\n'
)


def patch(text):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    if MARKER in text:
        return text, 'already'
    m = re.search(r'function onSpeak\(player, type, message\)[ \t]*\r?\n', text)
    if not m:
        return text, 'function onSpeak(player, type, message) not found'
    # the function's own last line: `return type` with one tab, followed by the `end` of onSpeak
    last = None
    for r in re.finditer(r'(?m)^\treturn type[ \t]*\r?\nend\b', text[m.end():]):
        last = r
    if not last:
        return text, '`return type` at the end of onSpeak not found'
    at = m.end() + last.start()
    hook = HOOK.replace('\n', '\r\n') if '\r\n' in text else HOOK
    return text[:at] + hook + text[at:], 'patched'


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    rel = 'chatchannels/scripts/help.lua'
    path = os.path.join(args[0], rel)
    if not os.path.isfile(path):
        print('%s: not found' % path)
        return 1
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, st = patch(text)
    if st not in ('patched', 'already'):
        print('%s: %s' % (rel, st))
        return 1
    if st == 'patched' and not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
    print('%s: %s%s' % (rel, st, ' (dry run, not written)' if dry and st == 'patched' else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
