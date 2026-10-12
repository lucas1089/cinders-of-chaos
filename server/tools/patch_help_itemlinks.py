#!/usr/bin/env python3
"""Keeps item links out of the Help channel (data/scripts/chaos/itemlink.lua).

usage: python3 -I patch_help_itemlinks.py DATA_DIR [--dry-run]

data/chatchannels/scripts/help.lua: onSpeak asks ChaosItemLink.helpBlocks(player, message) right after the level check;
a message with an item link from a player below tutor is refused ("Item links are not allowed in the Help channel.").
The client refuses to put a link into a Help message already; this is the server side of the rule, for modified clients.
Idempotent: the change carries a marker and is not made twice. Run it again after replacing the base file.
"""
import os, re, sys

MARKER = '-- Chaos: no item links in the Help channel (patch_help_itemlinks.py)'
HOOK = (
    '\t' + MARKER + '\n'
    '\tif ChaosItemLink and ChaosItemLink.helpBlocks and ChaosItemLink.helpBlocks(player, message) then\n'
    '\t\tplayer:sendCancelMessage("Item links are not allowed in the Help channel.")\n'
    '\t\treturn false\n'
    '\tend\n'
    '\n'
)


def patch(text):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    if MARKER in text:
        return text, 'already'
    m = re.search(r'function onSpeak\(player, type, message\)[ \t]*\r?\n', text)
    if not m:
        return text, 'function onSpeak(player, type, message) not found'
    # after the level check (its block ends with `return false` and `end`), else right at the top
    level = re.search(r'if player:getLevel\(\) == 1.*?\r?\n\t\treturn false\r?\n\tend\r?\n\r?\n', text[m.end():], re.S)
    at = m.end() + level.end() if level else m.end()
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
