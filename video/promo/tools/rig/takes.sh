#!/bin/bash
# takes.sh: record the raw clips that src/trailer_timing.json cuts (video/promo/README.md "Live rig").
# RIG=/scratch/rig takes.sh [name ...]   (no name: every take). Needs the rig up: rig.sh db, rig.sh server.
# Positions are on the installed base map with the contentareas plans (MAP_GUIDE.md); monsters respawn between takes.
# GM help is setup only: gear, level, teleports, a boss placed in a hunt, a pack thinned so a boss room opens.
# What the clips show is the game itself: the spells, the damage, the drops, the queues and the boss mechanics.
set -u
RIG=${RIG:?}; H=$(cd "$(dirname "$0")" && pwd); r() { "$H/rig.sh" "$@"; }
export DISPLAY=:831
ELEM="Rig.seq({{300,Rig.walk(East)},{450,Rig.walk(East)},{700,Rig.say('drai zhul infr doma')},{2700,Rig.attack()},{200,Rig.say('drai gal vas infr')},{2600,Rig.say('drai gal vas hyr krypt')},{2600,Rig.say('drai zhul infr doma')}}) return 1"
BOSSCAST="{200,Rig.say('drai gal vas infr')},{2300,Rig.say('drai gal vas hyr krypt')},{2300,Rig.say('drai zhul infr doma')},{2600,Rig.say('drai gal vas infr')},{2300,Rig.say('drai zhul infr doma')}"
tp() { echo "local p = Player('$1') p:teleportTo(Position($2)) return 'tp'"; }
# the boss named $1 near x,y ($2) on floor z: put $3 at an offset from it (bosses wander)
nearBoss() { echo "local b for z = 7, 11 do for _, c in ipairs(Game.getSpectators(Position($2, z), false, false, 90, 90, 90, 90)) do if c:isMonster() and c:getName():find('$1') then b = c end end end if not b then return 'no boss' end local q = b:getPosition() Player('$3'):teleportTo(Position(q.x + $4, q.y + $5, q.z)) RigBoss = b return 'boss'"; }
# every monster of the run's floor but the boss and the ones beside the player: the 85% gate opens for the take
thin() { echo "local q = Player('Ilsabet'):getPosition() local k = 0 for _, c in ipairs(Game.getSpectators(Position($1, 9), false, false, 80, 80, 80, 80)) do local cp = c:getPosition() if c:isMonster() and cp.z == 9 and not c:getName():find('$2') and math.max(math.abs(cp.x - q.x), math.abs(cp.y - q.y)) > 8 then c:remove() k = k + 1 end end return k"; }
queue() {  # open the Dungeons window, pick the row at y, press Enter queue
  r sx "RigPeace(Player('Ilsabet')) Player('Ilsabet'):setStorageValue(DUNGEON_SYSTEM.Storages.timerCooldown or DUNGEON_SYSTEM.Storages.TimerCooldown, 0) return 1" 1 >/dev/null
  ( sleep 0.5; r cx "modules.game_dungeons.show() return 1" 0.1 >/dev/null; sleep 2.5; xdotool mousemove 480 "$1"; sleep 0.5; xdotool click 1
    r sx "RigPeace(Player('Ilsabet')) return 1" 0.3 >/dev/null; sleep 1; xdotool mousemove 687 820; sleep 0.5; xdotool click 1
    sleep 0.3; xdotool mousemove 1919 1079; sleep 2.2; r cx "modules.game_dungeons.hide() return 1" 0.1 >/dev/null ) &
  r rec "$2" 13; wait
}
uiclips() {  # $1 client language, $2 file suffix: the feature windows at the temple
  LNG=$1 r char Ilsabet >/dev/null; r sx "$(tp Ilsabet 32957,32078,7)" 2 >/dev/null
  r cx "modules.game_dungeons.show() return 1" 3 >/dev/null
  ( sleep 1; xdotool mousemove 480 650 click 1; sleep 2.2; xdotool mousemove 480 710 click 1; sleep 0.5; xdotool mousemove 1919 1079 ) &
  r rec "ui_dungeons_$2" 7; wait; r cx "modules.game_dungeons.hide() return 1" 1 >/dev/null
  for m in game_riftatlas game_codex game_spellsupports game_charms; do
    r cx "modules.$m.show() return 1" 4 >/dev/null
    ( sleep 1.5; xdotool mousemove 900 560; sleep 0.5; xdotool mousemove 1919 1079 ) & r rec "ui_${m#game_}_$2" 5; wait
    r cx "pcall(modules.$m.hide) return 1" 1 >/dev/null
  done
  r cx "modules.game_passivetree.show() return 1" 12 >/dev/null
  ( sleep 0.6; xdotool mousemove 900 560 mousedown 1; for _ in $(seq 60); do xdotool mousemove_relative -- -6 -3; sleep 0.05; done
    xdotool mouseup 1; sleep 0.3; xdotool mousemove 1000 700 mousedown 1; for _ in $(seq 50); do xdotool mousemove_relative -- 4 -5; sleep 0.05; done
    xdotool mouseup 1; xdotool mousemove 1919 1079 ) & r rec "ui_tree_$2" 8; wait
  r cx "modules.game_passivetree.hide() return 1" 1 >/dev/null
}
charsel() {  # the character select, arrows down through the four rig characters
  r client - "$1" >/dev/null; sleep 2.5; xdotool mousemove 1919 1079
  ( for _ in 1 2 3; do sleep 2.4; xdotool key Down; done ) & r rec "ui_charsel_$2" 10; wait
}

WANT=""; [ $# -gt 0 ] && WANT=" $* "
go() { [ -z "$WANT" ] || [[ "$WANT" == *" $1 "* ]]; }

# Ilsabet, Elementalist, level 2000 (char with kit mage, then the level by sx; see README)
if go c1_take4 || go c1_take3 || go c1_melt || go c1_bone || go c2_teleport; then r char Ilsabet mage 2000 >/dev/null; fi
go c1_take4 && r take c1_take4 14 "$(tp Ilsabet 15186,15009,7)" "$ELEM"                 # Rimecrown Depths
go c1_take3 && r take c1_take3 14 "$(tp Ilsabet 14981,14641,8)" "$ELEM"                 # Widowmere
go c1_melt && r take c1_melt 13 "$(tp Ilsabet 15238,14405,9)" "$ELEM"                   # Wyrmspine Hollows
go c1_bone && r take c1_bone 11 "$(tp Ilsabet 14770,14401,10)" "Rig.seq({{300,Rig.walk(East)},{450,Rig.walk(East)},{1500,Rig.say('drai zhul infr doma')},{3400,Rig.say('drai zhul infr doma')}}) return 1"  # Bonechoir Catacomb: drops
go c2_teleport && r take c2_teleport 12 "$(tp Ilsabet 31629,32256,6)" "Rig.seq({{1200,Rig.walk(West)},{450,Rig.walk(West)},{450,Rig.walk(West)},{450,Rig.walk(West)},{450,Rig.walk(West)},{450,Rig.walk(West)},{450,Rig.walk(West)},{500,Rig.walk(North)},{500,Rig.walk(North)}}) return 1" 2  # Cinderhold teleport room
if go c3_berserker2 || go c3_berserker3; then r char Haldric berserker 2000 >/dev/null; fi
CLEAVE="Rig.seq({{300,Rig.walk(East)},{450,Rig.walk(East)},{450,Rig.walk(East)},{700,Rig.attack()},{300,Rig.say('kah gal')},{2000,Rig.say('kah grund krak')},{2000,Rig.attack()},{100,Rig.say('kah gal vas tyr')},{2200,Rig.attack()},{100,Rig.say('kah spir')},{2000,Rig.say('kah gal')}}) return 1"
go c3_berserker2 && r take c3_berserker2 14 "$(tp Haldric 14778,15009,7)" "$CLEAVE"      # Hexwood Thicket
go c3_berserker3 && r take c3_berserker3 13 "$(tp Haldric 14979,14401,10)" "$CLEAVE"     # Sulphur Gallery
go c4_bonelord2 && { r char Ysolde necromancer 2000 >/dev/null; r take c4_bonelord2 15 "$(tp Ysolde 14982,14386,10)" "Rig.seq({{300,Rig.say('vael gal oss')},{1300,Rig.say('vael oss')},{1300,Rig.say('vael oss')},{1300,Rig.say('tor vas oss')},{1200,Rig.walk(South)},{450,Rig.walk(South)},{450,Rig.walk(South)},{450,Rig.walk(South)},{450,Rig.walk(South)},{450,Rig.walk(South)},{450,Rig.walk(South)},{600,Rig.attack()},{200,Rig.say('kah nyx maled')},{1600,Rig.say('kah oss lanc')},{1600,Rig.say('drai sang oss')}}) return 1"; }
go c5_inquisitor && { r char Sorenne templar 2000 >/dev/null; r take c5_inquisitor 12 "$(tp Sorenne 14930,14361,10)" "Rig.seq({{300,Rig.walk(East)},{450,Rig.walk(East)},{700,Rig.attack()},{200,Rig.say('drai gal sol orr')},{1800,Rig.say('kah sol vehm')},{1800,Rig.say('drai gal sol orr')},{1800,Rig.say('drai sol haln')},{1800,Rig.say('drai gal sol orr')}}) return 1"; }
# dungeons, as Ilsabet from the temple: The Pyre Throne (row y 710) and its boss, The Fallen Sanctum (row 650) and Vaelith
if go ui_dungeon_enter2 || go c6_dungeon2 || go c11_azhkarrath; then
  r char Ilsabet >/dev/null; r sx "$(tp Ilsabet 32957,32076,7)" 2 >/dev/null
  go ui_dungeon_enter2 && queue 710 ui_dungeon_enter2
  go c6_dungeon2 && r take c6_dungeon2 13 "$(tp Ilsabet 24836,24855,9)" "Rig.seq({{300,Rig.walk(South)},{450,Rig.walk(South)},{700,Rig.say('drai zhul infr doma')},{2600,Rig.attack()},{200,Rig.say('drai gal vas infr')},{2400,Rig.say('drai gal vas hyr krypt')},{2400,Rig.say('drai zhul infr doma')}}) return 1"
  r sx "$(thin 24858,24853 Azhkarrath)" 8 >/dev/null
  go c11_azhkarrath && r take c11_azhkarrath 15 "$(nearBoss Azhkarrath 24858,24853 Ilsabet 2 1)" "Rig.seq({{100,Rig.attackName('Azhkarrath')},$BOSSCAST,{2300,Rig.say('drai gal vas infr')}}) return 1"
fi
if go c7_vaelith2; then
  r sx "$(tp Ilsabet 32957,32076,7)" 2 >/dev/null; queue 650 ui_dungeon_enter
  r sx "$(thin 24602,24853 Vaelith)" 8 >/dev/null
  r take c7_vaelith2 15 "$(nearBoss Vaelith 24602,24853 Ilsabet -3 1)" "Rig.seq({{200,Rig.attackName('Vaelith')},$BOSSCAST}) return 1"
fi
# Kharzun placed in the Slagmourn Foundry hunt (the room of his own dungeon is The Iron Crucible)
go c8_kharzun && r take c8_kharzun 15 "local c0 = Position(14379, 14831, 10) for _, c in ipairs(Game.getSpectators(c0, false, false, 12, 12, 9, 9)) do if c:isMonster() then c:remove() end end Game.createMonster('Forgewarden Kharzun', Position(14382, 14830, 10), false, true) Player('Ilsabet'):teleportTo(Position(14377, 14834, 10)) return 1" "Rig.seq({{200,Rig.attackName('Kharzun')},$BOSSCAST}) return 1"
# a tier 6 Rift Key (GM command, then the group back to player), the key used, a pack inside
if go c9_rift; then
  r sx "local p = Player('Ilsabet') p:teleportTo(p:getTown():getTemplePosition()) p:setGroup(Group(6)) return 1" 1 >/dev/null
  r cx "g_game.talk('/rift key 6 3') return 1" 3 >/dev/null
  r sx "local p = Player('Ilsabet') p:setGroup(Group(1)) RigPeace(p) return tostring(ChaosRift.open(p, p:getItemById(10155, true)))" 3
  r sx "local p = Player('Ilsabet') local q = p:getPosition() local best, bn = q, 0 for dx = -60, 60, 4 do for dy = -60, 60, 4 do local n = 0 for _, c in ipairs(Game.getSpectators(Position(q.x + dx, q.y + dy, q.z), false, false, 5, 5, 4, 4)) do if c:isMonster() then n = n + 1 end end if n > bn then bn, best = n, Position(q.x + dx - 4, q.y + dy - 2, q.z) end end end p:teleportTo(best) return bn" 3
  r take c9_rift 13 "return 1" "Rig.seq({{300,Rig.walk(South)},{450,Rig.walk(East)},{700,Rig.say('drai zhul infr doma')},{2600,Rig.attack()},{200,Rig.say('drai gal vas infr')},{2400,Rig.say('drai gal vas hyr krypt')},{2400,Rig.say('drai zhul infr doma')}}) return 1"
fi
# the world boss (GM start), through the temple portal, the boss arena after the lobby countdown
if go c10_worldboss; then
  r sx "local p = Player('Ilsabet') p:teleportTo(p:getTown():getTemplePosition()) p:setGroup(Group(6)) return 1" 1 >/dev/null
  r cx "g_game.talk('/worldboss start 1') return 1" 3 >/dev/null; r sx "Player('Ilsabet'):setGroup(Group(1)) return 1" 1 >/dev/null
  r cx "Rig.seq({{500,Rig.walk(East)},{450,Rig.walk(East)},{450,Rig.walk(East)}}) return 1" 100 >/dev/null
  r take c10_worldboss 14 "$(nearBoss Kaelgor 5017,5030 Ilsabet -2 4)" "Rig.seq({{300,Rig.attackName('Kaelgor')},$BOSSCAST}) return 1" 1.2
fi
go ui_charsel_pt && charsel pt-BR pt
go ui_charsel_en && charsel en en
go ui_pt && uiclips pt-BR pt
go ui_en && uiclips en en
echo done
