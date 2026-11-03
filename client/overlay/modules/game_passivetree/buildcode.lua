-- ChaosBuildCode: the full build code (O391), pure Lua, no engine calls (buildcode_test.lua; the PHP twin is
-- website/overlay/plugins/chaos/buildcode_lib.php; both read the shared vectors docs/build_code_vectors.txt).
-- One string holds the class, the level, the passive tree (the server's own tree code, CB<n>-, inside), the spell
-- rotation and the worn gear. The client makes it (Build Code panel, "Copy Full Build"), the website draws it
-- (page?plugin=chaos&p=build&c=CODE). Applying the tree always goes through the server: the client sends the inner
-- tree code to the server's preview (buildshare.lua), whose class and respec rules decide.
--
-- Format, version 1:  "CC1-" .. base64url(payload .. checksum), no padding, canonical form only
--   payload  = sections, each: tag (1 byte), length (2 bytes, high first), data (length bytes); tags ascending, each
--              tag at most once; a decoder skips a tag it does not know (a newer client may add one)
--     tag 1  class:  1 byte, index into C.CLASSES (append only, never reorder; not a vocation id)
--     tag 2  level:  2 bytes, high first (1..65535)
--     tag 3  tree:   1 byte, the tree code's version, then the tree code's bytes (its own checksum included); the
--                    tree code is "CB" .. version .. "-" .. base64url(those bytes) (server buildshare_core.lua)
--     tag 4  spells: 2 bytes per spell id (server spell ids, in rotation order), at most C.MAX_SPELLS
--     tag 5  gear:   3 bytes per item: slot (1 byte, C.GEAR_SLOTS), server item id (2 bytes); slots ascending
--   checksum = 3 bytes: h = (h * 257 + x) % 16777213 over the characters of "CC1" and every payload byte
-- Errors are kinds ('empty', 'toolong', 'format', 'version', 'damaged', 'checksum', 'class', 'tree', 'spells',
-- 'gear', 'level'); the window turns them into text.
ChaosBuildCode = ChaosBuildCode or {}
local C = ChaosBuildCode

C.PREFIX = 'CC'
C.VERSION = 1
C.MAX_CODE = 1000
C.MAX_SPELLS = 16
C.TREE_PREFIX = 'CB'
C.TREE_LAYOUT_MAX = 6 -- tree code versions whose layout this file reads (buildshare_core.lua B.READS: 1 to 6)
-- {class key, vocation id, name}; index = the code's class byte. Append only, never reorder.
C.CLASSES = {
  {'warrior', 4, 'Warrior'}, {'juggernaut', 8, 'Juggernaut'}, {'berserker', 14, 'Berserker'},
  {'ranger', 3, 'Ranger'}, {'deadeye', 7, 'Deadeye'}, {'beastmaster', 15, 'Beastmaster'},
  {'mystic', 1, 'Mystic'}, {'elementalist', 5, 'Elementalist'}, {'illusionist', 10, 'Illusionist'},
  {'thief', 11, 'Thief'}, {'ninja', 12, 'Ninja'}, {'samurai', 13, 'Samurai'},
  {'monk', 17, 'Monk'}, {'shadowfist', 18, 'Shadowfist'}, {'ironsage', 19, 'Iron Sage'},
  {'necromancer', 20, 'Necromancer'}, {'lich', 21, 'Lich'}, {'bonelord', 22, 'Bone Lord'},
  {'templar', 23, 'Templar'}, {'inquisitor', 24, 'Inquisitor'}, {'sentinel', 25, 'Sentinel'},
}
C.PARAGON_KEYS = {'damage', 'critDamage', 'health', 'reduction', 'speed', 'mana', 'goldFind', 'itemFind'} -- = buildshare_core.lua
C.GEAR_SLOTS = {1, 2, 4, 5, 6, 7, 8, 9, 10} -- head, amulet, armour, right hand, left hand, legs, feet, ring, ammo
C.TAG = {class = 1, level = 2, tree = 3, spells = 4, gear = 5}

local ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
local DECODE = {}
for i = 1, #ALPHABET do
  DECODE[ALPHABET:sub(i, i)] = i - 1
end
local MOD = 16777213
local floor = math.floor

local function checksum(head, bytes, count)
  local h = 0
  for i = 1, #head do
    h = (h * 257 + head:byte(i)) % MOD
  end
  for i = 1, count do
    h = (h * 257 + bytes[i]) % MOD
  end
  return h
end

function C.toBase64(bytes)
  local out = {}
  for i = 1, #bytes, 3 do
    local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local chars = 2 + (b and 1 or 0) + (c and 1 or 0)
    for k = 1, chars do
      local index = floor(n / 64 ^ (4 - k)) % 64
      out[#out + 1] = ALPHABET:sub(index + 1, index + 1)
    end
  end
  return table.concat(out)
end

-- bytes of a base64url text, or nil (bad character, bad length, not the canonical form)
function C.fromBase64(text)
  if type(text) ~= 'string' or #text % 4 == 1 then
    return nil
  end
  local bytes = {}
  for i = 1, #text, 4 do
    local chunk = text:sub(i, i + 3)
    local n = 0
    for k = 1, 4 do
      local ch = chunk:sub(k, k)
      local v = 0
      if ch ~= '' then
        v = DECODE[ch]
        if not v then
          return nil
        end
      end
      n = n * 64 + v
    end
    for k = 1, #chunk - 1 do
      bytes[#bytes + 1] = floor(n / 256 ^ (3 - k)) % 256
    end
  end
  if C.toBase64(bytes) ~= text then
    return nil -- the unused low bits of the last character must be zero, so a typo there is caught
  end
  return bytes
end

-- ------------------------------------------------------------------------------------------------ classes
function C.classIndex(key)
  for i, c in ipairs(C.CLASSES) do
    if c[1] == key then
      return i
    end
  end
  return nil
end

function C.classOfVocation(vocationId)
  for _, c in ipairs(C.CLASSES) do
    if c[2] == vocationId then
      return c[1]
    end
  end
  return nil
end

function C.vocationOf(key)
  local i = C.classIndex(key)
  return i and C.CLASSES[i][2] or nil
end

function C.className(key)
  local i = C.classIndex(key)
  return i and C.CLASSES[i][3] or nil
end

-- ------------------------------------------------------------------------------------------------ the inner tree code
-- the tree code's version and bytes (checked: canonical, its checksum), or nil
local function treeBytes(code)
  if type(code) ~= 'string' then
    return nil
  end
  local version, body = code:match('^' .. C.TREE_PREFIX .. '(%d+)%-([%w_%-]+)$')
  version = tonumber(version)
  if not version or version < 1 or version > 255 then
    return nil
  end
  local bytes = C.fromBase64(body)
  if not bytes or #bytes < 5 then
    return nil
  end
  local n = #bytes
  if checksum(C.TREE_PREFIX .. version, bytes, n - 3) ~= bytes[n - 2] * 65536 + bytes[n - 1] * 256 + bytes[n] then
    return nil
  end
  return floor(version), bytes
end

-- what a tree code holds: {code, version, line (class line byte), nodes = {sorted ids}, paragon = {key = points},
-- masteries = {[id] = choice}}, or {code, version, newer = true} for a layout newer than this file; nil when damaged
function C.readTree(code)
  local version, bytes = treeBytes(code)
  if not version then
    return nil
  end
  if version > C.TREE_LAYOUT_MAX then
    return {code = code, version = version, newer = true}
  end
  local n = #bytes
  local last = n - 3
  local info = {code = code, version = version, line = bytes[1], nodes = {}, paragon = {}, masteries = {}}
  local flags = bytes[2] or 0
  local pos = 3
  if flags % 2 == 1 then
    local count = bytes[pos] or 0
    pos = pos + 1
    for _ = 1, count do
      local key = C.PARAGON_KEYS[bytes[pos] or 0]
      if not key or pos + 1 > last then
        return nil
      end
      info.paragon[key] = bytes[pos + 1]
      pos = pos + 2
    end
  end
  if version >= 2 and floor(flags / 2) % 2 == 1 then
    local count = bytes[pos] or 0
    pos = pos + 1
    for _ = 1, count do
      if pos + 2 > last then
        return nil
      end
      info.masteries[bytes[pos] * 256 + bytes[pos + 1]] = bytes[pos + 2]
      pos = pos + 3
    end
  end
  if pos > last + 1 then
    return nil
  end
  for i = pos, last do
    local value, base = bytes[i], (i - pos) * 8
    for bit = 0, 7 do
      if floor(value / 2 ^ bit) % 2 == 1 then
        info.nodes[#info.nodes + 1] = base + bit
      end
    end
  end
  return info
end

-- ------------------------------------------------------------------------------------------------ encode / decode
local function push16(out, v)
  out[#out + 1] = floor(v / 256) % 256
  out[#out + 1] = v % 256
end

local function int(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then
    return nil
  end
  return floor(v)
end

-- card = {class = key, level = n, tree = tree code, spells = {ids}, gear = {{slot, id}}}; every part optional.
-- Returns the code, or nil + error kind. Spell and gear lists are cleaned (bad entries dropped, gear sorted by slot).
function C.encode(card)
  if type(card) ~= 'table' then
    return nil, 'format'
  end
  local sections = {}
  if card.class ~= nil then
    local index = C.classIndex(card.class)
    if not index then
      return nil, 'class'
    end
    sections[#sections + 1] = {C.TAG.class, {index}}
  end
  if card.level ~= nil then
    local level = int(card.level)
    if not level or level < 1 or level > 65535 then
      return nil, 'level'
    end
    local d = {}
    push16(d, level)
    sections[#sections + 1] = {C.TAG.level, d}
  end
  if card.tree ~= nil then
    local version, bytes = treeBytes(card.tree)
    if not version then
      return nil, 'tree'
    end
    local d = {version}
    for _, b in ipairs(bytes) do
      d[#d + 1] = b
    end
    sections[#sections + 1] = {C.TAG.tree, d}
  end
  if type(card.spells) == 'table' and #card.spells > 0 then
    local d, seen = {}, {}
    for _, raw in ipairs(card.spells) do
      local id = int(raw)
      if id and id > 0 and id < 65536 and not seen[id] and #d < C.MAX_SPELLS * 2 then
        seen[id] = true
        push16(d, id)
      end
    end
    if #d > 0 then
      sections[#sections + 1] = {C.TAG.spells, d}
    end
  end
  if type(card.gear) == 'table' and #card.gear > 0 then
    local bySlot = {}
    for _, g in ipairs(card.gear) do
      local slot, id = int(type(g) == 'table' and (g.slot or g[1])), int(type(g) == 'table' and (g.id or g[2]))
      if slot and id and id > 0 and id < 65536 then
        bySlot[slot] = id
      end
    end
    local d = {}
    for _, slot in ipairs(C.GEAR_SLOTS) do
      if bySlot[slot] then
        d[#d + 1] = slot
        push16(d, bySlot[slot])
      end
    end
    if #d > 0 then
      sections[#sections + 1] = {C.TAG.gear, d}
    end
  end
  local bytes = {}
  for _, s in ipairs(sections) do
    bytes[#bytes + 1] = s[1]
    push16(bytes, #s[2])
    for _, b in ipairs(s[2]) do
      bytes[#bytes + 1] = b
    end
  end
  local head = C.PREFIX .. C.VERSION
  local h = checksum(head, bytes, #bytes)
  bytes[#bytes + 1] = floor(h / 65536) % 256
  bytes[#bytes + 1] = floor(h / 256) % 256
  bytes[#bytes + 1] = h % 256
  local code = head .. '-' .. C.toBase64(bytes)
  if #code > C.MAX_CODE then
    return nil, 'toolong'
  end
  return code
end

-- the first full build code inside any text, or nil
function C.extract(text)
  if type(text) ~= 'string' then
    return nil
  end
  return text:match('(' .. C.PREFIX .. '%d+%-[%w_%-]+)')
end

function C.isCode(text)
  return C.extract(text) ~= nil
end

-- card {class, vocation, level, tree, treeInfo, spells, gear = {{slot, id}}, skipped} or nil + error kind
function C.decode(code)
  if type(code) ~= 'string' then
    return nil, 'empty'
  end
  code = code:gsub('^%s+', ''):gsub('%s+$', '')
  if code == '' then
    return nil, 'empty'
  end
  if #code > C.MAX_CODE then
    return nil, 'toolong'
  end
  local version, body = code:match('^' .. C.PREFIX .. '(%d+)%-([%w_%-]*)$')
  if not version then
    return nil, 'format'
  end
  if tonumber(version) ~= C.VERSION then
    return nil, 'version'
  end
  local bytes = C.fromBase64(body)
  if not bytes or #bytes < 3 then
    return nil, 'damaged'
  end
  local n = #bytes
  if checksum(C.PREFIX .. C.VERSION, bytes, n - 3) ~= bytes[n - 2] * 65536 + bytes[n - 1] * 256 + bytes[n] then
    return nil, 'checksum'
  end
  local card = {spells = {}, gear = {}, skipped = 0}
  local seen = {}
  local pos, last = 1, n - 3
  while pos <= last do
    if pos + 2 > last then
      return nil, 'damaged'
    end
    local tag, len = bytes[pos], bytes[pos + 1] * 256 + bytes[pos + 2]
    local from, to = pos + 3, pos + 2 + len
    if to > last or seen[tag] then
      return nil, 'damaged'
    end
    seen[tag] = true
    if tag == C.TAG.class then
      local c = len == 1 and C.CLASSES[bytes[from]] or nil
      if not c then
        return nil, 'class'
      end
      card.class, card.vocation = c[1], c[2]
    elseif tag == C.TAG.level then
      local level = len == 2 and bytes[from] * 256 + bytes[from + 1] or 0
      if level < 1 then
        return nil, 'level'
      end
      card.level = level
    elseif tag == C.TAG.tree then
      if len < 6 then
        return nil, 'tree'
      end
      local t = {}
      for i = from + 1, to do
        t[#t + 1] = bytes[i]
      end
      card.tree = C.TREE_PREFIX .. bytes[from] .. '-' .. C.toBase64(t)
      card.treeInfo = C.readTree(card.tree)
      if not card.treeInfo then
        return nil, 'tree'
      end
    elseif tag == C.TAG.spells then
      if len % 2 ~= 0 or len > C.MAX_SPELLS * 2 then
        return nil, 'spells'
      end
      for i = from, to, 2 do
        card.spells[#card.spells + 1] = bytes[i] * 256 + bytes[i + 1]
      end
    elseif tag == C.TAG.gear then
      if len % 3 ~= 0 then
        return nil, 'gear'
      end
      local prev = 0
      for i = from, to, 3 do
        local slot, id = bytes[i], bytes[i + 1] * 256 + bytes[i + 2]
        local known = false
        for _, s in ipairs(C.GEAR_SLOTS) do
          known = known or s == slot
        end
        if not known or slot <= prev or id == 0 then
          return nil, 'gear'
        end
        prev = slot
        card.gear[#card.gear + 1] = {slot = slot, id = id}
      end
    else
      card.skipped = card.skipped + 1 -- a part a newer client added
    end
    pos = to + 1
  end
  return card
end

-- ------------------------------------------------------------------------------------------------ text form (tests)
-- the canonical one-line text of a decoded card (docs/build_code_vectors.txt; buildcode_lib.php has the same):
-- class=..;level=..;tree=..;line=..;nodes=..;paragon=k:v,..;masteries=id:choice,..;spells=..;gear=slot:id,..;skipped=n
function C.describe(card)
  local parts = {}
  local function add(k, v)
    parts[#parts + 1] = k .. '=' .. v
  end
  if card.class then add('class', card.class) end
  if card.level then add('level', string.format('%d', card.level)) end
  if card.tree then
    add('tree', card.tree)
    local t = card.treeInfo
    if t and t.newer then
      add('newer', '1')
    elseif t then
      add('line', string.format('%d', t.line))
      local ids = {}
      for i, id in ipairs(t.nodes) do ids[i] = string.format('%d', id) end
      add('nodes', table.concat(ids, ','))
      local p = {}
      for _, k in ipairs(C.PARAGON_KEYS) do
        if t.paragon[k] then p[#p + 1] = k .. ':' .. string.format('%d', t.paragon[k]) end
      end
      if #p > 0 then add('paragon', table.concat(p, ',')) end
      local m, ms = {}, {}
      for id in pairs(t.masteries) do m[#m + 1] = id end
      table.sort(m)
      for _, id in ipairs(m) do ms[#ms + 1] = string.format('%d:%d', id, t.masteries[id]) end
      if #ms > 0 then add('masteries', table.concat(ms, ',')) end
    end
  end
  if card.spells and #card.spells > 0 then
    local s = {}
    for i, id in ipairs(card.spells) do s[i] = string.format('%d', id) end
    add('spells', table.concat(s, ','))
  end
  if card.gear and #card.gear > 0 then
    local g = {}
    for i, it in ipairs(card.gear) do g[i] = string.format('%d:%d', it.slot, it.id) end
    add('gear', table.concat(g, ','))
  end
  if (card.skipped or 0) > 0 then add('skipped', string.format('%d', card.skipped)) end
  return table.concat(parts, ';')
end
