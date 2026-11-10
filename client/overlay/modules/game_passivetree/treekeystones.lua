-- Keystone cap of the passive tree window (O447, owner decision of 2026-11-09): a character holds at most 3 keystones.
-- The server enforces it (server/data/scripts/chaos/passivetree_core.lua checkKeystones) and sends the live number as
-- sendNodes `keystoneMax`; this file only counts what the window shows and tells the player before the server has to
-- refuse. Pure logic, no client API (tested by treekeystones_test.lua, which pins DEFAULT_MAX to the server config).
-- A keystone is a node the tree data marks isKeystone: the same 47 nodes the server counts. Masteries and class notables
-- are not keystones.
TreeKeystones = {}
local T = TreeKeystones

-- the cap before the first sendNodes arrives (passivetree_config.lua keystoneMax)
T.DEFAULT_MAX = 3

-- the cap from the server's sendNodes (a whole number, 0 or more), else the default
function T.max(value)
  value = tonumber(value)
  if value and value >= 0 and value == math.floor(value) then
    return value
  end
  return T.DEFAULT_MAX
end

-- the keystones among the ids of the given sets (a list {id, ...} or a set {[id] = true}); an id in two sets counts once
function T.held(nodes, ...)
  local seen, count = {}, 0
  local function take(id)
    id = tonumber(id)
    local node = id and nodes[id]
    if node and node.isKeystone and not seen[id] then
      seen[id] = true
      count = count + 1
    end
  end
  for i = 1, select('#', ...) do
    local set = select(i, ...)
    for key, value in pairs(type(set) == 'table' and set or {}) do
      if type(value) == 'boolean' then
        if value then take(key) end
      else
        take(value)
      end
    end
  end
  return count
end

-- the keystones of a path (a list of ids) the character does not own yet (owned: a set)
function T.newOnPath(nodes, owned, path)
  local count = 0
  for _, id in ipairs(path or {}) do
    local node = nodes[id]
    if node and node.isKeystone and not (owned and owned[id]) then
      count = count + 1
    end
  end
  return count
end

-- true when taking `extra` more keystones would go past the cap
function T.over(held, extra, max)
  return held + extra > T.max(max)
end

return T
