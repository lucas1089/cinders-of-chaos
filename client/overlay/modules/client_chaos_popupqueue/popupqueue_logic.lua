-- One popup at a time (F46, O772). A big level jump used to open its centre popups together: the Helper's "New spell
-- available", the mentor offer "Want a mentor?" and the level survey lay on top of each other. A popup that comes by
-- itself now asks this queue; it opens when no other popup is on screen and the screen has been clear for SETTLE_MS, in
-- the order the popups came. Pure logic: the engine side (popupqueue.lua) says what is on screen and when.
local Q = {}

Q.SETTLE_MS = 400 -- the screen stays clear this long before the next popup opens (a box opening in the same burst wins)

function Q.new()
  return { list = {}, current = nil, clearSince = nil }
end

-- add a popup; a popup with the same key already waiting takes the new opener in its place (its turn is kept).
-- Returns 'now' when the popup is the one on screen (the caller refreshes it at once), else 'queued'.
function Q.push(s, key, entry)
  entry.key = key
  if s.current and s.current.key == key then
    s.current = entry
    return 'now'
  end
  for i, e in ipairs(s.list) do
    if e.key == key then
      s.list[i] = entry
      return 'queued'
    end
  end
  s.list[#s.list + 1] = entry
  return 'queued'
end

function Q.remove(s, key)
  for i = #s.list, 1, -1 do
    if s.list[i].key == key then table.remove(s.list, i) end
  end
  if s.current and s.current.key == key then
    s.current = nil
  end
end

function Q.clear(s)
  s.list, s.current, s.clearSince = {}, nil, nil
end

function Q.pending(s)
  return #s.list > 0 or s.current ~= nil
end

-- one look: now in ms; blocked = another popup (not of this queue) is on screen; currentOpen = the popup this queue
-- opened is still on screen. Returns the entry to open now, or nil.
function Q.step(s, now, blocked, currentOpen)
  if s.current then
    if currentOpen then return nil end
    s.current = nil -- closed: the next one waits for a clear screen
    s.clearSince = nil
  end
  if blocked or #s.list == 0 then
    s.clearSince = nil
    return nil
  end
  if not s.clearSince then
    s.clearSince = now
    return nil
  end
  if now - s.clearSince < Q.SETTLE_MS then return nil end
  local e = table.remove(s.list, 1)
  s.current, s.clearSince = e, nil
  return e
end

PopupQueueLogic = Q
return Q
