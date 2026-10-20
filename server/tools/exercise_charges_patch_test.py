#!/usr/bin/env python3
"""Test of patch_base_events.patch_exercise_charges on the stock exercise_weapons.lua line (no game data; CI runs it).

    python3 -I server/tools/exercise_charges_patch_test.py

The charge count of an exercise weapon is sent to the client again: setAttribute then item:sendUpdate() (engine patch
0003), else a transform to the same id with the new count; the last charge keeps setAttribute; the first version's
block (transform only) is upgraded; a second run changes nothing; an unknown file is refused. When luajit or lua5.3 is
installed the patched lines also run against a mocked item.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import patch_base_events as P  # noqa: E402

STOCK = '''                            local charges_n = exercise:getAttribute(ITEM_ATTRIBUTE_CHARGES)
                            if charges_n >= 1 then
                                exercise:setAttribute(ITEM_ATTRIBUTE_CHARGES, (charges_n - 1))
                                local voc = player:getVocation():getId()
'''
fails = []


def check(cond, what):
    if not cond:
        fails.append(what)


new, status = P.patch_exercise_charges(STOCK)
check(status == 'patched', 'patched (got %s)' % status)
check('exercise:sendUpdate()' in new, 'sendUpdate sends the new charges')
check('exercise:transform(exercise:getId(), charges_n - 1)' in new, 'the transform is the fallback')
check('exercise:setAttribute(ITEM_ATTRIBUTE_CHARGES, 0)' in new, 'the last charge keeps setAttribute')
check('local voc = player:getVocation():getId()' in new, 'the rest of the script is kept')
again, status2 = P.patch_exercise_charges(new)
check(status2 == 'already' and again == new, 'a second run changes nothing')
other, status3 = P.patch_exercise_charges('local x = 1\n')
check(status3.startswith('unexpected'), 'an unknown file is refused')

# a file patched by the first version (transform only) is upgraded to the same text as a stock file
IND = ' ' * 32
V1 = STOCK.replace(IND + 'exercise:setAttribute(ITEM_ATTRIBUTE_CHARGES, (charges_n - 1))\n',
                   IND + P.EXERCISE_MARKER + '\n'
                   + IND + 'if charges_n - 1 >= 1 then\n'
                   + IND + '\texercise:transform(exercise:getId(), charges_n - 1)\n'
                   + IND + 'else\n'
                   + IND + '\texercise:setAttribute(ITEM_ATTRIBUTE_CHARGES, 0)\n'
                   + IND + 'end\n')
check(V1 != STOCK, 'the first version block was built')
up, status4 = P.patch_exercise_charges(V1)
check(status4 == 'patched' and up == new, 'the first version is upgraded (got %s)' % status4)
odd, status5 = P.patch_exercise_charges(V1.replace('else\n', 'else -- edited\n'))
check(status5.startswith('unexpected'), 'an edited first version block is refused')
crlf, status6 = P.patch_exercise_charges(STOCK.replace('\n', '\r\n'))
check(status6 == 'patched' and '\r\n' + IND + 'if exercise.sendUpdate then\r\n' in crlf, 'CRLF line ends are kept')

# run the patched lines against a mocked item: what each engine does with charges 5 and 1
import shutil
import subprocess
block = new.split('\n', 2)[2].rsplit('local voc', 1)[0]
LUA = r"""
local function run(withUpdate, charges)
  local log = {}
  local exercise = {charges = charges}
  function exercise:setAttribute(k, v) log[#log + 1] = 'set ' .. v; self.charges = v end
  function exercise:getId() return 27737 end
  function exercise:transform(id, n) log[#log + 1] = 'transform ' .. id .. ' ' .. n; self.charges = n end
  if withUpdate then function exercise:sendUpdate() log[#log + 1] = 'update' end end
  local charges_n = charges
  if charges_n >= 1 then
%s
  end
  return table.concat(log, ',') .. '=' .. exercise.charges
end
ITEM_ATTRIBUTE_CHARGES = 4
print(run(true, 5)); print(run(true, 1)); print(run(false, 5)); print(run(false, 1))
""" % block
want = 'set 4,update=4\nset 0,update=0\ntransform 27737 4=4\nset 0=0\n'
ran = 0
for lua in ('luajit', 'lua5.3'):
    exe = shutil.which(lua)
    if not exe:
        continue
    out = subprocess.run([exe, '-'], input=LUA, capture_output=True, text=True)
    check(out.returncode == 0 and out.stdout == want, '%s runs the block (got %r %r)' % (lua, out.stdout, out.stderr))
    ran += 1
print('exercise_charges_patch_test: ran the block under %d Lua interpreter(s)' % ran)

if fails:
    for f in fails:
        print('FAIL ' + f)
    sys.exit(1)
print('exercise_charges_patch_test: OK')
