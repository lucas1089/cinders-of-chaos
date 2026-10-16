-- Pure rules of game_chaoslayout (client/MANIFEST.md "Window layout per character"; tested by layout_test.lua).
-- ChaosLayoutLogic: the saved layout of one character, { panels = { left = n, right = n }, mini = { [windowId] =
-- { panel, side, index, height, minimized, closed, locked } }, windows = { [windowId] = { x, y, width, height } } }.
ChaosLayoutLogic = {}
local L = ChaosLayoutLogic

L.NODE = 'chaos_layout'

-- the settings key of a character: world and name (two characters of one name on two worlds stay apart)
function L.key(world, name)
  if type(name) ~= 'string' or name == '' then return nil end
  return (type(world) == 'string' and world ~= '' and world or '-') .. '/' .. name
end

-- a window that may be remembered: an id, not a container window (their ids are slots, not containers)
function L.remembered(id)
  return type(id) == 'string' and id ~= '' and not id:find('^container') and not id:find('^widget')
end

-- the miniwindows of the side panels now. containers: { { id, side, windows = { { id, height, minimized, visible,
-- locked, resizeable } } } } in panel order, each container's windows in their order
function L.snapshot(containers)
  local mini = {}
  local panels = { left = 0, right = 0 }
  for _, c in ipairs(containers or {}) do
    if c.side == 'left' or c.side == 'right' then panels[c.side] = panels[c.side] + (c.persistent and 1 or 0) end
    local index = 0
    for _, w in ipairs(c.windows or {}) do
      if L.remembered(w.id) then
        index = index + 1
        mini[w.id] = { panel = c.id, side = c.side, index = index, height = tonumber(w.height),
          minimized = w.minimized == true, closed = w.visible == false, locked = w.locked == true }
      end
    end
  end
  return { mini = mini, panels = panels }
end

-- the saved layout after a snapshot: windows in the snapshot replace their entries; a window that does not exist now
-- (a panel opened later this session, a module not loaded) keeps its entry
function L.merge(saved, snap)
  local out = { mini = {}, windows = {}, panels = snap.panels or (saved and saved.panels) or {} }
  for id, e in pairs(saved and saved.mini or {}) do out.mini[id] = e end
  for id, e in pairs(snap.mini or {}) do out.mini[id] = e end
  for id, r in pairs(saved and saved.windows or {}) do out.windows[id] = r end
  for id, r in pairs(snap.windows or {}) do out.windows[id] = r end
  return out
end

-- where each saved window goes. existing: { [panelId] = side } of the panels now; first: { left = id, right = id }.
-- A panel that does not exist now (fewer side panels) gives the first panel of its side. Returns { [panelId] =
-- { entries sorted by index } } with entry.id set.
function L.placement(saved, existing, first)
  local out = {}
  for id, e in pairs(saved and saved.mini or {}) do
    if L.remembered(id) then
      local panel = e.panel
      if not (existing and existing[panel]) then panel = first and first[e.side] end
      if panel then
        out[panel] = out[panel] or {}
        local c = {}
        for k, v in pairs(e) do c[k] = v end
        c.id = id
        table.insert(out[panel], c)
      end
    end
  end
  for _, list in pairs(out) do
    table.sort(list, function(a, b)
      if (a.index or 0) ~= (b.index or 0) then return (a.index or 0) < (b.index or 0) end
      return a.id < b.id
    end)
  end
  return out
end

-- a window's rect inside the area (the game window): size between its minimum and the area, position inside it
function L.clampRect(rect, area, minimum)
  area = area or { x = 0, y = 0, width = 0, height = 0 }
  minimum = minimum or {}
  local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
  local aw, ah = math.max(0, area.width or 0), math.max(0, area.height or 0)
  local w = clamp(math.floor(tonumber(rect.width) or minimum.width or 0), math.min(minimum.width or 0, aw), aw)
  local h = clamp(math.floor(tonumber(rect.height) or minimum.height or 0), math.min(minimum.height or 0, ah), ah)
  local x = clamp(math.floor(tonumber(rect.x) or area.x), area.x, area.x + aw - w)
  local y = clamp(math.floor(tonumber(rect.y) or area.y), area.y, area.y + ah - h)
  return { x = x, y = y, width = w, height = h }
end

-- a stable text of a layout, to see whether it changed
function L.serialize(t)
  if type(t) ~= 'table' then return tostring(t) end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. '=' .. L.serialize(t[k]) end
  return '{' .. table.concat(out, ',') .. '}'
end

-- the session: nothing is saved until this character's layout was restored (never defaults over the saved one)
function L.newSession() return { key = nil, ready = false, last = nil } end
function L.begin(st) st.key, st.ready, st.last = nil, false, nil end
function L.restored(st, key, saved) st.key, st.ready, st.last = key, key ~= nil, L.serialize(saved or {}) end
function L.canSave(st, key) return st.ready and key ~= nil and st.key == key end

-- whether the layout should be written now (it changed since the last write or restore)
function L.changed(st, layout)
  local text = L.serialize(layout)
  if text == st.last then return false end
  st.last = text
  return true
end

return ChaosLayoutLogic
