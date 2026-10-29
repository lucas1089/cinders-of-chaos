-- Cosmetics: the rules without client API (tested by cosmeticslogic_test.lua with luajit and lua5.3).
-- Rows of the window (server server/data/scripts/chaos/cosmetics.lua, cosmetics_core.lua C.rows), the chat name colour
-- (only the speaker's name, only player messages, only colours the server sent), the label accent, and the Collection
-- tab (server exclusives.lua: the exclusives of every visual kind and how each is earned).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

CosmeticsLogic = {}
local CL = CosmeticsLogic

CL.KINDS = {
  { key = 'spellskin', name = 'Spell Effects' },
  { key = 'killfx', name = 'Kill Effects' },
  { key = 'lootbeam', name = 'Loot Labels' },
  { key = 'chatcolor', name = 'Chat Colours' },
  { key = 'footprint', name = 'Footprints' },
  { key = 'outline', name = 'Outlines' },
  { key = 'levelfx', name = 'Level-ups' },
  { key = 'rarefx', name = 'Rare Loot' },
  { key = 'emote', name = 'Emotes' },
  { key = 'collection', name = 'Collection' },
}
-- footprints and outlines: drawn by game_cosmeticfx on every client; the window's settings hide other players' ones
CL.DRAWN = { footprint = true, outline = true }
CL.DEFAULT_TEXT = {
  spellskin = 'Your spells show their own effects.',
  killfx = 'No effect on your kills.',
  lootbeam = 'Your highlighted loot labels keep the dark background.',
  chatcolor = 'Your name in chat keeps the colour of the message.',
  footprint = 'You leave no footprints.',
  outline = 'No outline around you.',
  levelfx = 'No effect when you gain a level.',
  rarefx = 'No effect when a kill drops a rare item.',
  emote = 'No emote after a boss kill.',
}
CL.SAMPLE_RARITY = { { name = 'Legendary', color = '#ffd040' }, { name = 'Magic', color = '#4a90ff' },
  { name = 'Divine', color = '#c8e8ff' } }

function CL.validColor(s)
  return type(s) == 'string' and (s:match('^#%x%x%x%x%x%x$') ~= nil or s:match('^#%x%x%x%x%x%x%x%x$') ~= nil)
end

-- ---------------------------------------------------------------- window rows
-- rows = the server's rows; kind = the tab; line = the character's class line (spell skins). Returns the rows of the
-- tab: the default first (id 0), then for spell skins the character's own line before the other lines.
function CL.tabRows(rows, kind, line, lineName)
  local out = {}
  local anySelected = false
  local mine, other = {}, {}
  for _, r in ipairs(type(rows) == 'table' and rows or {}) do
    if type(r) == 'table' and r.kind == kind then
      if kind == 'spellskin' then
        if r.line == line then
          mine[#mine + 1] = r
          if r.selected then anySelected = true end
        else
          other[#other + 1] = r
        end
      else
        mine[#mine + 1] = r
        if r.selected then anySelected = true end
      end
    end
  end
  if kind ~= 'spellskin' or line then
    out[1] = { id = 0, kind = kind, line = line, name = 'Default', owned = true, selected = not anySelected,
      desc = CL.DEFAULT_TEXT[kind] and tr(CL.DEFAULT_TEXT[kind]), how = kind == 'spellskin' and (tr('Every spell of your %s', (type(lineName) == 'string' and lineName or tr('line')))) or
      tr('Every character') }
  end
  for _, r in ipairs(mine) do out[#out + 1] = r end
  for _, r in ipairs(other) do
    local copy = {}
    for k, v in pairs(r) do copy[k] = v end
    copy.otherLine = true
    out[#out + 1] = copy
  end
  return out
end

-- the Collection tab (server exclusives_core.lua K.rows): owned ones first, then the rest, each in the server's order;
-- filter = nil | 'owned' | 'missing'
function CL.collectionRows(collection, filter, scoreView)
  local owned, missing = {}, {}
  for _, r in ipairs(type(collection) == 'table' and collection or {}) do
    if type(r) == 'table' and type(r.key) == 'string' then
      local copy = {}
      for k, v in pairs(r) do copy[k] = v end
      copy.id = 'x:' .. r.key -- the window's row id (never a cosmetic id)
      copy.collection = true
      if r.owned then owned[#owned + 1] = copy else missing[#missing + 1] = copy end
    end
  end
  local out = {}
  local score = CL.scoreRow(scoreView)
  if score then out[1] = score end
  if filter ~= 'missing' then for _, r in ipairs(owned) do out[#out + 1] = r end end
  if filter ~= 'owned' then for _, r in ipairs(missing) do out[#out + 1] = r end end
  return out
end

-- "3 / 34 earned" of the Collection tab
function CL.collectionCount(collection)
  local have, all = 0, 0
  for _, r in ipairs(type(collection) == 'table' and collection or {}) do
    if type(r) == 'table' and type(r.key) == 'string' then
      all = all + 1
      if r.owned then have = have + 1 end
    end
  end
  return have, all
end

-- the line text of a row in the list
function CL.subText(r)
  if r.id == CL.SCORE_ROW then return tr('Rewards for owning cosmetics') end
  if r.collection then
    return (r.kindName or r.kind or '') .. (r.owned and ' - Unlocked' or (' - ' .. (r.how or 'Locked')))
  end
  if r.otherLine then return tr('%s - not your class', tostring(r.lineName or 'Another line')) end
  if r.id == 0 then return r.selected and tr('In use') or 'Default' end
  if r.selected then return tr('In use') end
  if r.owned then return 'Unlocked' end
  return r.how or 'Locked'
end

-- can the row be chosen now (the server checks again)
function CL.canUse(r)
  return r ~= nil and r.owned == true and not r.selected and not r.otherLine and not r.collection
end

-- ---------------------------------------------------------------- the collection score
-- view = the server's `state.score` (collection_core.lua K.view): {score, groups = {{g, n, p}}, next = {points, left},
-- milestones = {{key, points, done, rewards = {{k, n, f}}}}}. Only plain numbers and names are read.
CL.SCORE_ROW = 'x:score'

local function whole(v) return math.floor(tonumber(v) or 0) end

-- the short line above the lists: "Collection score: 142 - next reward at 220 (78 to go)"
function CL.scoreLine(view)
  if type(view) ~= 'table' then return '' end
  local text = tr('Collection score: %d', whole(view.score))
  if type(view.next) == 'table' then
    text = text .. ' - ' .. tr('next reward at %d (%d to go)', whole(view.next.points), whole(view.next.left))
  else
    text = text .. ' - ' .. tr('every reward earned')
  end
  return text
end

-- the words for one reward: {k = 'title', n, f} or {k = <cosmetic kind>, n}
function CL.rewardLabel(r)
  if type(r) ~= 'table' then return '' end
  local name = tostring(r.n or '')
  if r.k == 'title' then
    return r.f and tr('Title %s and a plate frame', name) or tr('Title %s', name)
  elseif r.k == 'footprint' then
    return tr('Footprints %s', name)
  elseif r.k == 'chatcolor' then
    return tr('Chat colour %s', name)
  elseif r.k == 'killfx' then
    return tr('Kill effect %s', name)
  elseif r.k == 'outline' then
    return tr('Outline %s', name)
  end
  return tr('Cosmetic %s', name)
end

-- the milestones as lines, lowest first: "[x] 20 points: Title Collector" / "[ ] 60 points: ..."
function CL.milestoneLines(view)
  local out = {}
  for _, m in ipairs(type(view) == 'table' and type(view.milestones) == 'table' and view.milestones or {}) do
    local rewards = {}
    for _, r in ipairs(type(m.rewards) == 'table' and m.rewards or {}) do rewards[#rewards + 1] = CL.rewardLabel(r) end
    out[#out + 1] = (m.done and '[x] ' or '[ ] ') .. tr('%d points', whole(m.points)) .. ': ' .. table.concat(rewards, ', ')
  end
  return out
end

-- what the points come from: "Outfits 12 (34 points), Mounts 3 (27 points) ..." in the server's order
function CL.groupLine(view)
  local out = {}
  for _, g in ipairs(type(view) == 'table' and type(view.groups) == 'table' and view.groups or {}) do
    local name = CL.GROUP_NAMES[g.g]
    if name then out[#out + 1] = tr(name) .. ' ' .. whole(g.n) .. ' (' .. whole(g.p) .. ')' end
  end
  return table.concat(out, ', ')
end
CL.GROUP_NAMES = { outfit = 'Outfits', mount = 'Mounts', wings = 'Wings', aura = 'Auras', shader = 'Shaders', frame = 'Plate frames',
  spellskin = 'Spell skins', killfx = 'Kill effects', levelfx = 'Level-up effects', rarefx = 'Rare loot effects',
  emote = 'Emotes', lootbeam = 'Loot labels', chatcolor = 'Chat colours', footprint = 'Footprints', outline = 'Outlines',
  title = 'Titles' }

-- the first row of the Collection tab: the score, its next reward and all rewards in the detail (nil without a score)
function CL.scoreRow(view)
  if type(view) ~= 'table' or view.score == nil then return nil end
  local lines = CL.milestoneLines(view)
  return { id = CL.SCORE_ROW, key = 'score', collection = true, owned = true, kind = 'score',
    name = tr('Collection score: %d', whole(view.score)),
    desc = table.concat(lines, '\n'),
    how = CL.groupLine(view) }
end

-- ---------------------------------------------------------------- chat name colours
-- names = {[character name] = '#rrggbb'}; msg = {names | full}: a full list replaces, else entries are added (false
-- removes one). Only valid colours are kept.
function CL.mergeColors(current, msg)
  local out = {}
  if type(msg) ~= 'table' then return current or {} end
  if not msg.full then
    for k, v in pairs(current or {}) do out[k] = v end
  end
  for name, color in pairs(type(msg.names) == 'table' and msg.names or {}) do
    if type(name) == 'string' then
      if CL.validColor(color) then out[name] = color else out[name] = nil end
    end
  end
  return out
end

-- where the speaker's name is in a console line: the stock console writes "[time] Name[ [level]]: text"; the head
-- before the first ": " holds the timestamp (no letters, no ": ") and the name. Returns first, last (1-based).
function CL.nameRange(text, name)
  if type(text) ~= 'string' or type(name) ~= 'string' or name == '' then return nil end
  local stop = text:find(': ', 1, true)
  local head = stop and text:sub(1, stop - 1) or text
  local from = 1
  while true do
    local s = head:find(' ' .. name, from, true)
    if not s then return nil end
    local after = head:sub(s + 1 + #name, s + 2 + #name)
    if after == '' or after == ' [' then
      return s + 1, s + #name
    end
    from = s + 1
  end
end

-- parts = coloured text {text1, color1, text2, color2, ...}; the characters first..last (1-based, over the joined
-- text) get `color`. Returns new parts.
function CL.recolor(parts, first, last, color)
  local out = {}
  local pos = 0
  for i = 1, #parts - 1, 2 do
    local s, c = parts[i], parts[i + 1]
    local a, b = pos + 1, pos + #s
    if b < first or a > last then
      out[#out + 1] = s
      out[#out + 1] = c
    else
      local cutA, cutB = math.max(first, a) - pos, math.min(last, b) - pos
      if cutA > 1 then
        out[#out + 1] = s:sub(1, cutA - 1)
        out[#out + 1] = c
      end
      out[#out + 1] = s:sub(cutA, cutB)
      out[#out + 1] = color
      if cutB < #s then
        out[#out + 1] = s:sub(cutB + 1)
        out[#out + 1] = c
      end
    end
    pos = b
  end
  return out
end

-- msg = {name, level, npc}: player messages only (a level, not an NPC); the colour of `names`. Returns the parts with
-- the name coloured, or nil when nothing changes.
function CL.colorLine(parts, text, msg, names)
  if type(msg) ~= 'table' or msg.npc or (tonumber(msg.level) or 0) <= 0 then return nil end
  local color = names and names[msg.name]
  if not CL.validColor(color) then return nil end
  local first, last = CL.nameRange(text, msg.name)
  if not first then return nil end
  return CL.recolor(parts, first, last, color)
end
