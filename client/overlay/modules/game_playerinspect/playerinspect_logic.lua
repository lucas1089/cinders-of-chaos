-- Inspect Player (game_playerinspect), the logic without client API (tested by playerinspect_logic_test.lua).
-- The server (extended opcode 240, server/data/scripts/chaos/inspect.lua + inspect_core.lua) answers
--   result {name, level, voc, vocId, ascended, guild = {name, rank}, ach, rift, trials, outfit, self, parts}
--   equip  {name, rows = [{slot, tip}], part}      (parts packets of equipment follow a result; each fits one message,
--          a single big row comes in parts "S..", "P..", "E.." like the tree, joined by L.joinPart)
--   tree   {name, nodes, masteries = [{id, choice}], cls, line, vocation, spent, total}   the passive tree, after the
--          equipment; a big one comes in parts "S..", "P..", "E.." (Chaos.sendChunked), joined by L.joinPart
--   records {name, rows = [{key, name, value}]}   the personal records (best drop, Tower floor, rift tier, boss kills),
--          text already in the language of the viewer; after the result
--   denied {code, text}      privacy {allow}
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

PlayerInspectLogic = {}
local L = PlayerInspectLogic

L.OPCODE = 240
L.MAX_TRIAL_TIER = 3
L.MAX_RECORD_ROWS = 24
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
  [13] = { col = 2, row = 2, name = 'Badge' }, -- the badge slot, drawn where the ammunition slot was (server src-patch 0058)
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
  local voc = d.voc ~= '' and d.voc or tr('No vocation')
  out[#out + 1] = { text = tr('Level %d %s', tonumber(d.level) or 0, voc), color = C.text }
  if d.ascended then out[#out + 1] = { text = tr('Ascended class'), color = C.gold } end
  if type(d.guild) == 'table' and d.guild.name then
    out[#out + 1] = { text = tr('%s of %s', d.guild.rank and tr(d.guild.rank) or tr('Member'), d.guild.name), color = C.text }
  else
    out[#out + 1] = { text = tr('No guild'), color = C.dim }
  end
  out[#out + 1] = { text = tr('Achievement points: %s', L.numberText(d.ach)), color = C.text }
  local rift = tonumber(d.rift) or 0
  out[#out + 1] = rift > 0 and { text = tr('Best rift sealed: tier %d', rift), color = C.text }
    or { text = tr('No rift sealed yet'), color = C.dim }
  local trials = tonumber(d.trials) or 0
  out[#out + 1] = trials > 0 and { text = tr('Vocation Trials: tier %d of %d', trials, L.MAX_TRIAL_TIER), color = C.text }
    or { text = tr('No Vocation Trial cleared'), color = C.dim }
  return out
end

-- state of the window while packets arrive: a result starts a new set of slots
function L.newState()
  return { data = nil, tips = {}, parts = 0, got = 0 }
end

function L.onResult(state, d)
  state.data, state.tips, state.parts, state.got, state.tree, state.records = d, {}, tonumber(d.parts) or 0, 0, nil, nil
end

-- the records packet; false when it belongs to another character than the result shown or is not a records packet.
-- Keeps the rows that have a name and a value as text (at most L.MAX_RECORD_ROWS).
function L.onRecords(state, d)
  if not state.data or type(d) ~= 'table' or d.name ~= state.data.name or type(d.rows) ~= 'table' then return false end
  local rows = {}
  for _, r in ipairs(d.rows) do
    if type(r) == 'table' and type(r.name) == 'string' and r.value ~= nil and #rows < L.MAX_RECORD_ROWS then
      rows[#rows + 1] = { name = r.name, value = tostring(r.value) }
    end
  end
  state.records = rows
  return true
end

-- the Records button's text: "Records (5)", plain "Records" when the character has none, nil before the packet arrived
function L.recordsButtonText(state)
  if not state.records then return nil end
  if #state.records == 0 then return tr('Records') end
  return tr('Records (%d)', #state.records)
end

-- what the Records panel says when there are no rows
function L.recordsEmptyText(state)
  if not state.records then return tr('Nothing to show.') end
  return tr('No records yet.')
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
  return tr('Passive Tree (%d)', #state.tree.nodes)
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
  return string.format('inspect:%s:%d:%s', tostring(name), slot, tostring(tip and tip.key or tip and tip.name or '')) -- i18n-ok: not UI text
end
