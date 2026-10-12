#!/usr/bin/env python3
"""Lets the base server's crafting script talk to the client's crafting window (client game_craftingtable).

usage: python3 -I patch_base_crafting_ui.py DATA_DIR [--dry-run]

The base script data/scripts/customs/crafting/1crafting_mod.lua (extended opcode 91) answers every craft with popup
boxes (popupFYI), sends the materials of a recipe without their names and has nothing for an item tooltip. This tool
runs after patch_base_crafting.py (install_all.py step "basecraftingui" after "basecrafting") and needs its markers:
it refuses a file that patch_base_crafting.py has not patched, so that tool's hash of the stock Crafting:craft still
matches when both run on a fresh stock file. Four changes:

  1. after `Crafting = {}`: a `CraftingUi` block. CraftingUi.notify sends {action = "message", data = {kind, text}}
     on opcode 91 (kind "ok" or "error"); CraftingUi.tip answers {action = "tip", data = {category, craftId}} with
     {action = "tip", data = {category, craftId, tip}} (the Chaos item tooltip of a new item of the recipe's result,
     at most `tipsPerSecond` per player);
  2. the opcode handler: `elseif action == "tip"` before `elseif action == "craft"`;
  3. Crafting:sendCrafts: each material also carries its `name`;
  4. every `player:popupFYI(` of the file becomes `CraftingUi.notify(player, "ok" | "error", `. All of them answer a
     "craft" request, and only a client with the crafting window sends one. "ok" for the two success texts (the
     rarity and the plain success), "error" for the rest.

  5. request checks (v2 valid, also added to a file patched before it existed): after the crafting window block a
     `CraftingUi.category` / `CraftingUi.page` pair; the opcode handler takes the JSON and its `data` only as tables,
     a "fetch" only for one of the 7 categories (CraftingUi.CATEGORIES) and a whole page 1..CraftingUi.maxPage, "show"
     and "craft" only for one of the 7. The stock check `Crafting[category]` let a fetch name one of the script's own functions
     ("craft", "sendCrafts", ...): sendCrafts then took the length of a function and the request logged a Lua error.

Idempotent: markers `-- Chaos: crafting window (patch_base_crafting_ui.py) v1 ...`; all present: "already"; only
some: refused. The v2 checks have their own marker and anchors; a file with them is left alone. A base server without
the file is skipped (exit 0).
"""
import os
import re
import sys

REL = os.path.join('scripts', 'customs', 'crafting', '1crafting_mod.lua')
GUARD_MARKER = '-- Chaos: crafting guard (patch_base_crafting.py)'
MARKER = '-- Chaos: crafting window (patch_base_crafting_ui.py)'
MARK_UI = MARKER + ' v1 ui'
MARK_TIP = MARKER + ' v1 tip'
MARK_NAMES = MARKER + ' v1 names'
MARKS = (MARK_UI, MARK_TIP, MARK_NAMES)
MARK_VALID = MARKER + ' v2 valid'
NOTIFY = 'CraftingUi.notify(player, '

ANCHOR_TABLE = re.compile(r'^Crafting = \{\}[ \t]*\r?\n', re.M)
ANCHOR_CRAFT_ACTION = re.compile(r'^([ \t]*)elseif action == "craft" then[ \t]*\r?\n', re.M)
ANCHOR_MAT_COUNT = re.compile(r'^([ \t]*)player = player:getItemCount\(mat\.id\)[ \t]*(\r?\n)', re.M)
POPUP = re.compile(r'player:popupFYI\(')
# the two success texts of the stock script (patch_base_crafting.py keeps them)
SUCCESS = re.compile(r'acquired a rarity|Successfully Crafted')
# the request checks (v2): after the crafting window block, and four lines of the opcode handler
UI_END = '-- Chaos: crafting window end'
ANCHOR_UI_END = re.compile(r'^' + re.escape(UI_END) + r'[ \t]*\r?\n', re.M)
ANCHOR_JSON = re.compile(r'^([ \t]*)if not ok or not json_data or not json_data\.action then[ \t]*(\r?\n)', re.M)
ANCHOR_DATA = re.compile(r'^([ \t]*)local data\s*=\s*json_data\.data[ \t]*(\r?\n)', re.M)
ANCHOR_FETCH_CHECK = re.compile(
    r'^([ \t]*)if not requestedCategory or not Crafting\[requestedCategory\] then[ \t]*(\r?\n)', re.M)
ANCHOR_SHOW_CHECK = re.compile(r'^([ \t]*)if cat and Crafting\[cat\] then[ \t]*(\r?\n)', re.M)
ANCHOR_CRAFT_CHECK = re.compile(r'^([ \t]*)if not data\.category or not data\.craftId then[ \t]*(\r?\n)', re.M)

UI = '''\
''' + MARK_UI + '''
-- The client's crafting window (game_craftingtable) shows these messages under the recipe instead of popup boxes.
local CraftingUi = {opcode = 91, tipsPerSecond = 8, tipBudget = {}}

function CraftingUi.notify(player, kind, text)
  player:sendExtendedOpcode(CraftingUi.opcode, json.encode({action = "message",
    data = {kind = kind == "ok" and "ok" or "error", text = tostring(text or "")}}))
end

-- the item tooltip of a recipe's result: the Chaos tooltip of a new item (rarity and modifiers are rolled when crafted)
function CraftingUi.tip(player, data)
  if type(data) ~= "table" then
    return
  end
  local category, craftId = data.category, tonumber(data.craftId)
  local list = type(category) == "string" and rawget(Crafting, category) or nil
  local craft = type(list) == "table" and craftId and list[craftId] or nil
  if type(craft) ~= "table" or not craft.id then
    return
  end
  local pid, now = player:getId(), os.time()
  local b = CraftingUi.tipBudget[pid]
  if not b or b.at ~= now then
    b = {at = now, n = 0}
    CraftingUi.tipBudget[pid] = b
  end
  if b.n >= CraftingUi.tipsPerSecond then
    return
  end
  b.n = b.n + 1
  local tip
  if ChaosItemTooltip and ChaosItemTooltip.build then
    local item = Game.createItem(craft.id, 1)
    if item then
      local ok, t = pcall(ChaosItemTooltip.build, item, {})
      if ok and type(t) == "table" then
        tip = t
        tip.key = nil
        tip.count = craft.count or 1
      end
    end
  end
  player:sendExtendedOpcode(CraftingUi.opcode, json.encode({action = "tip",
    data = {category = category, craftId = craftId, tip = tip or false}}))
end
-- Chaos: crafting window end

'''


VALID = '''\
''' + MARK_VALID + '''
-- A request names one of the stock categories (not just any key of Crafting: "craft" is a method) and a whole page.
CraftingUi.CATEGORIES = {herbalist = true, woodcutting = true, mining = true, generalcrafting = true,
  armorsmith = true, weaponsmith = true, jewelsmith = true}
CraftingUi.maxPage = 1000

function CraftingUi.category(category)
  return type(category) == "string" and CraftingUi.CATEGORIES[category] == true
    and type(rawget(Crafting, category)) == "table"
end

-- the page as a whole number 1..maxPage, or nil
function CraftingUi.page(page)
  page = tonumber(page)
  if not page or page ~= page or page < 1 or page > CraftingUi.maxPage or page ~= math.floor(page) then
    return nil
  end
  return math.floor(page)
end
-- Chaos: crafting window checks end
'''


def patch_valid(text):
    """the v2 request checks on a text with the v1 block. returns (new text, status): 'patched', 'already' or an
    error message"""
    if MARK_VALID in text:
        return text, 'already'
    nl = '\r\n' if '\r\n' in text else '\n'
    hits = {}
    for name, rx in (('`%s`' % UI_END, ANCHOR_UI_END), ('the JSON check', ANCHOR_JSON),
                     ('`local data = json_data.data`', ANCHOR_DATA),
                     ('the fetch category check', ANCHOR_FETCH_CHECK), ('the show category check', ANCHOR_SHOW_CHECK),
                     ('the craft request check', ANCHOR_CRAFT_CHECK)):
        found = list(rx.finditer(text))
        if len(found) != 1:
            return text, 'not the expected version: %s found %d times (expected once); nothing written' % (
                name, len(found))
        hits[name] = found[0]
    order = sorted(hits.values(), key=lambda m: m.start())
    if order[0] is not hits['`%s`' % UI_END]:
        return text, 'not the expected version: the request checks are above the crafting window block'
    d = hits['`local data = json_data.data`']
    f = hits['the fetch category check']
    s = hits['the show category check']
    c = hits['the craft request check']
    j = hits['the JSON check']
    edits = [
        (j, lambda m: '%sif not ok or type(json_data) ~= "table" or not json_data.action then%s' % (m.group(1),
                                                                                                  m.group(2))),
        (hits['`%s`' % UI_END], lambda m: m.group(0) + VALID.replace('\n', nl)),
        (d, lambda m: m.group(0) + '%sif type(data) ~= "table" then data = {} end %s%s' % (m.group(1), MARK_VALID,
                                                                                             m.group(2))),
        (f, lambda m: '%srequestedPage = CraftingUi.page(requestedPage)%s%sif not CraftingUi.category(requestedCategory)'
                      ' or not requestedPage then%s' % (m.group(1), m.group(2), m.group(1), m.group(2))),
        (s, lambda m: '%sif CraftingUi.category(cat) then%s' % (m.group(1), m.group(2))),
        (c, lambda m: '%sif not CraftingUi.category(data.category) or not data.craftId then%s' % (m.group(1),
                                                                                                m.group(2))),
    ]
    out, last = [], 0
    for m, fn in sorted(edits, key=lambda e: e[0].start()):
        out.append(text[last:m.start()])
        out.append(fn(m))
        last = m.end()
    out.append(text[last:])
    return ''.join(out), 'patched'


def patch(text):
    """returns (new text, status) with status 'patched', 'already' or an error message"""
    out, st = patch_v1(text)
    if st not in ('patched', 'already'):
        return text, st
    out, st2 = patch_valid(out)
    if st2 not in ('patched', 'already'):
        return text, st2
    return out, 'already' if out == text else 'patched'


def patch_v1(text):
    """the crafting window (v1). returns (new text, status) with status 'patched', 'already' or an error message"""
    present = [m for m in MARKS if m in text]
    if len(present) == len(MARKS):
        return text, 'already'
    if present:
        return text, 'partly patched (markers %s only); restore the stock file and run again' % ', '.join(
            m.rsplit(' ', 1)[-1] for m in present)
    if GUARD_MARKER not in text:
        return text, 'not patched by patch_base_crafting.py yet; run that first (install_all.py step "basecrafting")'
    nl = '\r\n' if '\r\n' in text else '\n'
    table = list(ANCHOR_TABLE.finditer(text))
    action = list(ANCHOR_CRAFT_ACTION.finditer(text))
    mat = list(ANCHOR_MAT_COUNT.finditer(text))
    for name, hits in (('`Crafting = {}`', table), ('`elseif action == "craft" then`', action),
                       ('`player = player:getItemCount(mat.id)`', mat)):
        if len(hits) != 1:
            return text, 'not the expected version: %s found %d times (expected once); nothing written' % (
                name, len(hits))
    if not POPUP.search(text):
        return text, 'not the expected version: no popupFYI call found; nothing written'
    if not (table[0].end() <= action[0].start() and action[0].end() <= mat[0].start()):
        return text, 'not the expected version: the anchors are out of order; nothing written'

    a, m = action[0], mat[0]
    tip = ('%selseif action == "tip" then %s\n%s  CraftingUi.tip(player, data)\n' % (a.group(1), MARK_TIP, a.group(1)))
    names = ('%splayer = player:getItemCount(mat.id),%s%sname = matType and matType:getName() or "" %s%s'
             % (m.group(1), m.group(2), m.group(1), MARK_NAMES, m.group(2)))
    out = (text[:table[0].end()] + UI.replace('\n', nl)
           + text[table[0].end():a.start()] + tip.replace('\n', nl)
           + text[a.start():m.start()] + names
           + text[m.end():])

    def notify(match):
        line_end = out.find('\n', match.start())
        line = out[match.start():line_end if line_end >= 0 else len(out)]
        return NOTIFY + ('"ok", ' if SUCCESS.search(line) else '"error", ')
    out = POPUP.sub(notify, out)
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
