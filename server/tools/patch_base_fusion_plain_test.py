#!/usr/bin/env python3
"""Tests of patch_base_fusion_plain.py on a stock excerpt of the base item fusion script, alone and after the opcode
input and allowlist steps (both orders), LF and CRLF, plus a Lua run of the patched excerpt with the real core
(data/scripts/chaos/item_fusion_core.lua) and the real crafting rules when luajit or lua5.3 is present.

Run: python3 -I server/tools/patch_base_fusion_plain_test.py (standard library only)."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import patch_base_fusion_allowlist as A  # noqa: E402
import patch_base_fusion_plain as P  # noqa: E402
import patch_base_opcode_inputs as O  # noqa: E402

fails = []


def ok(cond, what):
    if not cond:
        fails.append(what)


# the lines of the base script the three steps touch, as the base server has them
STOCK = '''local itemFusionOpcode = 67
local clientToServerMapping = {
  [3079] = 2195, -- Boots of Haste
  [7384]  = 7384, -- a blade a unique is made of
}
local function convertClientToServer(clientId)
  return clientToServerMapping[clientId] or clientId
end
local function isEquipment(id) return id == 2195 or id == 7384 end
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
    local outputId = 29619

    if player:removeItem(convertedFirstId, 3) then
      player:addItem(outputId, 1)
      local response = { action = "fused_success", outputId = outputId }
      player:sendExtendedOpcode(itemFusionOpcode, json.encode(response))
    else
      local response = {
        action = "invalid_item",
        message = "You do not have enough items."
      }
      player:sendExtendedOpcode(itemFusionOpcode, json.encode(response))
    end
    return true
  end
  return true
end
'''

new, changed, err = P.patch(STOCK)
ok(changed and err is None and new.startswith(P.MARKER + '\n'), 'patched, marker on top: %s' % (err,))
ok(new.count(P.MARKER) == 1, 'one marker')
ok('removeItem' not in new, 'no removal by id is left')
ok('fusionTake(player, convertedFirstId, 3) == true' in new, 'the fusion asks the core for 3 copies')
ok('local fusionTake = function() return false end' in new, 'default: nothing fuses')
ok('pcall(dofile, "data/scripts/chaos/item_fusion_core.lua")' in new, 'core loaded with pcall')
ok('"You do not have enough items."' in new and 'player:addItem(outputId, 1)' in new, 'answer and reward lines untouched')
again, changed2, err2 = P.patch(new)
ok(again == new and not changed2 and err2 is None, 'idempotent')
_, c3, e3 = P.patch('function onExtendedOpcode() end\n')
ok(not c3 and e3 and e3.startswith('REFUSED'), 'refused on unknown code')
out4, c4, e4 = P.patch(STOCK + STOCK)
ok(not c4 and e4 and 'found 2 times' in e4 and out4 == STOCK + STOCK, 'refused when the code is there twice')
part = STOCK.replace(P.TAKE[0], '    if player:removeItem(convertedFirstId, 3, -1, true) then\n')
out5, c5, e5 = P.patch(part)
ok(not c5 and e5 and e5.startswith('REFUSED') and out5 == part, 'refused when the removal line is another text')
extra = STOCK.replace('    local outputId = 29619\n', '    local outputId = 29619\n    player:removeItem(2160, 1)\n')
out6, c6, e6 = P.patch(extra)
ok(not c6 and e6 and 'another removeItem' in e6 and out6 == extra, 'refused when a second removal by id is in the file')

# with the other two steps, in the install order and with the plain step first
inputs = O.patch(STOCK, [O.FUSION_DECODE, O.FUSION_ITEM, O.FUSION_ITEMS, O.FUSION_ENTRIES])
ok(inputs[2] is None and inputs[1], 'opcode input step takes the excerpt: %s' % (inputs[2],))
listed, lc, le = A.patch(inputs[0])
ok(lc and le is None, 'allowlist step takes the excerpt: %s' % (le,))
full, fc, fe = P.patch(listed)
ok(fc and fe is None and full.startswith(P.MARKER + '\n' + A.MARKER + '\n'), 'plain step after the allowlist: %s' % (fe,))
ok('fusionAllowed[data.items[i].clientId] ~= true' in full, 'the allowlist check is kept')
ok(full.index('fusionAllowed[data.items[i].clientId]') < full.index('fusionTake(player'), 'the allowlist runs before a copy is taken')
ok(A.patch(full) == (full, False, None) and P.patch(full) == (full, False, None), 'both steps idempotent on the result')
first, pc, pe = P.patch(inputs[0])
other, oc, oe = A.patch(first)
ok(pc and oc and pe is None and oe is None, 'the allowlist step still applies after the plain step: %s %s' % (pe, oe))
ok(sorted(other.split('\n')) == sorted(full.split('\n')), 'the same lines in either order (only the two load blocks swap)')
ok(other.index('fusionAllowed[data.items[i].clientId]') < other.index('fusionTake(player'), 'that order checks the list first too')

# main: dry run, write, CRLF kept, second run, a missing file skipped, refusal writes nothing
d = tempfile.mkdtemp()
try:
    path = os.path.join(d, *P.REL.split('/'))
    os.makedirs(os.path.dirname(path))
    ok(P.main([d]) == 0 and not os.path.exists(path), 'missing file skipped')
    with open(path, 'w', newline='') as f:
        f.write(listed.replace('\n', '\r\n'))
    ok(P.main([d, '--dry-run']) == 0 and P.MARKER not in open(path, newline='').read(), 'dry run writes nothing')
    ok(P.main([d]) == 0, 'writes')
    raw = open(path, newline='').read()
    ok(raw.startswith(P.MARKER + '\r\n') and '\n' not in raw.replace('\r\n', ''), 'CRLF kept')
    ok(raw.replace('\r\n', '\n') == full, 'the file is the patched text')
    ok(P.main([d]) == 0 and open(path, newline='').read() == raw, 'second run changes nothing')
    ok(A.main([d]) == 0 and open(path, newline='').read() == raw, 'the allowlist step changes nothing after it')
    with open(path, 'w', newline='') as f:
        f.write('local x = 1\n')
    ok(P.main([d]) == 1 and open(path).read() == 'local x = 1\n', 'refusal writes nothing')
    ok(P.main([]) == 1, 'usage')
finally:
    shutil.rmtree(d, ignore_errors=True)

# Lua run from the server folder (the core loads data/lib/chaos_crafting.lua): the patched excerpt on a mocked player
DRIVER = '''
local loadstring = loadstring or load
local SCRIPT, MODE = arg[1], arg[2]
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME = 1, 2
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_ARMOR = 11, 12
function ItemType(id)
  local zero = function() return 0 end
  return {getName = function() return "" end, isContainer = function() return id == 1988 end,
          isStackable = function() return false end, getWeaponType = function() return id == 7384 and 1 or 0 end,
          getSlotPosition = function() return 48 end, getArmor = zero, getAttack = function() return 44 end,
          getDefense = zero, getHitChance = zero, getElementDamage = zero, getAbilities = function() return {} end}
end
json = {decode = function(s) local f = loadstring("return " .. s) return f() end,
        encode = function(t) return (t.action or "?") .. "|" .. tostring(t.outputId or t.message) end}
local handler
CreatureEvent = function(name)
  local ev = {type = function() end, register = function() end}
  if name == "ItemFusionExtended" then handler = ev end
  return ev
end
if MODE == "nocore" then
  local real = dofile
  dofile = function(path)
    if path:find("item_fusion_core", 1, true) then error("no such file") end
    return real(path)
  end
end
dofile(SCRIPT)

local Item = {}
Item.__index = Item
local function item(id, custom)
  return setmetatable({id = id, custom = custom or {}, items = {}}, Item)
end
function Item:getId() return self.id end
function Item:getCount() return 1 end
function Item:getType() return ItemType(self.id) end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:getAttribute(k) return k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil end
function Item:isStoreItem() return false end
function Item:isContainer() return self.id == 1988 end
function Item:getSize() return #self.items end
function Item:getItems() return self.items end
function Item:remove()
  for i, it in ipairs(self.bag.items) do
    if it == self then table.remove(self.bag.items, i) break end
  end
  self.gone = true
  return true
end

-- marks: the bag's copies of the blade in order, "p" plain, "u" unique, "s" set piece, "r" Rare
local function try(marks, clientId)
  local bag, out, got = item(1988), {}, 0
  for m in marks:gmatch(".") do
    local custom = m == "u" and {chaos_unique = 1} or m == "s" and {chaos_set = "embers"} or m == "r" and {rarity = 4} or {}
    local it = item(7384, custom)
    it.bag, it.mark = bag, m
    bag.items[#bag.items + 1] = it
  end
  local p = {sendExtendedOpcode = function(_, _, s) out[#out + 1] = s end,
             getSlotItem = function(_, slot) return slot == 3 and bag or nil end,
             addItem = function(_, id, n) got = got + n end,
             removeItem = function() error("the fusion must not remove by id") end}
  local id = clientId or 7384
  handler.onExtendedOpcode(p, 67, "{action = 'fuse', items = {{clientId = " .. id .. "},{clientId = " .. id .. "},{clientId = " .. id .. "}}}")
  local left = {}
  for _, it in ipairs(bag.items) do left[#left + 1] = it.mark end
  print(tostring(out[1]) .. " left=" .. table.concat(left) .. " reward=" .. got)
end
try("ppp")      -- three plain copies
try("uppp")     -- the unique lies first: stock took it
try("pup")      -- two plain copies and a unique: stock took all three
try("spprp")    -- a set piece and a Rare copy among three plain ones
try("usr")      -- no plain copy at all
try("ppp", 3031) -- an id that is not on the list
'''
ENOUGH = 'invalid_item|You do not have enough items.'
WANT = ['fused_success|29619 left= reward=1',
        'fused_success|29619 left=u reward=1',
        ENOUGH + ' left=pup reward=0',
        'fused_success|29619 left=sr reward=1',
        ENOUGH + ' left=usr reward=0',
        'invalid_item|This item cannot be fused. left=ppp reward=0']
ran = 0
for name in ('luajit', 'lua5.3'):
    exe = shutil.which(name)
    if not exe:
        continue
    ran += 1
    d = tempfile.mkdtemp()
    try:
        script = os.path.join(d, 'item_fusion.lua')
        driver = os.path.join(d, 'run.lua')
        with open(script, 'w') as f:
            f.write(full)
        with open(driver, 'w') as f:
            f.write(DRIVER)
        r = subprocess.run([exe, driver, script, 'core'], cwd=SERVER, capture_output=True, text=True)
        lines = r.stdout.strip().split('\n')
        ok(r.returncode == 0, '%s run: %r %r' % (name, r.stdout, r.stderr))
        for i, want in enumerate(WANT):
            ok(len(lines) > i and lines[i] == want, '%s case %d: want %r, got %r' % (name, i + 1, want, lines[i] if len(lines) > i else None))
        # fail closed: the core cannot be loaded, nothing fuses and nothing is removed
        r = subprocess.run([exe, driver, script, 'nocore'], cwd=SERVER, capture_output=True, text=True)
        lines = r.stdout.strip().split('\n')
        ok(r.returncode == 0 and lines[0] == ENOUGH + ' left=ppp reward=0', '%s no core, nothing fuses: %r %r' % (name, r.stdout, r.stderr))
        ok(len(lines) > 1 and lines[1] == ENOUGH + ' left=uppp reward=0', '%s no core, the unique stays: %r' % (name, r.stdout))
    finally:
        shutil.rmtree(d, ignore_errors=True)
if os.environ.get('CI'):
    ok(ran > 0, 'CI has a Lua interpreter for the Lua run')

# the core is where the patched script looks for it, and the install runs the step after the allowlist
ok(os.path.isfile(os.path.join(SERVER, 'data', 'scripts', 'chaos', 'item_fusion_core.lua')), 'the core file is committed')
with open(os.path.join(HERE, 'install_all.py'), encoding='utf-8') as f:
    inst = f.read()
ok("'fusionplain'" in inst and 'patch_base_fusion_plain.py' in inst, 'install_all.py has the step fusionplain')
ok(inst.index("STEPS.index('sql'), 'fusionlist')") < inst.index("STEPS.index('sql'), 'fusionplain')"), 'fusionplain runs after fusionlist')

if fails:
    print('FAILED:')
    for f in fails:
        print('  ' + f)
    sys.exit(1)
print('patch_base_fusion_plain_test: ok')
