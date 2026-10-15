-- Nemesis window: pure parts (no client API), so nemesisview_test.lua runs under plain Lua. The server's "state"
-- payload (nemesis.lua, nemesis_core.lua K.view) becomes the lines the window shows.
--   state = {has, name, shown, monster, level, kills, traits = {{key, name, desc}}, lastSeen, created, expiresIn,
--            avenged, hunted}

NemesisView = {}
local V = NemesisView

V.TRAIT_COLORS = { vengeful = '#e05040', swift = '#70c8f0', thorned = '#c8a040', regenerating = '#60d070',
  stalker = '#b080e0' }
V.MAX_TEXT = 64

local function str(v, fallback)
  if type(v) ~= 'string' or v == '' then return fallback end
  if #v > V.MAX_TEXT then return v:sub(1, V.MAX_TEXT) end
  return v
end

local function int(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return 0 end
  return math.max(0, math.floor(v))
end

-- A text the window shows is {pattern, args...}: the window passes it to tr(pattern, args...), so every pattern is a
-- key of the client's pt-BR table (client_chaos_locale). V.plain(t) formats one without tr() (tests, logs).
function V.plain(t)
  if type(t) ~= 'table' then return tostring(t or '') end
  if #t <= 1 then return tostring(t[1] or '') end
  local ok, s = pcall(string.format, t[1], (table.unpack or unpack)(t, 2))
  return ok and s or tostring(t[1])
end

-- {'just now'}, {'%d min ago', 5}, {'%d h ago', 3}, {'%d day ago', 1}, {'%d days ago', 2}
function V.ago(seconds)
  seconds = int(seconds)
  if seconds < 60 then return { 'just now' } end
  if seconds < 3600 then return { '%d min ago', math.floor(seconds / 60) } end
  if seconds < 86400 then return { '%d h ago', math.floor(seconds / 3600) } end
  local d = math.floor(seconds / 86400)
  return { d == 1 and '%d day ago' or '%d days ago', d }
end

-- {'%d days', 13}, {'%d h', 5}, {'under an hour'}
function V.left(seconds)
  seconds = int(seconds)
  if seconds >= 86400 then
    local d = math.floor(seconds / 86400)
    return { d == 1 and '%d day' or '%d days', d }
  end
  if seconds >= 3600 then return { '%d h', math.floor(seconds / 3600) } end
  return { 'under an hour' }
end

-- the sub line by the kills: {'A %s that killed you once', monster} ...
local KILLS = { 'A %s that killed you once', 'A %s that killed you twice', 'A %s that killed you three times' }
function V.subText(monster, kills)
  kills = int(kills)
  if kills < 1 then kills = 1 end
  if KILLS[kills] then return { KILLS[kills], monster } end
  return { 'A %s that killed you %d times', monster, kills }
end

-- the traits as {name, desc, color}, at most 4, malformed ones left out (names and descriptions come from the server
-- in the player's language)
function V.traits(list)
  local out = {}
  if type(list) ~= 'table' then return out end
  for _, t in ipairs(list) do
    if type(t) == 'table' and type(t.name) == 'string' and t.name ~= '' then
      out[#out + 1] = { name = str(t.name, '?'), desc = str(t.desc, ''),
        color = V.TRAIT_COLORS[t.key] or '#d6c9ae' }
      if #out >= 4 then break end
    end
  end
  return out
end

-- state + the client's clock -> {has, title (plain: a name), sub, rows = {{label, value}}, traits, empty, footer};
-- sub, the row labels, values that are texts, empty and footer are {pattern, args...}
function V.build(state, now)
  local out = { has = false, rows = {}, traits = {} }
  state = type(state) == 'table' and state or {}
  local avenged, hunted = int(state.avenged), int(state.hunted)
  out.footer = { 'Nemeses avenged: %d   |   Nemeses of others slain: %d', avenged, hunted }
  if state.has ~= true then
    out.title = { 'No Nemesis hunts you' }
    out.empty = { 'When a monster kills you (level 50 or more), it may become your Nemesis. ' ..
      'It returns while you hunt its kind. Slay it for a trophy and the title Avenger of Self.' }
    return out
  end
  out.has = true
  out.title = { '%s', str(state.shown, str(state.name, '?')) }
  local monster = str(state.monster, '?')
  out.sub = V.subText(monster, state.kills)
  now = int(now)
  local lastSeen = int(state.lastSeen)
  out.rows = {
    { { 'Monster' }, { '%s', monster } },
    { { 'Level' }, { '%d', int(state.level) } },
    { { 'Kills' }, { '%d', math.max(1, int(state.kills)) } },
    { { 'Last seen' }, lastSeen > 0 and now > 0 and V.ago(now - lastSeen) or { '?' } },
    { { 'Fades in' }, V.left(state.expiresIn) },
  }
  out.traits = V.traits(state.traits)
  return out
end

-- every pattern this file gives to tr() (the pt-BR table must have each; nemesisview_test.lua lists them)
V.PATTERNS = { 'just now', '%d min ago', '%d h ago', '%d day ago', '%d days ago', '%d day', '%d days', '%d h',
  'under an hour', 'A %s that killed you once', 'A %s that killed you twice', 'A %s that killed you three times',
  'A %s that killed you %d times', 'Nemeses avenged: %d   |   Nemeses of others slain: %d', 'No Nemesis hunts you',
  'When a monster kills you (level 50 or more), it may become your Nemesis. It returns while you hunt its kind. ' ..
  'Slay it for a trophy and the title Avenger of Self.', 'Monster', 'Level', 'Kills', 'Last seen', 'Fades in' }

return V
