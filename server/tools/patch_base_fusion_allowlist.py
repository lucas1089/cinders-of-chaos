#!/usr/bin/env python3
"""The base item fusion (opcode 67) fuses only the ids of a Chaos list (idempotent). install_all.py step `fusionlist`.

usage: python3 -I patch_base_fusion_allowlist.py DATA_DIR [--dry-run]

DATA_DIR is the base server's data folder. File: scripts/customs/item_fusion/item_fusion.lua. Owner decision O310: the
base script turned any 3 identical items the player held into an Upgrade Rune v1-v4, cheap equipment too. Now:

  * the script loads data/scripts/chaos/item_fusion_config.lua once (`clientIds`, a set of client ids) with pcall;
  * "fuse" answers {action = "invalid_item", message = "This item cannot be fused."} when any sent clientId is not in
    the set, before an item is counted or taken;
  * the list missing, broken or not a table: the set is empty, nothing fuses (fail closed).

Run after patch_base_opcode_inputs.py (the second anchor is the line below its entry check). The marker line
`-- Chaos: fusion allowlist (patch_base_fusion_allowlist.py)` goes on top; a second run changes nothing; a file whose
code is not the expected text is refused, exit 1, nothing written; a missing file is skipped. CRLF files stay CRLF.
"""
import os
import sys

MARKER = '-- Chaos: fusion allowlist (patch_base_fusion_allowlist.py)'
TAG = '-- Chaos: fusion allowlist'
REL = 'scripts/customs/item_fusion/item_fusion.lua'

LOAD = ('local itemFusionExtended = CreatureEvent("ItemFusionExtended")\n',
        '-- ' + TAG + ': the ids that may be fused; no list, no fusion\n'
        'local fusionAllowed = {}\n'
        'do\n'
        '  local listOk, list = pcall(dofile, "data/scripts/chaos/item_fusion_config.lua")\n'
        '  if listOk and type(list) == "table" and type(list.clientIds) == "table" then\n'
        '    fusionAllowed = list.clientIds\n'
        '  end\n'
        'end\n'
        '\n'
        'local itemFusionExtended = CreatureEvent("ItemFusionExtended")\n')

CHECK = ('    local firstClientId = data.items[1].clientId\n',
         '    for i = 1, #data.items do -- ' + TAG + '\n'
         '      if fusionAllowed[data.items[i].clientId] ~= true then\n'
         '        player:sendExtendedOpcode(itemFusionOpcode, json.encode({action = "invalid_item", message = "This item cannot be fused."}))\n'
         '        return true\n'
         '      end\n'
         '    end\n'
         '    local firstClientId = data.items[1].clientId\n')

EDITS = [LOAD, CHECK]
# the entry check of patch_base_opcode_inputs.py must be there first: the allowlist reads clientId unchecked
NEEDS = 'Chaos: opcode input check'


def patch(text):
    """(new text, changed, error); text with LF line ends"""
    if MARKER in text:
        return text, False, None
    if NEEDS not in text:
        return text, False, 'REFUSED: run patch_base_opcode_inputs.py first (no entry check in the file)'
    new = text
    for old, repl in EDITS:
        if new.count(old) != 1:
            return text, False, 'REFUSED: expected code found %d times, want once: %s' % (new.count(old), old.strip()[:60])
        new = new.replace(old, repl)
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
        print('fusion allowlist: nothing to change')
        return 0
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    crlf = '\r\n' in text
    new, changed, err = patch(text.replace('\r\n', '\n'))
    if err:
        print('%s: %s (nothing written)' % (REL, err))
        return 1
    if not changed:
        print('fusion allowlist: nothing to change')
        return 0
    if not dry:
        with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new.replace('\n', '\r\n') if crlf else new)
    print('%s: fusion allowlist added' % REL)
    print('fusion allowlist: 1 file %s' % ('would change' if dry else 'changed'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
