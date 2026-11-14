-- game_killdissolve (client/MANIFEST.md "game_killdissolve", O563): the dissolve kill effects. The server (cosmetics.lua)
-- sends {action = 'kdis', data = {...}} on extended opcode 225 to the players near a kill of a character that wears one;
-- game_cosmetics hands it to onKill(). The dying monster is gone from the map in that same moment (and, with the loot
-- bag, leaves no corpse), so the module draws its look again on a creature of its own: a client-only Creature put on
-- the monster's tile whose outfit carries a dissolve shader (data/shaders/chaos_outfit_kd_<mode>.frag) and the shader's
-- progress, updated every 33 ms, then taken off the map again. The shader reads the progress and the sprite's rectangle
-- from base patch 0201 (Creature.hasShaderParams()); without it the plain effect of the server's message plays.
-- The real creature is blanked (empty outfit) first so base patch 0139's death fade draws nothing over the dissolve.
-- At most KillDissolveCore.MAX_ACTIVE dissolves run at once (3 on a phone); the next kills play the plain effect.
-- Pure logic (the decision, the cap, the timing, the outfit): killdissolve_core.lua.
-- The Customise window's previews: modules.game_killdissolve.previewOutfit / stage (game_lookpreview, game_outfitextras).
local K = KillDissolveCore
local OPTION = 'chaosKillDissolve'  -- g_settings boolean, default on (no options screen yet)
local cap = K.newCap(K.MAX_ACTIVE)
local ready = {}                     -- mode -> the shader is registered
local running = {}                   -- the dissolves on the map: {creature, pos, started, mode, tint, seed, width, look, event}
local reported = false

local function warn(what, err)
  if reported then return end
  reported = true
  g_logger.warning('[killdissolve] ' .. what .. ': ' .. tostring(err))
end

local function enabled()
  local ok, v = pcall(function()
    if g_settings and g_settings.getBoolean then return g_settings.getBoolean(OPTION, true) end
    return true
  end)
  return not ok or v ~= false
end

local function hasParams()
  return type(Creature) == 'table' and type(Creature.hasShaderParams) == 'function' and Creature.hasShaderParams() == true
end

local function isMobile()
  return type(g_app) == 'table' and type(g_app.isMobile) == 'function' and g_app.isMobile() == true
end

-- the width of a look in sprite pixels (a tile is 32): the shader lays its cells out in them
local function widthOf(lookType)
  local ok, w = pcall(function()
    local t = g_things.getThingType(lookType, ThingCategoryCreature)
    local size = t and t:getSize()
    return size and size.width and size.width * 32 or 32
  end)
  return ok and tonumber(w) or 32
end

-- ---------------------------------------------------------------- the plain effect (the cap, an old build, a missing shader)
local function playPlain(effect, pos)
  if not effect or not pos then return false end
  local ok, err = pcall(function()
    if type(Effect) ~= 'table' or not Effect.create or not g_map or not g_map.addThing then return end
    local e = Effect.create()
    e:setId(effect.id)
    g_map.addThing(e, { x = pos.x + effect.dx, y = pos.y + effect.dy, z = pos.z }, -1)
  end)
  if not ok then warn('plain effect', err) end
  return ok
end

-- ---------------------------------------------------------------- a dissolve on the map
local function finish(d)
  if d.event then removeEvent(d.event); d.event = nil end
  if d.creature then pcall(g_map.removeThing, d.creature) end
  d.creature = nil
  for i, r in ipairs(running) do
    if r == d then table.remove(running, i) break end
  end
  K.release(cap)
end

local function step(d)
  d.event = nil
  local ok, err = pcall(function()
    local elapsed = g_clock.millis() - d.started
    if elapsed >= K.duration(d.mode) or not d.creature then
      finish(d)
      return
    end
    local o = K.outfitFor(d.look, d.mode, d.tint, K.progress(d.mode, elapsed), d.seed, d.width)
    d.creature:setOutfit(o)
    d.event = scheduleEvent(function() step(d) end, K.FRAME_MS)
  end)
  if not ok then
    warn('step', err)
    finish(d)
  end
end

local function start(plan, msg)
  -- the real monster: an empty outfit, so the death fade of the engine has nothing to copy
  local real = msg.i and g_map.getCreatureById(msg.i) or nil
  if real then pcall(real.setOutfit, real, { type = 0 }) end
  local c = Creature.create()
  local width = widthOf(plan.look.type)
  local d = { creature = c, pos = plan.pos, started = g_clock.millis(), mode = plan.mode, tint = plan.tint, seed = plan.seed,
    width = width, look = plan.look }
  c:setOutfit(K.outfitFor(plan.look, plan.mode, plan.tint, K.MIN_PROGRESS, plan.seed, width))
  c:setDirection(plan.direction)
  c:setName('')
  c:setPassable(true)
  c:setHealthPercent(0) -- no bars, no battle list entry, no target
  g_map.addThing(c, plan.pos, -1)
  running[#running + 1] = d
  d.event = scheduleEvent(function() step(d) end, K.FRAME_MS)
end

-- called by game_cosmetics for {action = 'kdis'}
function onKill(data)
  if not g_game.isOnline() then return end
  local plan = K.plan(data, { enabled = enabled(), hasParams = hasParams(), ready = function(mode) return ready[mode] == true end,
    cap = cap })
  if plan.action == 'dissolve' then
    local ok, err = pcall(start, plan, data)
    if not ok then
      warn('start', err)
      K.release(cap)
      playPlain(K.plainEffect(data), plan.pos)
    end
  elseif plan.action == 'plain' then
    playPlain(plan.effect, plan.pos)
  end
end

-- ---------------------------------------------------------------- the Customise window
-- the outfit of the preview creature `ms` into the loop of a dissolve (nil: the shader is not there, show it plain)
function previewOutfit(baseLook, mode, tint, ms)
  local st = K.stage(mode, ms)
  if not ready[mode] or not hasParams() or type(baseLook) ~= 'table' then return nil, st end
  if st.phase == 'dissolve' then
    return K.outfitFor(baseLook, mode, tint, st.progress, 0.3, widthOf(baseLook.type)), st
  end
  return nil, st
end

function canPreview(mode)
  return ready[mode] == true and hasParams()
end

local function onGameEnd()
  for i = #running, 1, -1 do finish(running[i]) end
  cap = K.newCap(isMobile() and K.MAX_ACTIVE_MOBILE or K.MAX_ACTIVE)
  running = {}
end

function init()
  for _, mode in ipairs(K.ORDER) do
    local ok, err = pcall(g_shaders.createOutfitShader, K.shaderName(mode), K.VERTEX, K.FILE_PREFIX .. mode)
    ready[mode] = ok == true
    if not ok then g_logger.warning('[killdissolve] ' .. mode .. ': ' .. tostring(err)) end
  end
  cap = K.newCap(isMobile() and K.MAX_ACTIVE_MOBILE or K.MAX_ACTIVE)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  for i = #running, 1, -1 do finish(running[i]) end
  running = {}
end
