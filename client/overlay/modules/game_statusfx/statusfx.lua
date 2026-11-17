-- game_statusfx (client/MANIFEST.md "Status layer (O597)"): burn, freeze, shock, poison, curse, root, soak, stun,
-- confusion, haste, blessing, regeneration, shield and fury drawn on any creature on screen while the status holds:
-- its start once, its loop while it lasts, its stop once. The server (status_vfx.lua, extended opcode 165) tells which
-- creatures near the player show which statuses; the art is effects of the sprite pair (pair 73, client/tools/sprites/
-- gen_status_vfx.py), 2 x 2 tiles each, whose sprites this module shows in a widget on the creature (a creature top
-- widget, as game_chestaura's burn), so the status walks with it. A creature shows 2 statuses at most, the screen
-- StatusFxLogic.CAP_SCREEN (12 on a phone), the nearest creatures first.
-- Option: Options > Graphics "Status effects on creatures" (statusEffects, default on, base patch 0205 -> onOption);
-- off, the module tells the server to stop sending.
-- A client build without creature widgets or without the sprite list of a thing type draws nothing.
-- Pure rules: statusfx_logic.lua.
local L = StatusFxLogic
local model = L.newModel()
local cfg = nil              -- the server's effect ids (nil until its cfg message)
local enabled = false
local hosts = {}             -- creature id -> {creature, widget, side, tiles = {[slot] = {4 UISprite}}, sizeTiles}
local things = {}            -- effect id -> sprite list (false: cannot be read)
local animEvent = nil
local reported = false

local function warn(what, err)
  if reported then return end
  reported = true
  g_logger.warning('[statusfx] ' .. what .. ': ' .. tostring(err))
end

local function safe(what, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then warn(what, err) end
  end
end

local function now() return g_clock.millis() end
local function alive(w) return w ~= nil and not w:isDestroyed() end

local function isMobile()
  return type(g_app) == 'table' and type(g_app.isMobile) == 'function' and g_app.isMobile() == true
end

local function spriteSize()
  local ok, s = pcall(function() return g_sprites.spriteSize() end)
  return ok and tonumber(s) or L.SPRITE
end

local function spritesOf(effectId)
  local cached = things[effectId]
  if cached ~= nil then return cached or nil end
  local list = false
  local ok, v = pcall(function()
    local t = g_things.getThingType(effectId, ThingCategoryEffect)
    return t and t:getSprites() or nil
  end)
  if ok and type(v) == 'table' and #v > 0 then list = v end
  things[effectId] = list
  return list or nil
end

-- ---------------------------------------------------------------- the widget on a creature
local function release(h)
  local w, c = h.widget, h.creature
  if not alive(w) then return end
  local cleared = false
  if c and not c:isRemoved() then
    local ok, list = pcall(function() return c['get' .. h.side .. 'Widgets'](c) end)
    if ok and type(list) == 'table' and #list == 1 and list[1] == w then
      cleared = pcall(function() c['clear' .. h.side .. 'Widgets'](c) end)
    end
  end
  if not cleared then
    w:setOpacity(0)
    pcall(function() w:destroyChildren() end)
  end
end

local function drop(id)
  local h = hosts[id]
  hosts[id] = nil
  if h then release(h) end
end

local function host(creature, id)
  local h = hosts[id]
  if h and h.creature == creature and alive(h.widget) then return h end
  if h then drop(id) end
  if not creature.addTopWidget and not creature.addBottomWidget then return nil end
  local spr = spriteSize()
  local okSize, px = pcall(function() return creature:getExactSize() end)
  local size, ml, mt, tile = L.box(spr, L.tilesOf(okSize and px or nil, spr))
  local side = creature.addTopWidget and 'Top' or 'Bottom'
  local w = g_ui.createWidget('UIWidget')
  w:resize(size, size)
  pcall(function() w:setMarginLeft(ml) end)
  pcall(function() w:setMarginTop(mt) end)
  w:setPhantom(true)
  creature['add' .. side .. 'Widget'](creature, w)
  h = { creature = creature, widget = w, side = side, tile = tile, slots = {} }
  hosts[id] = h
  return h
end

local function slotOf(h, name)
  local s = h.slots[name]
  if s then return s end
  s = { sprites = {}, shown = {} }
  for hh = 0, L.TILES - 1 do
    for ww = 0, L.TILES - 1 do
      local sw = g_ui.createWidget('UISprite', h.widget)
      sw:setPhantom(true)
      sw:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      sw:addAnchor(AnchorTop, 'parent', AnchorTop)
      local x, y = L.tileCorner(ww, hh, h.tile)
      sw:setMarginLeft(x)
      sw:setMarginTop(y)
      sw:setSize({ width = h.tile, height = h.tile })
      sw:setVisible(false)
      s.sprites[hh * L.TILES + ww + 1] = sw
    end
  end
  h.slots[name] = s
  return s
end

local function dropSlot(h, name)
  local s = h.slots[name]
  h.slots[name] = nil
  if not s then return end
  for _, sw in ipairs(s.sprites) do
    if alive(sw) then sw:destroy() end
  end
end

local function draw(h, name, effectId, phase)
  local list = spritesOf(effectId)
  if not list then return end
  local s = slotOf(h, name)
  for hh = 0, L.TILES - 1 do
    for ww = 0, L.TILES - 1 do
      local k = hh * L.TILES + ww + 1
      local sid = tonumber(list[L.spriteIndex(ww, hh, phase)]) or 0
      local sw = s.sprites[k]
      if alive(sw) and s.shown[k] ~= sid then
        s.shown[k] = sid
        if sid > 0 then sw:setSpriteId(sid) end
        sw:setVisible(sid > 0)
      end
    end
  end
end

-- ---------------------------------------------------------------- the loop
local function nearestFirst()
  local me = g_game.getLocalPlayer()
  local mine = me and me:getPosition() or nil
  local ids = {}
  for id in pairs(model.masks) do ids[#ids + 1] = id end
  local dist = {}
  for _, id in ipairs(ids) do
    local c = g_map.getCreatureById(id)
    local p = c and not c:isRemoved() and c:getPosition() or nil
    dist[id] = (p and mine and p.z == mine.z) and math.max(math.abs(p.x - mine.x), math.abs(p.y - mine.y)) or 9999
  end
  table.sort(ids, function(a, b)
    if dist[a] ~= dist[b] then return dist[a] < dist[b] end
    return a < b
  end)
  return ids, dist
end

local function stopAnim()
  if animEvent then removeEvent(animEvent) end
  animEvent = nil
end

local function animate()
  if not enabled or not cfg or not cfg.on then
    stopAnim()
    return
  end
  local t = now()
  local ids, dist = nearestFirst()
  local allowed = L.budget(model, ids, isMobile() and L.CAP_SCREEN_MOBILE or L.CAP_SCREEN)
  local seen = {}
  for _, id in ipairs(ids) do seen[id] = true end
  for id in pairs(model.shows) do
    if not seen[id] then ids[#ids + 1] = id end
  end
  local any = false
  for _, id in ipairs(ids) do
    local c = g_map.getCreatureById(id)
    local visible = c ~= nil and not c:isRemoved() and (dist[id] or 0) < 9999
    if not visible then
      model.shows[id] = nil
      drop(id)
    else
      L.sync(model, id, t, allowed[id] == true)
      local shows = model.shows[id]
      local h = shows and host(c, id) or nil
      if shows and h then
        for name, s in pairs(shows) do
          local effectId, phase = L.frame(s, cfg.fx[name], t)
          if effectId then
            draw(h, name, effectId, phase)
            any = true
          else
            shows[name] = nil
            dropSlot(h, name)
          end
        end
        if next(shows) == nil then
          model.shows[id] = nil
          drop(id)
        end
      elseif not shows then
        drop(id)
      end
    end
  end
  if not any and next(model.masks) == nil then stopAnim() end
end

local function startAnim()
  if not animEvent then animEvent = cycleEvent(safe('anim', animate), 33) end
end

local function clearAll()
  stopAnim()
  for id in pairs(hosts) do drop(id) end
  hosts = {}
  model = L.newModel()
end

-- ---------------------------------------------------------------- the server
local function sendHello(on)
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(L.OPCODE, json.encode(L.hello(on))) end
end

local function onOpcode(protocol, opcode, msg)
  local c = L.parseCfg(msg)
  if c then
    cfg = c
    things = {}
    if not c.on then clearAll() end
    return
  end
  local list = L.parseList(msg)
  if not list or not enabled then return end
  for _, row in ipairs(list) do L.setMask(model, row.id, row.mask) end
  startAnim()
end

-- ---------------------------------------------------------------- option
local function optionValue()
  local cs = modules.client_settings
  local ok, v = pcall(function() return cs and cs.getOption and cs.getOption(L.OPTION) end)
  if ok and v ~= nil then return L.optionOn(v) end
  local ok2, has = pcall(g_settings.exists, L.OPTION)
  if ok2 and has then
    local ok3, b = pcall(g_settings.getBoolean, L.OPTION)
    if ok3 then return L.optionOn(b) end
  end
  return true
end

local function start()
  if enabled or not g_game.isOnline() then return end
  enabled = true
  sendHello(true)
end

local function stop()
  if not enabled then return end
  enabled = false
  clearAll()
  if g_game.isOnline() then pcall(sendHello, false) end
end

-- from the options' apply (client_settings dataset.lua, base patch 0205)
function onOption(name, value)
  if name ~= L.OPTION then return end
  if L.optionOn(value) then start() else stop() end
end

local function onGameStart()
  cfg = nil
  enabled = false
  clearAll()
  if optionValue() then start() end
end

local function onGameEnd()
  enabled = false
  cfg = nil
  clearAll()
end

local handlers = {}

function init()
  handlers.opcode = safe('opcode', onOpcode)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  ProtocolGame.registerExtendedJSONOpcode(L.OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then handlers.game.onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, L.OPCODE)
  if enabled and g_game.isOnline() then pcall(sendHello, false) end
  enabled = false
  clearAll()
end
