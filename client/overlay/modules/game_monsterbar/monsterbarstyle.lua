-- Pure part of game_monsterbar (monsterbarstyle_test.lua): which look a monster gets, the text on the bar, the modifier
-- chips and the damage trail. The art is client/tools/gen_monsterbar_art.py (images/chaos/monsterbar/).
MonsterBarStyle = {}
local S = MonsterBarStyle

S.IMAGES = '/images/chaos/monsterbar/'

-- name: the colour of the name (and of the in-world name and bar, `world`); label: the tier word before the name
-- when the server sends none. Server tiers: monster_tiers.lua ChaosTiers; roles: guardian (a rift guardian),
-- omen (an Omen guardian).
S.STYLES = {
  normal    = { name = '#d6c9ae', label = '' },
  magic     = { name = '#7fb0ff', label = 'Magic', world = '#7fb0ff' },
  rare      = { name = '#f6cf72', label = 'Rare', world = '#f6cf72' },
  legendary = { name = '#ff9a4a', label = 'Legendary', world = '#ff9a4a' },
  boss      = { name = '#e03a1e', label = '', world = '#e03a1e' },
  guardian  = { name = '#e03a1e', label = 'Rift Guardian', world = '#e03a1e', role = true },
  omen      = { name = '#c79bff', label = 'Omen Guardian', world = '#c79bff', role = true },
}

-- the look of a monster: its role (guardian, omen) wins over its tier; anything unknown looks normal
function S.key(tier, role)
  if role and S.STYLES[role] then return role end
  if tier and S.STYLES[tier] then return tier end
  return 'normal'
end

function S.images(key)
  key = S.STYLES[key] and key or 'normal'
  return {
    frame = S.IMAGES .. 'frame_' .. key,
    fill = S.IMAGES .. 'fill_' .. key,
    plaque = S.IMAGES .. 'plaque_' .. key,
    trail = S.IMAGES .. 'trail',
  }
end

-- the name line: the server's label (Magic, Rare, Legendary) or the style's, then the name; a role's tag wins over
-- the tier's (a rift guardian is a legendary monster)
function S.title(key, label, name)
  local st = S.STYLES[key] or S.STYLES.normal
  local tag = (not st.role and type(label) == 'string' and label ~= '') and label or st.label
  name = tostring(name or '')
  if tag == '' then return name end
  return tag .. ' ' .. name
end

function S.levelText(level)
  level = tonumber(level)
  if not level or level <= 0 then return nil end
  return 'Lv ' .. math.floor(level)
end

function S.percentText(percent)
  return string.format('%d%%', math.max(0, math.min(100, math.floor(tonumber(percent) or 0))))
end

-- width in pixels of a fill of `width` at `percent` (a sliver stays visible above 0)
function S.fillWidth(percent, width)
  percent = math.max(0, math.min(100, tonumber(percent) or 0))
  local px = math.floor(width * percent / 100 + 0.5)
  if percent > 0 and px < 1 then px = 1 end
  return px
end

-- modifier chips: the name the server sends (ChaosMods[..].name) -> icon key and tooltip. The numbers are those of
-- server monster_tiers.lua.
S.MODS = {
  blazing      = 'Blazing: its hits may set you on fire (30%).',
  chilling     = 'Chilling: its hits may slow you for 3 seconds (25%).',
  venomous     = 'Venomous: its hits may poison you (30%).',
  shocking     = 'Shocking: its hits may electrify you (25%).',
  vampiric     = 'Vampiric: heals 30% of the damage it deals.',
  berserker    = 'Berserker: deals 50% more damage below half health.',
  brutal       = 'Brutal: deals 40% more damage.',
  stoneskin    = 'Stoneskin: takes 30% less damage.',
  reflective   = 'Reflective: returns 15% of the damage it takes.',
  regenerating = 'Regenerating: heals 2% of its health every 2.5 seconds.',
  swift        = 'Swift: moves faster.',
  explosive    = 'Explosive: explodes on death (5% of its health, 2 tiles).',
  juggernaut   = 'Juggernaut: 60% more health.',
}

function S.mod(name)
  local key = tostring(name or ''):lower():gsub('[^%a]', '')
  local tip = S.MODS[key]
  if tip then
    return S.IMAGES .. 'mods/' .. key, tip
  end
  return S.IMAGES .. 'mods/unknown', tostring(name or '?')
end

-- damage trail: the part of the bar just lost stays lit, holds a moment, then shrinks to the health.
-- trail = { value = percent shown lit, hold = ms left before it shrinks }
S.TRAIL_HOLD = 350     -- ms
S.TRAIL_SPEED = 60     -- percent per second at least
S.TRAIL_EASE = 0.006   -- and this share of the gap per ms (a big hit shrinks fast, then eases in)

function S.trailHit(trail, before, after)
  trail = trail or { value = after, hold = 0 }
  if after < before then
    trail.value = math.max(trail.value or before, before)
    trail.hold = S.TRAIL_HOLD
  end
  if after >= (trail.value or 0) then
    trail.value = after -- healed past it (or a new target): nothing lit
    trail.hold = 0
  end
  return trail
end

-- one step of `dt` ms toward `health`; returns the trail and whether it still moves
function S.trailStep(trail, health, dt)
  if not trail or trail.value <= health then
    if trail then trail.value, trail.hold = health, 0 end
    return trail, false
  end
  if trail.hold > 0 then
    trail.hold = math.max(0, trail.hold - dt)
    return trail, true
  end
  local gap = trail.value - health
  local step = math.max(S.TRAIL_SPEED * dt / 1000, gap * math.min(1, S.TRAIL_EASE * dt))
  trail.value = math.max(health, trail.value - step)
  return trail, trail.value > health
end
