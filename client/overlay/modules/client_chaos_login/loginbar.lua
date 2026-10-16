-- ChaosLoginBar: when the login screen's bottom bar (client_background: event schedule, boosted creature / boss,
-- casts) and each of its panels show (pure; loginbar_test.lua; client/MANIFEST.md "Login screen").
-- Owner: the bar stayed on the character select (over "Double-click a card or press Enter to play") and in game, and
-- showed empty panels when nothing served clientServicesLink. Now: the bar only with the sign-in panel itself (not
-- during the splash, not with the character list or the game open, not when the screen has no room for it); a panel
-- only with data (schedule: at least one event; boosted: a creature or a boss); casts only when the server has them
-- (Services.casts = true in init.lua, base patch 0071: our server has no cast list). No panel with data: no bar (also
-- when the service cannot be reached).
ChaosLoginBar = {}
local B = ChaosLoginBar

-- s: splash, noRoom, loginPanel (the sign-in panel is shown), charList, inGame, events (count), boosted, casts
function B.state(s)
  s = s or {}
  local screen = s.loginPanel == true and not s.splash and not s.noRoom and not s.charList and not s.inGame
  local info = (tonumber(s.events) or 0) > 0
  local boost = s.boosted == true
  local cast = s.casts == true
  return { bar = screen and (info or boost or cast), info = info, boost = boost, cast = cast }
end

-- the number of events in the schedule the service sent (EventSchedule.events: a list or a map)
function B.eventCount(events)
  if type(events) ~= 'table' then return 0 end
  local n = 0
  for _ in pairs(events) do n = n + 1 end
  return n
end

-- the shown panels side by side, centred in `width`: { {id, x} ... } (widths: { [id] = w }, order: ids)
function B.row(order, shown, widths, width, gap)
  gap = gap or 1
  local list, total = {}, 0
  for _, id in ipairs(order) do
    if shown[id] then
      list[#list + 1] = id
      total = total + (widths[id] or 0)
    end
  end
  total = total + math.max(0, #list - 1) * gap
  local x = math.floor((width - total) / 2)
  local out = {}
  for _, id in ipairs(list) do
    out[#out + 1] = { id = id, x = x }
    x = x + (widths[id] or 0) + gap
  end
  return out
end

-- a key of a state, to redo the layout only when it changes
function B.key(st)
  return (st.bar and 'B' or 'b') .. (st.info and 'I' or 'i') .. (st.boost and 'O' or 'o') .. (st.cast and 'C' or 'c')
end

return ChaosLoginBar
