-- The badge slot, the logic without client API (tested by badgeslotlogic_test.lua). Owner decision 2026-10-21: the
-- second ring slot goes (server src-patch 0058: the ammunition slot, 10, takes nothing) and the badge slot (13) is
-- drawn where it was (client base patch 0113; server/README.md "Badge slot"). Its placeholder image is drawn by
-- client/tools/gen_skin.py (data/images/game/slots/badge(-blessed).png, a shield with a star).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
BadgeSlotLogic = {}
local L = BadgeSlotLogic

L.SLOT = 13 -- InventorySlotBadge (base patch 0113)
L.TOOLTIP = 'Badge'
-- the soul label of the inventory window named ammunition among what soul points create; there is none any more
L.SOUL_TOOLTIP = tr('Soul Points: Needed to cast spells that create items such as runes\nor food. They can be regained by killing monsters,\nsleeping in a bed, or in resting areas provided you have reached\nthe needed reward streak.')

-- the tooltip of an inventory slot widget: 'Badge' on the empty badge slot; '' once an item is in it (the item
-- tooltip takes over); nil for every other slot (left as it is)
function L.slotTooltip(slot, hasItem)
  if tonumber(slot) ~= L.SLOT then return nil end
  return hasItem and '' or L.TOOLTIP
end

return L
