-- Pure rules of "a container window always opens" (O485; client/MANIFEST.md "Window layout per character", client/BASE.md
-- 0191; tested by panelroom_test.lua). The base client threw a new container window away, and blamed "space", when no
-- side panel had room for one more window. Now base patch 0191 asks this plan where the window goes and which other
-- windows shrink to make room. Nothing is ever closed.
--
-- ChaosPanelRoom.plan(panels, new)
--   panels   the side panels in the order the base tries them, each
--              { id, height, reserved, windows }
--              height    the room for windows (panel height without its padding)
--              reserved  the minimap's expansion reservation: skipped, as the base does
--              windows   the visible windows now in it, each { id, height, min, kind, resizable, minimized, protected }
--                        kind 'container' or 'mini'; min = the least height the window may have (0 = not resizable)
--   new      the window to place { height, min } (it is not in `windows`)
--   returns  { action, panel, shrinks, height } or nil when there is no panel to use
--              action   'fit'    room as it is (the base rule: the height, or its minimum height, fits)
--                       'shrink' room made by shrinking other windows towards their minimum height
--                       'force'  not enough room even then: the panel with the most room, every shrinkable window at
--                                its minimum, and the window goes in anyway
--              panel    the index in `panels`
--              shrinks  { { window = index in that panel's windows, id, from, to } }, never below `min`
--              height   the height the new window gets: the room there when 'fit' (at most new.height), else its
--                       minimum height (the room just made, or the least it may have when forced)
-- Order of the shrinking: container windows first, the biggest first, then the other resizable windows, the biggest
-- first. Each is shrunk only as far as the room needed, the last one partly. A minimized window, a window that is not
-- resizable (min 0), a protected one (inventory, main buttons) and a window already at its minimum are left alone.
ChaosPanelRoom = {}
local R = ChaosPanelRoom

local function num(v, d)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return d end
  return v
end

local function used(panel)
  local sum = 0
  for _, w in ipairs(panel.windows or {}) do sum = sum + num(w.height, 0) end
  return sum
end

-- the windows that may shrink: { index, window, take = height - min }
local function shrinkable(panel)
  local list = {}
  for i, w in ipairs(panel.windows or {}) do
    local h, m = num(w.height, 0), num(w.min, 0)
    if not w.protected and not w.minimized and w.resizable ~= false and m > 0 and h > m then
      list[#list + 1] = { index = i, window = w, take = h - m, container = w.kind == 'container' }
    end
  end
  table.sort(list, function(a, b)
    if a.container ~= b.container then return a.container end
    if a.window.height ~= b.window.height then return a.window.height > b.window.height end
    return a.index < b.index
  end)
  return list
end

-- the least room the new window needs: its minimum height, never more than its height
local function required(new)
  local h = num(new.height, 0)
  local m = num(new.min, 0)
  if m > 0 and m < h then return m end
  return h
end

local function reducible(list)
  local sum = 0
  for _, s in ipairs(list) do sum = sum + s.take end
  return sum
end

-- shrinks, in order, until `deficit` is gained (or all, when deficit is nil)
local function shrinks(list, deficit)
  local out = {}
  for _, s in ipairs(list) do
    if deficit and deficit <= 0 then break end
    local take = deficit and math.min(s.take, deficit) or s.take
    out[#out + 1] = { window = s.index, id = s.window.id, from = s.window.height, to = s.window.height - take }
    if deficit then deficit = deficit - take end
  end
  return out
end

function R.plan(panels, new)
  new = new or {}
  local want = num(new.height, 0)
  local need = required(new)
  local usable = {}
  for i, p in ipairs(panels or {}) do
    if not p.reserved then usable[#usable + 1] = i end
  end
  if #usable == 0 then return nil end

  -- 1) room as it is, the first panel in the base's order
  for _, i in ipairs(usable) do
    local empty = num(panels[i].height, 0) - used(panels[i])
    if empty >= need then
      return { action = 'fit', panel = i, shrinks = {}, height = math.min(want, empty) }
    end
  end

  -- 2) make room by shrinking, in the panel with the most room (the first one on a tie)
  local best, bestRoom, bestList, bestEmpty
  for _, i in ipairs(usable) do
    local empty = num(panels[i].height, 0) - used(panels[i])
    local list = shrinkable(panels[i])
    local room = empty + reducible(list)
    if not best or room > bestRoom then best, bestRoom, bestList, bestEmpty = i, room, list, empty end
  end
  if bestRoom >= need then
    return { action = 'shrink', panel = best, shrinks = shrinks(bestList, need - bestEmpty), height = need }
  end

  -- 3) last resort: the same panel, everything shrinkable at its minimum, the window goes in anyway
  return { action = 'force', panel = best, shrinks = shrinks(bestList, nil), height = need }
end

return R
