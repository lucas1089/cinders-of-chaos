#!/usr/bin/env python3
"""Monster debuffs last at most 10 s (idempotent).

usage: python3 -I patch_debuff_durations.py DATA_DIR [--dry-run]

Owner, 2026-10-20 (beta): "deixe debuffs padrões durarem 10s, em vez de 1min". The stock monsters slowed a player for up
to 60 s (speed), turned them into a rabbit or a chicken for 60 s (outfit) and made them drunk for 25 s. Every
<attack> of a monster file under DATA_DIR/monster whose name is a debuff (DEBUFFS) and whose duration is over
MAX_MS gets duration MAX_MS. Defenses (a monster's own haste or disguise) and damage attacks are never touched; a
shorter debuff keeps its duration. The Chaos monsters (data/monster/monsters/chaos) follow the same rule in the
repository, so this changes nothing there.
"""
import os, re, sys

MAX_MS = 10000
DEBUFFS = ('speed', 'drunk', 'outfit', 'strength', 'skill', 'weakness')
TAG = re.compile(r'<attack\b[^>]*>')
NAME = re.compile(r'\bname="([^"]*)"')
DURATION = re.compile(r'(\bduration=")(\d+)(")')


def patch_text(text):
    """returns (new text, number of attacks shortened)"""
    count = 0

    def fix(m):
        nonlocal count
        tag = m.group(0)
        name = NAME.search(tag)
        dur = DURATION.search(tag)
        if not name or name.group(1).lower() not in DEBUFFS or not dur or int(dur.group(2)) <= MAX_MS:
            return tag
        count += 1
        return DURATION.sub(lambda d: d.group(1) + str(MAX_MS) + d.group(3), tag, count=1)

    return TAG.sub(fix, text), count


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__)
        return 2
    root = os.path.join(args[0], 'monster')
    if not os.path.isdir(root):
        print('no monster folder: %s' % root)
        return 1
    files = total = 0
    for base, _, names in os.walk(root):
        for n in sorted(names):
            if not n.endswith('.xml'):
                continue
            path = os.path.join(base, n)
            text = open(path, encoding='latin-1').read()
            new, count = patch_text(text)
            if count:
                files += 1
                total += count
                if not dry:
                    open(path, 'w', encoding='latin-1', newline='').write(new)
    print('debuff durations: %d attack(s) in %d monster file(s) cut to %d ms%s'
          % (total, files, MAX_MS, ' (dry run)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
