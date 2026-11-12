-- Inspect Player (game_playerinspect), the logic without client API (tested by playerinspect_logic_test.lua).
-- The server (extended opcode 240, server/data/scripts/chaos/inspect.lua + inspect_core.lua) answers
--   result {name, level, voc, vocId, ascended, guild = {name, rank}, ach, rift, trials, outfit, self, parts, tree,
--           and the profile fields of O413, each missing on an older server or when its system is not loaded:
--           paragon (points), title (active title text), bestiary {points, rank}, bosses {got, total},
--           pvp {name, tier, rating}, collection (score), passive {spent, total},
--           combat {attack, hit, maxHit, attackSpeed, critChance, critAmount, lifeLeech {chance, amount}, manaLeech,
--           damage = [{k, pct}], defense, armor, mitigation, resist = [{k, pct}], maxHealth, maxMana, moveSpeed;
--           O464: resist rows are fire, cold, lightning, chaos with sum and penalty, and defence = {armourShare, reduction,
--           dodge, block, suppress, penalty, cap} (percent)}
--           (public by owner decision 2026-11-06, O423)}
--   equip  {name, rows = [{slot, tip}], part}      (parts packets of equipment follow a result; each fits one message,
--          a single big row comes in parts "S..", "P..", "E.." like the tree, joined by L.joinPart)
--   tree   {name, nodes, masteries = [{id, choice}], cls, line, vocation, spent, total}   the passive tree, after the
--          equipment; a big one comes in parts "S..", "P..", "E.." (Chaos.sendChunked), joined by L.joinPart
--   records {name, rows = [{key, name, value}]}   the personal records (best drop, Tower floor, rift tier, boss kills),
--          text already in the language of the viewer; after the result
--   denied {code, text}      privacy {allow}
local function tr(s, ...) local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr) if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

PlayerInspectLogic = {}
local L = PlayerInspectLogic

L.OPCODE = 240
L.MAX_TRIAL_TIER = 3
L.MAX_RECORD_ROWS = 24
L.COLORS = { text = '#d6c9ae', dim = '#8c8070', gold = '#f6cf72', accent = '#7fc4d6', red = '#e03a1e', good = '#5ccf5c' }

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

local function lnum(text) local c = rawget(_G, 'ChaosLocale') if c and c.localize then return c.localize(text) end return text end
function L.numberText(n)
  n = math.floor(tonumber(n) or 0)
  local s = tostring(n)
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return lnum(out)
end

-- the header band: the name, "Level N Class", the ascended badge, the active title and the guild line. Every field is
-- { text, color } or nil (an empty line is hidden by the window).
function L.header(d)
  local C = L.COLORS
  local voc = (d.voc and d.voc ~= '') and d.voc or tr('No vocation')
  local out = {
    name = { text = tostring(d.name or ''), color = C.gold },
    class = { text = tr('Level %d %s', tonumber(d.level) or 0, voc), color = C.text },
  }
  if d.ascended then out.badge = { text = tr('Ascended class'), color = C.gold } end
  if type(d.title) == 'string' and d.title ~= '' then out.title = { text = d.title, color = C.accent } end
  if type(d.guild) == 'table' and d.guild.name then
    out.guild = { text = tr('%s of %s', d.guild.rank and tr(d.guild.rank) or tr('Member'), d.guild.name), color = C.text }
  else
    out.guild = { text = tr('No guild'), color = C.dim }
  end
  return out
end

local function num(v)
  local n = math.floor(tonumber(v) or 0)
  return n > 0 and n or nil
end

-- the stat rows of the window, in sections: { { title, rows = { { label, value, color } } } }. A field the server did not
-- send (an older server, or a system that is not loaded) has no row; the rift and trial rows always show, dim "None"
-- without a record (they have been in the packet from the start).
function L.stats(d)
  local C = L.COLORS
  local progress, combat = {}, {}
  local function add(list, label, value, color) list[#list + 1] = { label = label, value = value, color = color or C.text } end

  if num(d.paragon) then add(progress, tr('Paragon points'), L.numberText(d.paragon)) end
  if type(d.passive) == 'table' and (num(d.passive.total) or num(d.passive.spent)) then
    add(progress, tr('Passive points'), string.format('%s / %s', L.numberText(d.passive.spent),
      L.numberText(math.max(tonumber(d.passive.total) or 0, tonumber(d.passive.spent) or 0))))
  end
  add(progress, tr('Achievement points'), L.numberText(d.ach), num(d.ach) and C.text or C.dim)
  if num(d.collection) then add(progress, tr('Collection score'), L.numberText(d.collection)) end
  if type(d.bestiary) == 'table' and num(d.bestiary.points) then
    local rank = type(d.bestiary.rank) == 'string' and d.bestiary.rank ~= '' and d.bestiary.rank or nil
    add(progress, tr('Bestiary'), rank and string.format('%s (%s)', L.numberText(d.bestiary.points), tr(rank)) or L.numberText(d.bestiary.points))
  end
  if type(d.bosses) == 'table' and num(d.bosses.got) then
    add(progress, tr('Boss Points'), string.format('%s / %s', L.numberText(d.bosses.got), L.numberText(d.bosses.total)))
  end

  local rift = num(d.rift)
  if rift then add(combat, tr('Best rift sealed'), tr('Tier %d', rift)) else add(combat, tr('Best rift sealed'), tr('None'), C.dim) end
  local trials = num(d.trials)
  if trials then
    add(combat, tr('Vocation Trials'), tr('Tier %d of %d', trials, L.MAX_TRIAL_TIER), trials >= L.MAX_TRIAL_TIER and C.good or C.text)
  else
    add(combat, tr('Vocation Trials'), tr('None'), C.dim)
  end
  if type(d.pvp) == 'table' and num(d.pvp.rating) then
    local tier = type(d.pvp.tier) == 'string' and d.pvp.tier ~= '' and d.pvp.tier or nil
    add(combat, tr('PvP: %s', tr(type(d.pvp.name) == 'string' and d.pvp.name or 'Arena')),
      tier and string.format('%s (%s)', L.numberText(d.pvp.rating), tier) or L.numberText(d.pvp.rating))
  end
  return {
    { title = tr('Progress'), rows = progress },
    { title = tr('Combat'), rows = combat },
  }
end

L.TYPE_NAMES = { physical = 'Physical', fire = 'Fire', energy = 'Energy', earth = 'Earth', ice = 'Ice', holy = 'Holy', death = 'Death',
  water = 'Water', arcane = 'Arcane', drown = 'Drowning', lifedrain = 'Life drain', manadrain = 'Mana drain',
  cold = 'Cold', lightning = 'Lightning', chaos = 'Chaos' } -- O464: the four resistances are fire, cold, lightning and chaos
L.TYPE_ORDER = { 'physical', 'fire', 'cold', 'lightning', 'chaos', 'energy', 'earth', 'ice', 'holy', 'death', 'water', 'arcane', 'drown',
  'lifedrain', 'manadrain' }

local function pct(v)
  v = tonumber(v) or 0
  if v == math.floor(v) then return string.format('%d', v) end
  return string.format('%.1f', v)
end
L.percentText = pct

local function byType(list)
  local map = {}
  for _, row in ipairs(type(list) == 'table' and list or {}) do
    if type(row) == 'table' and type(row.k) == 'string' then map[row.k] = tonumber(row.pct) end
  end
  return map
end

-- the combat sheet page (O423, the server's public `combat` block): sections Offense, Defense and Resistances as
-- { { title, rows = { { label, value, color } } } }; {} when the server sent no combat block (an older server) so the
-- window disables the tab. A number the server left out has no row.
function L.combatStats(d)
  local c = type(d) == 'table' and d.combat
  if type(c) ~= 'table' then return {} end
  local C = L.COLORS
  local off, def, res = {}, {}, {}
  local function add(list, label, value, color) list[#list + 1] = { label = label, value = value, color = color or C.text } end
  local function has(v) return (tonumber(v) or 0) > 0 end
  if has(c.attack) then add(off, tr('Weapon attack'), L.numberText(c.attack)) end
  if has(c.hit) then add(off, tr('Average hit'), L.numberText(c.hit)) end
  if has(c.maxHit) then add(off, tr('Highest hit'), L.numberText(c.maxHit), C.gold) end
  if has(c.attackSpeed) then add(off, tr('Attack speed'), '+' .. pct(c.attackSpeed) .. '%') end
  if has(c.critChance) then add(off, tr('Critical chance'), pct(c.critChance) .. '%') end
  if has(c.critAmount) then add(off, tr('Critical damage'), '+' .. pct(c.critAmount) .. '%') end
  if type(c.lifeLeech) == 'table' then
    add(off, tr('Life leech'), string.format('%s%% / %s%%', pct(c.lifeLeech.chance), pct(c.lifeLeech.amount)))
  end
  if type(c.manaLeech) == 'table' then
    add(off, tr('Mana leech'), string.format('%s%% / %s%%', pct(c.manaLeech.chance), pct(c.manaLeech.amount)))
  end
  local dmg = byType(c.damage)
  for _, key in ipairs(L.TYPE_ORDER) do
    if dmg[key] then add(off, tr('%s damage', tr(L.TYPE_NAMES[key])), '+' .. pct(dmg[key]) .. '%') end
  end
  if has(c.defense) then add(def, tr('Defense'), L.numberText(c.defense)) end
  if has(c.armor) then add(def, tr('Armor'), L.numberText(c.armor)) end
  if has(c.mitigation) then add(def, tr('Damage reduction'), pct(c.mitigation) .. '%') end
  local d = type(c.defence) == 'table' and c.defence or nil
  if d then
    add(def, tr('Armor share against a typical hit'), pct(d.armourShare) .. '%')
    add(def, tr('Physical reduction'), pct(d.reduction) .. '%')
    add(def, tr('Dodge'), pct(d.dodge) .. '%')
    add(def, tr('Block'), pct(d.block) .. '%')
    add(def, tr('Spell suppression'), pct(d.suppress) .. '%')
  end
  if has(c.maxHealth) then add(def, tr('Maximum health'), L.numberText(c.maxHealth)) end
  if has(c.maxMana) then add(def, tr('Maximum mana'), L.numberText(c.maxMana)) end
  if has(c.moveSpeed) then add(def, tr('Movement speed'), L.numberText(c.moveSpeed)) end
  local rmap = byType(c.resist)
  local rrow = {}
  for _, row in ipairs(type(c.resist) == 'table' and c.resist or {}) do
    if type(row) == 'table' and type(row.k) == 'string' then rrow[row.k] = row end
  end
  for _, key in ipairs(L.TYPE_ORDER) do
    local v = rmap[key]
    if v then
      local text = pct(v) .. '%'
      local r = rrow[key]
      if r and r.sum ~= nil then -- O464: the result, then the sum of the sources minus the penalty of the level
        text = text .. string.format(' (%s - %s)', pct(r.sum), pct(r.penalty or 0))
      end
      add(res, tr(L.TYPE_NAMES[key]), text, v < 0 and C.red or C.good)
    end
  end
  if d and (tonumber(d.cap) or 75) ~= 75 then add(res, tr('Maximum resistance'), pct(d.cap) .. '%') end
  return {
    { title = tr('Offense'), rows = off },
    { title = tr('Defense'), rows = def },
    { title = tr('Resistances'), rows = res },
  }
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
