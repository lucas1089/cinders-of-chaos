-- Name plates over players: the active title (coloured by its source), the guild in braces and the name in gold on a
-- small frame. Server: server/data/scripts/chaos/nameplate.lua, extended opcode 248 (plain text, see nameplatemath.lua).
--   server -> client  one plate per line: cid|title|color|guild|frame
--   client -> server  q|id,id,...   players that appeared without a plate (or with an old one), batched
-- Drawn by the engine (base patch 0022: Creature:setNameplate; the title line is the engine's Creature:setTitle).
-- A client built without patch 0022 shows the title and guild as one block above the name, without the frame.
-- Monsters and NPCs are left alone.

local OPCODE = 248
local FONT = 'verdana-11px-rounded'
local BORDER = 6 -- 9-slice border of the plate images (client/tools/gen_nameplate_art.py)
local FLUSH_MS = 250

local M = NameplateMath
local cache = {}   -- cid -> { title, color, guild, frame, at, stale }
local pending = {} -- cid -> { at, tries }: asked, no answer yet (asked again, see NameplateMath.retries)
local queue = {}   -- cid -> true: to ask in the next flush
local flushEvent, retryEvent

local function now()
  return g_clock.seconds()
end

local function apply(creature, rec)
  if not creature or not creature:isPlayer() then return end
  local titleColor = rec and rec.color or M.TITLE_COLOR
  if creature.setNameplate then
    creature:setTitle(rec and rec.title or '', FONT, titleColor)
    creature:setNameplate(M.guildText(rec and rec.guild), FONT, M.guildColor(creature:getEmblem()), M.NAME_COLOR,
      M.framePath(rec and rec.frame), BORDER)
  else
    creature:setTitle(M.fallbackText(rec), FONT, titleColor)
  end
end

local function flush()
  flushEvent = nil
  local protocol = g_game.getProtocolGame()
  if not protocol or not g_game.isOnline() then
    queue = {}
    return
  end
  for _, msg in ipairs(M.queries(queue)) do
    protocol:sendExtendedOpcode(OPCODE, msg)
  end
  local t = now()
  for id in pairs(queue) do
    pending[id] = { at = t, tries = (pending[id] and pending[id].tries or 0) + 1 }
  end
  queue = {}
end

-- an answer can be lost (a malformed message of another module earlier in the same packet makes the client drop the
-- rest of it), so players still on screen without a plate are asked again a few times
local retry
retry = function()
  retryEvent = nil
  if not g_game.isOnline() then return end
  for _, id in ipairs(M.retries(pending, now(), function(cid) return g_map.getCreatureById(cid) ~= nil end)) do
    queue[id] = true
  end
  if next(queue) then flush() end
  if next(pending) then retryEvent = scheduleEvent(retry, M.RETRY_SECONDS * 1000) end
end

local function ask(id)
  queue[id] = true
  if not flushEvent then
    flushEvent = scheduleEvent(flush, FLUSH_MS)
  end
  if not retryEvent then
    retryEvent = scheduleEvent(retry, M.RETRY_SECONDS * 1000)
  end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  for _, rec in ipairs(M.parse(buffer)) do
    rec.at = now()
    cache[rec.cid] = rec
    pending[rec.cid] = nil
    apply(g_map.getCreatureById(rec.cid), rec)
  end
end

local function onAppear(creature)
  if not creature:isPlayer() then return end
  local id = creature:getId()
  local rec = cache[id]
  -- draw what is known at once (the default frame for a player not known yet), ask for the rest
  apply(creature, rec)
  local t = now()
  if M.needsQuery(rec, t, pending[id] ~= nil) then
    ask(id)
  end
end

local function onDisappear(creature)
  local rec = cache[creature:getId()]
  if rec then rec.stale = true end
end

local function onEmblemChange(creature)
  local rec = cache[creature:getId()]
  if rec and rec.guild and creature:isPlayer() then
    apply(creature, rec)
  end
end

local function onGameEnd()
  cache, pending, queue = {}, {}, {}
  if flushEvent then
    removeEvent(flushEvent)
    flushEvent = nil
  end
  if retryEvent then
    removeEvent(retryEvent)
    retryEvent = nil
  end
end

function init()
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  connect(Creature, { onAppear = onAppear, onDisappear = onDisappear, onEmblemChange = onEmblemChange })
  -- module (re)loaded in game: plate the players already on screen
  local player = g_game.isOnline() and g_game.getLocalPlayer()
  if player then
    for _, creature in ipairs(g_map.getSpectators(player:getPosition(), true)) do
      onAppear(creature)
    end
  end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  disconnect(Creature, { onAppear = onAppear, onDisappear = onDisappear, onEmblemChange = onEmblemChange })
  if flushEvent then
    removeEvent(flushEvent)
    flushEvent = nil
  end
  if retryEvent then
    removeEvent(retryEvent)
    retryEvent = nil
  end
  -- back to the plain name
  local player = g_game.isOnline() and g_game.getLocalPlayer()
  if player then
    for _, creature in ipairs(g_map.getSpectators(player:getPosition(), true)) do
      if creature:isPlayer() then
        creature:clearTitle()
        if creature.clearNameplate then creature:clearNameplate() end
      end
    end
  end
  cache, pending, queue = {}, {}, {}
end
