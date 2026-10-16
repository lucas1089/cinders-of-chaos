-- ChaosHelperSave: how the helper (mods/game_helper, base patch 0067) reads and writes its per-character
-- helper.json (pure: helpersave_test.lua; client/MANIFEST.md "Helper settings survive death").
-- Owner: the helper's settings reset when the character died. The helper unblocked its saves at the end of every UI
-- reload (onLoadHelperData), whether or not the file had been read, and a file it could not read (missing, cut short
-- by a client killed on the death screen, not JSON) gave defaults that the next save wrote over it. Now:
-- * saves are allowed only after a load for this character finished (canSave); logout, death and the next login
--   block them until the file is read again;
-- * a file that cannot be read is never written over: the backup (.bak) or the last temp copy (.tmp) is read instead,
--   and when none can be read the broken file is kept aside as .broken before the defaults may be saved;
-- * a write goes to .tmp first and is read back; the previous good file becomes .bak; then the file is written and
--   checked (a cut write leaves .tmp and .bak);
-- * a change saves after DEBOUNCE_MS (the last change wins); death and logout save at once.
ChaosHelperSave = ChaosHelperSave or {}
local HS = ChaosHelperSave

HS.DEBOUNCE_MS = 500

local function decodes(fs, path, decode)
  if not fs.exists(path) then return nil end
  local okRead, text = pcall(fs.read, path)
  if not okRead or type(text) ~= 'string' or text == '' then return false end
  local ok, value = pcall(decode, text)
  if not ok or type(value) ~= 'table' then return false end
  return value, text
end

-- read the config: returns value (or nil), status ('ok' | 'missing' | 'broken'), source ('main' | 'bak' | 'tmp')
function HS.read(fs, path, decode)
  local anyFile = false
  for _, source in ipairs({ 'main', 'bak', 'tmp' }) do
    local p = source == 'main' and path or (path .. '.' .. source)
    local value = decodes(fs, p, decode)
    if value then
      if source ~= 'main' then
        -- put the good copy back in place (the main file is broken or missing)
        if fs.exists(path) and not fs.exists(path .. '.broken') then pcall(fs.copy, path, path .. '.broken') end
        pcall(fs.copy, p, path)
      end
      return value, 'ok', source
    end
    if value == false then anyFile = true end
  end
  if anyFile then
    if fs.exists(path) and not fs.exists(path .. '.broken') then pcall(fs.copy, path, path .. '.broken') end
    return nil, 'broken'
  end
  return nil, 'missing'
end

-- write the config text: .tmp first (read back), the old good file to .bak, then the file (read back)
function HS.write(fs, path, text, decode)
  if type(text) ~= 'string' or text == '' then return false end
  local tmp = path .. '.tmp'
  if not pcall(fs.write, tmp, text) or not decodes(fs, tmp, decode) then return false end
  if decodes(fs, path, decode) then pcall(fs.copy, path, path .. '.bak') end
  local ok = pcall(fs.write, path, text)
  if not ok or not decodes(fs, path, decode) then
    pcall(fs.copy, tmp, path)
    return type(decodes(fs, path, decode)) == 'table'
  end
  pcall(fs.delete, tmp)
  return true
end

-- ---------------------------------------------------------------- the session
function HS.newSession()
  return { key = nil, loaded = false, dirty = false, dueAt = nil }
end

-- a load starts (login, character change, a reload): no save until it finished
function HS.beginLoad(st)
  st.loaded, st.key, st.dirty, st.dueAt = false, nil, false, nil
end

-- the load of `key` finished with status 'ok', 'missing' or 'broken' (broken: the file was kept aside by read)
function HS.finishLoad(st, key, status)
  st.key = key
  st.loaded = key ~= nil and (status == 'ok' or status == 'missing' or status == 'broken')
end

function HS.canSave(st, key)
  return st.loaded == true and key ~= nil and st.key == key
end

-- a change: the save is due DEBOUNCE_MS after the last one. Returns the due time, or nil when saving is blocked
function HS.request(st, key, now)
  if not HS.canSave(st, key) then return nil end
  st.dirty = true
  st.dueAt = (tonumber(now) or 0) + HS.DEBOUNCE_MS
  return st.dueAt
end

function HS.isDue(st, now)
  return st.dirty and st.dueAt ~= nil and (tonumber(now) or 0) >= st.dueAt
end

function HS.flushed(st)
  st.dirty, st.dueAt = false, nil
end

-- logout or death: the caller writes the pending change first (if canSave), then the session ends
function HS.endSession(st)
  st.loaded, st.key, st.dirty, st.dueAt = false, nil, false, nil
end

return ChaosHelperSave
