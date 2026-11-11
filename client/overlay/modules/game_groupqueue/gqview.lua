-- Pure helpers of the Group Queue window (no client API; tested by gqview_test.lua with plain Lua).
local function tr(s, ...) local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr) if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
GqView = {}
local V = GqView

V.ARENA_SIZE = { ['1v1'] = 1, ['2v2'] = 2, ['3v3'] = 3 }
V.ARENA_ORDER = { '1v1', '2v2', '3v3' }
V.COLORS = { text = '#d6c9ae', dim = '#8c8070', good = '#6fd8a8', warn = '#f6cf72', bad = '#e03a1e' }

local function num(v, d) return tonumber(v) or d or 0 end

-- 75 -> "1:15"
function V.clock(s)
  s = math.max(0, math.floor(num(s)))
  return string.format('%d:%02d', math.floor(s / 60), s % 60)
end

-- in a group (queued or in a ready check)
function V.inGroup(state)
  return type(state) == 'table' and type(state.group) == 'table'
end

-- may this player change the choice and join? (alone, or the party leader, and not queued yet)
function V.canEdit(state)
  return type(state) == 'table' and state.enabled ~= false and state.leader == true and not V.inGroup(state)
end

-- the arena buttons: {mode, enabled, checked, tooltip}; only the mode of the party's size can be picked
function V.arenaOptions(state, sel)
  local out = {}
  local size = num(state and state.size, 1)
  local order = (state and state.arena and type(state.arena.order) == 'table') and state.arena.order or V.ARENA_ORDER
  for _, mode in ipairs(order) do
    local need = V.ARENA_SIZE[mode] or 0
    local fits = need == size
    out[#out + 1] = {
      mode = mode,
      enabled = fits and V.canEdit(state),
      checked = sel and sel.arena == mode or false,
      tooltip = need == 1 and tr('Arena 1v1: alone.') or tr('Arena %s: a party of exactly %d.', mode, need),
    }
  end
  return out
end

-- the difficulties a dungeon offers: 1 .. its unlocked maximum, or its one fixed difficulty
function V.difficulties(dungeon)
  if type(dungeon) ~= 'table' then return { 1 } end
  if tonumber(dungeon.fixed) then return { math.floor(dungeon.fixed) } end
  local out = {}
  for d = 1, math.max(1, math.floor(num(dungeon.max, 1))) do out[#out + 1] = d end
  return out
end

-- the request for "join" from the choice {arena = mode|nil, bg = bool, dungeon = bool, dungeonId, difficulty}
function V.payload(sel)
  local p = {}
  if type(sel) ~= 'table' then return p end
  if sel.arena then p.arena = sel.arena end
  if sel.bg then p.bg = true end
  if sel.dungeon and tonumber(sel.dungeonId) then
    p.dungeon = { id = math.floor(sel.dungeonId), difficulty = math.floor(num(sel.difficulty, 1)) }
  end
  return p
end

-- true, or false + the reason the Join button is off
function V.joinable(state, sel)
  if type(state) ~= 'table' then return false, tr('Waiting for the server.') end
  if state.enabled == false then return false, tr('The Group Queue is closed.') end
  if V.inGroup(state) then return false, '' end
  if state.leader ~= true then return false, tr('Only the party leader can queue the party.') end
  local p = V.payload(sel)
  if not (p.arena or p.bg or p.dungeon) then return false, tr('Pick at least one queue.') end
  if p.arena and V.ARENA_SIZE[p.arena] ~= num(state.size, 1) then
    return false, tr('Arena: 1v1 is played alone, 2v2 as a party of two, 3v3 as a party of three.')
  end
  local max = num(state.bg and state.bg.partyMax, 5)
  if p.bg and num(state.size, 1) > max then return false, tr('Your party is too large for the battleground.') end
  return true, ''
end

-- the status block: list of {text, color}
function V.statusLines(state, elapsed)
  local out = {}
  if type(state) ~= 'table' then return out end
  local g = state.group
  if type(g) ~= 'table' then
    out[#out + 1] = { text = tr('Not queued.'), color = V.COLORS.dim }
    if state.inParty and state.leader ~= true then
      out[#out + 1] = { text = tr('Your party leader picks the queues.'), color = V.COLORS.dim }
    end
    return out
  end
  local names = {}
  for _, p in ipairs(type(g.picks) == 'table' and g.picks or {}) do names[#names + 1] = tostring(p.label or p.key) end
  out[#out + 1] = { text = tr('Queued for: %s', table.concat(names, ', ')), color = V.COLORS.good }
  out[#out + 1] = { text = tr('Waiting %s', V.clock(num(g.waited) + num(elapsed))), color = V.COLORS.text }
  if type(g.check) == 'table' then
    out[#out + 1] = { text = tr('Ready check: %s, %d of %d ready', tostring(g.check.label or g.check.key),
      num(g.check.accepted), num(g.check.total)), color = V.COLORS.warn }
  elseif g.ready then
    out[#out + 1] = { text = tr('Everyone is ready: the match starts as soon as it can.'), color = V.COLORS.good }
  end
  out[#out + 1] = { text = tr('When a queue finds a match, you leave the others. A party gets a ready check first.'),
    color = V.COLORS.dim }
  return out
end

-- the ready check popup: title, the line under it, the bar percent (0-100), seconds left
function V.check(c, elapsed, total)
  if type(c) ~= 'table' then return nil end
  total = math.max(1, num(total, 20))
  local left = math.max(0, num(c.left) - num(elapsed))
  return {
    title = tr('%s is ready to start', tostring(c.label or c.key or '?')),
    sub = tr('%d of %d party members ready', num(c.accepted), math.max(1, num(c.total, 1))),
    percent = math.floor(math.min(100, 100 * left / total) + 0.5),
    left = left,
    timer = V.clock(left),
    answered = c.mine == true,
  }
end

return V
