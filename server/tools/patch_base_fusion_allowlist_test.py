#!/usr/bin/env python3
"""Tests of patch_base_fusion_allowlist.py on a stock excerpt of the base item fusion script (after the opcode input
step), LF and CRLF, plus a Lua run of the patched excerpt when luajit is present.

Run: python3 -I server/tools/patch_base_fusion_allowlist_test.py (standard library only)."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import patch_base_fusion_allowlist as P  # noqa: E402
import patch_base_opcode_inputs as O  # noqa: E402

fails = []


def ok(cond, what):
    if not cond:
        fails.append(what)


STOCK = '''local itemFusionOpcode = 67
local clientToServerMapping = {
  [3079] = 2195, -- Boots of Haste
  [3366]  = 2472, -- Magic Plate Armor
}
local function convertClientToServer(clientId)
  return clientToServerMapping[clientId] or clientId
end
local function isEquipment(id) return id == 2195 or id == 2472 end
local itemFusionExtended = CreatureEvent("ItemFusionExtended")

function itemFusionExtended.onExtendedOpcode(player, opcode, buffer)

  if opcode ~= itemFusionOpcode then
    return false
  end

  local data = json.decode(buffer)
  if not data or type(data) ~= "table" then
    return false
  end

  if data.action == "clear_items" then
    return true
  elseif data.action == "added_item" then
    if not data.item then
      return true
    end
    return true
  elseif data.action == "fuse" then
    if not data.items or #data.items < 3 then
      return true
    end
    local firstClientId = data.items[1].clientId
    local convertedFirstId = convertClientToServer(firstClientId)
    if not isEquipment(convertedFirstId) then
      player:sendExtendedOpcode(itemFusionOpcode, json.encode({action = "invalid_item", message = "Not equipment."}))
      return true
    end
    if player:removeItem(convertedFirstId, 3) then
      player:sendExtendedOpcode(itemFusionOpcode, json.encode({action = "fused_success", outputId = 29619}))
    end
    return true
  end
  return true
end
'''
# the stock text first goes through the opcode input step (the order install_all.py uses)
inputs = O.patch(STOCK, [O.FUSION_DECODE, O.FUSION_ITEM, O.FUSION_ITEMS, O.FUSION_ENTRIES])
ok(inputs[2] is None and inputs[1], 'opcode input step takes the excerpt: %s' % (inputs[2],))
PRE = inputs[0]

new, changed, err = P.patch(PRE)
ok(changed and err is None and new.startswith(P.MARKER + '\n'), 'patched, marker on top')
ok(new.count(P.MARKER) == 1, 'one marker')
ok('fusionAllowed = {}' in new and 'pcall(dofile, "data/scripts/chaos/item_fusion_config.lua")' in new, 'list loaded with pcall, empty default')
ok(new.index('fusionAllowed[data.items[i].clientId]') < new.index('removeItem'), 'check runs before the items are taken')
again, changed2, err2 = P.patch(new)
ok(again == new and not changed2 and err2 is None, 'idempotent')
_, c3, e3 = P.patch('-- Chaos: opcode input check\nfunction onExtendedOpcode() end\n')
ok(not c3 and e3 and e3.startswith('REFUSED'), 'refused on unknown code')
_, _, e4 = P.patch(PRE + PRE)
ok(e4 and 'found 2 times' in e4, 'refused when the code is there twice')
_, c5, e5 = P.patch(STOCK)
ok(not c5 and e5 and 'opcode_inputs' in e5, 'refused before the opcode input step')
part = PRE.replace(P.CHECK[0], '')
out6, c6, e6 = P.patch(part)
ok(not c6 and e6 and out6 == part, 'refused when one anchor is missing')

# main: dry run, write, CRLF kept, second run, a missing file skipped
d = tempfile.mkdtemp()
try:
    path = os.path.join(d, *P.REL.split('/'))
    os.makedirs(os.path.dirname(path))
    ok(P.main([d]) == 0 and not os.path.exists(path), 'missing file skipped')
    with open(path, 'w', newline='') as f:
        f.write(PRE.replace('\n', '\r\n'))
    ok(P.main([d, '--dry-run']) == 0 and P.MARKER not in open(path, newline='').read(), 'dry run writes nothing')
    ok(P.main([d]) == 0, 'writes')
    raw = open(path, newline='').read()
    ok(raw.startswith(P.MARKER + '\r\n') and '\n' not in raw.replace('\r\n', ''), 'CRLF kept')
    ok(P.main([d]) == 0 and open(path, newline='').read() == raw, 'second run changes nothing')
    with open(path, 'w', newline='') as f:
        f.write('local x = 1\n')
    ok(P.main([d]) == 1 and open(path).read() == 'local x = 1\n', 'refusal writes nothing')
    ok(P.main([]) == 1, 'usage')
finally:
    shutil.rmtree(d, ignore_errors=True)

# Lua run: an allowed id fuses, a cheap equipment id is refused, no list means nothing fuses
LUAJIT = shutil.which('luajit')
if LUAJIT:
    d = tempfile.mkdtemp()
    try:
        os.makedirs(os.path.join(d, 'data', 'scripts', 'chaos'))
        cfg = os.path.join(d, 'data', 'scripts', 'chaos', 'item_fusion_config.lua')
        src = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'item_fusion_config.lua')
        shutil.copy(src, cfg)
        script = new.replace('\r\n', '\n')
        lua = os.path.join(d, 'run.lua')
        driver = '''
json = {decode = function(s) local f = loadstring("return " .. s) return f() end,
        encode = function(t) return (t.action or "?") .. "|" .. tostring(t.outputId or t.message) end}
function CreatureEvent(name) return {type = function() end, register = function() end} end
local handler
CreatureEvent = function(name)
  local ev = {type = function() end, register = function() end}
  if name == "ItemFusionExtended" then handler = ev end
  return ev
end
dofile("item.lua")
local function try(ids)
  local out, taken = {}, 0
  local p = {sendExtendedOpcode = function(_, _, s) out[#out + 1] = s end,
             removeItem = function(_, id, n) taken = taken + n return true end}
  local items = {}
  for i = 1, 3 do items[i] = "{clientId = " .. ids[i] .. "}" end
  handler.onExtendedOpcode(p, 67, "{action = 'fuse', items = {" .. table.concat(items, ",") .. "}}")
  return out[1], taken
end
local a, ta = try({3079, 3079, 3079})
local b, tb = try({3079, 3079, 3031})   -- one unlisted id among listed ones
local c, tc = try({2195, 2195, 2195})   -- the server id the table maps to is not on the list
local d, td = try({3031, 3031, 3031})   -- gold coin: cheap
print(a, ta); print(b, tb); print(c, tc); print(d, td)
'''
        with open(os.path.join(d, 'item.lua'), 'w') as f:
            f.write(script)
        with open(lua, 'w') as f:
            f.write(driver)
        r = subprocess.run([LUAJIT, 'run.lua'], cwd=d, capture_output=True, text=True)
        lines = r.stdout.split('\n')
        ok(r.returncode == 0 and lines[0] == 'fused_success|29619\t3', 'allowed id fuses and takes 3: %r %r' % (r.stdout, r.stderr))
        ok(len(lines) > 3 and lines[1].startswith('invalid_item|') and lines[1].endswith('\t0'), 'mixed list refused, nothing taken: %r' % r.stdout)
        ok(len(lines) > 3 and lines[2].startswith('invalid_item|This item cannot be fused.') and lines[2].endswith('\t0'), 'mapped server id refused')
        ok(len(lines) > 3 and lines[3] == 'invalid_item|This item cannot be fused.\t0', 'cheap id refused, nothing taken')
        # fail closed: list missing, and list broken
        for what in ('missing', 'broken'):
            if what == 'missing':
                os.remove(cfg)
            else:
                with open(cfg, 'w') as f:
                    f.write('return 5 +')
            r = subprocess.run([LUAJIT, 'run.lua'], cwd=d, capture_output=True, text=True)
            ls = r.stdout.split('\n')
            ok(r.returncode == 0 and ls[0] == 'invalid_item|This item cannot be fused.\t0', 'list %s: nothing fuses: %r %r' % (what, r.stdout, r.stderr))
    finally:
        shutil.rmtree(d, ignore_errors=True)

# the shipped list: a table of whole-number client ids set to true, no cheap stackable or currency ids
cfgpath = os.path.join(HERE, '..', 'data', 'scripts', 'chaos', 'item_fusion_config.lua')
text = open(cfgpath).read()
ok(text.count('= true,') >= 100 and '[3031]' not in text and '[2148]' not in text, 'shipped list has equipment, no gold coin')

if fails:
    print('FAILED:')
    for f in fails:
        print('  ' + f)
    sys.exit(1)
print('patch_base_fusion_allowlist_test: ok')
