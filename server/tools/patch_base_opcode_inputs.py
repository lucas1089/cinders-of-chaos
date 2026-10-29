#!/usr/bin/env python3
"""The base server's extended opcode handlers check what a modified client sends (idempotent). install_all.py step
`opcodeinputs`.

usage: python3 -I patch_base_opcode_inputs.py DATA_DIR [--dry-run]

DATA_DIR is the base server's data folder. Found by the input audit O252 (server/README.md "Opcode input audit
(O252)"): the base handlers that patch_base_json_guards.py only keeps from indexing a non-table. Read against a client
that sends arbitrary bytes, these were left:

  creaturescripts/scripts/game_store.lua                   store, opcode 201
      gift_coins: the amount was any positive number. 1.5 coins moved as "- 1.5" from the sender and "+ 1.5" to the
      recipient, and the database rounds each side to a whole number: a coin made per request (high). The debit was
      not conditional either. Now a whole number from 1 to 2,000,000,000, a debit that only runs `WHERE points >=
      amount` and is read back with ROW_COUNT(), a credit that is read back too (the debit is given back when the
      recipient account has no points row). A "data" that is not an object is refused before any action.
  scripts/customs/highscores/highscores.lua                highscores, opcode 73
      entriesPerPage and page were unbounded (one request could list the whole players table, and "1e999" or 1.5 made
      the `%d` of the query a Lua error): whole numbers, page 1-10000, 1-100 entries. "vocations" that was not a list
      of numbers went into the SQL text (the class patch already turns it into numbers; this keeps it true without
      that patch, and drops a non-table value). An unknown category was a Lua error; now it ranks by experience. The
      "online" flag no longer shows a hidden (ghost) player as online (canSeeCreature).
  scripts/customs/stats_inspect/inspect.lua                inspect, opcode 107
      Any online player could be inspected by name, a hidden (ghost) staff character too: "not found" now, like for a
      name that is not online. The name must be a string.
  scripts/customs/stats_inspect/character_stats.lua        character stats, opcode 106
      add / remove with a stat name that does not exist called getCharacterStat(nil): a Lua error per packet.
  scripts/customs/waystone_system/character_upgrades.lua   upgrades, opcode 181
      action "points" / "upgrade_points" called onUpgradesUpdatePoints, a function that exists nowhere (a Lua error per
      packet); it sends the points now, like the rest of the script does. "data" must be an object.
  scripts/customs/tasks/tasks.lua                          tasks, opcode 92
      "start" without a number in "kills" was math.max(nil, ...): a Lua error. A non-number becomes the minimum, a
      fraction is floored (the range is still clamped).
  scripts/customs/item_fusion/item_fusion.lua              item fusion, opcode 67
      the JSON was decoded without pcall (a bad or too deeply nested text was a Lua error), "item" and the entries of
      "items" were indexed without a type check. Now tables with a whole-number clientId, else "invalid_item".

Each file gets the marker line `-- Chaos: opcode input checks (patch_base_opcode_inputs.py)` on top; a second run
changes nothing; a file whose code is not the expected text is refused, exit 1, nothing written; a missing file is
skipped. Run after patch_base_json_guards.py and the class / tester / hideout steps (the anchors are lines they leave
alone). A valid client sends exactly what these handlers accepted before: no change for it.
"""
import os
import sys

MARKER = '-- Chaos: opcode input checks (patch_base_opcode_inputs.py)'
TAG = '-- Chaos: opcode input check'

# ---------------------------------------------------------------------------------------------- store (201)
STORE_DATA = ('  if not action or not data then\n    return false\n  end\n',
              '  if not action or type(data) ~= "table" then -- ' + TAG + '\n    return false\n  end\n')

STORE_AMOUNT = ('  local amount = tonumber(data["amount"])\n'
                '  if not recipientName or not amount or amount <= 0 then\n'
                '    return sendMessage(player, "Error!", "Invalid data provided.")\n'
                '  end\n',
                '  local amount = tonumber(data["amount"])\n'
                '  -- ' + TAG + ': a whole number of coins (a fraction was rounded up on one side and down on the other)\n'
                '  if type(recipientName) ~= "string" or not amount or amount < 1 or amount > 2000000000\n'
                '     or amount ~= math.floor(amount) then\n'
                '    return sendMessage(player, "Error!", "Invalid data provided.")\n'
                '  end\n'
                '  amount = math.floor(amount)\n')

STORE_MOVE = ('  db.query("UPDATE `znote_accounts` SET `points` = `points` - " .. amount .. " WHERE `id` = " .. senderAccountId)\n'
              '  db.query("UPDATE `znote_accounts` SET `points` = `points` + " .. amount .. " WHERE `id` = " .. recipientAccountId)\n',
              '  -- ' + TAG + ': the debit only runs while the coins are there and is read back; the credit is read back too\n'
              '  db.query("UPDATE `znote_accounts` SET `points` = `points` - " .. amount .. " WHERE `id` = " .. senderAccountId\n'
              '           .. " AND `points` >= " .. amount)\n'
              '  local chaosRows = db.storeQuery("SELECT ROW_COUNT() AS `n`")\n'
              '  local chaosMoved = 0\n'
              '  if chaosRows then chaosMoved = result.getDataInt(chaosRows, "n"); result.free(chaosRows) end\n'
              '  if chaosMoved ~= 1 then\n'
              '    return sendMessage(player, "Error!", "You do not have enough coins.")\n'
              '  end\n'
              '  db.query("UPDATE `znote_accounts` SET `points` = `points` + " .. amount .. " WHERE `id` = " .. recipientAccountId)\n'
              '  chaosRows = db.storeQuery("SELECT ROW_COUNT() AS `n`")\n'
              '  chaosMoved = 0\n'
              '  if chaosRows then chaosMoved = result.getDataInt(chaosRows, "n"); result.free(chaosRows) end\n'
              '  if chaosMoved ~= 1 then\n'
              '    db.query("UPDATE `znote_accounts` SET `points` = `points` + " .. amount .. " WHERE `id` = " .. senderAccountId)\n'
              '    return sendMessage(player, "Error!", "Recipient not found.")\n'
              '  end\n')

# ---------------------------------------------------------------------------------------------- highscores (73)
HS_VOCS = ('  local vocs        = req.vocations or {}\n',
           '  local vocs        = type(req.vocations) == "table" and req.vocations or {} -- ' + TAG + '\n')

HS_PAGE = ('  local page        = math.max(1, tonumber(req.page) or 1)\n'
           '  local perPage     = math.max(1, tonumber(req.entriesPerPage) or 10)\n',
           '  -- ' + TAG + ': whole numbers in a range (they go into the query with %d)\n'
           '  local function chaosInt(v, lo, hi, def)\n'
           '    v = tonumber(v)\n'
           '    if not v or v ~= v then return def end\n'
           '    if v < lo then v = lo elseif v > hi then v = hi end\n'
           '    return math.floor(v)\n'
           '  end\n'
           '  local page        = chaosInt(req.page, 1, 10000, 1)\n'
           '  local perPage     = chaosInt(req.entriesPerPage, 1, 100, 10)\n')

HS_FILTER = ('  local vocFilter = table.concat(vocs, ",")\n',
             '  -- ' + TAG + ': only numbers reach the SQL text\n'
             '  local chaosSafe = {}\n'
             '  for i = 1, math.min(#vocs, 64) do\n'
             '    local n = tonumber(vocs[i])\n'
             '    if n and n == n and n > -1 and n < 100000 then chaosSafe[#chaosSafe + 1] = math.floor(n) end\n'
             '  end\n'
             '  if #chaosSafe == 0 then chaosSafe[1] = 0 end\n'
             '  local vocFilter = table.concat(chaosSafe, ",")\n')

HS_CATEGORY = ('SKILL_COLUMNS[category] or error("invalid category")', 'SKILL_COLUMNS[category] or "experience"')
HS_ONLINE = ('local isOnline = Player(nm) and 1 or 0',
             'local isOnline = (function() local t = Player(nm); return t and player:canSeeCreature(t) end)() and 1 or 0 -- '
             + TAG[len('-- '):])

# ---------------------------------------------------------------------------------------------- inspect (107)
INSPECT = ('function inspectPlayer(player, targetName)\n  local target = Player(targetName)\n  if target then\n',
           'function inspectPlayer(player, targetName)\n'
           '  if type(targetName) ~= "string" or #targetName > 64 then return end -- ' + TAG + '\n'
           '  local target = Player(targetName)\n'
           '  if target and not player:canSeeCreature(target) then target = nil end -- a hidden player is "not found"\n'
           '  if target then\n')

# ---------------------------------------------------------------------------------------------- character stats (106)
STATS_ADD = ('  local statId = statIndexByName[data]\n  if player:getCharacterStat(statId) >= StatsMaxValues[statId] then\n',
             '  local statId = statIndexByName[data]\n'
             '  if not statId then return end -- ' + TAG + '\n'
             '  if player:getCharacterStat(statId) >= StatsMaxValues[statId] then\n')
STATS_REMOVE = ('  local statId = statIndexByName[data]\n  if player:getCharacterStat(statId) <= 0 then\n',
                '  local statId = statIndexByName[data]\n'
                '  if not statId then return end -- ' + TAG + '\n'
                '  if player:getCharacterStat(statId) <= 0 then\n')

# ---------------------------------------------------------------------------------------------- upgrades (181)
UPG_DATA = ('\t\tif not action or not data then\n\t\t\treturn\n\t\tend\n',
            '\t\tif not action or type(data) ~= "table" then -- ' + TAG + '\n\t\t\treturn\n\t\tend\n')
UPG_POINTS = ('onUpgradesUpdatePoints(data)', 'gameUpgradesUpdatePoints(player) -- ' + TAG)

# ---------------------------------------------------------------------------------------------- tasks (92)
TASKS_KILLS = ('      kills = math.max(kills, Config.RequiredKills.Min)\n',
               '      kills = math.floor(tonumber(kills) or Config.RequiredKills.Min) -- ' + TAG + '\n'
               '      kills = math.max(kills, Config.RequiredKills.Min)\n')

# ---------------------------------------------------------------------------------------------- item fusion (67)
FUSION_DECODE = ('  local data = json.decode(buffer)\n  if not data or type(data) ~= "table" then\n    return false\n  end\n',
                 '  local decoded, data = pcall(json.decode, buffer) -- ' + TAG + '\n'
                 '  if not decoded or type(data) ~= "table" then\n    return false\n  end\n')
FUSION_ITEM = ('    if not data.item then\n      return true\n    end\n',
               '    if type(data.item) ~= "table" then -- ' + TAG + '\n      return true\n    end\n')
FUSION_ITEMS = ('    if not data.items or #data.items < 3 then\n',
                '    if type(data.items) ~= "table" or #data.items < 3 then -- ' + TAG + '\n')
FUSION_ENTRIES = ('    local firstClientId = data.items[1].clientId\n',
                  '    for i = 1, #data.items do\n'
                  '      local entry = data.items[i]\n'
                  '      if type(entry) ~= "table" or type(entry.clientId) ~= "number" or entry.clientId ~= math.floor(entry.clientId) then\n'
                  '        player:sendExtendedOpcode(itemFusionOpcode, json.encode({action = "invalid_item", message = "Invalid item."}))\n'
                  '        return true\n'
                  '      end\n'
                  '    end\n'
                  '    local firstClientId = data.items[1].clientId\n')

FILES = [
    ('creaturescripts/scripts/game_store.lua', [STORE_DATA, STORE_AMOUNT, STORE_MOVE]),
    ('scripts/customs/highscores/highscores.lua', [HS_VOCS, HS_PAGE, HS_FILTER, HS_CATEGORY, HS_ONLINE]),
    ('scripts/customs/stats_inspect/inspect.lua', [INSPECT]),
    ('scripts/customs/stats_inspect/character_stats.lua', [STATS_ADD, STATS_REMOVE]),
    ('scripts/customs/waystone_system/character_upgrades.lua', [UPG_DATA, UPG_POINTS]),
    ('scripts/customs/tasks/tasks.lua', [TASKS_KILLS]),
    ('scripts/customs/item_fusion/item_fusion.lua', [FUSION_DECODE, FUSION_ITEM, FUSION_ITEMS, FUSION_ENTRIES]),
]


def patch(text, edits):
    """(new text, changed, error); text with LF line ends"""
    if MARKER in text:
        return text, False, None
    new = text
    for old, repl in edits:
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
        print('%s: opcode input checks added' % rel)
    print('opcode inputs: %d file(s) %s' % (len(plans), 'would change' if dry else 'changed') if plans
          else 'opcode inputs: nothing to change')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
