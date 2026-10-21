-- Median experience and health per kill by hunting level, as the engine gives them: file experience x the engine's
-- monster level factor (x0.03 L of a level-scaled monster, when above 1; base player.lua, server/README.md "Late game")
-- x the pace curve, file health x the engine's x(1 + 0.0074 L) of a level-scaled monster x the pace curve. Before the
-- stage, the monster tier and every bonus (bounty_core.lua B.monsterKillBase is the same experience).
--     cd server && luajit tools/pace_scan.lua      (also lua5.3)
-- Until 2026-10-22 this left out both engine factors (server/README.md "Pack combat (pace)", O108).
ChaosPaceCore = nil
local P = dofile("data/scripts/chaos/pace_core.lua") or ChaosPaceCore
local cfg = dofile("data/scripts/chaos/pace_config.lua")
local pool = dofile("data/scripts/chaos/bounty_pool.lua")
local rows = {}
for _, e in ipairs(pool.hunt) do
  local lvl, sc = P.entryLevel(cfg, e)
  local f = P.factors(cfg, lvl, sc)
  local xpL, hpL = 1, 1
  if sc then
    xpL = math.max(1, lvl * 0.03)
    hpL = 1 + 0.0074 * lvl
  end
  rows[#rows+1] = {name=e.name, lvl=lvl, sc=sc, exp=e.exp, hp=e.health, xp=e.exp*xpL*f.xp, hpE=e.health*hpL*f.health}
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
for _, r in ipairs(rows) do if r.sc then print(r.name, r.lvl, "exp="..r.exp, "hp="..r.hp, "effXP="..string.format("%.0f", r.xp), "effHP="..string.format("%.0f", r.hpE), "xpPerHp="..string.format("%.2f", r.xp / r.hpE)) end end
