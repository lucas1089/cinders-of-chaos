#!/usr/bin/env python3
"""The base item fusion (opcode 67) takes only plain copies (idempotent). install_all.py step `fusionplain`.

usage: python3 -I patch_base_fusion_plain.py DATA_DIR [--dry-run]

DATA_DIR is the base server's data folder. File: scripts/customs/item_fusion/item_fusion.lua. O511: on "fuse" the base
script ran player:removeItem(id, 3). The engine takes by item id, the first three copies it meets (head, necklace, the
backpack and everything in it, then the other slots), so a fusion of three plain copies could take a unique, a set
piece or a rolled copy of the same base. Now:

  * the script loads data/scripts/chaos/item_fusion_core.lua once with pcall (`take`);
  * "fuse" calls take(player, id, 3): it counts and removes only plain copies (no lock, unique, set, raid, faction or
    store mark, no rarity, modifiers, +N level, sockets, gems, quality or transmog look, no filled container);
  * fewer than three plain copies: nothing is removed, the script's own answer "You do not have enough items.";
  * the core missing or broken: nothing fuses (fail closed).

The allowlist of patch_base_fusion_allowlist.py is not touched; the two steps run in any order. The marker line
`-- Chaos: fusion plain copies (patch_base_fusion_plain.py)` goes on top; a second run changes nothing; a file whose
code is not the expected text is refused, exit 1, nothing written; a missing file is skipped. CRLF files stay CRLF.
"""
import os
import sys

MARKER = '-- Chaos: fusion plain copies (patch_base_fusion_plain.py)'
TAG = '-- Chaos: fusion plain copies'
REL = 'scripts/customs/item_fusion/item_fusion.lua'

LOAD = ('local itemFusionExtended = CreatureEvent("ItemFusionExtended")\n',
        TAG + ': the rule that takes the copies of a fusion; no rule, no fusion\n'
        'local fusionTake = function() return false end\n'
        'do\n'
        '  local coreOk, core = pcall(dofile, "data/scripts/chaos/item_fusion_core.lua")\n'
        '  if coreOk and type(core) == "table" and type(core.take) == "function" then\n'
        '    fusionTake = core.take\n'
        '  end\n'
        'end\n'
        '\n'
        'local itemFusionExtended = CreatureEvent("ItemFusionExtended")\n')

TAKE = ('    if player:removeItem(convertedFirstId, 3) then\n',
        '    if fusionTake(player, convertedFirstId, 3) == true then ' + TAG + '\n')

EDITS = [LOAD, TAKE]


def patch(text):
    """(new text, changed, error); text with LF line ends"""
    if MARKER in text:
        return text, False, None
    new = text
    for old, repl in EDITS:
        if new.count(old) != 1:
            return text, False, 'REFUSED: expected code found %d times, want once: %s' % (new.count(old), old.strip()[:60])
        new = new.replace(old, repl)
    if 'removeItem(' in new:
        return text, False, 'REFUSED: another removeItem call is in the file, the fusion would still take by id'
    return MARKER + '\n' + new, True, None


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    path = os.path.join(args[0], *REL.split('/'))
    if not os.path.isfile(path):
        print('%s: not found (skipped)' % REL)
        print('fusion plain copies: nothing to change')
        return 0
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    crlf = '\r\n' in text
    new, changed, err = patch(text.replace('\r\n', '\n'))
    if err:
        print('%s: %s (nothing written)' % (REL, err))
        return 1
    if not changed:
        print('fusion plain copies: nothing to change')
        return 0
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new.replace('\n', '\r\n') if crlf else new)
    print('%s: fusion takes only plain copies' % REL)
    print('fusion plain copies: 1 file %s' % ('would change' if dry else 'changed'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
