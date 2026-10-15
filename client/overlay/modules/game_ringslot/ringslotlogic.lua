-- The second ring slot, the logic without client API (tested by ringslotlogic_test.lua). Since server src-patch 0023
-- inventory slot 10 (the old ammunition slot) takes rings only (server/README.md "Second ring slot"). Its placeholder
-- image is the ring's: the Chaos skin draws data/images/game/slots/ammo(-blessed).png with the ring silhouette
-- (client/tools/gen_skin.py), so the inventory window and the action bar's equipment presets show a ring slot.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
RingSlotLogic = {}
local L = RingSlotLogic

L.SLOT = 10 -- InventorySlotAmmo
L.TOOLTIP = 'Ring'
-- the soul label of the inventory window named ammunition among what soul points create; there is none any more
L.SOUL_TOOLTIP = tr('Soul Points: Needed to cast spells that create items such as runes\nor food. They can be regained by killing monsters,\nsleeping in a bed, or in resting areas provided you have reached\nthe needed reward streak.')

-- the tooltip of an inventory slot widget: 'Ring' on the empty second ring slot; '' once an item is in it (the item
-- tooltip takes over); nil for every other slot (left as it is)
function L.slotTooltip(slot, hasItem)
  if tonumber(slot) ~= L.SLOT then return nil end
  return hasItem and '' or L.TOOLTIP
end

return L
