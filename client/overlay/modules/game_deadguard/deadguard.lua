-- game_deadguard: a dead monster whose removal packet was lost stays drawn at 0 percent. 3 seconds after a non-player
-- creature reached 0 percent and is still on the map, it is removed locally (and dropped as attack target). A once-a-second
-- sweep catches what the health event cannot: a monster seen at 0 percent for 3 s, and a second object of one creature id. One
-- g_logger.warning per removal, so a phone log shows if the root cause still happens. Decisions: deadguard_logic.lua.
local L = DeadGuardLogic
local state = L.newState()
local handler = nil
local reported = false

local function snapshot(creature)
  local pos = creature:getPosition()
  return {
    isPlayer = creature:isPlayer(),
    isLocalPlayer = creature:isLocalPlayer(),
    healthPercent = creature:getHealthPercent(),
    removed = creature:isRemoved(),
    onMap = pos ~= nil and pos.x ~= 65535 and pos.x > 0 and creature:getTile() ~= nil,
  }
end

local function check(creature, id, startedAt)
  state.pending[id] = nil
  local verdict = L.decide(snapshot(creature), g_clock.millis() - startedAt)
  if verdict == 'wait' then
    -- fired early (timer rounding): look again shortly
    state.pending[id] = true
    scheduleEvent(function() check(creature, id, startedAt) end, 250)
    return
  end
  if verdict ~= 'remove' then return end
  if L.shouldLog(state, id) then
    g_logger.warning('[deadguard] removed id ' .. tostring(id) .. ' name ' .. tostring(creature:getName()) .. ' after ' .. L.GRACE_MS .. ' ms at 0 percent')
  end
  if g_game.getAttackingCreature() == creature then g_game.cancelAttack() end
  g_map.removeThing(creature)
end

local function onHealth(creature, percent)
  local ok, err = pcall(function()
    if not creature then return end
    local id = creature:getId()
    if percent ~= nil and percent > 0 then
      L.forget(state, id)
      state.warned[id] = nil
      return
    end
    if not L.wantsWatch(state, id, creature:isPlayer(), creature:isLocalPlayer(), percent) then return end
    state.pending[id] = true
    local startedAt = g_clock.millis()
    scheduleEvent(function()
      local ok2, err2 = pcall(check, creature, id, startedAt)
      if not ok2 and not reported then
        reported = true
        g_logger.warning('[deadguard] check: ' .. tostring(err2))
      end
    end, L.GRACE_MS)
  end)
  if not ok and not reported then
    reported = true
    g_logger.warning('[deadguard] health: ' .. tostring(err))
  end
end

local function onGameEnd()
  L.reset(state)
end

-- the sweep: see DeadGuardLogic.sweep (a monster at 0 percent the watch never saw, a second object of one creature id)
local sweepEvent = nil

local function sweep()
  sweepEvent = nil
  local ok, err = pcall(function()
    if not g_game.isOnline() then return end
    local me = g_game.getLocalPlayer()
    local pos = me and me:getPosition()
    if not pos then return end
    local list = {}
    for _, c in pairs(g_map.getSpectators(pos, false) or {}) do
      if c ~= me and not c:isPlayer() then
        local cp = c:getPosition()
        list[#list + 1] = {
          id = c:getId(), obj = c, isPlayer = false, isLocalPlayer = c:isLocalPlayer(),
          healthPercent = c:getHealthPercent(), removed = c:isRemoved(),
          onMap = cp ~= nil and cp.x ~= 65535 and cp.x > 0 and c:getTile() ~= nil,
        }
      end
    end
    local verdicts = L.sweep(state, list, function(id) return g_map.getCreatureById(id) end, g_clock.millis())
    for _, v in ipairs(verdicts) do
      local c = v.entry.obj
      if L.shouldLog(state, tostring(v.why) .. v.entry.id) then
        g_logger.warning('[deadguard] sweep removed id ' .. tostring(v.entry.id) .. ' name ' .. tostring(c:getName()) .. ' (' .. v.why .. ')')
      end
      if g_game.getAttackingCreature() == c then g_game.cancelAttack() end
      g_map.removeThing(c)
    end
  end)
  if not ok and not reported then
    reported = true
    g_logger.warning('[deadguard] sweep: ' .. tostring(err))
  end
  if handler then sweepEvent = scheduleEvent(sweep, L.SWEEP_MS) end
end

function init()
  handler = { onHealthPercentChange = onHealth }
  connect(Creature, handler)
  connect(g_game, { onGameEnd = onGameEnd })
  sweepEvent = scheduleEvent(sweep, L.SWEEP_MS)
end

function terminate()
  if sweepEvent then removeEvent(sweepEvent); sweepEvent = nil end
  disconnect(g_game, { onGameEnd = onGameEnd })
  if handler then disconnect(Creature, handler) end
  handler = nil
  L.reset(state)
end
