-- Spell combos on the client (O686 phase 6): the pure part of the label and the chime, tested by combologic_test.lua (client loop).
-- Server: server/data/scripts/chaos/spell_combos.lua sends `combo {id, n, x, y, z}` on extended opcode 168 when a combo fires:
-- id = the row of spell_combos_config.lua, n = its English name (the pt-BR text is client_chaos_locale/pt_br.lua, key = the English name),
-- x y z = the tile of the target that took the hit. This file turns the message into what to draw (a short label over the tile in the
-- colour of the combo, ChaosComboLogic.clean), says which of the two chimes to play, and throttles a flood (ChaosComboLogic.gate).
-- Design: docs/SPELL_UPGRADES.md 4.4. No UI calls here; spellranks.lua draws it with the engine's animated text and plays the sound.
-- Plain Lua 5.1 / LuaJIT / 5.3, no globals but ChaosComboLogic.

ChaosComboLogic = ChaosComboLogic or {}
local C = ChaosComboLogic

-- the combos by id (spell_combos_config.lua rows; combologic_test.lua holds the ids and kinds equal when run from the repo root).
-- kind: reaction (an element pair, the high chime) or signature (a class combo or the heal combo, the low chime). color: the 8-bit
-- palette colour of the engine's animated text (the same palette as the damage numbers: skyblue 143, lightblue 35, purple 154,
-- electric purple 155, light green 30, yellow 210, orange 198, pastel red 194)
C.COMBOS = {
  steam_burst = { kind = 'reaction', color = 143 },
  thermal_shock = { kind = 'reaction', color = 35 },
  overload = { kind = 'reaction', color = 155 },
  pyre_of_the_dead = { kind = 'reaction', color = 154 },
  mudslide = { kind = 'reaction', color = 30 },
  consecrated_ash = { kind = 'reaction', color = 210 },
  pinned_shot = { kind = 'signature', color = 198 },
  meat_grinder = { kind = 'signature', color = 194 },
  anvil_chain = { kind = 'signature', color = 198 },
  backstab = { kind = 'signature', color = 194 },
  rotting_curse = { kind = 'signature', color = 154 },
  psychic_shatter = { kind = 'signature', color = 155 },
  echoing_mend = { kind = 'signature', color = 30 },
}
C.DEFAULT_COLOR = 215   -- an id the client does not know: white
C.DEFAULT_KIND = 'signature'

-- how long a label stays (ms): the engine's animated text has its own time; this is the throttle window for the same combo on one tile
C.LABEL_MS = 800
-- two labels closer than this are one (a flood guard; the server already pauses 1.2 s between the combos of a player)
C.MIN_GAP_MS = 200
C.MAX_NAME = 40

C.SOUND_DIR = '/modules/game_spellranks/sounds/'
C.SOUNDS = { reaction = 'combo_a', signature = 'combo_b' }

local function int(v)
  v = tonumber(v)
  if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
  return math.floor(v)
end

-- a readable name from an id when the message has none: steam_burst -> "Steam Burst"
function C.nameOf(id)
  local out = tostring(id):gsub('_', ' '):gsub('(%a)(%a*)', function(a, b) return a:upper() .. b end)
  return out
end

-- the `combo` message -> {id, name, kind, color, pos = {x, y, z}, sound}, or nil for junk
function C.clean(data)
  if type(data) ~= 'table' then return nil end
  local id = data.id
  if type(id) ~= 'string' or not id:match('^[a-z][a-z_]*$') or #id > C.MAX_NAME then return nil end
  local x, y, z = int(data.x), int(data.y), int(data.z)
  if not x or not y or not z or x < 0 or y < 0 or z < 0 or z > 15 then return nil end
  local name = data.n
  if type(name) ~= 'string' or name == '' or #name > C.MAX_NAME then name = C.nameOf(id) end
  local row = C.COMBOS[id]
  local kind = row and row.kind or C.DEFAULT_KIND
  return { id = id, name = name, kind = kind, color = row and row.color or C.DEFAULT_COLOR, pos = { x = x, y = y, z = z },
    sound = C.SOUND_DIR .. C.SOUNDS[kind] .. '.ogg' }
end

-- the text over the target: the name through tr(), never more than the name (the translation is the English key's pt-BR)
function C.labelText(c, translate)
  local t = translate and translate(c.name) or c.name
  if type(t) ~= 'string' or t == '' then t = c.name end
  return t
end

-- a gate against a flood: gate:allow(c, nowMs) is false for a label within MIN_GAP_MS of the last one, or the same combo on the same
-- tile within LABEL_MS
function C.newGate()
  return { lastAt = nil, seen = {} }
end

function C.allow(gate, c, now)
  if gate.lastAt and now - gate.lastAt < C.MIN_GAP_MS then return false end
  local key = c.id .. '@' .. c.pos.x .. ',' .. c.pos.y .. ',' .. c.pos.z
  local at = gate.seen[key]
  if at and now - at < C.LABEL_MS then return false end
  gate.seen[key] = now
  gate.lastAt = now
  for k, t in pairs(gate.seen) do
    if now - t >= C.LABEL_MS then gate.seen[k] = nil end
  end
  return true
end

return C
