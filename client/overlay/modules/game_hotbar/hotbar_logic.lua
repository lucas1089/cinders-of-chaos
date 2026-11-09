-- Pure rules of the central hotbar (client/MANIFEST.md "Floating chat and central hotbar (O414)"; hotbar_test.lua):
-- the size of the bar from the slot count, the scale and the globes, fitting it into a window, its place and the drag,
-- which slot of the first action bar goes where, the cooldown number, the event line above the slots, the saved
-- settings. Global HotbarLogic. The geometry numbers are the size of the art drawn by tools/gen_hotbar_art.py, which
-- checks them (--check).
HotbarLogic = {}
local L = HotbarLogic

-- ------------------------------------------------------------------ art geometry (unscaled pixels)
L.SLOT_FRAME = 44      -- frame of one slot (the base button, 36 px, sits inside it)
L.BUTTON = 36
L.SLOT_GAP = 4
L.KEY_W = 30           -- the key label box under a slot
L.KEY_H = 14
L.KEY_BORDER = 4
L.SOCKET = 44          -- the round side slots
L.SOCKET_GAP = 8       -- socket <-> first slot
L.BODY_H = 84          -- the iron frame
L.BODY_BORDER = 20
L.CAP_CLOSED_W = 26    -- an end without a globe
L.CAP_OPEN_W = 22
L.PAD_X = 14           -- frame edge <-> socket
L.SLOT_TOP = 14        -- body top <-> slot frame top
L.LINE_H = 14          -- the event line above the body
L.ORB_BASE = 110       -- diameter of a globe at 100%
L.ORB_PAD = 6          -- globe <-> bar
L.BOTTOM_GAP = 4       -- bar <-> window's bottom edge

-- ------------------------------------------------------------------ options
L.COUNTS = { 6, 8, 10, 12 }
L.DEFAULT_COUNT = 8
L.SCALE_MIN = 75
L.SCALE_MAX = 125
L.SCALE_STEP = 5
L.DEFAULT_SCALE = 100
L.FIT_MIN_SCALE = 60   -- a window too small for the wanted bar shrinks it to this, then drops slots
L.FIT_MIN_COUNT = 4
L.SOCKET_SLOTS = { potion = 13, utility = 14 } -- slots of the first action bar, past the 12 that can be shown
L.SOCKET_KEYS = { potion = 'Q', utility = 'E' }  -- shown when the slot has no hotkey of its own
L.NODE = 'chaos_hotbar'
L.SNAP = 10

local function num(v)
  v = tonumber(v)
  if v and v == v and v ~= math.huge and v ~= -math.huge then return v end
  return nil
end

local function round(v) return math.floor(v + 0.5) end

function L.clampScale(v)
  v = num(v) or L.DEFAULT_SCALE
  v = round(v / L.SCALE_STEP) * L.SCALE_STEP
  return math.max(L.SCALE_MIN, math.min(L.SCALE_MAX, v))
end

-- the nearest allowed slot count (6, 8, 10 or 12)
function L.clampCount(v)
  v = num(v)
  if not v then return L.DEFAULT_COUNT end
  local best, bd = L.COUNTS[1], math.huge
  for _, c in ipairs(L.COUNTS) do
    local d = math.abs(c - v)
    if d < bd then best, bd = c, d end
  end
  return best
end

-- ------------------------------------------------------------------ size
-- opts: count, scale (percent), globes (boolean). Every length is rounded to whole pixels at that scale.
function L.metrics(opts)
  opts = opts or {}
  -- raw: no option clamps (what fit may give back is under the option range)
  local count = opts.raw and math.floor(num(opts.count) or L.DEFAULT_COUNT) or L.clampCount(opts.count)
  local pct = opts.raw and (num(opts.scale) or 100) or L.clampScale(opts.scale)
  local s = pct / 100
  local globes = opts.globes ~= false
  local function px(v) return round(v * s) end
  local m = { count = count, scale = pct, globes = globes }
  m.slot, m.gap, m.button = px(L.SLOT_FRAME), px(L.SLOT_GAP), px(L.BUTTON)
  m.pitch = m.slot + m.gap
  m.socket, m.socketGap, m.pad = px(L.SOCKET), px(L.SOCKET_GAP), px(L.PAD_X)
  m.keyW, m.keyH = px(L.KEY_W), px(L.KEY_H)
  m.bodyH, m.lineH, m.slotTop = px(L.BODY_H), px(L.LINE_H), px(L.SLOT_TOP)
  m.orb = globes and round(L.ORB_BASE * s) or 0
  m.capW = globes and (m.orb + px(L.ORB_PAD)) or px(L.CAP_CLOSED_W)
  m.cellsW = count * m.slot + (count - 1) * m.gap
  m.innerW = 2 * m.pad + 2 * (m.socket + m.socketGap) + m.cellsW
  m.width = m.innerW + 2 * m.capW
  -- the globes rise over the body when they are taller than it
  m.height = math.max(m.lineH + m.bodyH, m.orb)
  m.bodyTop = m.height - m.bodyH
  -- x of the parts from the bar's left edge
  m.socketLX = m.capW + m.pad
  m.slotsX = m.socketLX + m.socket + m.socketGap
  m.socketRX = m.slotsX + m.cellsW + m.socketGap
  m.slotY = m.bodyTop + m.slotTop
  m.socketY = m.slotY + round((m.slot - m.socket) / 2)
  m.keyY = m.slotY + m.slot - round(4 * s)
  m.lineY = m.bodyTop - m.lineH
  return m
end

-- The options that fit `available` pixels of width: the scale goes down in steps to FIT_MIN_SCALE first, then
-- the slot count down by 2 (never under FIT_MIN_COUNT). Returns the fitted options, whether anything was cut, and
-- the bar's metrics for them (a fitted bar is under the option range, so use these, not metrics(opts)).
function L.fit(opts, available)
  opts = opts or {}
  local o = { count = L.clampCount(opts.count), scale = L.clampScale(opts.scale), globes = opts.globes ~= false }
  available = num(available) or math.huge
  local cut = false
  local function size() return L.metrics({ count = o.count, scale = o.scale, globes = o.globes, raw = true }) end
  while size().width > available and o.scale > L.FIT_MIN_SCALE do
    o.scale = math.max(L.FIT_MIN_SCALE, o.scale - L.SCALE_STEP)
    cut = true
  end
  while size().width > available and o.count - 2 >= L.FIT_MIN_COUNT do
    o.count = o.count - 2
    cut = true
  end
  return o, cut, size()
end

-- ------------------------------------------------------------------ place
-- Place the bar sideways and up.
--   regionLeft, regionRight  the game area between the side panels
--   width, height            the bar
--   x                        left edge from regionLeft; nil = centred in the region
--   lift                     pixels over the window's bottom gap
--   windowHeight
-- Returns { left, top-lift-clamped lift, x (nil when centred), centredLeft, bottom (distance of the bar's bottom
-- edge from the window's bottom edge) }.
function L.place(p)
  local left = math.floor(num(p.regionLeft) or 0)
  local right = math.max(left, math.floor(num(p.regionRight) or left))
  local width = math.floor(num(p.width) or 0)
  local centred = left + math.floor((right - left - width) / 2)
  local x = num(p.x)
  local at = x and (left + math.floor(x)) or centred
  at = math.max(left, math.min(math.max(left, right - width), at))
  local maxLift = math.max(0, math.floor((num(p.windowHeight) or 0) - (num(p.height) or 0) - L.BOTTOM_GAP))
  local lift = math.max(0, math.min(maxLift, math.floor(num(p.lift) or 0)))
  return { left = at, lift = lift, x = x and (at - left) or nil, centredLeft = centred,
           bottom = L.BOTTOM_GAP + lift }
end

-- the place while the bar is dragged by its handle: where it was at the press plus the mouse travel
-- (start = { left, lift, mouseX, mouseY })
function L.dragPlace(start, mouseX, mouseY, regionLeft)
  local dx = math.floor((num(mouseX) or 0) - (num(start.mouseX) or 0))
  local dy = math.floor((num(mouseY) or 0) - (num(start.mouseY) or 0))
  return (num(start.left) or 0) + dx - (num(regionLeft) or 0), math.max(0, (num(start.lift) or 0) - dy)
end

-- at the end of a move: back to the centre (x nil) when within SNAP of it, onto the bottom when within SNAP
function L.snap(place)
  local x = place.x
  if x == nil or math.abs(place.left - place.centredLeft) <= L.SNAP then x = nil end
  local lift = place.lift
  if lift <= L.SNAP then lift = 0 end
  return x, lift
end

function L.rect(placed, m, windowHeight)
  return { x = placed.left, y = (num(windowHeight) or 0) - placed.bottom - m.height, width = m.width, height = m.height }
end

function L.overlap(a, b)
  if not a or not b then return false end
  return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

-- ------------------------------------------------------------------ slots of the first action bar
-- total: slots the bar has. Returns { shown = {1..count}, potion = index | nil, utility = index | nil, hidden = list }.
-- The sockets use slots 13 and 14 whatever the count is, so a slot never changes its spell when the count changes.
function L.slotPlan(total, count)
  total = math.max(0, math.floor(num(total) or 0))
  count = math.max(1, math.floor(num(count) or L.DEFAULT_COUNT)) -- a fitted bar may have fewer than 6
  local plan = { shown = {}, hidden = {} }
  local socket = {}
  for kind, idx in pairs(L.SOCKET_SLOTS) do
    if idx <= total then plan[kind] = idx socket[idx] = true end
  end
  for i = 1, total do
    if i <= count and i <= total then plan.shown[#plan.shown + 1] = i
    elseif not socket[i] then plan.hidden[#plan.hidden + 1] = i end
  end
  return plan
end

-- the label of a key box: the slot's own hotkey text, the socket's default key, or empty
function L.keyLabel(hotkey, socketKind)
  local t = type(hotkey) == 'string' and hotkey:gsub('^%s+', ''):gsub('%s+$', '') or ''
  if t ~= '' then
    t = t:gsub('Shift%+', 'S+'):gsub('Ctrl%+', 'C+'):gsub('Alt%+', 'A+')
    if #t > 5 then t = t:sub(1, 5) end
    return t
  end
  return socketKind and L.SOCKET_KEYS[socketKind] or ''
end

-- ------------------------------------------------------------------ default keys (owner: hotkeys 1-8 by default)
-- The base hotkey sets (Options.array.hotkeyOptions.hotkeySets[name].chatOn / .chatOff, lists of
-- { actionsetting = { action = 'TriggerActionButton_<bar>.<slot>' }, keysequence = 'F1' }) give the slots of the first
-- bar the stock keys F1..F12. Slots 1..8 get the number keys, slots 13 and 14 (the sockets) get Q and E. Only the
-- "Chat Off" list is touched: that is the mode where the movement keys work. In "Chat On" the keys go to the chat line,
-- so the digits and letters must stay free there; its F keys stay (the F keys work in both modes).
-- Rule per default, in one set, one time (the caller keeps the done flag per set):
--   a slot with the stock key (or a blank one) gets the new key; a slot with no entry gets it (fresh set);
--   a slot with any other key keeps it (the player's own choice, never replaced);
--   a key held by another entry is not taken, except Go North-West / Go North-East (Q and E of the stock walking
--   set): their entries are dropped, the numpad keys still walk the diagonals.
L.DEFAULT_KEY_SLOTS = {
  { slot = 1, key = '1', stock = 'F1' }, { slot = 2, key = '2', stock = 'F2' }, { slot = 3, key = '3', stock = 'F3' },
  { slot = 4, key = '4', stock = 'F4' }, { slot = 5, key = '5', stock = 'F5' }, { slot = 6, key = '6', stock = 'F6' },
  { slot = 7, key = '7', stock = 'F7' }, { slot = 8, key = '8', stock = 'F8' },
  { slot = L.SOCKET_SLOTS.potion, key = L.SOCKET_KEYS.potion }, { slot = L.SOCKET_SLOTS.utility, key = L.SOCKET_KEYS.utility },
}
L.KEY_STEAL_ACTIONS = { GoNorthWest = true, GoNorthEast = true }
L.KEYS_NODE = 'chaos_hotbar_keys'

local function lower(v) return type(v) == 'string' and v:lower() or nil end

-- Applies the default keys to one chatOff list of a bar (barNumber 1 = the first bottom bar). Returns true when the
-- list changed, then the slots left alone because another entry holds their key.
function L.applyDefaultKeys(list, barNumber)
  if type(list) ~= 'table' then return false, {} end
  barNumber = math.floor(num(barNumber) or 1)
  local changed, skipped = false, {}
  for _, d in ipairs(L.DEFAULT_KEY_SLOTS) do
    local action = 'TriggerActionButton_' .. barNumber .. '.' .. d.slot
    local entry
    for _, e in ipairs(list) do
      local a = type(e) == 'table' and type(e.actionsetting) == 'table' and e.actionsetting.action
      if a == action and not e.secondary then entry = e break end
    end
    local want = lower(d.key)
    local current = entry and lower(entry.keysequence) or ''
    local replace = entry == nil or current == '' or (d.stock ~= nil and current == lower(d.stock))
    if replace and current ~= want then
      local holders, blocked = {}, false
      for i, e in ipairs(list) do
        if e ~= entry and type(e) == 'table' and lower(e.keysequence) == want then
          local a = type(e.actionsetting) == 'table' and e.actionsetting.action
          if a and L.KEY_STEAL_ACTIONS[a] and not e.secondary then holders[#holders + 1] = i else blocked = true end
        end
      end
      if blocked then
        skipped[#skipped + 1] = d.slot
      else
        for k = #holders, 1, -1 do table.remove(list, holders[k]) end
        if entry then entry.keysequence = d.key
        else list[#list + 1] = { actionsetting = { action = action }, keysequence = d.key } end
        changed = true
      end
    end
  end
  return changed, skipped
end

-- applyDefaultKeys over the chatOff list of every hotkey set not yet in `done` ({ [setName] = true }, kept by the caller
-- in g_settings node L.KEYS_NODE; a key the player clears later stays cleared). Returns: the set named `current` changed,
-- any set changed, the updated done table.
function L.applyToSets(sets, done, current, barNumber)
  done = type(done) == 'table' and done or {}
  local anyChanged, currentChanged = false, false
  if type(sets) ~= 'table' then return false, false, done end
  for name, set in pairs(sets) do
    if type(set) == 'table' and type(set.chatOff) == 'table' and not done[name] then
      if L.applyDefaultKeys(set.chatOff, barNumber) then
        anyChanged = true
        if name == current then currentChanged = true end
      end
      done[name] = true
    end
  end
  return currentChanged, anyChanged, done
end

-- ------------------------------------------------------------------ cooldown number
-- The big number on a slot: whole seconds left rounded up, one decimal under 2 s, "1m" from 60 s, nothing without a
-- cooldown. Also the dark fill's share (0..1, the part still to wait).
function L.cooldown(durationMs, elapsedMs)
  local d, e = num(durationMs) or 0, num(elapsedMs) or 0
  if d <= 0 or e >= d then return '', 0 end
  local left = d - math.max(0, e)
  local share = math.min(1, left / d)
  if left >= 60000 then return math.ceil(left / 60000) .. 'm', share end
  if left < 2000 then return string.format('%.1f', math.ceil(left / 100) / 10), share end
  return tostring(math.ceil(left / 1000)), share
end

-- ------------------------------------------------------------------ the event line
L.EVENT_SHOW_MS = 4000  -- full for this long
L.EVENT_FADE_MS = 1000  -- then it fades out (5 s in all)

-- A game message as a short event, or nil: "Loot of a rat: 3 gold coins" -> "Gained 3 gold coins",
-- "You advanced to Level 120" -> "Level 120". Anything else is no event.
function L.eventFromMessage(text)
  if type(text) ~= 'string' then return nil end
  local items = text:match('^[Ll]oot of [^:]*:%s*(.+)$')
  if items then
    if items:lower() == 'nothing' then return nil end
    items = items:gsub('%.$', '')
    if #items > 60 then items = items:sub(1, 57) .. '...' end
    return 'Gained ' .. items
  end
  local lvl = text:match('[Aa]dvanced from Level %d+ to Level (%d+)') or text:match('[Aa]dvanced to [Ll]evel (%d+)')
  if lvl then return 'Level ' .. lvl end
  return nil
end

-- state of the line: { text, at } ; the newest event replaces the one before
function L.pushEvent(state, text, now)
  state = state or {}
  if type(text) == 'string' and text ~= '' then state.text, state.at = text, num(now) or 0 end
  return state
end

-- text and opacity (0..1) of the line at `now`
function L.eventLine(state, now)
  if not state or not state.text then return '', 0 end
  local age = (num(now) or 0) - (state.at or 0)
  if age < 0 or age >= L.EVENT_SHOW_MS + L.EVENT_FADE_MS then return '', 0 end
  if age <= L.EVENT_SHOW_MS then return state.text, 1 end
  return state.text, 1 - (age - L.EVENT_SHOW_MS) / L.EVENT_FADE_MS
end

-- ------------------------------------------------------------------ settings
-- the saved options of one character (g_settings node L.NODE) with every value clamped; defaults for a new one
function L.settingsFor(saved, name)
  local e = type(saved) == 'table' and name and saved[name] or nil
  if type(e) ~= 'table' then e = {} end
  local globes = e.globes
  if globes == 'false' or globes == 0 then globes = false end
  return { count = L.clampCount(e.count), scale = L.clampScale(e.scale), globes = globes ~= false,
           x = num(e.x) and math.floor(num(e.x)) or nil, lift = math.max(0, math.floor(num(e.lift) or 0)) }
end

function L.store(saved, name, s)
  saved = type(saved) == 'table' and saved or {}
  if not name then return saved end
  saved[name] = { count = L.clampCount(s.count), scale = L.clampScale(s.scale), globes = s.globes ~= false,
                  x = s.x and math.floor(s.x) or nil, lift = math.max(0, math.floor(num(s.lift) or 0)) }
  return saved
end

-- the diameter of the globes for the docked bar (game_shaderfx scales its art to it)
function L.orbDiameter(scale)
  return round(L.ORB_BASE * (L.clampScale(scale) / 100))
end

return HotbarLogic
