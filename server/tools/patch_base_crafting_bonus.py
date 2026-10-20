#!/usr/bin/env python3
"""Gives the base server's crafting tables the Chaos crafting bonus (data/scripts/chaos/craft_bonus.lua).

usage: python3 -I patch_base_crafting_bonus.py DATA_DIR [--dry-run]

The base script data/scripts/customs/crafting/1crafting_mod.lua (extended opcode 91) gives every product the stock
rarity roll: 5% of crafts, then the stock chance of each of the base's rarities, made with Game.createItemWithRarity (the
engine's own stats, no item level, no modifier tiers). With this patch crafted equipment rolls a Chaos rarity (Common ..
Rare; data/lib/chaos_rarity.lua) and an item level the way a drop does (ChaosCraftBonus.make: ChaosCrafting.createItem, sockets by
ChaosGems.rollDropSockets), and potions and runes may come with extra pieces; both grow with the crafter's skill above
the recipe's level (numbers in data/scripts/chaos/craft_bonus_config.lua). Any other product keeps the stock roll.

This tool runs after patch_base_crafting.py and patch_base_crafting_ui.py (install_all.py step "basecraftingbonus"
after "basecraftingui") and refuses a file without both of their markers. Four changes:

  1. before `local LoginEvent = CreatureEvent("CraftingLogin")` (after the stock rollRarity and RarityNames): a
     `CraftingBonus` block (make, finish, odds; it calls ChaosCraftBonus when the server has it, else the stock way);
  2. Crafting:sendCrafts: each recipe also carries `bonus` (the rarity odds and item level of an equipment recipe, the
     extra-piece odds of a potion or rune, at the player's skill), after `storageText = craft.storageText or "",`;
  3. in the guarded Crafting:craft, the stock product block (`local rarityId = rollRarity()` ... `end`) becomes
     `CraftingBonus.make`. It must come after `CraftGuard.take(player, craft)`: the bonus is rolled only once the gold
     and the materials were taken, and a failure to make or add the item still gives both back;
  4. the two success texts (`if rarityId > 0 then` ... `end`, as patch_base_crafting_ui.py left them) become one
     `CraftingUi.notify(player, "ok", CraftingBonus.finish(player, craft, made))` after the item was added:
     "You crafted a Rare Crown Shield (item level 32)." / "You crafted 7 Exalted Health Potions (bonus +2)."

Idempotent: markers `-- Chaos: crafting bonus (patch_base_crafting_bonus.py) v1 ...`; all present: "already"; only
some: refused. A base server without the file is skipped (exit 0).
"""
import os
import re
import sys

REL = os.path.join('scripts', 'customs', 'crafting', '1crafting_mod.lua')
NEEDS = (('-- Chaos: crafting guard (patch_base_crafting.py) v1 craft', 'patch_base_crafting.py', 'basecrafting'),
         ('-- Chaos: crafting window (patch_base_crafting_ui.py) v1 ui', 'patch_base_crafting_ui.py', 'basecraftingui'))
MARKER = '-- Chaos: crafting bonus (patch_base_crafting_bonus.py)'
MARK_BLOCK = MARKER + ' v1 bonus'
MARK_ODDS = MARKER + ' v1 odds'
MARK_MAKE = MARKER + ' v1 make'
MARK_TEXT = MARKER + ' v1 text'
MARKS = (MARK_BLOCK, MARK_ODDS, MARK_MAKE, MARK_TEXT)

NL = r'[ \t]*\r?\n'
ANCHOR_LOGIN = re.compile(r'^local LoginEvent = CreatureEvent\("CraftingLogin"\)' + NL, re.M)
ANCHOR_ODDS = re.compile(r'^([ \t]*)storageText = craft\.storageText or "",' + NL, re.M)
ANCHOR_TAKE = re.compile(r'^[ \t]*if not CraftGuard\.take\(player, craft\) then' + NL, re.M)
ANCHOR_MAKE = re.compile(
    r'^([ \t]*)local rarityId = rollRarity\(\)' + NL
    + r'[ \t]*local item' + NL
    + r'[ \t]*if rarityId > 0 then' + NL
    + r'[ \t]*item = Game\.createItemWithRarity\(craft\.id, craft\.count, rarityId\)' + NL
    + r'[ \t]*else' + NL
    + r'[ \t]*item = Game\.createItem\(craft\.id, craft\.count\)' + NL
    + r'[ \t]*end' + NL, re.M)
ANCHOR_ADDED = re.compile(r'^[ \t]*if not CraftGuard\.added\(player:addItemEx\(item\)\) then' + NL, re.M)
ANCHOR_TEXT = re.compile(
    r'^([ \t]*)if rarityId > 0 then' + NL
    + r'[ \t]*CraftingUi\.notify\(player, "ok", "Your crafted item has acquired a rarity: " \.\. RarityNames\[rarityId\]\)'
    + NL
    + r'[ \t]*else' + NL
    + r'[ \t]*CraftingUi\.notify\(player, "ok", string\.format\("Item Successfully Crafted: %s", itemType:getName\(\)\)\)'
    + NL
    + r'[ \t]*end' + NL, re.M)

BLOCK = '''\
''' + MARK_BLOCK + '''
-- Crafted equipment rolls a Chaos rarity and item level, potions and runes may give extra pieces, both by the crafter's
-- skill (data/scripts/chaos/craft_bonus.lua, ChaosCraftBonus). Any other product, or a server without that file: the
-- stock rarity roll and texts.
local CraftingBonus = {}

function CraftingBonus.stock(craft)
  local rarityId = rollRarity()
  local item
  if rarityId > 0 then
    item = Game.createItemWithRarity(craft.id, craft.count, rarityId)
  else
    item = Game.createItem(craft.id, craft.count)
  end
  return rarityId, item
end

-- the product of a craft, made after the gold and the materials were taken: {kind, item, rarity, ...}
function CraftingBonus.make(player, category, craft, skill)
  local made
  if ChaosCraftBonus and ChaosCraftBonus.make then
    local ok, res = pcall(ChaosCraftBonus.make, player, category, craft, skill)
    if ok then
      made = res
    else
      print("[Crafting] bonus: " .. tostring(res))
    end
  end
  if type(made) == "table" and made.kind == "gear" then
    return made
  end
  if type(made) ~= "table" then
    made = {kind = "stock"}
  end
  made.rarity, made.item = CraftingBonus.stock(craft)
  return made
end

-- after the item was added: gives a potion's or rune's extra pieces and returns the text
function CraftingBonus.finish(player, craft, made)
  local text
  if made.kind ~= "stock" and ChaosCraftBonus and ChaosCraftBonus.finish then
    local ok, res = pcall(ChaosCraftBonus.finish, player, craft, made)
    if ok and type(res) == "string" then
      text = res
    elseif not ok then
      print("[Crafting] bonus: " .. tostring(res))
    end
  end
  if made.kind ~= "gear" and (made.rarity or 0) > 0 then
    local rarity = "Your crafted item has acquired a rarity: " .. tostring(RarityNames[made.rarity])
    text = text and (text .. " " .. rarity) or rarity
  end
  return text or string.format("Item Successfully Crafted: %s", ItemType(craft.id):getName())
end

-- what the window shows for a recipe (nil: nothing)
function CraftingBonus.odds(player, category, craft)
  if ChaosCraftBonus and ChaosCraftBonus.odds then
    local ok, res = pcall(ChaosCraftBonus.odds, player, category, craft)
    if ok then
      return res
    end
  end
  return nil
end
-- Chaos: crafting bonus end

'''


def patch(text):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    present = [m for m in MARKS if m in text]
    if len(present) == len(MARKS):
        return text, 'already'
    if present:
        return text, 'partly patched (markers %s only); restore the stock file and run again' % ', '.join(
            m.rsplit(' ', 1)[-1] for m in present)
    for marker, tool, step in NEEDS:
        if marker not in text:
            return text, 'not patched by %s yet; run that first (install_all.py step "%s")' % (tool, step)
    nl = '\r\n' if '\r\n' in text else '\n'
    hits = {}
    for name, rx in (('login', ANCHOR_LOGIN), ('odds', ANCHOR_ODDS), ('take', ANCHOR_TAKE), ('make', ANCHOR_MAKE),
                     ('added', ANCHOR_ADDED), ('text', ANCHOR_TEXT)):
        found = list(rx.finditer(text))
        if len(found) != 1:
            return text, 'not the expected version: anchor "%s" found %d times (expected once); nothing written' % (
                name, len(found))
        hits[name] = found[0]
    h = hits
    if not (h['login'].end() <= h['odds'].start() and h['odds'].end() <= h['take'].start()
            and h['take'].end() <= h['make'].start() and h['make'].end() <= h['added'].start()
            and h['added'].end() <= h['text'].start()):
        return text, 'not the expected version: the anchors are out of order; nothing written'

    o, m, t = h['odds'], h['make'], h['text']
    odds = '%sbonus = CraftingBonus.odds(player, category, craft), %s\n' % (o.group(1), MARK_ODDS)
    make = ('%s%s\n%slocal made = CraftingBonus.make(player, category, craft, playerSkill)\n'
            '%slocal rarityId, item = made.rarity, made.item\n') % (m.group(1), MARK_MAKE, m.group(1), m.group(1))
    done = ('%sCraftingUi.notify(player, "ok", CraftingBonus.finish(player, craft, made)) %s\n'
            % (t.group(1), MARK_TEXT))
    out = (text[:h['login'].start()] + BLOCK.replace('\n', nl)
           + text[h['login'].start():o.end()] + odds.replace('\n', nl)
           + text[o.end():m.start()] + make.replace('\n', nl)
           + text[m.end():t.start()] + done.replace('\n', nl)
           + text[t.end():])
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
