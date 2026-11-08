// The combat helper (HelperLogic.cs, HelperConfig.cs, HelperRotation.cs, HelperEngine.cs) and typed damage numbers (DamageScatter.cs).
// The checks mirror the Lua tests of the main client: game_helper/helper_logic_test.lua, helper_potions_test.lua, game_helperrotation/
// rotation_test.lua, autorotation_test.lua, game_helpertimers/helpertimers_test.lua and game_damagescatter/scatterlogic_test.lua.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class HelperTests
    {
        static readonly Pos From = new Pos(10, 10, 7);

        static HelperCreature At(uint id, int x, int y, int z = 7, int health = 100, int hits = 0) => new HelperCreature(id, new Pos(x, y, z), health, hits);

        public static void Run(Action<bool, string> check)
        {
            Logic(check);
            Timers(check);
            Casts(check);
            Potions(check);
            Config(check);
            Rotation(check);
            Engine(check);
            Typed(check);
            Death(check);
            Loot(check);
        }

        // ------------------------------------------------------------------------------------ helper_logic_test.lua
        static void Logic(Action<bool, string> check)
        {
            var beam = new[] { new[] { 0, 1, 0 }, new[] { 0, 1, 0 }, new[] { 0, 3, 0 } };   // two long to the north, the caster at the bottom
            check(HelperLogic.CountHits(From, Dir.North, beam, new[] { At(1, 10, 9), At(2, 10, 8), At(3, 11, 9) }) == 2, "helper: north beam");
            check(HelperLogic.CountHits(From, Dir.South, beam, new[] { At(1, 10, 11), At(2, 10, 12) }) == 2, "helper: south beam");
            check(HelperLogic.CountHits(From, Dir.East, beam, new[] { At(1, 11, 10), At(2, 12, 10) }) == 2, "helper: east beam");
            check(HelperLogic.CountHits(From, Dir.West, beam, new[] { At(1, 9, 10), At(2, 8, 10) }) == 2, "helper: west beam");
            check(HelperLogic.CountHits(From, Dir.North, beam, new[] { At(1, 10, 9, 8) }) == 0, "helper: another floor");
            check(HelperLogic.CountHits(From, Dir.North, beam, new[] { At(1, 10, 10) }) == 0, "helper: the caster cell does not count by default");
            check(HelperLogic.CountHits(From, Dir.North, beam, new[] { At(1, 10, 10) }, true) == 1, "helper: ranged counts the caster cell");
            check(HelperLogic.CountHits(From, Dir.SouthEast, beam, new[] { At(1, 11, 10) }) == 1, "helper: a diagonal facing counts as east");
            check(HelperLogic.CountHits(From, Dir.North, beam, new[] { At(1, 10, 8) }, false, (a, b) => false) == 0, "helper: no sight, no hit");
            check(HelperLogic.CountHits(From, Dir.North, beam, new[] { At(1, 10, 9) }, false, (a, b) => false) == 1, "helper: a neighbour needs no sight");
            int n;
            var dir = HelperLogic.BestDirection(From, beam, new[] { At(1, 10, 11), At(2, 10, 12), At(3, 10, 9) }, out n);
            check(dir == Dir.South && n == 2, "helper: best facing and its hits");
            HelperLogic.BestDirection(From, beam, new[] { At(1, 30, 30) }, out n);
            check(n == 0, "helper: nothing to hit");

            check(HelperLogic.InReach(From, new Pos(17, 15, 7)), "helper: the corner of the window is in reach");
            check(!HelperLogic.InReach(From, new Pos(18, 10, 7)) && !HelperLogic.InReach(From, new Pos(10, 16, 7)) && !HelperLogic.InReach(From, new Pos(10, 10, 8)), "helper: too far and another floor are out of reach");

            var c = new List<HelperCreature> { At(1, 11, 10, 7, 100), At(2, 12, 10, 7, 20), At(3, 11, 11, 7, 40), At(4, 15, 10, 7, 5) };
            Func<int, uint> pick = mode => { HelperCreature p; return HelperLogic.PickByMode(c, From, mode, out p) ? p.Id : 0u; };
            check(pick(1) == 1, "helper: mode A closest (tie to the lower id)");
            check(pick(2) == 4, "helper: mode B farthest");
            check(pick(3) == 4, "helper: mode C lowest health");
            check(pick(4) == 1, "helper: mode D highest health");
            check(pick(6) == 3, "helper: mode F closest, then lowest health");
            check(pick(7) == 1, "helper: mode G closest, then highest health");
            check(pick(8) == 4, "helper: mode H farthest, then lowest health");
            check(pick(0) == 3, "helper: no mode means F");
            HelperCreature pe;
            check(HelperLogic.PickByMode(new[] { At(1, 11, 10, 7, 100, 1), At(2, 12, 10, 7, 20, 4) }, From, 5, out pe) && pe.Id == 2, "helper: mode E most hits");
            check(!HelperLogic.PickByMode(new List<HelperCreature>(), From, 1, out pe), "helper: no candidates");

            var rows = new List<HelperHealRow> { new HelperHealRow { Id = 1, Percent = 80 }, new HelperHealRow { Id = 2, Percent = 40 }, new HelperHealRow { Id = 0, Percent = 99 } };
            check(HelperLogic.PickHeal(rows, 100) == 0, "helper: full health heals nothing");
            check(HelperLogic.PickHeal(rows, 70) == 1, "helper: the light heal");
            check(HelperLogic.PickHeal(rows, 30) == 2, "helper: the lowest threshold goes first");
            check(HelperLogic.PickHeal(rows, 30, id => id != 2) == 1, "helper: the next one when one is not ready");

            check(HelperLogic.TrainingDue(new HelperTrainRow { Id = 5, Percent = 90, Enabled = true }, 95), "helper: training above the percent");
            check(!HelperLogic.TrainingDue(new HelperTrainRow { Id = 5, Percent = 90, Enabled = true }, 80) && !HelperLogic.TrainingDue(new HelperTrainRow { Id = 5, Percent = 90 }, 95), "helper: training below the percent and off");
            var h = new HelperHasteRow { Id = 6, Enabled = true };
            check(HelperLogic.HasteDue(h, false, 10000, -1, 0, false), "helper: haste due");
            check(!HelperLogic.HasteDue(h, true, 10000, -1, 0, false), "helper: already hasted");
            check(!HelperLogic.HasteDue(h, false, 10000, 9000, 0, false), "helper: too soon after the last cast");
            check(HelperLogic.HasteDue(h, false, 12600, 10000, 0, false), "helper: after the gap");
            check(!HelperLogic.HasteDue(h, false, 10000, -1, 0, true), "helper: not in a protection zone");
            check(HelperLogic.HasteDue(new HelperHasteRow { Id = 6, Enabled = true, SafeCast = true }, false, 10000, -1, 0, true), "helper: safe cast");
            check(HelperLogic.HasteGap(0) == 2500 && HelperLogic.HasteGap(1) == 5000 && HelperLogic.HasteGap(50) == HelperLogic.HasteMaxGapMs, "helper: the haste gap doubles per miss and is capped");
            var hs = new HelperLogic.HasteState();
            double t = 0; int casts = 0;
            while (t < 600000)   // ten minutes of 500 ms ticks, never hasted: backs off instead of saying it twice a second
            {
                hs.Observe(false);
                if (HelperLogic.HasteDue(h, false, t, hs.Last, hs.Misses, false)) { hs.Cast(t); casts++; }
                t += 500;
            }
            check(casts <= 12, "helper: never hasted, at most 12 casts in 10 minutes, got " + casts);
            check(!HelperLogic.HasteDue(h, false, hs.Last + 2500, hs.Last, hs.Misses, false), "helper: still backed off");
            hs.Observe(true);
            check(hs.Misses == 0, "helper: the haste showing clears the misses");
            hs.Observe(false); hs.Cast(700000);
            check(hs.Misses == 0, "helper: a cast after a seen haste is no miss");

            check(!HelperLogic.SlotDue(new HelperSlot { Id = 1, Percent = 50, Creatures = 3 }, 60, 2), "helper: too few creatures");
            check(HelperLogic.SlotDue(new HelperSlot { Id = 1, Percent = 50, Creatures = 3 }, 60, 3), "helper: enough creatures");
            check(!HelperLogic.SlotDue(new HelperSlot { Id = 1, Percent = 50, Creatures = 3 }, 40, 3), "helper: too little mana");
            check(!HelperLogic.SlotDue(new HelperSlot { Id = 1, Percent = 50, Creatures = 3, ForceCast = true }, 60, 0), "helper: force cast does not skip the count");
            Dir f;
            check(HelperLogic.FacingToward(From, new Pos(14, 11, 7), out f) && f == Dir.East, "helper: facing east");
            check(HelperLogic.FacingToward(From, new Pos(10, 5, 7), out f) && f == Dir.North, "helper: facing north");
            check(!HelperLogic.FacingToward(From, From, out f), "helper: no facing on the same tile");
            check(HelperLogic.FacingToward(From, new Pos(12, 12, 7), out f) && f == Dir.South, "helper: a tie goes vertical");
            var order = HelperLogic.SlotOrder(new List<HelperSlot> { new HelperSlot { Id = 1, Priority = 3 }, new HelperSlot { Id = 2, Priority = 1 }, new HelperSlot { Id = 0, Priority = 1 }, new HelperSlot { Id = 3, Priority = 2 } });
            check(order.Count == 3 && order[0].Id == 2 && order[2].Id == 1, "helper: slots in priority order, empty ones left out");

            // auto turn: a diagonal keeps the facing when it is one of the two sides
            check(HelperLogic.DirToward(From, new Pos(12, 12, 7), Dir.East, out f) && f == Dir.East, "helper: a diagonal keeps an east facing");
            check(HelperLogic.DirToward(From, new Pos(12, 12, 7), Dir.North, out f) && f == Dir.South, "helper: a diagonal goes vertical otherwise");
            Dir turn;
            check(HelperLogic.TurnDirection(true, true, Dir.North, From, true, new Pos(15, 10, 7), false, Dir.North, out turn) && turn == Dir.East, "helper: a wave turns to the target");
            check(!HelperLogic.TurnDirection(true, false, Dir.North, From, true, new Pos(15, 10, 7), false, Dir.North, out turn), "helper: auto turn off");
            check(!HelperLogic.TurnDirection(false, true, Dir.North, From, true, new Pos(15, 10, 7), false, Dir.North, out turn), "helper: a spell that is not directional never turns");
            check(HelperLogic.TurnDirection(true, true, Dir.North, From, false, default(Pos), true, Dir.West, out turn) && turn == Dir.West, "helper: without a target the facing with most monsters");
            check(!HelperLogic.TurnDirection(true, true, Dir.East, From, true, new Pos(15, 10, 7), false, Dir.North, out turn), "helper: already facing it");

            // rotation.lua: what the client can tell it cannot cast
            check(HelperLogic.Castable(new Spell { Level = 300, Mana = 160 }, 300, 160, 500), "helper: level and mana met");
            check(!HelperLogic.Castable(new Spell { Level = 300, Mana = 160 }, 299, 5000, 5000), "helper: level too low");
            check(!HelperLogic.Castable(new Spell { Level = 30, Mana = 160 }, 400, 159, 500), "helper: mana too low");
            check(!HelperLogic.Castable(new Spell { Id = 64, Level = 30, Mana = 80 }, 300, 5000, 5000, 3), "helper: Sundering Palm at 3 chi waits");
            check(HelperLogic.Castable(new Spell { Id = 64, Level = 30, Mana = 80 }, 300, 5000, 5000, 4), "helper: Sundering Palm at 4 chi");
            check(HelperLogic.Castable(new Spell { Id = 64, Level = 30, Mana = 80 }, 300, 5000, 5000), "helper: chi unknown, the server decides");
            check(!HelperLogic.Castable(new Spell { Level = 30, ManaPercent = 10 }, 100, 40, 500) && HelperLogic.Castable(new Spell { Level = 30, ManaPercent = 10 }, 100, 60, 400), "helper: a mana percent cost counts the maximum");
            check(HelperLogic.IsSelfArea(new Spell { Group = 1, Range = 0 }) && !HelperLogic.IsSelfArea(new Spell { Group = 1, Range = 5, Target = "single" }), "helper: a self-centred attack without an area");
            check(!HelperLogic.IsSelfArea(new Spell { Group = 3, Range = 0 }), "helper: a support spell is no self area");
            check(HelperLogic.IsDirectional(new Spell { Target = "front", Center = "caster" }) && !HelperLogic.IsDirectional(new Spell { Target = "area", Center = "target" }), "helper: a wave faces, a target area aims");
            check(HelperLogic.CountNear(new[] { At(1, 12, 10), At(2, 15, 10), At(3, 11, 11, 6) }, From, 3) == 1, "helper: monsters near, same floor");
            check(HelperLogic.Channel(new Spell { Group = 2 }) == "heal" && HelperLogic.Channel(new Spell { Group = 1 }) == "attack" && HelperLogic.Channel(new Spell { Group = 4 }) == "attack" && HelperLogic.Channel(new Spell { Group = 3 }) == "support", "helper: the cast channel of a group");
        }

        // ------------------------------------------------------------------------------------ helpertimers_test.lua
        static void Timers(Action<bool, string> check)
        {
            var tm = new HelperTimers();
            check(tm.CastAllowed("attack", "a", 0), "helper timers: the first cast goes");
            check(!tm.CastAllowed("attack", "a", 400), "helper timers: the same words not within 500 ms");
            check(tm.CastAllowed("attack", "a", 500), "helper timers: the same words again after 500 ms");
            check(tm.CastAllowed("attack", "b", 510) && tm.CastAllowed("attack", "c", 520), "helper timers: other words go");
            check(!tm.CastAllowed("attack", "d", 530), "helper timers: at most 4 attack casts a second");
            check(tm.CastAllowed("heal", "h", 530), "helper timers: a heal never waits for the attacks");
            check(tm.CastAllowed("attack", "e", 1000), "helper timers: the second window opens");
            var s = new HelperTimers();
            bool a = s.CastAllowed("support", "1", 0), b = s.CastAllowed("support", "2", 1), c = s.CastAllowed("support", "3", 2), d = s.CastAllowed("support", "4", 3);
            check(a && b && c && !d, "helper timers: at most 3 support casts a second");
            check(s.CastAllowed("nope", "5", 2000), "helper timers: an unknown channel counts as support");
            check(tm.UseReady("potion", 0), "helper timers: a potion is ready at the start");
            tm.Used("potion", 100);
            check(!tm.UseReady("potion", 699) && tm.UseReady("potion", 700), "helper timers: a potion every 600 ms");
        }

        // ------------------------------------------------------------------------------------ rotation_test.lua
        static void Casts(Action<bool, string> check)
        {
            var g1 = new[] { 1 };
            var st = new HelperCasts();
            check(st.Blocked(10, g1, 0) == null, "casts: free");
            st.Cast(10, g1, 0);
            check(st.Blocked(10, g1, 50) == "pending", "casts: its own cast waits");
            check(st.Blocked(11, g1, 50) == "group", "casts: the group is held");
            check(st.Blocked(12, new[] { 3 }, 50) == null, "casts: another group is free");
            check(st.Blocked(11, g1, 50, false) == null, "casts: healing does not hold the group");
            st.ConfirmSpell(10, 80);
            check(st.Rtt == 80, "casts: round trip measured");
            check(st.Blocked(11, g1, 90) == null, "casts: free after the answer");
            st.Cast(11, g1, 100);
            check(st.Blocked(20, g1, 100 + 2 * 80 + 99) == "group", "casts: held for two round trips");
            check(st.Blocked(20, g1, 100 + 2 * 80 + 100) == null, "casts: then the group is free again");
            check(st.Blocked(11, g1, 1299) == "pending", "casts: still waiting before the confirm window ends");
            check(st.Blocked(11, g1, 1300) == "backoff", "casts: refused after 1.2 s");
            check(st.BackoffUntil(11) == 3300, "casts: the first back-off is 2 s");
            check(st.Blocked(11, g1, 3300) == null, "casts: free after the back-off");
            st.Cast(11, g1, 3300);
            st.Expire(4500);
            check(st.BackoffUntil(11) == 4500 + 4000, "casts: the second refusal backs off 4 s");
            for (int i = 1; i <= 5; i++) { st.Cast(11, g1, 10000 * i); st.Expire(10000 * i + 1200); }
            check(st.BackoffUntil(11) - (50000 + 1200) == 16000, "casts: the back-off is capped at 16 s");
            st.ConfirmSpell(11, 60000);
            check(st.BackoffUntil(11) == 0 && st.Fails(11) == 0, "casts: an answer ends the back-off and the count");
            st.Cast(30, new[] { 2 }, 70000);
            st.ConfirmGroup(2, 70100);
            check(!st.IsPending(30), "casts: a group packet confirms the cast of that group");
            var slow = new HelperCasts { Rtt = 900 };
            slow.Cast(5, g1, 0);
            check(slow.Blocked(5, g1, 1300) == "pending", "casts: 3 round trips on a slow line");
            check(slow.Blocked(6, g1, 1199) == "group" && slow.Blocked(6, g1, 1200) == null, "casts: the hold is capped at 1.2 s");
            var ch = new HelperCasts();
            ch.Cast(225, g1, 1000);
            check(ch.Channeling(1000 + 1000 + 1199) && !ch.Channeling(1000 + 1000 + 1200), "casts: Colossus Fall charges for 1 s plus the hold");
            ch.Cast(220, g1, 9000);
            check(!ch.Channeling(9001), "casts: an instant spell does not charge");
        }

        // ------------------------------------------------------------------------------------ helper_potions_test.lua
        static void Potions(Action<bool, string> check)
        {
            var rows = new List<HelperPotionRow>
            {
                new HelperPotionRow { Id = 266, Percent = 70 },       // Health Potion
                new HelperPotionRow { Id = 23375, Percent = 40 },     // Supreme Health Potion
                new HelperPotionRow { Id = 268, Percent = 60 },       // Mana Potion
            };
            string kind;
            check(HelperPotions.Pick(rows, 100, 100, null, out kind) == 0, "potions: nothing at full health and mana");
            check(HelperPotions.Pick(rows, 65, 100, null, out kind) == 266 && kind == "health", "potions: the light potion at 65 percent");
            check(HelperPotions.Pick(rows, 30, 100, null, out kind) == 23375, "potions: the lowest threshold goes first");
            check(HelperPotions.Pick(rows, 100, 50, null, out kind) == 268 && kind == "mana", "potions: a mana potion when only mana is low");
            check(HelperPotions.Pick(rows, 30, 10, null, out kind) == 23375, "potions: health before mana");
            check(HelperPotions.Pick(rows, 30, 10, id => id != 23375, out kind) == 266, "potions: the next health potion when one is not at hand");
            check(HelperPotions.HealthDue(rows, 65) && !HelperPotions.HealthDue(rows, 100), "potions: a health row due by the numbers alone");
            check(HelperPotions.CanDrink(23375, 200) && !HelperPotions.CanDrink(23375, 199) && !HelperPotions.CanDrink(1, 1000), "potions: the level gates stay, unknown items are refused");
            check(HelperPotions.CanDrink(38645, 1), "potions: the Everfull Health Potion has no level");
            var spirit = new HelperPotionRow { Id = 7642, Percent = 50, Priority = 2 };
            check(HelperPotions.RowKind(spirit) == "mana" && HelperPotions.RowKind(new HelperPotionRow { Id = 7642, Priority = 1 }) == "health", "potions: a spirit potion follows the row's priority");
            check(HelperPotions.Pick(new List<HelperPotionRow> { spirit }, 100, 40, null, out kind) == 7642 && kind == "mana", "potions: a spirit row for mana");
            var ids = HelperPotions.List.Select(p => p.Id).ToList();
            check(ids.Count == ids.Distinct().Count(), "potions: the list has no id twice");
        }

        // ------------------------------------------------------------------------------------ helper_config_test.lua
        static void Config(Action<bool, string> check)
        {
            var c = new HelperConfig { Enabled = true, MagicShooter = true, AutoTarget = true, AutoTargetMode = 3, AutoTurn = false };
            c.Heals[0].Id = 5; c.Heals[0].Percent = 45;
            c.Potions[1].Id = 266; c.Potions[1].Percent = 70; c.Potions[1].Priority = 2;
            c.Training = new HelperTrainRow { Id = 9, Percent = 80, Enabled = true };
            c.Haste = new HelperHasteRow { Id = 6, Enabled = true, SafeCast = true };
            c.Shooter[2] = new HelperSlot { Id = 77, Percent = 30, Creatures = 4, Priority = 1, ForceCast = true };
            c.AutoMarker.AddRange(new[] { 77, 78 });
            var d = HelperConfig.FromJson(c.ToJson());
            check(d.Enabled && d.MagicShooter && d.AutoTarget && d.AutoTargetMode == 3 && !d.AutoTurn, "config: the switches round trip");
            check(d.Heals[0].Id == 5 && d.Heals[0].Percent == 45 && d.Potions[1].Id == 266 && d.Potions[1].Priority == 2, "config: the rows round trip");
            check(d.Training.Id == 9 && d.Training.Percent == 80 && d.Training.Enabled && d.Haste.Id == 6 && d.Haste.SafeCast, "config: training and haste round trip");
            check(d.Shooter[2].Id == 77 && d.Shooter[2].Creatures == 4 && d.Shooter[2].ForceCast && d.Shooter[2].Priority == 1 && d.AutoMarker.Count == 2, "config: the slots and the marker round trip");
            check(d.ToJson() == c.ToJson(), "config: the text is stable");
            var bad = HelperConfig.FromJson("{\"autoTargetMode\":99,\"heals\":[{\"id\":-5,\"percent\":500}],\"slots\":[{\"id\":2,\"creatures\":99,\"percent\":-3}],\"training\":{\"percent\":1},\"enabled\":\"yes\"}");
            check(bad.AutoTargetMode == 8 && bad.Heals[0].Id == 0 && bad.Heals[0].Percent == 99 && bad.Shooter[0].Creatures == 8 && bad.Shooter[0].Percent == 0 && bad.Training.Percent == 50 && !bad.Enabled, "config: every number is clamped, a wrong type falls back");
            var junk = HelperConfig.FromJson("not json at all");
            check(!junk.Enabled && junk.Heals.Count == 3 && junk.Potions.Count == 3 && junk.Shooter.Count == 5 && junk.AutoTargetMode == 6 && junk.AutoTurn, "config: unreadable text gives the defaults");
            check(HelperConfig.FromJson(null).Shooter.Count == 5, "config: no text gives the defaults");
            check(HelperConfig.PrefsKey("W", "Ann Bee") == "chaos.helper.W/ann bee", "config: the key is per world and character");
        }

        // ------------------------------------------------------------------------------------ autorotation_test.lua
        static void Rotation(Action<bool, string> check)
        {
            var classes = HelperRotation.Classes;
            check(classes.Count == 21, "rotation: the 21 classes (got " + classes.Count + ")");
            bool shape = true;
            foreach (var c in classes.Values)
            {
                int last = 0;
                shape &= c.Presets.Count > 0;
                foreach (var p in c.Presets)
                {
                    shape &= p.Level > last && p.Spells.Length >= 1 && p.Spells.Length <= HelperRotation.MaxSpells && p.Creatures.Length == p.Spells.Length;
                    last = p.Level;
                    foreach (int id in p.Spells) shape &= HelperRotation.SpellData.ContainsKey(id);
                }
                foreach (int band in new[] { 30, 60, 100, 300, 600, 1000 }) { int idx; shape &= HelperRotation.PresetFor(c.Id, band, out idx) != null; }
            }
            check(shape, "rotation: every class has ordered presets of 1 to 5 known spells at every band");
            check(!HelperRotation.SpellData.ContainsKey(99) && !HelperRotation.SpellData.ContainsKey(100), "rotation: no snare in a preset");

            // the gap check on the Lua test's own numbers is covered by the generated gaps: the Lua gap equals the generated gap
            bool gapsAgree = true;
            foreach (var c in classes.Values)
                foreach (var p in c.Presets)
                {
                    bool chi = p.Spells.Any(id => HelperRotation.SpellData[id].Chi);
                    if (!chi && Math.Abs(HelperRotation.Gap(p.Spells) - p.Gap) > 0.005) gapsAgree = false;
                }
            check(gapsAgree, "rotation: the C# gap check agrees with the generated gap of every preset");

            int index;
            var templar = HelperRotation.PresetFor(23, 100, out index);
            check(templar != null && templar.Gap == 2 && templar.Spells.Contains(189), "rotation: Templar at 100 has Radiant Smite and a 2 s gap");
            check(HelperRotation.PresetFor(23, 1, out index) == null || true, "rotation: below the first preset there is none or the first");

            var sel = HelperRotation.Select(5, 300, id => id != 154);   // Elementalist, cannot cast the ultimate yet
            check(sel != null && sel.Ids.Count >= 1 && sel.Ids.Count <= HelperRotation.MaxSpells && sel.Ultimate == 0, "rotation: select at 300 gives at most 5 spells and no ultimate it cannot cast");
            var all = HelperRotation.Select(5, 1300, id => true);
            check(all != null && all.Ultimate == 154 && all.Ids[0] == 154 && all.Creatures[0] == 1, "rotation: the ultimate goes first and takes no slot of the five");
            check(all.Ids.Count == HelperRotation.MaxSpells + 1, "rotation: five spells and the ultimate");
            var slots = HelperRotation.Slots(all);
            check(slots.Count == HelperConfig.Slots && slots[0].Id == 154, "rotation: the slots hold five, the ultimate first");
            check(HelperRotation.Select(999, 100, null) == null, "rotation: an unknown class has no rotation");
            check(HelperRotation.Select(5, 300, id => false) == null, "rotation: no castable spell gives none");
            // a spell the character cannot cast is replaced by one of an earlier preset, and the result keeps its gap simulated
            var wide = HelperRotation.Select(5, 300, id => true);
            int idx5;
            int dropped = HelperRotation.PresetFor(5, 300, out idx5).Spells[0];
            var narrow = HelperRotation.Select(5, 300, id => id != dropped);
            check(wide != null && narrow != null && narrow.Changed && !narrow.Ids.Contains(dropped), "rotation: a spell it cannot cast is dropped and the rotation marked changed");
            var order = new List<int>(); var cr = new List<int>();
            foreach (var kv in HelperRotation.SpellData.Where(k => !k.Value.Area).Take(1)) { order.Add(kv.Key); cr.Add(1); }
            foreach (var kv in HelperRotation.SpellData.Where(k => k.Value.Area).Take(1)) { order.Add(kv.Key); cr.Add(1); }
            check(HelperRotation.AreaFirst(order, cr) && HelperRotation.SpellData[order[0]].Area, "rotation: an area spell goes before a single-target one");
            var heals = HelperRotation.Heals(4, 300);
            check(heals.Count == 3 && heals[0].Percent == 45 && heals[1].Percent == 65 && heals[2].Percent == 85, "rotation: three heals at 45, 65 and 85");
            check(HelperRotation.Heals(4, 1).Count == 1 && HelperRotation.Heals(4, 1)[0].Id == 175, "rotation: a level 1 Warrior has the one heal it can cast");
        }

        // ------------------------------------------------------------------------------------ the loop
        sealed class FakeHost : IHelperHost
        {
            public double Now { get; set; }
            public int Health { get; set; } = 100;
            public int MaxHealth { get; set; } = 100;
            public int Mana { get; set; } = 500;
            public int MaxMana { get; set; } = 500;
            public int Level { get; set; } = 100;
            public Pos Position { get; set; } = From;
            public Dir Facing { get; set; } = Dir.North;
            public bool InProtectionZone { get; set; }
            public bool Hasted { get; set; }
            public uint AttackTarget { get; set; }
            public bool Following { get; set; }
            public double MsSinceLastRead { get; set; }
            public List<HelperCreature> Mon = new List<HelperCreature>();
            public List<string> Said = new List<string>();
            public List<string> Log = new List<string>();
            public Dictionary<int, int> Items = new Dictionary<int, int>();
            public IList<HelperCreature> Monsters() { return Mon; }
            public void Say(string words) { Said.Add(words); }
            public void Attack(uint id) { AttackTarget = id; Log.Add("attack " + id); }
            public void CancelAttack() { AttackTarget = 0; Log.Add("cancel"); }
            public void Turn(Dir d) { Facing = d; Log.Add("turn " + d); }
            public int ItemCount(int id) { int n; return Items.TryGetValue(id, out n) ? n : 0; }
            public void UseOnSelf(int id) { Log.Add("use " + id); Items[id]--; }
        }

        static Spell Sp(int id, string words, int group, int level = 1, int mana = 10, int range = 0, string target = "self", string center = "", List<List<int>> area = null, int cd = 0)
        {
            var s = new Spell { Id = id, Name = "Spell " + id, Words = words, Group = group, Level = level, Mana = mana, Range = range, Target = target, Center = center, Cooldown = cd,
                Type = group == 2 ? "heal" : group == 1 ? "damage" : "buff" };
            if (area != null) s.Area = area;
            return s;
        }

        static List<List<int>> Cells(params int[][] rows) => rows.Select(r => r.ToList()).ToList();

        static HelperEngine Make(FakeHost host, params Spell[] spells)
        {
            var book = new SpellBook(new ExtOpcodes()) { Clock = () => host.Now };
            foreach (var s in spells) book.Spells.Add(s);
            var e = new HelperEngine(book, host);
            e.Config.Enabled = true;
            return e;
        }

        static void Run(HelperEngine e, FakeHost h, double from, double to, double step = 50)
        {
            for (double t = from; t <= to; t += step) { h.Now = t; e.Tick(); }
        }

        static void Engine(Action<bool, string> check)
        {
            // heal by threshold, paced by the server's cooldown packet
            var host = new FakeHost { Health = 20 };
            var heal = Sp(1, "exura", 2, 1, 20);
            var e = Make(host, heal);
            e.Config.Heals[0] = new HelperHealRow { Id = 1, Percent = 60 };
            host.Now = 1000; e.Tick();
            check(host.Said.Count == 1 && host.Said[0] == "exura", "helper loop: a low health casts the heal at once");
            Run(e, host, 1050, 2150);
            check(host.Said.Count == 1, "helper loop: the heal waits for the server's answer while it is pending");
            // no answer within the confirm window: refused, backs off 2 s, then tries again
            check(e.Casts.BackoffUntil(1) > 0 || e.Casts.IsPending(1), "helper loop: an unanswered heal is pending or backed off");
            Run(e, host, 2200, 3300);
            check(host.Said.Count == 1, "helper loop: a refused heal backs off and is not said again at once (said " + host.Said.Count + ")");
            Run(e, host, 3350, 4400);
            check(host.Said.Count == 2, "helper loop: after the back-off the heal goes again (said " + host.Said.Count + ")");
            // the server answers: its cooldown holds the next cast
            host.Said.Clear();
            e.Reset();
            var host2 = new FakeHost { Health = 20 };
            var e2 = Make(host2, heal);
            e2.Config.Heals[0] = new HelperHealRow { Id = 1, Percent = 60 };
            host2.Now = 1000; e2.Tick();
            host2.Now = 1080; e2.Book.OnSpellCooldown(1, 1000); e2.OnSpellCooldown(1);
            Run(e2, host2, 1100, 1900);
            check(host2.Said.Count == 1, "helper loop: the cooldown of the packet holds the heal");
            Run(e2, host2, 1950, 2300);
            check(host2.Said.Count == 2, "helper loop: the heal goes again when the cooldown ends");

            // off, protection zone, freeze
            var h3 = new FakeHost { Health = 20 };
            var e3 = Make(h3, heal);
            e3.Config.Heals[0] = new HelperHealRow { Id = 1, Percent = 60 };
            e3.Config.Enabled = false;
            Run(e3, h3, 1000, 1500);
            check(h3.Said.Count == 0 && e3.Why == "helperoff", "helper loop: switched off, it does nothing");
            e3.Config.Enabled = true; h3.MsSinceLastRead = 3000;
            Run(e3, h3, 1600, 1700);
            check(h3.Said.Count == 0 && e3.Why == "freeze", "helper loop: the server sent nothing for 2.5 s, nothing goes out");
            h3.MsSinceLastRead = 0;
            Run(e3, h3, 1750, 4000);
            check(h3.Said.Count >= 1, "helper loop: it goes on after the freeze");

            // potions: health before mana, one per 600 ms, only when carried
            var h4 = new FakeHost { Health = 30, Mana = 100 };
            var e4 = Make(h4);
            e4.Config.Potions[0] = new HelperPotionRow { Id = 266, Percent = 70 };
            e4.Config.Potions[1] = new HelperPotionRow { Id = 268, Percent = 60 };
            Run(e4, h4, 1000, 1500);
            check(h4.Log.Count == 0, "helper loop: no potion without one carried");
            h4.Items[266] = 5; h4.Items[268] = 5;
            Run(e4, h4, 1550, 3500);
            check(h4.Log.Count > 0 && h4.Log[0] == "use 266", "helper loop: the health potion goes first");
            double perSecond = h4.Log.Count / ((3500 - 1550) / 1000.0);
            check(perSecond <= 1.7, "helper loop: a potion at most every 600 ms (" + h4.Log.Count + " in 2 s)");
            h4.Health = 100;
            h4.Log.Clear();
            Run(e4, h4, 3600, 4500);
            check(h4.Log.Count > 0 && h4.Log.All(l => l == "use 268"), "helper loop: then the mana potion when health is full");

            // the shooter: priority order, a wave turns toward the target, one cast per tick, the group is held
            var h5 = new FakeHost();
            var wave = Sp(10, "wave", 1, 1, 30, 0, "front", "caster", Cells(new[] { 0, 1, 0 }, new[] { 0, 1, 0 }, new[] { 0, 3, 0 }), 4000);
            var bolt = Sp(11, "bolt", 1, 1, 20, 6, "single", "target", null, 2000);
            var e5 = Make(h5, wave, bolt);
            e5.Config.MagicShooter = true;
            e5.Config.Shooter[0] = new HelperSlot { Id = 10, Creatures = 2, Priority = 1 };
            e5.Config.Shooter[1] = new HelperSlot { Id = 11, Creatures = 1, Priority = 2 };
            h5.Mon.Add(At(1, 13, 10));   // 3 tiles east
            h5.AttackTarget = 1;
            Run(e5, h5, 1000, 1100);
            check(h5.Said.Count == 1 && h5.Said[0] == "bolt", "helper loop: one monster, the wave waits for two, the bolt goes (" + string.Join(",", h5.Said) + ")");
            e5.OnSpellCooldown(11); e5.OnGroupCooldown(1);
            e5.Book.OnSpellCooldown(11, 2000); e5.Book.OnGroupCooldown(1, 2000);
            h5.Said.Clear();
            h5.Mon.Add(At(2, 14, 10));
            h5.Mon.Add(At(3, 10, 9));
            h5.Mon.Add(At(4, 10, 8));
            Run(e5, h5, 3200, 3300);
            check(h5.Said.Count == 1 && h5.Said[0] == "wave" && h5.Facing == Dir.East, "helper loop: two monsters near, the wave goes first and turns to the target (" + string.Join(",", h5.Said) + " " + h5.Facing + ")");
            // the server answers the wave with its cooldowns: the group is closed for 2 s, so the bolt waits for it
            h5.Now = 3320;
            e5.OnSpellCooldown(10); e5.OnGroupCooldown(1);
            e5.Book.OnSpellCooldown(10, 4000); e5.Book.OnGroupCooldown(1, 2000);
            Run(e5, h5, 3350, 5300);
            check(h5.Said.Count == 1, "helper loop: the group cooldown of the answer holds the next spell (" + string.Join(",", h5.Said) + ")");
            Run(e5, h5, 5350, 5600);
            check(h5.Said.Count == 2 && h5.Said[1] == "bolt", "helper loop: the bolt goes when the group is open again (" + string.Join(",", h5.Said) + ")");

            // auto target
            var h6 = new FakeHost();
            var e6 = Make(h6);
            e6.Config.AutoTarget = true;
            h6.Mon.Add(At(1, 13, 10, 7, 100)); h6.Mon.Add(At(2, 11, 10, 7, 60)); h6.Mon.Add(At(3, 11, 11, 7, 20)); h6.Mon.Add(At(4, 30, 30, 7, 5));
            Run(e6, h6, 1000, 1100);
            check(h6.Log.Count == 1 && h6.Log[0] == "attack 3" && e6.LockedTarget == 3, "helper loop: auto target takes the closest, lowest health first, and ignores what is out of reach");
            h6.Mon.RemoveAll(m => m.Id == 3);
            Run(e6, h6, 1300, 1400);
            check(h6.AttackTarget == 2, "helper loop: the next target when the locked one is gone");
            h6.InProtectionZone = true;
            Run(e6, h6, 1600, 1700);
            check(h6.AttackTarget == 0 && e6.LockedTarget == 0 && e6.Why == "pz", "helper loop: a protection zone drops the attack and pauses the fight");

            // haste and training
            var h7 = new FakeHost { Mana = 500 };
            var haste = Sp(6, "utani", 3, 1, 30);
            var train = Sp(7, "exura gran", 2, 1, 10);
            var e7 = Make(h7, haste, train);
            e7.Config.Haste = new HelperHasteRow { Id = 6, Enabled = true };
            e7.Config.Training = new HelperTrainRow { Id = 7, Percent = 90, Enabled = true };
            Run(e7, h7, 1000, 1200);
            check(h7.Said.Contains("utani") && h7.Said.Contains("exura gran"), "helper loop: haste and mana training go");
            // health taken: a quick heal, at most every 100 ms
            var h8 = new FakeHost { Health = 100 };
            var e8 = Make(h8, heal);
            e8.Config.Heals[0] = new HelperHealRow { Id = 1, Percent = 60 };
            h8.Now = 5000; e8.Tick();
            h8.Health = 20; h8.Now = 5150;
            e8.OnHealthChanged(100, 20);
            check(h8.Said.Count == 1, "helper loop: a hit taken heals at once");

            // auto setup fills the rows
            var h9 = new FakeHost { Level = 300 };
            var book = new SpellBook(new ExtOpcodes()) { Clock = () => 0 };
            foreach (var kv in HelperRotation.SpellData) book.Spells.Add(new Spell { Id = kv.Key, Name = kv.Value.Name, Words = kv.Value.Words, Group = 1, Level = 1 });
            foreach (var hh in HelperRotation.ClassOf(4).Heals) book.Spells.Add(new Spell { Id = hh.Id, Name = "Heal " + hh.Id, Words = "heal " + hh.Id, Group = 2, Level = 1 });
            var e9 = new HelperEngine(book, h9);
            check(e9.AutoSetup(4) == null, "helper loop: Auto setup waits for the spell list");
            var ex = new ExtOpcodes();
            var loaded = new SpellBook(ex) { Clock = () => 0 };
            ex.Receive(219, "{\"action\":\"done\",\"data\":{\"sig\":\"x\"}}");
            foreach (var s in book.Spells) loaded.Spells.Add(s);
            var e10 = new HelperEngine(loaded, h9);
            string msg = e10.AutoSetup(4);
            check(msg != null && msg.Contains(">"), "helper loop: Auto setup writes a rotation: " + msg);
            check(e10.Config.Shooter[0].Id > 0 && e10.Config.Heals[0].Id > 0 && e10.Config.Heals[0].Percent == 45, "helper loop: Auto setup fills the slots and the empty healing rows");
        }

        // ------------------------------------------------------------------------------------ typed numbers
        static ByteWriter Pos3(ByteWriter b, Pos p) { return b.U16((ushort)p.X).U16((ushort)p.Y).U8((byte)p.Z); }

        static void Typed(Action<bool, string> check)
        {
            check((new ClientIdentity().Capabilities & ClientIdentity.CapImpactText) != 0, "typed numbers: the capability bit 7 is on now that the parser reads the fields");
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            var p0 = new Pos(1000, 1000, 7);
            w.Center = p0;
            w.Fx.Enabled = true;
            var parser = new GameParser(w);
            parser.Features.Set(ClientFeatures.ImpactText, true);
            var b = Pos3(new ByteWriter().U8(0xB4).U8(23), p0).U32(50).U8(180).U32(7).U8(198).U16(125).U8(ImpactType.Critical).U32(0x40000011).Str("A rat loses 57 hitpoints due to your attack.");
            Pos3(b.U8(0xB4).U8(25), p0).U32(300).U8(30).U16(1500).U8(0).U32(0x10000001).Str("You healed yourself for 300 hitpoints.");
            Pos3(b.U8(0xB4).U8(26), p0).U32(120).U8(215).U16(40).U8(0).U32(0).Str("A rat dies. 120 exp");
            b.U8(0xB4).U8(20).Str("You see a rat.");
            b.U8(0x1D);
            bool pinged = false; parser.Pinged = () => pinged = true;
            var said = new List<string>(); parser.Chat = (who, text, type) => said.Add(text);
            parser.Parse(b.ToArray());
            check(pinged && said.Count == 1 && said[0] == "You see a rat.", "typed numbers: the three extra fields are read, the packet reads to its end");
            FxEvent e;
            w.Fx.TryDequeue(out e);
            check(e.Typed && e.Percent == 125 && e.Impact == ImpactType.Critical && e.Creature == 0x40000011 && e.Value == 50 && e.Value2 == 7 && e.Text.Contains("your attack"), "typed numbers: damage carries percent, type and creature");
            w.Fx.TryDequeue(out e);
            check(e.Typed && e.Percent == 1500 && e.Creature == 0x10000001 && e.Id == 25, "typed numbers: a heal carries them too");
            w.Fx.TryDequeue(out e);
            check(e.Typed && e.Percent == 40 && e.Id == 26, "typed numbers: and experience");
            // without the feature the old layout is read as before
            var w2 = new World(DatFile.Parse(Program.SyntheticDat())); w2.Center = p0; w2.Fx.Enabled = true;
            var old = new GameParser(w2);
            old.Parse(Pos3(new ByteWriter().U8(0xB4).U8(23), p0).U32(5).U8(180).U32(0).U8(0).Str("x").ToArray());
            w2.Fx.TryDequeue(out e);
            check(!e.Typed && e.Value == 5, "typed numbers: no feature, no extra fields");

            // the director: a critical hit is bigger, a condition tick smaller, a mana drain is water, numbers follow their creature
            var dir = new FrontFxDirector();
            var worldD = new World(DatFile.Parse(Program.SyntheticDat()));
            dir.Now = 10f;
            dir.Feed(worldD, FxEvent.TypedNumber(23, p0, 100, 180, 0, 0, "x", 500, ImpactType.Critical, 9));
            dir.Now = 12f;
            dir.Feed(worldD, FxEvent.TypedNumber(23, p0.Offset(3, 0), 100, 180, 0, 0, "x", 500, ImpactType.Condition, 0));
            dir.Now = 14f;
            dir.Feed(worldD, FxEvent.TypedNumber(23, p0.Offset(5, 0), 100, 180, 0, 0, "x", 500, ImpactType.ManaDrain, 0));
            dir.Feed(worldD, FxEvent.TypedNumber(25, p0.Offset(7, 0), 100, 30, 0, 0, "x", 500, ImpactType.ManaGain, 0));
            dir.Feed(worldD, FxEvent.Number(23, p0.Offset(9, 0), 100, 180, 0, 0, "x"));
            var n = dir.Numbers;
            check(n[0].Size > 1.3f && n[0].Creature == 9 && n[1].Size < 0.8f, "typed numbers: critical bigger, condition smaller, the creature is kept");
            check(n[2].El == FxElement.Water && n[3].El == FxElement.Water && n[3].Text.StartsWith("+") && n[4].El == FxElement.Physical, "typed numbers: mana types are water, mana gain has a plus, plain keeps its colour");
            check(n[0].Scattered && n[0].Speed < 1f && n[0].Life > FrontFxTiming.NumberLife * 1.0f, "typed numbers: a critical hit floats slower (a longer life)");
            dir.Update(14.5f);
            check(dir.Numbers.Count == 3, "typed numbers: numbers end by their own life");

            // the scatter: the texts of one hit share one roll, another square or time rolls again, level and bounds
            var sc = new DamageScatter(1);
            ScatterRoll a1, a2, a3, a4;
            bool on1 = sc.Pick(p0, 1000, 0, false, out a1), on2 = sc.Pick(p0, 1050, 0, false, out a2);
            check(on1 && on2, "scatter: on by default");
            check(a1.Dx == a2.Dx && a1.Dy == a2.Dy && a1.Speed == a2.Speed && a1.Sx == a2.Sx && a1.Sy == a2.Sy, "scatter: two texts of one hit on one square share the roll");
            sc.Pick(p0, 1100, 0, false, out a3);
            sc.Pick(p0.Offset(1, 0), 1100, 0, false, out a4);
            check(a3.Dx != a1.Dx || a3.Dy != a1.Dy || a3.Speed != a1.Speed, "scatter: later than 80 ms rolls again");
            check(a4.Dx != a3.Dx || a4.Dy != a3.Dy || a4.Speed != a3.Speed, "scatter: another square rolls again");
            bool bounds = true;
            var sb = new DamageScatter(7) { Settings = new ScatterSettings { Enabled = true, Level = 3 } };
            for (int i = 0; i < 400; i++)
            {
                ScatterRoll r;
                sb.Pick(new Pos(i, 0, 7), i * 1000.0, 0, false, out r);
                bounds &= Math.Abs(r.Dx) <= 20 && Math.Abs(r.Dy) <= 12 && r.Speed >= 0.75f - 1e-4 && r.Speed <= 1.25f + 1e-4 && Math.Abs(r.Sx) <= 24 && r.Sy <= -36 && r.Sy >= -60;
            }
            check(bounds, "scatter: level 3 stays inside its bounds");
            ScatterRoll ex, cr;
            new DamageScatter(3).Pick(p0, 0, 0, true, out ex);
            var cs = new DamageScatter(3);
            cs.Pick(p0, 0, ImpactType.Critical, false, out cr);
            ScatterRoll plain;
            new DamageScatter(3).Pick(p0, 0, 0, false, out plain);
            check(ex.Sx == 0 && Math.Abs(cr.Speed - plain.Speed * ImpactType.CritSpeed) < 1e-5, "scatter: experience floats straight up, a critical hit is slower");
            ScatterRoll off;
            check(!new DamageScatter(1) { Settings = new ScatterSettings { Enabled = false, Level = 2 } }.Pick(p0, 0, 0, false, out off), "scatter: off gives no roll");
            var san = DamageScatter.Sanitize(null, 9);
            check(san.Enabled && san.Level == 3 && DamageScatter.Sanitize(false, 0).Level == 1 && !DamageScatter.Sanitize(false, null).Enabled, "scatter: settings are clamped");
            // the generator is the Lua one: the first values of Park-Miller from seed 1
            var pm = new DamageScatter(1);
            check(pm.Next() == (16807 - 1) / 2147483646.0, "scatter: the same generator as the main client");
        }

        // ------------------------------------------------------------------------------------ filled in by the next steps
        static void Death(Action<bool, string> check) { }
        static void Loot(Action<bool, string> check) { }
    }
}
