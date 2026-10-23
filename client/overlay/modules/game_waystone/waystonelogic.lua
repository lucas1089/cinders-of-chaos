-- ChaosWaystone: the rules of the waystone device window (pure Lua: no engine calls; tests: waystonelogic_test.lua).
-- The glue is waystone.lua.
--
-- The device is the base server's waystone system (data/scripts/customs/waystone_system/tier_maps.lua of the installed
-- server, made to work in the hideout by server/tools/patch_waystone_hideout.py). It talks on extended opcode 202 in
-- its own JSON, without the {action, data} wrapper of the Chaos modules:
--   server -> client  show {tiers = {{clientId, look, tier, count, level}, ...}, pick}   (tiers and pick: patch part 2;
--                     part 3: the tiers VII-XV keyed by their server ids, and each tier's monster level)
--                     teleport_done | teleport_error {text} | choice_show {choices = {{id, text}}} | choice_done |
--                     choice_error {text} | wrap_done | wrap_error {text}
--   client -> server  teleport {clientId} | choice | choice_apply {choiceId}
-- The base server had no window in this client: the device's Use sent "show" and nothing listened (player report
-- 2026-10-22: "Map Device in the hideout: Use does nothing").
ChaosWaystone = ChaosWaystone or {}
local W = ChaosWaystone

W.OPCODE = 202
-- the client ids of the Waystone Tier I-VI items, in tier order (tier_maps.lua clientToServer; server ids 29845-29850).
-- A server with part 3 of the patch lists VII-XV as well (owner 2026-10-23: 15 tiers, monster level 1100 to 2500).
W.TIER_CLIENT_IDS = { 27189, 27190, 27191, 27192, 27193, 27194 }
W.ROMAN = { 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII', 'XIII', 'XIV', 'XV' }

local function whole(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
  if v ~= math.floor(v) then return nil end
  return v
end

-- the rows of the window from a "show" message, in tier order: {tier, roman, clientId, look (the icon's client id), count,
-- level, usable}. The six base tiers always; a tier the server lists (a whole tier 1..15 with a client id) adds or
-- replaces its row. count is nil when the server did not say (a server without part 2 of the patch): such a row stays
-- usable and the server decides. level is nil without part 3.
function W.rows(msg)
  local byTier = {}
  for i, clientId in ipairs(W.TIER_CLIENT_IDS) do
    byTier[i] = { clientId = clientId }
  end
  local tiers = type(msg) == 'table' and type(msg.tiers) == 'table' and msg.tiers or nil
  if tiers then
    local base = {}
    for i, clientId in ipairs(W.TIER_CLIENT_IDS) do base[clientId] = i end
    for _, t in ipairs(tiers) do
      if type(t) == 'table' then
        local id, tier = whole(t.clientId), whole(t.tier)
        if id and base[id] then tier = base[id] end
        if id and tier and tier >= 1 and tier <= #W.ROMAN then
          byTier[tier] = { clientId = id, info = t }
        end
      end
    end
  end
  local out = {}
  for tier = 1, #W.ROMAN do
    local e = byTier[tier]
    if e then
      local t = e.info
      local count = nil
      if tiers then
        count = t and whole(t.count) or 0
        if count < 0 then count = 0 end
      end
      local look = t and whole(t.look) or e.clientId
      if look <= 0 then look = e.clientId end
      local level = t and whole(t.level) or nil
      if level and level <= 0 then level = nil end
      out[#out + 1] = { tier = tier, roman = W.ROMAN[tier], clientId = e.clientId, look = look, count = count,
        level = level, usable = count == nil or count > 0 }
    end
  end
  return out
end

-- the level text of a row ('' without a level)
function W.levelText(row, tr)
  tr = tr or function(s, ...) return select('#', ...) > 0 and string.format(s, ...) or s end
  if type(row) ~= 'table' or not row.level then return '' end
  return tr('level %d', row.level)
end

-- the row to select first: the server's pick (a tier used on the device), else the lowest tier the player holds,
-- else the first row
function W.firstRow(rows, pick)
  pick = whole(pick)
  if pick then
    for i, r in ipairs(rows) do
      if r.clientId == pick then return i end
    end
  end
  for i, r in ipairs(rows) do
    if r.count and r.count > 0 then return i end
  end
  return 1
end

-- the count text of a row (tr: the translation function)
function W.countText(row, tr)
  tr = tr or function(s, ...) return select('#', ...) > 0 and string.format(s, ...) or s end
  if row.count == nil then return '' end
  if row.count == 0 then return tr('none') end
  return tr('%d held', row.count)
end

-- the request that opens the portals of a row, or nil (no row, none held)
function W.teleportRequest(row)
  if type(row) ~= 'table' or not row.usable or not whole(row.clientId) then return nil end
  return { action = 'teleport', clientId = row.clientId }
end

-- the pad looks of a "choice_show" message: {id, text}, the default first
function W.choices(msg)
  local out = {}
  local list = type(msg) == 'table' and type(msg.choices) == 'table' and msg.choices or {}
  for _, c in ipairs(list) do
    if type(c) == 'table' and whole(c.id) and c.id >= 0 then
      out[#out + 1] = { id = c.id, text = tostring(c.text or '?') }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- what a message from the server means for the window: 'show', 'close' (portals open), 'choices', 'status' (a
-- line of text) or nil (unknown); plus the text for 'status'
function W.classify(msg, tr)
  tr = tr or function(s) return s end
  if type(msg) ~= 'table' or type(msg.action) ~= 'string' then return nil end
  local a = msg.action
  if a == 'show' then return 'show' end
  if a == 'teleport_done' then return 'close', tr('The portals are open around the device for 60 seconds.') end
  if a == 'choice_show' then return 'choices' end
  if a == 'choice_done' then return 'status', tr('Portal look saved.') end
  if a == 'wrap_done' then return 'close' end
  if a == 'teleport_error' or a == 'choice_error' or a == 'wrap_error' then
    local text = type(msg.text) == 'string' and msg.text or ''
    return 'status', text ~= '' and text or tr('The device refused.')
  end
  return nil
end

return ChaosWaystone
