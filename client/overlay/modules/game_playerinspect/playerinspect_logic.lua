-- Inspect Player (game_playerinspect), the logic without client API (tested by playerinspect_logic_test.lua).
-- The server (extended opcode 240, server/data/scripts/chaos/inspect.lua + inspect_core.lua) answers
--   result {name, level, voc, vocId, ascended, guild = {name, rank}, ach, rift, trials, outfit, self, parts}
--   equip  {name, rows = [{slot, tip}], part}      (parts packets of equipment follow a result)
--   tree   {name, nodes, masteries = [{id, choice}], cls, line, vocation, spent, total}   the passive tree, after the
--          equipment; a big one comes in parts "S..", "P..", "E.." (Chaos.sendChunked), joined by L.joinPart
--   denied {code, text}      privacy {allow}

PlayerInspectLogic = {}
local L = PlayerInspectLogic

L.OPCODE = 240
L.MAX_TRIAL_TIER = 3
L.COLORS = { text = '#d6c9ae', dim = '#8c8070', gold = '#f6cf72', red = '#e03a1e', good = '#5ccf5c' }

-- where each inventory slot sits in the window: column and row (0-based), and its name
L.SLOTS = {
  [2] = { col = 0, row = 0, name = 'Amulet' },
  [1] = { col = 1, row = 0, name = 'Helmet' },
  [3] = { col = 2, row = 0, name = 'Backpack' },
  [6] = { col = 0, row = 1, name = 'Left hand' },
  [4] = { col = 1, row = 1, name = 'Armour' },
  [5] = { col = 2, row = 1, name = 'Right hand' },
  [9] = { col = 0, row = 2, name = 'Ring' },
  [7] = { col = 1, row = 2, name = 'Legs' },
  [10] = { col = 2, row = 2, name = 'Ring' }, -- the second ring slot (the old ammunition slot, server src-patch 0023)
  [8] = { col = 1, row = 3, name = 'Boots' },
}

-- a name typed in the window: letters, spaces, ' and -, 2 to 29 characters (the server checks again)
function L.cleanName(name)
  if type(name) ~= 'string' then return nil end
  name = name:gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
  if #name < 2 or #name > 29 or not name:match("^[%a][%a '%-]*$") then return nil end
  return name
end

function L.numberText(n)
  n = math.floor(tonumber(n) or 0)
  local s = tostring(n)
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return out
end

-- the lines of the character panel: { text, color }
function L.lines(d)
  local C = L.COLORS
  local out = {}
  local voc = d.voc ~= '' and d.voc or 'No vocation'
  out[#out + 1] = { text = string.format('Level %d %s', tonumber(d.level) or 0, voc), color = C.text }
  if d.ascended then out[#out + 1] = { text = 'Ascended class', color = C.gold } end
  if type(d.guild) == 'table' and d.guild.name then
    out[#out + 1] = { text = string.format('%s of %s', d.guild.rank or 'Member', d.guild.name), color = C.text }
  else
    out[#out + 1] = { text = 'No guild', color = C.dim }
  end
  out[#out + 1] = { text = string.format('Achievement points: %s', L.numberText(d.ach)), color = C.text }
  local rift = tonumber(d.rift) or 0
  out[#out + 1] = rift > 0 and { text = string.format('Best rift sealed: tier %d', rift), color = C.text }
    or { text = 'No rift sealed yet', color = C.dim }
  local trials = tonumber(d.trials) or 0
  out[#out + 1] = trials > 0 and { text = string.format('Vocation Trials: tier %d of %d', trials, L.MAX_TRIAL_TIER), color = C.text }
    or { text = 'No Vocation Trial cleared', color = C.dim }
  return out
end

-- state of the window while packets arrive: a result starts a new set of slots
function L.newState()
  return { data = nil, tips = {}, parts = 0, got = 0 }
end

function L.onResult(state, d)
  state.data, state.tips, state.parts, state.got, state.tree = d, {}, tonumber(d.parts) or 0, 0, nil
end

-- the tree packet; false when it belongs to another character than the result shown or is not a tree
function L.onTree(state, d)
  if not state.data or type(d) ~= 'table' or d.name ~= state.data.name or type(d.nodes) ~= 'table' then return false end
  state.tree = d
  return true
end

-- the Passive Tree button's text: "Passive Tree (42)" or nil when there is no tree to show
function L.treeButtonText(state)
  if not state.tree then return nil end
  return string.format('Passive Tree (%d)', #state.tree.nodes)
end

-- the parts of a chunked message (Chaos.sendChunked: "S" first part, "P" middle parts, "E" last part; a message that fits
-- comes whole, starting with "{"). Returns the whole text when it is complete, else nil. parts: a table kept per opcode.
function L.joinPart(parts, buffer)
  if type(buffer) ~= 'string' or buffer == '' then return nil end
  local kind, rest = buffer:sub(1, 1), buffer:sub(2)
  if kind == 'S' then
    parts.buf = { rest }
    return nil
  elseif kind == 'P' then
    if parts.buf then parts.buf[#parts.buf + 1] = rest end
    return nil
  elseif kind == 'E' then
    if not parts.buf then return nil end
    parts.buf[#parts.buf + 1] = rest
    local whole = table.concat(parts.buf)
    parts.buf = nil
    return whole
  end
  return buffer
end

-- an equipment packet; false when it belongs to another character than the result shown
function L.onEquip(state, d)
  if not state.data or d.name ~= state.data.name then return false end
  for _, row in ipairs(type(d.rows) == 'table' and d.rows or {}) do
    local slot = tonumber(row.slot)
    if slot and L.SLOTS[slot] and type(row.tip) == 'table' then state.tips[slot] = row.tip end
  end
  state.got = state.got + 1
  return true
end

function L.complete(state)
  return state.data ~= nil and state.got >= state.parts
end

-- the slot with the widest tooltip need not be known; the tooltip key of a slot is unique per character, slot and item
function L.tipKey(name, slot, tip)
  return string.format('inspect:%s:%d:%s', tostring(name), slot, tostring(tip and tip.key or tip and tip.name or ''))
end
