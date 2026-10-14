-- Pure helpers of game_shaderfx (no client API; shaderfx_test.lua). The UI widget shaders of base patch 0044:
-- liquid orbs (chaos_ui_orb), the shine across legendary and unique frames (chaos_ui_shine) and greyscale for
-- locked items (chaos_ui_grey). Lua 5.1 / LuaJIT and Lua 5.3.
ShaderFxLogic = {}
local L = ShaderFxLogic

-- the UI shaders: name -> {vertex, fragment} (files in data/shaders, ".frag" added by the client)
L.UI_SHADERS = {
  { name = 'chaos_ui_orb', vertex = '/shaders/chaos_ui_vertex', fragment = '/shaders/chaos_ui_orb' },
  { name = 'chaos_ui_shine', vertex = '/shaders/chaos_ui_vertex', fragment = '/shaders/chaos_ui_shine' },
  { name = 'chaos_ui_grey', vertex = '/shaders/chaos_ui_vertex', fragment = '/shaders/chaos_ui_grey' },
}

L.SHINE_FROM_RARITY = 5   -- Legendary (game_itemrarity RARITY ids) and up, and every unique
L.SHINE_PERIOD = 3.5      -- seconds between sweeps
L.SHINE_STRENGTH = 0.8
L.SHINE_WIDTH = 0.12
L.UNIQUE_SHINE_STRENGTH = 1.0
L.LOCKED_ATTR = 3         -- item custom attribute 3 (ChaosItemAttr.LOCKED): 1 = locked

L.ORB_COLORS = { health = '#d8262c', mana = '#2f6ef0' }
L.SLOSH_DECAY_PER_SECOND = 0.12 -- what is left of the slosh after one second
L.SLOSH_MIN = 0.01

-- 0..1 fill of an orb (0 without a maximum)
function L.fill(value, max)
  value, max = tonumber(value) or 0, tonumber(max) or 0
  if max <= 0 or value <= 0 then return 0 end
  if value >= max then return 1 end
  return value / max
end

-- the slosh after the fill moved from `old` to `new`: a bigger change sloshes more, it never drops on a change
function L.sloshAfter(old, new, slosh)
  slosh = tonumber(slosh) or 0
  local d = math.abs((tonumber(new) or 0) - (tonumber(old) or 0))
  if d <= 0 then return slosh end
  return math.min(1, math.max(slosh, 0.25 + d * 3))
end

-- the slosh after dtMs milliseconds of rest (0 once it is too small to see)
function L.decay(slosh, dtMs)
  slosh = tonumber(slosh) or 0
  local s = slosh * (L.SLOSH_DECAY_PER_SECOND ^ ((tonumber(dtMs) or 0) / 1000))
  if s < L.SLOSH_MIN then return 0 end
  return s
end

-- a stable 0..1 number for a text (two widgets of different ids get different phases)
function L.phaseOf(text)
  text = tostring(text or '')
  local h = 7
  for i = 1, #text do
    h = (h * 31 + text:byte(i)) % 1000003
  end
  return (h % 1000) / 1000
end

-- the four shader values of an orb: fill, slosh, phase, foam line on
function L.orbParams(fill, slosh, phase)
  return math.max(0, math.min(1, tonumber(fill) or 0)), math.max(0, math.min(1, tonumber(slosh) or 0)),
    math.max(0, math.min(1, tonumber(phase) or 0)), 1
end

-- the shine of a rarity frame: nil (no shine) or the four shader values (phase offset s, period s, strength, width)
function L.shineParams(rarityId, unique, enabled, key)
  if not enabled then return nil end
  rarityId = tonumber(rarityId) or 0
  if not unique and rarityId < L.SHINE_FROM_RARITY then return nil end
  return L.phaseOf(key) * L.SHINE_PERIOD, L.SHINE_PERIOD, unique and L.UNIQUE_SHINE_STRENGTH or L.SHINE_STRENGTH,
    L.SHINE_WIDTH
end

-- is an item locked (custom attribute 3)? item = anything with getCustomAttribute
function L.isLocked(item)
  if not item or not item.getCustomAttribute then return false end
  local ok, v = pcall(item.getCustomAttribute, item, L.LOCKED_ATTR)
  return ok and (tonumber(v) or 0) > 0
end

-- what a slot's item shader should become: 'grey' to set it, 'clear' to take back our grey, nil to leave it
function L.greyAction(locked, greyedByUs)
  if locked and not greyedByUs then return 'grey' end
  if not locked and greyedByUs then return 'clear' end
  return nil
end

-- an item slot: grey it, or take our grey back. The mark is set BEFORE setItemShader: the engine calls the slot's
-- onItemChange from setItemShader, game_itemrarity answers with onSlotItem and so this again; with the mark set after
-- the call every re-entry greyed once more, without end ("stack overflow" at each container with a locked item, such
-- as the store's Loot Bag or Everfull Ration: live test 2026-10-14). Returns the action taken.
function L.applyItemGrey(widget, on)
  local action = L.greyAction(on, widget.sfxGrey == true)
  if action == 'grey' then
    widget.sfxGrey = true
    widget:setItemShader('chaos_ui_grey')
  elseif action == 'clear' then
    widget.sfxGrey = nil
    widget:setItemShader('')
  end
  return action
end
