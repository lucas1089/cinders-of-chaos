-- The helper's cooldown channels (pure Lua: no engine calls; tests: helpertimers_test.lua). Base patch 0062 calls it
-- from mods/game_helper (healing, magic shooter, potions, runes, special foods) as the global ChaosHelperTimers.
--
-- The server keeps a cooldown channel per kind of action (server/README.md "Cooldown channels", engine src-patch 0042):
-- attack spells and attack runes share the attack group, healing spells and healing runes the healing group, potions
-- have a channel of their own, and none of them holds another. The helper still ran everything through two shared
-- gates, so a heal and an attack waited for each other in the client although the server would take both:
--   * one rate guard for every spell cast (base patch 0026: at most 4 casts a second, all kinds together): the attack
--     rotation used up the second and the heal below 50% health waited for the next one;
--   * one object-use timer for potions and every rune (1 s), plus a "turn" that kept the next potion back 1.1 s after a
--     rune: an attack rune held the health potion, a potion held the next attack rune and the healing rune.
-- Here each channel has its own rate guard (casts: heal, attack, support) or its own timer (object uses: potion,
-- healRune, attackRune, supportRune, food). Each one stays limited on its own, so the helper never floods the server.

ChaosHelperTimers = ChaosHelperTimers or {}
local T = ChaosHelperTimers

T.defaults = {
  -- spell casts: the same words not again within sameWordsGap ms, at most maxPerSecond casts of the channel per second
  cast = {
    heal = { sameWordsGap = 500, maxPerSecond = 4 },
    attack = { sameWordsGap = 500, maxPerSecond = 4 },
    support = { sameWordsGap = 500, maxPerSecond = 3 },
  },
  -- object uses: the server's channel delays (runeChannelDelay, potionChannelDelay: 1000 ms; a special food is a
  -- plain use, the helper keeps its own 1 s)
  use = { potion = 1000, healRune = 1000, attackRune = 1000, supportRune = 1000, food = 1000 },
}

T.CAST_CHANNELS = { "heal", "attack", "support" }

local function copy(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = type(v) == "table" and copy(v) or v
  end
  return c
end

local function merge(into, from)
  for k, v in pairs(from) do
    if type(v) == "table" and type(into[k]) == "table" then
      merge(into[k], v)
    else
      into[k] = type(v) == "table" and copy(v) or v
    end
  end
end

function T.new(cfg)
  local c = copy(T.defaults)
  if cfg then
    merge(c, cfg)
  end
  local st = { cfg = c, casts = {}, uses = {} }
  for name in pairs(c.cast) do
    st.casts[name] = { last = {}, recent = {} }
  end
  return st
end

-- a spell's cast channel from its groups ({[group] = cooldown} or a group number): healing (2) -> "heal", attack (1) or
-- special (4) -> "attack", anything else -> "support"
function T.castChannel(groups)
  local has = {}
  if type(groups) == "table" then
    for k, v in pairs(groups) do
      if type(k) == "number" then
        has[k] = true
      elseif type(v) == "number" then
        has[v] = true
      end
    end
  elseif type(groups) == "number" then
    has[groups] = true
  end
  if has[2] then
    return "heal"
  end
  if has[1] or has[4] then
    return "attack"
  end
  return "support"
end

-- a rune's object-use channel from its group: the server's channel of that rune (src-patch 0042)
function T.runeChannel(groups)
  local c = T.castChannel(groups)
  if c == "heal" then
    return "healRune"
  end
  if c == "attack" then
    return "attackRune"
  end
  return "supportRune"
end

-- may this cast go out now? Records it when it may. An unknown channel counts as "support".
function T.castAllowed(st, channel, words, now)
  local guard = st.cfg.cast[channel] and channel or "support"
  local cfg, g = st.cfg.cast[guard], st.casts[guard]
  local recent = g.recent
  while recent[1] and now - recent[1] >= 1000 do
    table.remove(recent, 1)
  end
  local last = words and g.last[words]
  if #recent >= cfg.maxPerSecond or (last and now - last < cfg.sameWordsGap) then
    return false
  end
  if words then
    g.last[words] = now
  end
  recent[#recent + 1] = now
  return true
end

-- object uses
function T.useReady(st, channel, now)
  return (st.uses[channel] or 0) <= now
end

function T.used(st, channel, now, ms)
  local d = ms or st.cfg.use[channel] or 1000
  st.uses[channel] = now + d
  return st.uses[channel]
end

function T.reset(st)
  for _, g in pairs(st.casts) do
    g.last, g.recent = {}, {}
  end
  st.uses = {}
end
