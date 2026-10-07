-- Run from the server/ folder: lua5.3 tests/daily_test.lua (mock engine API; CI runs it)
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local registry = {}
function CreatureEvent(name) local o = {}; function o:register() registry[name] = o end; function o:type() end; return o end
function addEvent() end
function TalkAction() local o = {}; function o:register() end; function o:separator() end; return o end
function ItemType(id) return {getClientId = function() return id + 1000 end, getName = function() return "item" .. id end} end
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.dayKey = function() return 20261007 end
Chaos.yesterdayKey = function() return 20261006 end
local sent = {}
Chaos.send = function(_, _, action, data) sent[#sent + 1] = {action = action, data = data} end
Chaos.decode = function(b) return b end
local room = 100 -- how many items fit
Chaos.giveItem = function(p, id, count) local g = math.min(count, room); room = room - g; p.items[id] = (p.items[id] or 0) + g; return g end
local function mkPlayer()
  local p = {st = {}, items = {}, msgs = {}}
  function p:getStorageValue(k) return self.st[k] or -1 end
  function p:setStorageValue(k, v) self.st[k] = v end
  function p:sendCancelMessage(t) self.cancel = t end
  function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
  function p:removeItem(id, c) self.items[id] = self.items[id] - c; room = room + c end
  function p:getPosition() return {sendMagicEffect = function() end} end
  function p:getId() return 1 end
  return p
end
dofile("data/scripts/chaos/daily.lua")
local assertEq = function(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local cfg = Chaos.daily
assertEq(#cfg.rewards, 7, "seven rewards")
local ev = registry["ChaosDailyExtended"]
local S = Chaos.storage
-- the client sends v = map[slot] with map = {6,7,1,2,3,4,5}
local map = {6, 7, 1, 2, 3, 4, 5}
local p = mkPlayer()
-- day 1
ev.onExtendedOpcode(p, ChaosOpcodes.daily, {action = "calim", data = map[1]})
assertEq(p.items[2152], 20, "day 1 reward")
-- same day again is refused
ev.onExtendedOpcode(p, ChaosOpcodes.daily, {action = "calim", data = map[2]})
assert(p.cancel and p.cancel:find("already"), "second claim refused")
-- walk the streak: pretend each following day
for slot = 2, 7 do
  p.st[S.dailyLastClaim] = 20261006 -- yesterday
  p.st[S.dailyStreakDay] = slot - 1
  p.cancel = nil
  ev.onExtendedOpcode(p, ChaosOpcodes.daily, {action = "calim", data = map[slot]})
  assert(not p.cancel, "claim day " .. slot)
end
assertEq(p.items[2160], 1 + 2, "crystal coins from day 5 and the week bonus")
assertEq(p.items[29857], 1 + 3, "divine orbs")
-- all or nothing on day 7 when the bonus does not fit
local q = mkPlayer(); room = 3 -- the 3 orbs fit, the 2 crystal coins do not
q.st[S.dailyLastClaim] = 20261006; q.st[S.dailyStreakDay] = 6
ev.onExtendedOpcode(q, ChaosOpcodes.daily, {action = "calim", data = map[7]})
assert(q.cancel and q.cancel:find("room"), "refused when the bonus does not fit")
assertEq(q.items[29857], 0, "orbs taken back")
assertEq(q.st[S.dailyLastClaim], 20261006, "no streak change on failure")
print("daily: all asserts passed")
