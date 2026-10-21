-- Median experience and health per kill by hunting level, file experience x the pace curve. It leaves out the engine's x0.03 L
-- experience factor of level-scaled monsters (server/README.md "Pack combat (pace)", correction 2026-10-22).
ChaosPaceCore = nil
local P = dofile("data/scripts/chaos/pace_core.lua") or ChaosPaceCore
local cfg = dofile("data/scripts/chaos/pace_config.lua")
local pool = dofile("data/scripts/chaos/bounty_pool.lua")
local rows = {}
for _, e in ipairs(pool.hunt) do
  local lvl, sc = P.entryLevel(cfg, e)
  local f = P.factors(cfg, lvl, sc)
  rows[#rows+1] = {name=e.name, lvl=lvl, sc=sc, exp=e.exp, hp=e.health, xp=e.exp*f.xp, hpE=e.health*f.health}
end
table.sort(rows, function(a,b) return a.lvl<b.lvl end)
local b = {}
for _, r in ipairs(rows) do
  local k = math.floor(r.lvl/100)*100
  b[k] = b[k] or {}
  table.insert(b[k], r)
end
local ks = {} for k in pairs(b) do ks[#ks+1]=k end table.sort(ks)
for _,k in ipairs(ks) do
  local t = b[k]; table.sort(t, function(a,c) return a.xp<c.xp end)
  local m = t[math.ceil(#t/2)]
  local sc = 0 for _,r in ipairs(t) do if r.sc then sc=sc+1 end end
  print(k, #t, "scaled="..sc, "medXP="..string.format("%.0f",m.xp), "minXP="..string.format("%.0f",t[1].xp), "maxXP="..string.format("%.0f",t[#t].xp), "medHP="..string.format("%.0f",m.hpE), m.name, m.lvl)
end
print("--- scaled")
for _, r in ipairs(rows) do if r.sc then print(r.name, r.lvl, "exp="..r.exp, "hp="..r.hp, "effXP="..string.format("%.0f", r.xp), "effHP="..string.format("%.0f", r.hpE)) end end
