-- ChaosHelperSupport: the helper's "Support spells" section (pure Lua: no engine calls; tests: supportspells_test.lua).
-- The glue (the tab, the rows, the cycle) is supportspells_ui.lua; Auto setup (game_helperrotation/autosetup.lua) asks
-- H.autoPlan which spells go where.
--
-- Owner, 2026-10-18: "O auto setup coloca poucas magias no timer. Acho que seria bom a gente ter um espaço no helper só
-- pra spells de suporte pra serem castadas off the CD." The helper's Timer rules are blind (the words go out when a
-- fixed time passed, whatever the server answers) and the Auto setup only knew a hand-written list of 1 to 3 buffs per
-- class. The Support spells section is a list of up to H.SUPPORT_MAX support spells the helper casts by itself, in
-- priority order, whenever they are off cooldown and, for a buff, while the buff is not active:
--   * eligible = a support spell (spell group 3 without the attack group 1) that needs no target and no typed name,
--     is on the server and is not a utility (light, rope, teleport home, a dash ...). What counts comes from the
--     spell data (groups, parameter, needTarget), not from a class list: a support spell added later shows up by itself;
--   * the buff is "active" when the buff bar (game_buffbar, the server's list) shows a buff of the spell's name; when the
--     bar cannot tell (no bar data, or it never showed this spell's buff) while the spell's own duration since our
--     last cast has not run out, else for H.RECAST_MIN_MS (or its cooldown, if longer) after our last cast;
--   * a summon whose creatures are known (capped ones, H.KINDS minions) is cast by the count of those out;
--   * the safeguards of the attack rotation apply: the server's cooldowns (spell and group), the cast bookkeeping with
--     pending / back-off of a refused cast (ChaosHelperRotation, base patch 0052; after H.REFUSE_LIMIT refusals in a
--     row a longer rest), the rate guard of the support channel
--     (ChaosHelperTimers), no cast in a protection zone, a mana reserve, and nothing while the attack rotation charges
--     a cast-time spell.
-- A vigil is a switch (a second cast turns it off): it is cast only when the buff bar shows it is off, and one cast
-- is not repeated for SWITCH_SETTLE_MS while the bar catches up. A vigil the player switches off by hand stays off:
-- its row is unticked (H.takeUserOff) until the player ticks it again.
--
-- Auto setup placement (H.autoPlan): fight buffs (Red Frenzy, Poison Blades, Banner Call ...) go to the Timer section,
-- up to H.TIMER_MAX, cast only while attacking a monster outside protection zones; everything else (shields, summons,
-- one vigil ...) goes to this section, up to H.SUPPORT_MAX.
ChaosHelperSupport = ChaosHelperSupport or {}
local H = ChaosHelperSupport

H.SUPPORT_MAX = 8            -- rows of the section
H.TIMER_MAX = 6              -- timer rules Auto setup writes (3 before); see H.TIMER_STAGGER_MS
H.TIMER_STAGGER_MS = 2500    -- the first casts of the timer rules go out this far apart (all support spells share
                             -- the support group's 2 s cooldown on the server; a timer rule does not wait for an answer)
H.RESERVES = { 0, 10, 20, 30, 40, 50 }  -- mana reserve choices (percent of the maximum that stays after a cast)
H.DEFAULT_RESERVE = 20
H.MAX_AUTO_COOLDOWN_MS = 1800000        -- Auto setup leaves out spells that come back later than 30 min (the avatars)
H.SETTLE_MS = 2500           -- after a cast: wait for the server's answer and the buff bar
H.SWITCH_SETTLE_MS = 6000    -- the same for a switch (a vigil): a second cast would turn it off
H.SUMMON_GAP_MS = 10000      -- a summon is not cast again sooner than this (a refused one backs off on top)
-- Owner beta, 2026-10-20: "Support keeps casting the spells nonstop, the character has the cloud all the time". A spell
-- whose effect the buff bar never lists (a summon, Hunter's Instinct, Smoke Bomb, a stock buff the bar calls "Spell
-- Buff") counted as "not active" whenever the bar had data, and one with no bar data and no duration was cast every
-- time it came off cooldown: Wild Bond every 10 s, Bone Golem every 30 s, each with its effect. Now the bar decides only
-- for a buff it has shown (st.seen); otherwise the spell's duration, else at least RECAST_MIN_MS (or its cooldown) since
-- our last cast. A spell the server refused REFUSE_LIMIT times in a row (no cooldown answer: ChaosHelperRotation's
-- back-off) rests REFUSED_HOLD_MS after the last try instead of a poof every 16 s.
H.RECAST_MIN_MS = 60000
H.REFUSE_LIMIT = 3
H.REFUSED_HOLD_MS = 30000
H.SUMMON_CAP = 3             -- the most summons of a capped kind of spell (below) the helper keeps out when the class is unknown
-- The Necromancer line's summons are capped: at the limit the next summon kills the OLDEST one (server/data/scripts/chaos/
-- necro_config.lua minions.classes[].total). A summon spell marked `capped` below is therefore cast only while the character
-- has fewer summons than the cap, else the helper would keep killing its own army. Server vocation id -> cap
-- (Necromancer 3, Lich 1, Bone Lord 6, 7 from level 400; the passive tree's Legion adds more: the helper stays below it).
function H.summonCap(vocId, level)
  vocId = tonumber(vocId)
  if vocId == 20 then return 3 end
  if vocId == 21 then return 1 end
  if vocId == 22 then return (tonumber(level) or 0) >= 400 and 7 or 6 end
  return H.SUMMON_CAP
end
H.CYCLE_MS = 250

-- spells that are never offered: the teleport home, the mines trigger (needs mines), the dash and the roll (move the
-- character), and the stock utilities (by words, the same in every client table)
H.NEVER_IDS = { [254] = true, [104] = true, [232] = true, [67] = true }
H.NEVER_WORDS = {}
H.NEVER_STOCK = {}
for _, w in ipairs({ 'utevo lux', 'utevo gran lux', 'utevo vis lux', 'exani tera', 'exiva moe res', 'exevo pan',
    'exana ina', 'exeta res', 'exeta amp res', 'exani hur', 'utevo res ina', 'utevo res', 'exana vita', 'exevo con',
    'exevo con flam', 'exevo infir con', 'exeta con', 'utani tempo hur', 'utamo tempo san', 'utana vid',
    'exevo gran mort', 'exana amp res' }) do
  H.NEVER_WORDS[w] = true
  H.NEVER_STOCK[w] = true
end

-- the client says the Chaos words of the stock spells (game_chaosspells ChaosSpellNames: "utevo lux" -> "vael lyss"),
-- so the stock words alone missed Lantern, Ghost Rope and the rest (owner 2026-10-22: "light and magic rope go into
-- Support by themselves"). names: that table (the global when nil); its words join NEVER_WORDS once.
function H.addRenamedWords(names)
  names = names or rawget(_G, 'ChaosSpellNames')
  if type(names) ~= 'table' then return false end
  for stock in pairs(H.NEVER_STOCK) do
    local e = names[stock]
    if type(e) == 'table' and type(e.words) == 'string' and e.words ~= '' then H.NEVER_WORDS[e.words:lower()] = true end
  end
  return true
end
local renamedDone = false
local function isNeverWords(words)
  if not renamedDone then renamedDone = H.addRenamedWords() end
  return H.NEVER_WORDS[words] == true
end

-- what the spells are, by spell id (the server's ids; the Chaos spells in server/data/spells/chaos/spells_chaos.xml, the
-- stock ones in the client's table):
--   auto   'timer' (a fight buff for the Timer section) | 'support' (this section) | false (offered, never set up)
--   kind   'buff' (default) | 'shield' | 'summon' | 'switch' (a vigil) | 'party' (needs a party)
--   capped true: a summon that is cast only below the summon cap (H.summonCap; the next one would kill the oldest)
--   minion the creature name of that summon: a capped summon with a minion is cast only while none of that name is out
--          (one of each kind: Auto setup builds a mixed army)
--   minions, keep  an uncapped summon's creature names and how many the character keeps out ({ {level, count}, ... }):
--          cast only while fewer of those are out
--   fight  true: only while attacking a monster
--   dur    seconds the effect lasts (the timer cools down at least that long; the fallback when no buff bar data)
--   bar    names the buff bar shows for it, when they are not the spell's name
--   rank   order among the section's rows (lower first)
H.KINDS = {
  -- fight buffs: the Timer section
  [209] = { auto = 'timer', dur = 20 },  -- Ironbark Hide
  [217] = { auto = 'timer', dur = 8 },   -- Lightward
  [222] = { auto = 'timer', dur = 12 },  -- Red Frenzy
  [233] = { auto = 'timer', dur = 12 },  -- Banner Call
  [239] = { auto = 'timer', dur = 20 },  -- Poison Blades
  [245] = { auto = 'timer', dur = 30 },  -- Bushido Focus
  [250] = { auto = 'timer', dur = 20 },  -- Zealotry
  [72] = { auto = 'timer', dur = 12 },   -- Mantra of Stone
  [223] = { auto = 'timer', dur = 8 },   -- Iron Bellow
  [226] = { auto = 'timer', dur = 10 },  -- Hall of Mirrors
  [243] = { auto = 'timer', dur = 3 },   -- Counter Stance
  [251] = { auto = 'timer', dur = 6 },   -- Rebuke
  [133] = { auto = 'timer', dur = 10 },  -- Blood Rage (stock)
  [132] = { auto = 'timer', dur = 12 },  -- Ironhold (the Chaos id 132 of the retired stock Bulwark, 2026-10-20)
  [135] = { auto = 'timer', dur = 12 },  -- Tautstring (the Chaos id 135 of the retired stock Hawkeye, 2026-10-20)
  -- the hastes: offered, but the Tools tab keeps them up (Auto setup sets that), so Auto setup leaves them out here
  [6] = { auto = false, kind = 'buff', dur = 33, bar = { 'haste' } },
  [39] = { auto = false, kind = 'buff', dur = 22, bar = { 'haste' } },
  [134] = { auto = false, kind = 'buff', dur = 12 },  -- Wildstride (the Chaos id 134 of the retired stock Windrunner)
  -- the support section
  [234] = { auto = 'support', kind = 'shield', dur = 15, rank = 2 },        -- Soulward
  [44] = { auto = 'support', kind = 'shield', dur = 200, bar = { 'magic shield' }, rank = 2 }, -- Ward of the Mind
  [162] = { auto = 'support', kind = 'switch', rank = 1 },                  -- Vigil of Clarity (the one Auto setup sets)
  [161] = { auto = false, kind = 'switch', rank = 1 },                      -- Vigil of Haste
  [179] = { auto = false, kind = 'switch', rank = 1 },                      -- Vigil of Wrath
  [255] = { auto = false, kind = 'switch', rank = 1 },                      -- Vigil of Iron
  [211] = { auto = 'support', kind = 'summon', fight = true, dur = 40, rank = 4 },   -- Moonfang Pack
  [180] = { auto = 'support', kind = 'summon', fight = true, rank = 4, capped = true },    -- Raise Dead
  [192] = { auto = 'support', kind = 'summon', fight = true, rank = 4, capped = true, minion = 'Risen Warrior' }, -- Raise Bone Warrior
  [193] = { auto = 'support', kind = 'summon', fight = true, rank = 4, capped = true, minion = 'Risen Archer' },  -- Raise Bone Archer
  [176] = { auto = 'support', kind = 'summon', fight = true, rank = 4, capped = true, minion = 'Risen Mage' },    -- Raise Bone Mage
  -- (a recast with the golem / the companions out only calls them back and heals them: cast while fewer than `keep` are out)
  [186] = { auto = 'support', kind = 'summon', fight = true, rank = 4, minions = { 'Bone Golem' }, keep = { { 0, 1 } } }, -- Bone Golem
  [187] = { auto = 'support', kind = 'buff', fight = true, dur = 20, rank = 5 }, -- Banner of Bones
  [248] = { auto = 'support', kind = 'summon', fight = true, rank = 4, minions = { 'War Wolf', 'Wolf' },
    keep = { { 0, 1 }, { 400, 2 } } },                                      -- Wild Bond (server Chaos.classes.companion.caps)
  [194] = { auto = 'support', kind = 'summon', rank = 3 },                  -- the familiars (stock; 30 min)
  [195] = { auto = 'support', kind = 'summon', rank = 3 },
  [196] = { auto = 'support', kind = 'summon', rank = 3 },
  [197] = { auto = 'support', kind = 'summon', rank = 3 },
  [282] = { auto = 'support', kind = 'summon', rank = 3 },
  -- offered, never set up by Auto setup (they cost health, need a shield, a named target or a party, or give up the fight)
  [203] = { auto = false },                          -- Crimson Covenant (costs health)
  [247] = { auto = false },                          -- Bloodrage (costs health)
  [252] = { auto = false, fight = true, dur = 5 },   -- Aegis of Faith (needs a shield)
  [229] = { auto = false, dur = 8 },                 -- Wraithshroud (invisible: the fight ends)
  [238] = { auto = false, dur = 4 },                 -- Shadow Veil
  [241] = { auto = false },                          -- Smoke Bomb
  [235] = { auto = false },                          -- Hunter's Instinct
  [70] = { auto = false },                           -- Chi Ward (a party member's shield, needs chi)
  [126] = { auto = false, kind = 'party', dur = 60 },-- Train Party
  [127] = { auto = false, kind = 'party', dur = 60 },-- Shielding Communion / Protect Party
  [129] = { auto = false, kind = 'party', dur = 60 },-- Enchant Party
  [278] = { auto = false, kind = 'party', dur = 60 },-- Enlighten Party
}

local DEFAULT_RANK = { shield = 2, switch = 1, summon = 4, buff = 5, party = 6 }

local function lower(s)
  return tostring(s or ''):lower()
end

-- the spell's group ids as a set ({[group] = cooldown}, the spell table's form, or a number)
local function groupSet(groups)
  local has = {}
  if type(groups) == 'table' then
    for k, v in pairs(groups) do
      if type(k) == 'number' and v ~= false then has[k] = true end
    end
  elseif type(groups) == 'number' then
    has[groups] = true
  end
  return has
end

-- a support spell by its data: the support group (3) and not the attack group (1)
function H.isSupportGroup(groups)
  local g = groupSet(groups)
  return g[3] == true and not g[1]
end

function H.cooldownMs(spell)
  return tonumber(spell.exhaustion) or tonumber(spell.cooldown) or 0
end

-- the kind record of a spell (a table copy with the defaults filled in)
function H.info(spell)
  local k = H.KINDS[spell.id] or {}
  local kind = k.kind or 'buff'
  local bar = {}
  for _, n in ipairs(k.bar or {}) do bar[#bar + 1] = lower(n) end
  bar[#bar + 1] = lower(spell.name)
  return {
    kind = kind, auto = k.auto, fight = k.fight == true, dur = k.dur, bar = bar,
    capped = k.capped == true, minion = k.minion, minions = k.minions, keep = k.keep,
    rank = k.rank or DEFAULT_RANK[kind] or 5, known = H.KINDS[spell.id] ~= nil,
  }
end

-- may this spell stand in the section? Returns true, or false and the reason
function H.eligible(spell)
  if type(spell) ~= 'table' or type(spell.id) ~= 'number' then return false, 'entry' end
  if spell.notOnServer then return false, 'server' end
  if type(spell.words) ~= 'string' or spell.words == '' then return false, 'words' end
  if not H.isSupportGroup(spell.group) then return false, 'group' end
  if spell.parameter or spell.needTarget then return false, 'target' end
  if H.NEVER_IDS[spell.id] or isNeverWords(lower(spell.words)) then return false, 'utility' end
  return true
end

local function byRank(a, b)
  if a.info.rank ~= b.info.rank then return a.info.rank < b.info.rank end
  local la, lb = tonumber(a.spell.level) or 0, tonumber(b.spell.level) or 0
  if la ~= lb then return la > lb end -- the stronger (higher level) first
  return a.spell.id < b.spell.id
end

-- the eligible spells the character can cast: a list of { spell, info }, in the order of the section
function H.candidates(spells, canCast)
  local out = {}
  for _, s in ipairs(spells or {}) do
    if H.eligible(s) and (not canCast or canCast(s.id)) then
      out[#out + 1] = { spell = s, info = H.info(s) }
    end
  end
  table.sort(out, byRank)
  return out
end

-- unknown support spells (added to the data later) are set up when they are cheap to keep up: not a long cooldown
local function autoSlot(c)
  local a = c.info.auto
  if a ~= nil then return a end
  local cd = H.cooldownMs(c.spell)
  if c.spell.special or cd > H.MAX_AUTO_COOLDOWN_MS then return false end
  return 'support'
end

-- what Auto setup puts where: { support = { spell id, ... }, timer = { { id, words, name, cooldown (s) }, ... } }
-- (the timer's cooldown: the longer of the spell's cooldown and its effect, plus one second)
function H.autoPlan(spells, canCast)
  local support, timer = {}, {}
  for _, c in ipairs(H.candidates(spells, canCast)) do
    local slot = autoSlot(c)
    if slot == 'timer' then
      if #timer < H.TIMER_MAX then
        local cd = math.max(math.ceil(H.cooldownMs(c.spell) / 1000), c.info.dur or 0) + 1
        timer[#timer + 1] = { id = c.spell.id, words = c.spell.words, name = c.spell.name, cooldown = cd }
      end
    elseif slot == 'support' then
      if #support < H.SUPPORT_MAX then support[#support + 1] = c.spell.id end
    end
  end
  return { support = support, timer = timer }
end

-- ---------------------------------------------------------------- the player's list (saved per character)
function H.defaultConfig()
  return { enabled = true, reserve = H.DEFAULT_RESERVE, slots = {} }
end

-- a saved node -> a valid config (wrong values fall back to the defaults, an id twice or an empty one is dropped)
function H.sanitize(node)
  local c = H.defaultConfig()
  if type(node) ~= 'table' then return c end
  if type(node.enabled) == 'boolean' then c.enabled = node.enabled end
  local r = tonumber(node.reserve)
  for _, v in ipairs(H.RESERVES) do
    if r == v then c.reserve = v end
  end
  local seen = {}
  if type(node.slots) == 'table' then
    for _, s in ipairs(node.slots) do
      local id = type(s) == 'table' and tonumber(s.id) or nil
      -- config.otml can be edited by hand: whole spell ids only
      if id and id ~= math.floor(id) then id = nil end
      if id and id > 0 and id <= 1000000 and not seen[id] and #c.slots < H.SUPPORT_MAX then
        seen[id] = true
        c.slots[#c.slots + 1] = { id = id, enabled = s.enabled ~= false }
      end
    end
  end
  return c
end

-- a saved list without the utility spells (a list made before they were left out). spellOf(id) -> the spell or nil (an
-- unknown spell stays). Returns the list and how many rows left it.
function H.dropUtilities(slots, spellOf)
  local out, dropped = {}, 0
  for _, s in ipairs(slots or {}) do
    local spell = spellOf and spellOf(s.id)
    local ok, why = true, nil
    if spell then ok, why = H.eligible(spell) end
    if not ok and why == 'utility' then dropped = dropped + 1 else out[#out + 1] = s end
  end
  return out, dropped
end

-- the list after Auto setup. mode 'replace': the plan's ids; 'add': the player's rows stay, planned ids not there yet go
-- below (up to SUPPORT_MAX)
function H.mergeSlots(current, planned, mode)
  local out, have = {}, {}
  if mode ~= 'replace' then
    for _, s in ipairs(current or {}) do
      if #out < H.SUPPORT_MAX and not have[s.id] then
        out[#out + 1] = { id = s.id, enabled = s.enabled ~= false }
        have[s.id] = true
      end
    end
  end
  for _, id in ipairs(planned or {}) do
    if #out >= H.SUPPORT_MAX then break end
    if not have[id] then
      out[#out + 1] = { id = id, enabled = true }
      have[id] = true
    end
  end
  return out
end

-- ---------------------------------------------------------------- the cycle
function H.newState()
  return { castAt = {}, settleUntil = {}, status = {}, seen = {}, barOn = {}, userOff = {}, casts = 0 }
end

-- how many of an uncapped summon the character keeps out at this level (info.keep: { {level, count}, ... })
function H.keepCount(info, level)
  local n = 0
  for _, step in ipairs(info.keep or {}) do
    if (tonumber(level) or 0) >= step[1] then n = step[2] end
  end
  return n
end

local function manaOk(ctx, spell, reserve)
  local cost = tonumber(spell.mana) or 0
  if cost <= 0 then return true end
  local mana, maxMana = tonumber(ctx.mana) or 0, tonumber(ctx.maxMana) or 0
  if mana < cost then return false, 'mana' end
  if maxMana > 0 and (mana - cost) * 100 / maxMana < reserve then return false, 'reserve' end
  return true
end

-- is the effect of this spell on us now? true / false, or nil when nothing tells (no buff bar data, never cast).
-- The bar's "not shown" counts only for a buff the bar has shown before (st.seen): the server lists the class buffs,
-- the vigils and the engine conditions, not a summon or an instant effect, and a stock buff under its own name.
local function active(st, info, spell, ctx, now)
  local seen = st.seen or {}
  st.seen = seen
  local fromBar = nil
  if ctx.buffActive then fromBar = ctx.buffActive(info.bar) end
  if info.kind == 'switch' then
    -- a vigil the bar showed on goes off without a cast of ours settling: the player switched it off (a cast of
    -- its words, or the spellbook / hotbar). The helper leaves it off (H.takeUserOff unticks the row) instead of
    -- casting it again at once (player report 2026-10-22: "it comes back right away").
    st.barOn = st.barOn or {}
    st.userOff = st.userOff or {}
    local was = st.barOn[spell.id]
    if fromBar ~= nil then st.barOn[spell.id] = fromBar end
    if fromBar == false and was == true and (st.settleUntil[spell.id] or 0) <= now then
      st.userOff[spell.id] = now
    elseif fromBar == true then
      st.userOff[spell.id] = nil -- on again (the player's cast): the helper may keep it up once its row is ticked
    end
  end
  if fromBar == true then
    seen[spell.id] = true
    return true
  end
  if info.kind == 'switch' and fromBar == nil then return nil end -- a vigil is never cast blind
  local at = st.castAt[spell.id]
  if fromBar == false and (seen[spell.id] or not at) then return false end
  if not at then return nil end
  -- the bar cannot tell: the spell's duration, else a long enough gap since our last cast
  if info.dur then return now < at + info.dur * 1000 end
  return now < at + math.max(H.RECAST_MIN_MS, H.cooldownMs(spell))
end

-- why this spell may not be cast now (nil: it may). Does not consume anything.
function H.why(st, cfg, slot, ctx)
  local now = ctx.now
  local spell = ctx.spellOf(slot.id)
  if not spell then return 'unknown' end
  local info = H.info(spell)
  if not slot.enabled then return 'off' end
  if info.fight and not ctx.attacking then return 'nofight' end
  if info.kind == 'party' and not (ctx.inParty and ctx.inParty()) then return 'noparty' end
  if ctx.castable and not ctx.castable(spell) then return 'level' end
  local ok, why = manaOk(ctx, spell, cfg.reserve)
  if not ok then return why end
  if ctx.onCooldown and ctx.onCooldown(spell) then return 'cooldown' end
  if (st.settleUntil[spell.id] or 0) > now then return 'wait' end
  if info.kind == 'summon' and st.castAt[spell.id] and now - st.castAt[spell.id] < H.SUMMON_GAP_MS then
    return 'wait'
  end
  if info.capped then
    -- ctx.summonCount(minionName) -> own summons in all, of that name (nil: the client cannot tell: no cast, a cast at
    -- the cap would kill the oldest summon); ctx.summonCap() -> the cap of the character's class (default H.SUMMON_CAP)
    local total, own = nil, 0
    if ctx.summonCount then total, own = ctx.summonCount(info.minion) end
    if total == nil then return 'nocount' end
    local cap = ctx.summonCap and ctx.summonCap() or H.SUMMON_CAP
    if total >= cap then return 'full' end
    if info.minion and (own or 0) > 0 then return 'have' end
  end
  local counted = info.capped
  if not info.capped and info.minions and ctx.summonCount then
    -- an uncapped summon with known creatures: the count decides (nil: the client cannot tell, the gap below does)
    local _, own = ctx.summonCount(info.minions)
    if own ~= nil then
      counted = true
      if own >= H.keepCount(info, ctx.level) then return 'have' end
    end
  end
  if not counted then
    local isActive = active(st, info, spell, ctx, now)
    if isActive == true then return 'active' end
    if info.kind == 'switch' and st.userOff and st.userOff[spell.id] then return 'useroff' end
    if info.kind == 'switch' and isActive == nil then return 'nobar' end
  end
  -- refused again and again (no cooldown answer from the server): rest after the last try
  local refused = ctx.refusals and ctx.refusals(spell) or 0
  if refused >= H.REFUSE_LIMIT and st.castAt[spell.id] and now - st.castAt[spell.id] < H.REFUSED_HOLD_MS then
    return 'backoff'
  end
  if ctx.blocked then
    local b = ctx.blocked(spell)
    if b then return b end
  end
  return nil
end

-- the next spell to cast: the first row (in order) that may go out. ctx: now, online, helperOn, inPz, mana, maxMana,
-- attacking, channeling (the attack rotation charges a cast-time spell), spellOf(id), castable(spell), onCooldown(spell),
-- buffActive(names) -> true / false / nil, blocked(spell) -> reason or nil, inParty(), level, refusals(spell) -> the
-- server's refusals of it in a row, summonCount(name or list of names) -> all own summons, those of the name(s) (nil:
-- unknown), summonCap(), allowed(spell, now) -> bool
-- (the rate guard; records the cast when it says yes). Returns the spell, or nil and the overall reason. Every row's
-- reason lands in st.status[id] (the rows show it).
function H.pick(st, cfg, ctx)
  st.status = {}
  if not cfg.enabled then return nil, 'disabled' end
  if not ctx.online then return nil, 'offline' end
  if not ctx.helperOn then return nil, 'helperoff' end
  if ctx.inPz then return nil, 'pz' end
  local winner = nil
  for _, slot in ipairs(cfg.slots) do
    local why = H.why(st, cfg, slot, ctx)
    if not why then
      if winner then
        why = 'queued'
      elseif ctx.channeling then
        why = 'casting'
      else
        local spell = ctx.spellOf(slot.id)
        if ctx.allowed and not ctx.allowed(spell, ctx.now) then
          why = 'rate'
        else
          winner, why = spell, 'cast'
        end
      end
    end
    st.status[slot.id] = why
  end
  return winner, winner and 'cast' or 'idle'
end

-- the vigils the player switched off by hand (st.userOff): their rows are unticked in cfg, so the helper does not
-- switch them on again, now or after a relog, until the player ticks the row again. Returns the ids it unticked.
-- now: only a switch-off at least USEROFF_CONFIRM_MS old (a death drops every buff a moment before the health packet;
-- the caller stops and resets on death, so a drop that close to it is never saved); nil: every mark.
H.USEROFF_CONFIRM_MS = 2000
function H.takeUserOff(st, cfg, now)
  local out = {}
  if not (st and st.userOff and cfg and cfg.slots) then return out end
  for _, slot in ipairs(cfg.slots) do
    local at = st.userOff[slot.id]
    local due = at and (now == nil or type(at) ~= 'number' or now - at >= H.USEROFF_CONFIRM_MS)
    if due and slot.enabled then
      slot.enabled = false
      out[#out + 1] = slot.id
    end
  end
  return out
end

-- the cast went out
function H.noteCast(st, spell, now)
  local info = H.info(spell)
  st.castAt[spell.id] = now
  st.settleUntil[spell.id] = now + (info.kind == 'switch' and H.SWITCH_SETTLE_MS or H.SETTLE_MS)
  st.casts = st.casts + 1
end

function H.reset(st)
  st.castAt, st.settleUntil, st.status, st.seen, st.casts = {}, {}, {}, {}, 0
  st.barOn, st.userOff = {}, {}
end

return ChaosHelperSupport
