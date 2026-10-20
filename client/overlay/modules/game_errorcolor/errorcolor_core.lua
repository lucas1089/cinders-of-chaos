-- Pure helpers of the error colour (no engine calls, unit tested by errorcolor_test.lua).
-- The stock client shows the server's error lines ("You cannot use this object.", "You do not have enough mana.") with the
-- status-small settings, which are white and shared with other messages. withColor makes a copy for the error mode only.
ErrorColor = {}

ErrorColor.COLOR = '#ff7a5c' -- readable on grass, snow and cave floors, clearly not the warning red of broadcasts

-- a copy of a message settings table with another colour; nil when there is nothing to copy
function ErrorColor.withColor(base, color)
  if type(base) ~= 'table' then return nil end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  if type(color) == 'string' and color:match('^#%x%x%x%x%x%x$') then out.color = color else out.color = ErrorColor.COLOR end
  return out
end

-- Gives types[mode] the coloured copy; returns the previous entry to put back (false when nothing was there / nothing
-- to do). Calling it twice keeps the first previous entry: a marked copy is not copied again.
function ErrorColor.apply(types, mode, color)
  if type(types) ~= 'table' or mode == nil then return false end
  local cur = types[mode]
  if type(cur) ~= 'table' or cur.chaosError then return false end
  local copy = ErrorColor.withColor(cur, color)
  copy.chaosError = true
  types[mode] = copy
  return cur
end

function ErrorColor.restore(types, mode, previous)
  if type(types) == 'table' and mode ~= nil and previous then types[mode] = previous end
end

return ErrorColor
