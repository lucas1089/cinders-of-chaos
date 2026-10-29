-- Right-click equips items, the logic without client API (tested by rightclickequiplogic_test.lua).
-- The server does the equipping (src-patch 0024, Game::chaosUseEquip): a use of a piece of equipment the character
-- carries, when the item has no use of its own, puts it on; a use of a worn one takes it off into the backpack. The
-- client's mouse controls are untouched: whatever click is "use" in the chosen preset equips (a right-click in
-- Classic Controls, Ctrl + click in Regular Controls, a left-click in Left Smart-Click, "Use" in the menu). This
-- module only tells the server the option "Right-click equips items" (Options > Interface, client base patch 0037):
-- client -> server, extended opcode 188, {"on": true | false}. Without the option (an older settings module) it
-- counts as on, the server's default.
-- One exception needs the client: a multi-use weapon (the stock "break furniture" use with) starts a use with on that
-- click. The server sends at login which looks those are ({action = "multiuse", data = {ids = {client ids}}}:
-- equipment, tool weapons such as the crowbar included); for them, on the preset's use click in the inventory or an open
-- container, the module sends a plain use instead (L.shouldEquip). "Use with ..." stays in the context menu.
RightClickEquipLogic = {}
local L = RightClickEquipLogic

L.OPCODE = 188
L.OPTION = 'rightClickEquip'

-- the option's value as on / off: unset or anything but an explicit "off" is on (the default)
function L.isOn(value)
  if value == false or value == 0 or value == '0' or value == 'false' then
    return false
  end
  return true
end

-- the message for the server
function L.message(on)
  return { on = on and true or false }
end

-- true when the server must be told: a new session (lastSent nil), a forced send, or a changed value
function L.needsSend(lastSent, on, force)
  if force or lastSent == nil then
    return true
  end
  return lastSent ~= (on and true or false)
end

-- the server's list as a set {[client id] = true}
function L.idSet(ids)
  local set = {}
  for _, id in ipairs(type(ids) == 'table' and ids or {}) do
    local n = tonumber(id)
    if n then set[n] = true end
  end
  return set
end

-- true when the click is the mouse preset's use of an item widget that starts a use with for a multi-use item
-- (modules/game_interface processMouseAction): mode is the option classicControl (1 Classic Controls, 2 Regular
-- Controls, 3 Left Smart-Click), button 'left' | 'right', mods {ctrl, shift, alt}, both true while the other button
-- is held too (Classic: look).
function L.useClick(mode, button, mods, both)
  mods = mods or {}
  mode = tonumber(mode) or 1
  if mode < 1 or mode > 3 then mode = 1 end
  local none = not mods.ctrl and not mods.shift and not mods.alt
  if both then return false end
  if mode == 1 then
    return button == 'right' and none
  elseif mode == 2 then
    return (button == 'left' or button == 'right') and mods.ctrl and not mods.shift and not mods.alt or false
  end
  return button == 'left' and none
end

-- true when an item position is an inventory slot (1-10, and 13: the badge slot) or a slot of an open container, as the
-- server takes it (an item lying on the map keeps the base behaviour)
function L.inContainerOrInventory(pos)
  if type(pos) ~= 'table' or tonumber(pos.x) ~= 0xFFFF then return false end
  local y = tonumber(pos.y) or 0
  if y >= 0x40 then return true end
  return y >= 1 and y <= 10 or y == 13
end

-- true when the module sends a plain use (the server then equips): the option on, a multi-use look from the
-- server's list, the item in the inventory or an open container, and the preset's use click
function L.shouldEquip(o)
  if not o or not L.isOn(o.option) or not o.multiUse then return false end
  if not (o.ids or {})[tonumber(o.clientId) or -1] then return false end
  if not L.inContainerOrInventory(o.pos) then return false end
  return L.useClick(o.mode, o.button, o.mods, o.both)
end

return L
