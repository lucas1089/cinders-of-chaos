-- The simplified skill list (owner debug item 46: "Simplificar skills: melee, ranged, magic, wand e shielding"; server/README.md
-- "One melee skill"). Pure Lua, no client calls; tests: simpleskills_logic_test.lua.
--
-- The protocol still carries the seven weapon skills (fist, club, sword, axe, distance, shielding, fishing). The server hits,
-- casts and trains with the BEST of club, sword and axe (data/scripts/chaos/melee_skill_core.lua), so the window shows
-- one "Melee" row: the best of the three, with its percent to the next level. Distance fighting is "Ranged"; the magic
-- level is "Magic / Wand" (wands and rods hit by magic level, they have no skill of their own); Fist Fighting is the
-- Monk line's skill and is shown for the Monk, Shadowfist and Iron Sage only.

ChaosSimpleSkills = ChaosSimpleSkills or {}
local S = ChaosSimpleSkills

S.SKILL = { fist = 0, club = 1, sword = 2, axe = 3, distance = 4, shielding = 5, fishing = 6 }
S.MELEE = { 'sword', 'club', 'axe' } -- the order ties are broken in (the server's, melee_skill_core.lua)
S.MONK_LINE = { [17] = true, [18] = true, [19] = true }

-- skills = { sword = {level, base, percent}, club = ..., axe = ... } -> the row to show: { name, level, base, percent }
-- (the best level, a tie by the higher percent, then by the order above)
function S.melee(skills)
  local best, bestName
  for _, name in ipairs(S.MELEE) do
    local s = skills and skills[name]
    if s then
      local level, percent = tonumber(s.level) or 0, tonumber(s.percent) or 0
      if not best or level > best.level or (level == best.level and percent > best.percent) then
        best = { level = level, base = tonumber(s.base) or level, percent = percent }
        bestName = name
      end
    end
  end
  if not best then
    return { name = 'sword', level = 0, base = 0, percent = 0 }
  end
  best.name = bestName
  return best
end

-- the Fist Fighting row belongs to the Monk line (server vocation ids)
function S.showFist(vocationId)
  return S.MONK_LINE[tonumber(vocationId) or -1] == true
end

-- the weapon-skill rows the window hides: the club and the axe (the sword row becomes "Melee"), and the fist unless Monk
function S.hidden(vocationId)
  local list = { 'club', 'axe' }
  if not S.showFist(vocationId) then
    list[#list + 1] = 'fist'
  end
  return list
end
