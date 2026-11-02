-- Lists saved through g_settings (client/MANIFEST.md "Lists in g_settings nodes"; tested by settingslist_test.lua).
-- g_settings.setNode(key, table) writes every key as a tag (lua_isstring is true for numbers), so list index 1 becomes
-- the tag "1"; g_settings.getNode sets the children by their tag string, so t.list[1] comes back as t.list["1"]. ipairs
-- and # over a list read back from g_settings see nothing after a relog or a client restart. Booleans and numbers come
-- back typed; an empty table comes back nil.
-- Global ChaosSettings (not sandboxed, autoload-priority 10: before gamelib and every game module).
ChaosSettings = ChaosSettings or {}
local S = ChaosSettings

S.LIST_MAX = 100000 -- a hand-edited config.otml cannot make a reader walk forever

-- the whole-number index of a key (1, 2.0, "3", "03"), or nil ("x", "1.5", 0, negatives)
local function index(k)
  local n = tonumber(k)
  if not n or n ~= math.floor(n) or n < 1 or n > S.LIST_MAX then return nil end
  if type(k) == 'string' and not k:match('^%s*%d+%s*$') then return nil end
  return n
end

-- the values of a list read from g_settings, in index order: integer keys and numeric-string keys both count (an
-- in-memory list and one read back from disk give the same result). A gap is skipped, not an end. Other keys are left
-- out. Not a table: an empty list. Two keys of one index (1 and "1"): the integer one.
function S.list(t)
  local out = {}
  if type(t) ~= 'table' then return out end
  local at, idx = {}, {}
  for k, v in pairs(t) do
    local i = index(k)
    if i and (at[i] == nil or type(k) == 'number') then
      if at[i] == nil then idx[#idx + 1] = i end
      at[i] = v
    end
  end
  table.sort(idx)
  for _, i in ipairs(idx) do out[#out + 1] = at[i] end
  return out
end

-- What g_settings.setNode then getNode gives back for a value, as the engine does it (tests use it as their mock):
-- keys become strings (a key that is not a string or a number is dropped), strings that read as a number or as
-- true / false come back typed, an empty table comes back nil.
function S.roundTrip(v)
  local tv = type(v)
  if tv == 'table' then
    local out, any = {}, false
    for k, x in pairs(v) do
      if type(k) == 'string' or type(k) == 'number' then
        local c = S.roundTrip(x)
        if c ~= nil then out[tostring(k)] = c any = true end
      end
    end
    return any and out or nil
  elseif tv == 'string' then
    if v == 'true' then return true elseif v == 'false' then return false end
    return tonumber(v) or v
  elseif tv == 'number' or tv == 'boolean' then
    return v
  end
  return nil
end

-- a g_settings stand-in with the engine's casts: setNode stores the round trip, getNode gives a fresh copy of it
function S.mockSettings()
  local store = {}
  local m = {}
  function m.setNode(key, t) store[key] = S.roundTrip(t) end
  function m.getNode(key) return S.roundTrip(store[key]) end
  function m.save() end
  m.store = store
  return m
end

return S
