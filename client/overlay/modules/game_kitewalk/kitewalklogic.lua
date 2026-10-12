-- Keep attacking while moving, the logic without client API (tested by kitewalklogic_test.lua).
-- The server does the walking and the attacks (src-patch 0028): a walk the player asks for (a map or minimap click,
-- a key) wins over the chase of the attacked creature, and its steps neither cancel nor delay the next attack, so the
-- character walks the clicked path and hits the target whenever it is in range. The client's walking is untouched (a
-- click walk never cancelled the attack in the base client); base patch 0039 only stops the base option "Auto Chase
-- Off" from switching the stance to Don't Chase on each manual walk while this option is on. This module tells the
-- server the option "Keep attacking while moving" (Options > Interface, client base patch 0039): client -> server,
-- extended opcode 186, {"on": true | false}. Without the option (an older settings module) it counts as on, the
-- server's default.
KiteWalkLogic = {}
local L = KiteWalkLogic

L.OPCODE = 186
L.OPTION = 'keepAttackingWhileMoving'

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
