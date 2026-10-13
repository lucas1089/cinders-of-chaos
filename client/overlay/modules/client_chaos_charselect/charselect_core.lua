-- Cinders of Chaos character select: the pure part (no client API; charselect_core_test.lua runs it under LuaJIT and
-- Lua 5.3). The classes and their icons, the card text, the outfit drawn (the login server's list plus the website's
-- looks) and where it stands (its feet on the pedestal), the world name shown, keyboard navigation, the name pre-check of the create window and the account API's
-- requests and answers (website/README.md "Client API").

CharSelectCore = CharSelectCore or {}
local C = CharSelectCore

-- ---------------------------------------------------------------- classes (docs/CLASSES.md, Chaos.classes)
-- base class id -> line; asc: the two ascended classes. lock: the store's class unlock key ('' = open to every account)
C.LINES = {
  { base = 4, name = 'Warrior', icon = 'warrior', lock = '', asc = { [8] = 'Juggernaut', [14] = 'Berserker' } },
  { base = 3, name = 'Ranger', icon = 'ranger', lock = '', asc = { [7] = 'Deadeye', [15] = 'Beastmaster' } },
  { base = 1, name = 'Mystic', icon = 'mystic', lock = '', asc = { [5] = 'Elementalist', [10] = 'Illusionist' } },
  { base = 11, name = 'Thief', icon = 'thief', lock = '', asc = { [12] = 'Ninja', [13] = 'Samurai' } },
  { base = 17, name = 'Monk', icon = 'monk', lock = 'monk', asc = { [18] = 'Shadowfist', [19] = 'Iron Sage' } },
  { base = 20, name = 'Necromancer', icon = 'necromancer', lock = 'necromancer', asc = { [21] = 'Lich', [22] = 'Bone Lord' } },
  { base = 23, name = 'Templar', icon = 'templar', lock = 'templar', asc = { [24] = 'Inquisitor', [25] = 'Sentinel' } },
}
-- ids retired by the class rework (class_migration.lua): shown as the class they move to
C.RETIRED = { [2] = 1, [6] = 10, [9] = 1 }
C.ICON_DIR = '/images/chaos/charselect/'

-- {id, name, base, line, icon, ascended, lock} of a vocation id, or a plain entry for an unknown id
function C.classInfo(vocation)
  local id = tonumber(vocation) or 0
  id = C.RETIRED[id] or id
  for _, line in ipairs(C.LINES) do
    if id == line.base then
      return { id = id, name = line.name, base = line.base, line = line.name, icon = line.icon, ascended = false, lock = line.lock }
    end
    if line.asc[id] then
      return { id = id, name = line.asc[id], base = line.base, line = line.name, icon = line.icon, ascended = true, lock = line.lock }
    end
  end
  return { id = id, name = id == 0 and 'No class' or 'Unknown class', base = 0, line = '', icon = '', ascended = false, lock = '' }
end

-- "Juggernaut (Warrior)" for an ascended class, "Warrior" for a base class
function C.classText(vocation)
  local c = C.classInfo(vocation)
  if c.ascended then return c.name .. ' (' .. c.line .. ')' end
  return c.name
end

function C.iconPath(vocation)
  local c = C.classInfo(vocation)
  return c.icon ~= '' and (C.ICON_DIR .. 'class_' .. c.icon) or (C.ICON_DIR .. 'class_none')
end

-- ---------------------------------------------------------------- card text
-- last login, in words: never (a new character), minutes / hours / days ago, else the date
function C.lastLoginText(ts, now)
  ts, now = tonumber(ts) or 0, tonumber(now) or 0
  if ts <= 0 then return 'Never played' end
  local d = now - ts
  if d < 0 then d = 0 end
  if d < 120 then return 'Last played just now' end
  if d < 3600 then return string.format('Last played %d minutes ago', math.floor(d / 60)) end
  if d < 7200 then return 'Last played an hour ago' end
  if d < 86400 then return string.format('Last played %d hours ago', math.floor(d / 3600)) end
  if d < 172800 then return 'Last played yesterday' end
  if d < 30 * 86400 then return string.format('Last played %d days ago', math.floor(d / 86400)) end
  return 'Last played on ' .. os.date('!%Y-%m-%d', ts)
end

-- the same, short, for a card: "2 hours ago", "yesterday", "never played", "2026-09-03"
function C.lastLoginShort(ts, now)
  local t = C.lastLoginText(ts, now)
  if t == 'Never played' then return 'never played' end
  return (t:gsub('^Last played on ', ''):gsub('^Last played ', ''))
end

-- The world name of a character card: the name the login server sent when it is one of `allowed` (our world names
-- from the client's own config: the Servers entries), else `fallback` (the chosen server's name). A server that still
-- sends its base data's name (a test server without the production config.lua) never puts that name on the screen.
-- The ", Preview" suffix of the stock list is kept.
function C.worldText(name, allowed, fallback)
  name = tostring(name or '')
  local base, suffix = name:match('^(.-)(, Preview)$')
  base = base or name
  suffix = suffix or ''
  for _, a in ipairs(allowed or {}) do
    if a == base then return base .. suffix end
  end
  return tostring(fallback or 'Cinders of Chaos') .. suffix
end

-- the names allowed on the cards: every `name` of the client's Servers table
function C.allowedWorlds(servers)
  local out = {}
  for _, s in pairs(servers or {}) do
    if type(s) == 'table' and type(s.name) == 'string' and s.name ~= '' then out[#out + 1] = s.name end
  end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------- the outfit drawn
-- The login server's character list (10.98 entry, base patch 0025) carries the look type, colours and addons; the
-- website's looks add wings, aura and shader (the base server keeps them in players.wings_id / aura_id / shader_id,
-- which the list does not carry). The list's own values win where both have one (it is read at this login).
-- shaderKnown(name): only a shader the client has is set (an unknown name draws nothing).
function C.mergeOutfit(listOutfit, look, shaderKnown)
  local o = {}
  local src = listOutfit
  if type(src) ~= 'table' or (tonumber(src.type) or 0) == 0 then
    src = look
  end
  if type(src) ~= 'table' or (tonumber(src.type) or 0) == 0 then return nil end
  o.type = tonumber(src.type)
  for _, k in ipairs({ 'head', 'body', 'legs', 'feet', 'addons' }) do o[k] = tonumber(src[k]) or 0 end
  if type(look) == 'table' then
    o.wings = tonumber(look.wings) or 0
    o.aura = tonumber(look.aura) or 0
    local sh = type(look.shader) == 'string' and look.shader or ''
    if sh ~= '' and (not shaderKnown or shaderKnown(sh)) then o.shader = sh end
  end
  return o
end

-- ---------------------------------------------------------------- cards
-- characters: G.characters (in the stock list's order); looks: name -> look of the account API (or nil); now: time.
-- worlds = {allowed = {...}, fallback = '...'}. Returns one model per character.
function C.cards(characters, looks, now, worlds, shaderKnown)
  local out = {}
  looks = looks or {}
  worlds = worlds or {}
  for i, ch in ipairs(characters or {}) do
    local look = looks[ch.name]
    local voc = ch.vocationId or (look and look.vocation) or 0
    local level = tonumber(ch.level) or (look and tonumber(look.level)) or 0
    local cls = C.classInfo(voc)
    out[#out + 1] = {
      index = i,
      name = ch.name,
      level = level,
      class = cls,
      classText = C.classText(voc),
      icon = C.iconPath(voc),
      world = C.worldText(ch.worldName, worlds.allowed, worlds.fallback),
      lastLogin = look and C.lastLoginText(look.lastLogin, now) or '',
      lastShort = look and C.lastLoginShort(look.lastLogin, now) or '',
      season = look and look.season or '',
      outfit = C.mergeOutfit(ch.outfit, look, shaderKnown),
      levelText = level > 0 and ('Level ' .. level) or '',
    }
  end
  return out
end

-- ---------------------------------------------------------------- navigation
-- the index after a key (Up, Down, Left, Right, Home, End, PageUp, PageDown) in a list of `count`; page = cards per page
function C.move(index, count, key, page)
  count = tonumber(count) or 0
  if count <= 0 then return 0 end
  index = math.max(1, math.min(count, tonumber(index) or 1))
  page = math.max(1, tonumber(page) or 5)
  if key == 'Up' or key == 'Left' then
    index = index - 1
  elseif key == 'Down' or key == 'Right' then
    index = index + 1
  elseif key == 'Home' then
    index = 1
  elseif key == 'End' then
    index = count
  elseif key == 'PageUp' then
    index = index - page
  elseif key == 'PageDown' then
    index = index + page
  end
  return math.max(1, math.min(count, index))
end

-- the index of the character to select first: the last one played (setting), else the first
function C.initialIndex(characters, lastName)
  for i, ch in ipairs(characters or {}) do
    if lastName and ch.name == lastName then return i end
  end
  return (characters and #characters > 0) and 1 or 0
end

-- ---------------------------------------------------------------- the preview
-- UICreature draws a creature at its tile's top left (0, 0) and maps the square from (-32, -32) to (32, 32) of those
-- pixels onto its rect (DrawQueue::correctOutfit): a rect of 2 * T px draws at T / 32 px per sprite pixel, the
-- creature's own tile being the rect's lower right quarter. Where the feet are in those pixels differs per look (a 1x1
-- stock outfit, a 2x2 class look drawn in the middle of its frame, the look's displacement): outfit_anchors.lua
-- (client/tools/sprites/gen_outfit_anchors.py, from the pair) has them, per creature thing:
--   [id] = {feet x, feet y, top, left, right, width, height}   (pixels at 1x, displacement applied; tiles)

-- the anchor of a creature thing; for a thing the table lacks (a look of a newer pair), its size and displacement
-- (thing = {w, h, dx, dy}, the client's ThingType values) give the middle of its own tile's bottom
function C.anchorOf(anchors, id, thing)
  local a = anchors and anchors[tonumber(id) or 0]
  if type(a) == 'table' then
    return { fx = a[1], fy = a[2], top = a[3], left = a[4], right = a[5], w = a[6] or 1, h = a[7] or 1 }
  end
  thing = thing or {}
  local w, h = tonumber(thing.w) or 1, tonumber(thing.h) or 1
  local dx, dy = tonumber(thing.dx) or 8, tonumber(thing.dy) or 8
  return { fx = 16 - dx, fy = 32 - dy, top = 32 - dy - 32 * h, left = 32 - dx - 32 * w, right = 32 - dx, w = w, h = h }
end

-- the whole picture around the feet: the body, its wings (drawn at the same place) and its aura (the client moves a
-- big aura by (w - 1) * 16, (h - 1) * 16: GameBigAurasCenter). things(id) -> thing info for the fallback, or nil.
function C.figure(anchors, outfit, things)
  if type(outfit) ~= 'table' then return nil end
  local function info(id) return things and things(id) or nil end
  local body = C.anchorOf(anchors, outfit.type, info(outfit.type))
  local f = { fx = body.fx, fy = body.fy, top = body.top, left = body.left, right = body.right }
  for _, kind in ipairs({ 'wings', 'aura' }) do
    local id = tonumber(outfit[kind]) or 0
    if id > 0 then
      local a = C.anchorOf(anchors, id, info(id))
      local ox, oy = 0, 0
      if kind == 'aura' and (a.w > 1 or a.h > 1) then ox, oy = (a.w - 1) * 16, (a.h - 1) * 16 end
      f.top = math.min(f.top, a.top + oy)
      f.left = math.min(f.left, a.left + ox)
      f.right = math.max(f.right, a.right + ox)
    end
  end
  return f
end

-- the scale and how far the feet move down: 4x when the whole picture fits (above the feet: room.above px; on each
-- side of the feet: room.half px), else the next of `scales` (default 4, 3); when even the last one is too tall, the
-- feet move down by what is missing, at most room.below px. Returns tile size T (px), scale, drop (px).
function C.fitPreview(fig, room, scales)
  scales = scales or { 4, 3 }
  local function fits(sc)
    return (fig.fy - fig.top) * sc <= room.above and (fig.fx - fig.left) * sc <= room.half
      and (fig.right - fig.fx) * sc <= room.half
  end
  for _, sc in ipairs(scales) do
    if fits(sc) then return sc * 32, sc, 0 end
  end
  local sc = scales[#scales]
  local drop = math.max(0, math.min(tonumber(room.below) or 0, (fig.fy - fig.top) * sc - room.above))
  return sc * 32, sc, drop
end

-- the UICreature rect (x, y, size) that puts the feet of `fig` at (cx, feetY) with tile size T
function C.placeRect(fig, T, cx, feetY)
  local s = T / 32
  return math.floor(cx - (fig.fx + 32) * s + 0.5), math.floor(feetY - (fig.fy + 32) * s + 0.5), 2 * T
end

-- where the feet are drawn for a rect (the inverse of placeRect; the tests check both)
function C.feetOf(fig, x, y, size)
  local s = size / 64
  return x + (fig.fx + 32) * s, y + (fig.fy + 32) * s
end

-- ---------------------------------------------------------------- the create window
-- A hint before sending (the website checks again: these are ZnoteX's rules with the website's numbers): nil or text.
function C.checkName(name, rules)
  rules = rules or {}
  local minL, maxL, maxW = tonumber(rules.minL) or 3, tonumber(rules.maxL) or 20, tonumber(rules.maxW) or 3
  name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if name == '' then return 'Enter a name.' end
  if name:find('[^A-Za-z ]') then return 'Use letters and spaces only.' end
  if name:find('  ', 1, true) then return 'Use one space between words.' end
  local words = 0
  for w in name:gmatch('%S+') do
    words = words + 1
    if #w == 1 then return 'Every word needs at least two letters.' end
  end
  if words > maxW then return string.format('Use at most %d words.', maxW) end
  if #name < minL or #name > maxL then return string.format('The name needs %d to %d letters.', minL, maxL) end
  return nil
end

-- the classes the window offers: the account API's list (locked ones marked), or the four open ones without it
function C.classChoices(state)
  local out = {}
  local fromApi = state and state.account and state.account.classes
  if type(fromApi) == 'table' and #fromApi > 0 then
    for _, c in ipairs(fromApi) do
      out[#out + 1] = { id = tonumber(c.id), name = c.name, plays = c.plays or '', locked = c.locked and true or false,
        icon = C.ICON_DIR .. 'class_' .. tostring(c.icon or 'none') }
    end
    return out
  end
  for _, line in ipairs(C.LINES) do
    out[#out + 1] = { id = line.base, name = line.name, plays = '', locked = line.lock ~= '',
      icon = C.ICON_DIR .. 'class_' .. line.icon }
  end
  return out
end

-- the season choices: "No season" first, then one per mode of the running season ({season, mode, label, hc, warning})
function C.seasonChoices(state)
  local out = { { season = 0, mode = '', label = 'No season (standard character)', hc = false, warning = '' } }
  local s = state and state.account and state.account.season
  if type(s) == 'table' and tonumber(s.id) then
    for _, m in ipairs(s.modes or {}) do
      out[#out + 1] = { season = tonumber(s.id), mode = m.key, label = string.format('%s %s: %s', s.name or 'Season',
        s.tag or '', m.name or m.key), hc = m.hc and true or false, warning = m.warning or '' }
    end
  end
  return out
end

-- a random nonce for a request (hex): the website refuses a request whose nonce it has already seen
function C.nonce(rand)
  rand = rand or math.random
  local t = {}
  for i = 1, 32 do t[i] = string.format('%x', rand(0, 15)) end
  return table.concat(t)
end

function C.loginRequest(account, password, nonce)
  return { action = 'login', account = account, password = password, nonce = nonce }
end

-- form = {name, vocation, sex, season, mode, hardcore, town}
function C.createRequest(token, form, nonce)
  local name = tostring(form.name or ''):gsub('^%s+', ''):gsub('%s+$', '')
  return { action = 'create', token = token, nonce = nonce, name = name, vocation = tonumber(form.vocation) or 0,
    sex = tonumber(form.sex) or 1, season = tonumber(form.season) or 0, mode = form.mode or '',
    hardcore = form.hardcore and true or false, town = tonumber(form.town) or 0 }
end

-- the text of a failed answer: the website's message (and its other errors), or the transport error
function C.errorText(body, err)
  if type(body) == 'table' then
    if type(body.errors) == 'table' and #body.errors > 0 then
      local seen, lines = {}, {}
      for _, e in ipairs(body.errors) do
        if type(e) == 'string' and not seen[e] then
          seen[e] = true
          lines[#lines + 1] = e
        end
      end
      return table.concat(lines, '\n')
    end
    if type(body.message) == 'string' and body.message ~= '' then return body.message end
  end
  if err and tostring(err) ~= '' then
    return 'The website could not be reached (' .. tostring(err) .. ').'
  end
  return 'The website gave no answer.'
end

-- The account API's URL from the client config: HTTPS, or plain HTTP to this machine only (a local test server).
-- nil when unset or not allowed.
function C.apiUrl(url)
  if type(url) ~= 'string' or url == '' then return nil end
  if url:match('^https://[%w%.%-]+[:%d]*/') then return url end
  if url:match('^http://127%.0%.0%.1[:%d]*/') or url:match('^http://localhost[:%d]*/') then return url end
  return nil
end

return C
