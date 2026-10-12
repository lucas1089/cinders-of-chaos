#!/usr/bin/env python3
"""Closes the duplication hole of the base server's crafting script (data/scripts/customs/crafting/1crafting_mod.lua).

usage: python3 -I patch_base_crafting.py DATA_DIR [--dry-run]

The stock script (extended opcode 91, tables with action ids 38820-38826) checks gold and materials when the "craft"
request arrives, creates the item 860 ms later in an addEvent and only then takes gold and materials, without checking
the results: N requests inside 860 ms gave N items for one set of materials. It also never checked that the player
stands at a crafting table. Three changes, each anchored on a stable piece of the stock file:

  1. after `local CODE_CRAFTING = 91`: a `CraftGuard` block (busy flag and cooldown, crafting table record, take and
     refund helpers);
  2. the tables' `actionEvent.onUse(player)`: records which table (category, position, time) the player used;
  3. `function Crafting:craft` ... `end, 860)` / `end` is replaced as a whole. The stock text is compared by a hash
     (line ends and trailing blanks ignored); any other version is refused and nothing is written.

The new Crafting:craft refuses unless the player used a table of that category in the last 5 minutes and stands within
2 tiles of it, and while a craft of the same player is pending or less than 1 s old. In the delayed event it finds the
player again by id, checks table, recipe unlock, skill, gold, materials, capacity and backpack space again, takes the
gold and then the materials (every result checked; a failure gives back what this attempt took and crafts nothing),
and only then creates and adds the item. When the item cannot be created or added (addItemEx returns a ReturnValue:
the stock `if player:addItemEx(item)` was always true) the gold and materials are given back. The rarity roll is
unchanged.

Idempotent: the patched file carries a marker and is not changed again. A file with only part of the markers is refused.
A base server without the file is skipped (exit 0). Run it again after replacing the base file.
"""
import hashlib
import os
import re
import sys

REL = os.path.join('scripts', 'customs', 'crafting', '1crafting_mod.lua')
MARKER = '-- Chaos: crafting guard (patch_base_crafting.py)'
MARK_GUARD = MARKER + ' v1 guard'
MARK_USE = MARKER + ' v1 table'
MARK_CRAFT = MARKER + ' v1 craft'
MARKS = (MARK_GUARD, MARK_USE, MARK_CRAFT)

# sha256 of the stock `function Crafting:craft` ... `end, 860)` / `end`, LF line ends, trailing blanks stripped
STOCK_CRAFT_SHA256 = '05b6b1ebde44060b71b3665cb5f3a15594cc9b5a0920988c1d1b4c3f41bd5821'

ANCHOR_CODE = re.compile(r'^local CODE_CRAFTING = 91[ \t]*\r?\n', re.M)
ANCHOR_USE = re.compile(r'^([ \t]*)function actionEvent\.onUse\(player\)[ \t]*\r?\n'
                        r'([ \t]*)player:showCrafting\(category\)[ \t]*\r?\n', re.M)
ANCHOR_CRAFT = re.compile(r'^function Crafting:craft\(player, category, craftId\)[ \t]*\r?\n.*?'
                          r'^  end, 860\)[ \t]*\r?\nend[ \t]*\r?\n', re.M | re.S)

GUARD = '''\
''' + MARK_GUARD + '''
-- A craft needs a recent use of a crafting table of its category (the player within tableRange tiles of it), and one
-- player has at most one craft pending (plus cooldownMs between two). Gold and materials are taken before the item
-- is made; refund gives back what was taken when the item cannot be made or added.
local CraftGuard = {delayMs = 860, cooldownMs = 1000, staleMs = 10000, tableRange = 2, tableSeconds = 300,
  pending = {}, last = {}, tables = {}}
CraftGuard.TABLE_TEXT = "Use the crafting table and stay next to it to craft."
CraftGuard.BUSY_TEXT = "You are already crafting. Wait a moment."

function CraftGuard.nowMs()
  return os.mtime and os.mtime() or os.time() * 1000
end

function CraftGuard.markTable(player, category, item, fromPosition)
  local pos = fromPosition
  if not pos or not pos.x or pos.x == 0xFFFF then
    pos = item and item.getPosition and item:getPosition() or player:getPosition()
  end
  CraftGuard.tables[player:getId()] = {category = category, x = pos.x, y = pos.y, z = pos.z, at = os.time()}
end

function CraftGuard.atTable(player, category)
  local rec = CraftGuard.tables[player:getId()]
  if not rec or rec.category ~= category or os.time() - rec.at > CraftGuard.tableSeconds then
    return false
  end
  local pos = player:getPosition()
  return pos.z == rec.z and math.abs(pos.x - rec.x) <= CraftGuard.tableRange
    and math.abs(pos.y - rec.y) <= CraftGuard.tableRange
end

function CraftGuard.busy(cid)
  local now = CraftGuard.nowMs()
  local p = CraftGuard.pending[cid]
  if p and now - p < CraftGuard.delayMs + CraftGuard.staleMs then
    return true
  end
  local l = CraftGuard.last[cid]
  return l ~= nil and now - l < CraftGuard.cooldownMs
end

function CraftGuard.refusal(player, category)
  if not CraftGuard.atTable(player, category) then
    return CraftGuard.TABLE_TEXT
  end
  if CraftGuard.busy(player:getId()) then
    return CraftGuard.BUSY_TEXT
  end
  return nil
end

function CraftGuard.start(cid)
  local now = CraftGuard.nowMs()
  CraftGuard.pending[cid] = now
  CraftGuard.last[cid] = now
end

function CraftGuard.finish(cid)
  CraftGuard.pending[cid] = nil
end

-- recipe unlock, gold, skill and materials, with the stock texts; returns the skill level or nil
function CraftGuard.check(player, craft, skillType, skillNames)
  if craft.storage and craft.storage > 0 and player:getStorageValue(craft.storage) ~= 1 then
    local message = "You haven't unlocked this recipe."
    if craft.storageText and craft.storageText ~= "" then
      message = message .. "\\n" .. craft.storageText
    end
    player:popupFYI(message)
    return nil
  end
  if player:getMoney() < craft.cost then
    player:popupFYI(string.format("You don't have enough money: %d.", craft.cost))
    return nil
  end
  local playerSkill = player:getEffectiveSkillLevel(skillType)
  if playerSkill < craft.level then
    player:popupFYI(string.format("You don't have the required %s skill: %d. Your skill is: %d.",
      skillNames[skillType] or "crafting", craft.level, playerSkill))
    return nil
  end
  for _, mat in ipairs(craft.materials) do
    if player:getItemCount(mat.id) < mat.count then
      player:popupFYI(string.format("You don't have enough %s (need %d).", ItemType(mat.id):getName(), mat.count))
      return nil
    end
  end
  return playerSkill
end

function CraftGuard.refund(player, cost, materials)
  if cost and cost > 0 then
    player:addMoney(cost)
  end
  for _, mat in ipairs(materials or {}) do
    player:addItem(mat.id, mat.count, true)
  end
end

-- takes the gold, then each material; on a failure gives back what this call took and returns false
function CraftGuard.take(player, craft)
  local cost = craft.cost or 0
  if cost > 0 and not player:removeMoney(cost) then
    player:popupFYI("Your gold could not be taken. Nothing was crafted.")
    return false
  end
  local taken = {}
  for _, mat in ipairs(craft.materials) do
    if not player:removeItem(mat.id, mat.count) then
      CraftGuard.refund(player, cost, taken)
      player:popupFYI("Your materials could not be taken. Nothing was crafted.")
      return false
    end
    taken[#taken + 1] = mat
  end
  return true
end

-- Player:addItemEx returns a ReturnValue (0 = no error), not a boolean
function CraftGuard.added(ret)
  return ret == true or ret == (RETURNVALUE_NOERROR or 0)
end
-- Chaos: crafting guard end

'''

CRAFT = '''\
function Crafting:craft(player, category, craftId)
  ''' + MARK_CRAFT + '''
  local skillsStages = {
    {minlevel = 8, maxlevel = 20, multiplier = 30},
    {minlevel = 21, maxlevel = 40, multiplier = 20},
    {minlevel = 41, maxlevel = 60, multiplier = 18},
    {minlevel = 61, maxlevel = 90, multiplier = 15},
    {minlevel = 91, maxlevel = 120, multiplier = 12},
    {minlevel = 121, maxlevel = 150, multiplier = 10},
    {minlevel = 151, maxlevel = 200, multiplier = 8},
    {minlevel = 201, multiplier = 5}
  }

  if not Crafting[category] then
    return
  end

  local craft = Crafting[category][craftId]
  if not craft then
    return
  end

  local skillType
  if category == "herbalist" then
    skillType = SKILL_HERBALIST
  elseif category == "woodcutting" then
    skillType = SKILL_WOODCUTTING
  elseif category == "mining" then
    skillType = SKILL_MINING
  elseif category == "generalcrafting" then
    skillType = SKILL_CRAFTING
  elseif category == "armorsmith" then
    skillType = SKILL_ARMORSMITH
  elseif category == "weaponsmith" then
    skillType = SKILL_WEAPONSMITH
  elseif category == "jewelsmith" then
    skillType = SKILL_JEWELSMITH
  end
  if not skillType then
    return
  end

  local refusal = CraftGuard.refusal(player, category)
  if refusal then
    player:popupFYI(refusal)
    return
  end
  if not CraftGuard.check(player, craft, skillType, skillNames) then
    return
  end

  local cid = player:getId()
  CraftGuard.start(cid)
  player:sendExtendedOpcode(CODE_CRAFTING, json.encode({action = "craft", data = {success = true}}))
  addEvent(function()
    CraftGuard.finish(cid)
    local player = Player(cid)
    if not player then
      return
    end
    if not CraftGuard.atTable(player, category) then
      player:popupFYI(CraftGuard.TABLE_TEXT)
      return
    end
    local playerSkill = CraftGuard.check(player, craft, skillType, skillNames)
    if not playerSkill then
      return
    end

    local itemType = ItemType(craft.id)
    local weight = itemType:getWeight(craft.count)
    if player:getFreeCapacity() < weight then
      player:popupFYI("You don't have enough capacity to carry the item. It weighs " ..
        string.format("%.2f", weight / 100) .. " oz, but you only have " ..
        string.format("%.2f", player:getFreeCapacity()) .. " oz free.")
      return
    end

    local backpack = player:getSlotItem(CONST_SLOT_BACKPACK)
    local requiredSlots = 1
    if not itemType:isStackable() then
      requiredSlots = craft.count
    end
    if not backpack or backpack:getEmptySlots(true) < requiredSlots then
      player:popupFYI("You don't have free space in your backpack!")
      return
    end

    -- gold and materials first; the item only after both were taken
    if not CraftGuard.take(player, craft) then
      return
    end

    local rarityId = rollRarity()
    local item
    if rarityId > 0 then
      item = Game.createItemWithRarity(craft.id, craft.count, rarityId)
    else
      item = Game.createItem(craft.id, craft.count)
    end
    if not item then
      CraftGuard.refund(player, craft.cost, craft.materials)
      player:popupFYI("The item could not be crafted. Your gold and materials were given back.")
      return
    end
    if not CraftGuard.added(player:addItemEx(item)) then
      CraftGuard.refund(player, craft.cost, craft.materials)
      player:popupFYI("You do not have enough space to receive the crafted item. Your gold and materials were given back.")
      return
    end

    if rarityId > 0 then
      player:popupFYI("Your crafted item has acquired a rarity: " .. RarityNames[rarityId])
    else
      player:popupFYI(string.format("Item Successfully Crafted: %s", itemType:getName()))
    end

    local skillMultiplier = 1
    for _, stage in ipairs(skillsStages) do
      if playerSkill >= stage.minlevel then
        if not stage.maxlevel or playerSkill <= stage.maxlevel then
          skillMultiplier = stage.multiplier
          break
        end
      end
    end
    player:addSkillTries(skillType, math.floor(skillMultiplier))
    Crafting:sendMoney(player)
    Crafting:sendCrafts(player, category, math.ceil(craftId / fetchLimit))
    playSound(player, "crafting.ogg")
  end, CraftGuard.delayMs)
end
'''


def norm(text):
    return '\n'.join(line.rstrip() for line in text.replace('\r\n', '\n').split('\n'))


def craft_hash(block):
    return hashlib.sha256(norm(block).encode('utf-8', 'surrogateescape')).hexdigest()


def patch(text):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    present = [m for m in MARKS if m in text]
    if len(present) == len(MARKS):
        return text, 'already'
    if present:
        return text, 'partly patched (markers %s only); restore the stock file and run again' % ', '.join(
            m.rsplit(' ', 1)[-1] for m in present)
    nl = '\r\n' if '\r\n' in text else '\n'
    code = list(ANCHOR_CODE.finditer(text))
    use = list(ANCHOR_USE.finditer(text))
    craft = list(ANCHOR_CRAFT.finditer(text))
    for name, hits in (('`local CODE_CRAFTING = 91`', code), ('the tables\' `actionEvent.onUse(player)`', use),
                       ('`function Crafting:craft` ... `end, 860)`', craft)):
        if len(hits) != 1:
            return text, 'not the expected stock version: %s found %d times (expected once); nothing written' % (
                name, len(hits))
    if craft_hash(craft[0].group(0)) != STOCK_CRAFT_SHA256:
        return text, ('not the expected stock version: Crafting:craft differs from the stock function '
                      '(sha256 %s); nothing written' % craft_hash(craft[0].group(0))[:16])
    if not (code[0].end() <= use[0].start() and use[0].end() <= craft[0].start()):
        return text, 'not the expected stock version: the anchors are out of order; nothing written'
    m = use[0]
    on_use = ('%sfunction actionEvent.onUse(player, item, fromPosition, target, toPosition)\n'
              '%s%s\n'
              '%sCraftGuard.markTable(player, category, item, fromPosition)\n'
              '%splayer:showCrafting(category)\n') % (m.group(1), m.group(2), MARK_USE, m.group(2), m.group(2))
    out = (text[:code[0].end()] + GUARD.replace('\n', nl)
           + text[code[0].end():m.start()] + on_use.replace('\n', nl)
           + text[m.end():craft[0].start()] + CRAFT.replace('\n', nl)
           + text[craft[0].end():])
    return out, 'patched'


def main(argv):
    args = [a for a in argv if not a.startswith('--')]
    dry = '--dry-run' in argv
    if len(args) != 1:
        print(__doc__.strip().splitlines()[2])
        return 2
    path = os.path.join(args[0], REL)
    rel = REL.replace(os.sep, '/')
    if not os.path.isfile(path):
        print('%s: not found, nothing to do' % rel)
        return 0
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
