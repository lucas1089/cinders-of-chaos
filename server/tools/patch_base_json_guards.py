#!/usr/bin/env python3
"""The base server's extended opcode handlers accept only a JSON object (idempotent). install_all.py step `jsonguards`.

usage: python3 -I patch_base_json_guards.py DATA_DIR [--dry-run]

DATA_DIR is the base server's data folder. Found by the network fuzzer (server/README.md "Engine hardening (sanitizers,
fuzzing)"): the base handlers decode the client's JSON and then index the result. A payload that is valid JSON but not
an object (`1`, `"x"`, `true`) made them index a number or a string: a Lua error and a "Lua Script Error" in the
server log for every such packet (game_store.lua:350 "attempt to index local 'json_data' (a number value)"). The tier
maps handler did not even catch a decode error. Each handler now returns, like it does for bad JSON, when the decoded
value is not a table, and the tasks handler also when its "data" is not one. No change for a valid client: it always
sends an object.

Files (each a marker line `-- Chaos: JSON object guard (patch_base_json_guards.py)` on top; a second run changes
nothing; a file whose code is not the expected text is refused, exit 1, nothing written; a missing file is skipped):
  creaturescripts/scripts/game_store.lua                   store, opcode 201
  scripts/customs/tasks/tasks.lua                          tasks, opcode 92
  scripts/customs/waystone_system/character_upgrades.lua   upgrades, opcode 181
  scripts/customs/stats_inspect/inspect.lua                inspect, opcode 107
  scripts/customs/stats_inspect/character_stats.lua        character stats, opcode 106
  scripts/customs/waystone_system/tier_maps.lua            waystone device, opcode 202
"""
import os
import sys

MARKER = '-- Chaos: JSON object guard (patch_base_json_guards.py)'

STORE = ('  local status, json_data = pcall(function() return json.decode(buffer) end)\n'
         '  if not status then\n'
         '    print("DEBUG Server: failed to decode buffer")\n'
         '    return false\n'
         '  end \n',  # the base line ends with a space
         '  local status, json_data = pcall(function() return json.decode(buffer) end)\n'
         '  if not status then\n'
         '    print("DEBUG Server: failed to decode buffer")\n'
         '    return false\n'
         '  end \n'
         '  if type(json_data) ~= "table" then return false end -- Chaos: JSON object guard\n')

TASKS = ('      local action = json_data.action\n      local data = json_data.data\n',
         '      if type(json_data) ~= "table" or type(json_data.data) ~= "table" then return false end -- Chaos: JSON object guard\n'
         '      local action = json_data.action\n      local data = json_data.data\n')

UPGRADES = ('\t\tlocal action = json_data.action\n\t\tlocal data = json_data.data\n',
            '\t\tif type(json_data) ~= "table" then return end -- Chaos: JSON object guard\n'
            '\t\tlocal action = json_data.action\n\t\tlocal data = json_data.data\n')

STATS = ('    local action = json_data.action\n    local data = json_data.data\n',
         '    if type(json_data) ~= "table" then return end -- Chaos: JSON object guard\n'
         '    local action = json_data.action\n    local data = json_data.data\n')

TIER = ('''  local data = json.decode(buffer)
  if not data or not data.action then return false end
''', '''  local decoded, data = pcall(json.decode, buffer) -- Chaos: JSON object guard
  if not decoded or type(data) ~= "table" or not data.action then return false end
''')

FILES = [
    ('creaturescripts/scripts/game_store.lua', [STORE]),
    ('scripts/customs/tasks/tasks.lua', [TASKS]),
    ('scripts/customs/waystone_system/character_upgrades.lua', [UPGRADES]),
    ('scripts/customs/stats_inspect/inspect.lua', [STATS]),
    ('scripts/customs/stats_inspect/character_stats.lua', [STATS]),
    ('scripts/customs/waystone_system/tier_maps.lua', [TIER]),
]


def patch(text, edits):
    """(new text, changed, error); text with LF line ends"""
    if MARKER in text:
        return text, False, None
    for old, new in edits:
        if text.count(old) != 1:
            return text, False, 'REFUSED: expected code found %d times, want once' % text.count(old)
        text = text.replace(old, new)
    return MARKER + '\n' + text, True, None


def main(argv):
    args = [a for a in argv if a != '--dry-run']
    dry = '--dry-run' in argv
    if len(args) != 1 or args[0].startswith('-'):
        print(__doc__)
        return 1
    plans = []
    for rel, edits in FILES:
        path = os.path.join(args[0], *rel.split('/'))
        if not os.path.isfile(path):
            print('%s: not found (skipped)' % rel)
            continue
        with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
            text = f.read()
        crlf = '\r\n' in text
        new, changed, err = patch(text.replace('\r\n', '\n'), edits)
        if err:
            print('%s: %s (nothing written)' % (rel, err))
            return 1
        if changed:
            plans.append((rel, path, new.replace('\n', '\r\n') if crlf else new))
    for rel, path, new in plans:
        if not dry:
            with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
                f.write(new)
        print('%s: handler accepts only a JSON object' % rel)
    print('json guards: %d file(s) %s' % (len(plans), 'would change' if dry else 'changed') if plans
          else 'json guards: nothing to change')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
