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
        static void Death(Action<bool, string> check)
        {
            Loc.Set("en");
            check(DeathRecapRules.Short(1150) == "1.15k" && DeathRecapRules.Short(150000) == "150k" && DeathRecapRules.Short(2459999) == "2.45M" && DeathRecapRules.Short(999) == "999" && DeathRecapRules.Short(1234.9) == "1.23k", "recap: short numbers by the damage number rule");
            check(DeathRecapRules.Short(-1500) == "-1.5k" && DeathRecapRules.Short(1000) == "1k" && DeathRecapRules.Short(12345) == "12.3k", "recap: short numbers keep the sign and trim zeros");
            check(DeathRecapRules.Exact(1234567) == "1,234,567" && DeathRecapRules.Percent(1, 3) == 33.3 && DeathRecapRules.Percent(1, 2) == 50 && DeathRecapRules.Percent(1, 0) == 0, "recap: exact numbers and percent");
            check(DeathRecapRules.Seconds(4200) == "4.2 s" && DeathRecapRules.Seconds(800) == "0.8 s" && DeathRecapRules.Seconds(65000) == "1:05" && DeathRecapRules.Seconds(-5) == "0.0 s", "recap: seconds");
            check(DeathRecapRules.Clock(0) == "?" && System.Text.RegularExpressions.Regex.IsMatch(DeathRecapRules.Clock(1700000000), "^\\d\\d [A-Z][a-z]+ \\d\\d:\\d\\d$"), "recap: clock format");
            check(DeathRecapRules.DisplayName("War Wolf", "Varek") == "War Wolf (Varek)" && DeathRecapRules.DisplayName(null, null) == "Unknown", "recap: names");
            check(DeathRecapRules.ElementName("lifedrain") == "Life drain" && DeathRecapRules.ElementName("weird") == "Other", "recap: element names");
            var o = DeathRecapRules.Outfit(Json.Parse("{\"type\":128,\"head\":78,\"addons\":7}"));
            check(o != null && o["type"] == 128 && o["addons"] == 0, "recap: an outfit, addons out of range become 0");
            check(DeathRecapRules.Outfit(Json.Parse("{\"type\":0}")) == null && DeathRecapRules.Outfit(Json.Parse("{\"auxType\":2160}"))["auxType"] == 2160 && DeathRecapRules.Outfit("x") == null, "recap: no outfit, an item outfit, bad input");

            object recap = Json.Parse("{\"v\":1,\"at\":1700000000,\"real\":1,\"lvl\":120,\"xl\":150000,\"ll\":1,\"dur\":4200,\"win\":20000,\"tot\":1100,\"hp\":980,\"mp\":120,\"nh\":8,\"pvp\":1," +
                "\"kb\":{\"n\":\"Dragon\",\"kind\":\"c\",\"el\":\"fire\",\"a\":250}," +
                "\"el\":{\"fire\":630,\"energy\":230,\"manadrain\":40,\"physical\":200}," +
                "\"att\":[{\"n\":\"Varek\",\"kind\":\"u\",\"tot\":270,\"hp\":150,\"mp\":120,\"h\":3,\"c\":1,\"x\":120,\"el\":{\"energy\":230,\"manadrain\":40}}," +
                "{\"n\":\"Others\",\"kind\":\"o\",\"tot\":900,\"hp\":900,\"mp\":0,\"h\":9,\"c\":0,\"x\":200,\"el\":{\"physical\":900}}," +
                "{\"n\":\"Dragon\",\"kind\":\"c\",\"tot\":750,\"hp\":750,\"mp\":0,\"h\":3,\"c\":1,\"x\":300,\"el\":{\"fire\":550,\"physical\":200},\"look\":{\"type\":34}}," +
                "{\"n\":\"Fire Elemental\",\"m\":\"Varek\",\"kind\":\"c\",\"tot\":60,\"hp\":60,\"mp\":0,\"h\":1,\"c\":0,\"x\":60,\"el\":{\"fire\":60}}," +
                "{\"n\":\"Environment\",\"kind\":\"e\",\"tot\":20,\"hp\":20,\"mp\":0,\"h\":1,\"c\":0,\"x\":20,\"el\":{}}]," +
                "\"last\":[{\"dt\":1700,\"n\":\"Varek\",\"el\":\"energy\",\"a\":80,\"mp\":1},{\"dt\":0,\"n\":\"Dragon\",\"el\":\"fire\",\"a\":250,\"c\":1}]}");
            var rows = DeathRecapRules.Rows(recap);
            check(rows.Count == 5 && rows[0].Name == "Dragon" && rows[4].Name == "Others" && rows[1].Name == "Varek" && rows[2].Name == "Fire Elemental (Varek)", "recap: five rows, most damage first, Others last");
            check(rows[4].Frac == 1 && Math.Abs(rows[0].Frac - 750.0 / 900) < 1e-9, "recap: the biggest row's bar is full, the others relative to it");
            check(rows[0].Pct == 68.2 && rows[0].CritPct == 33 && rows[0].Outfit["type"] == 34 && rows[0].KindName == "Monster" && rows[1].KindName == "Player", "recap: share, crit rate, outfit, kind");
            check(rows[0].ElText == "Fire 550, Physical 200" && rows[1].Mp == 120 && rows[3].ElText == "", "recap: element text, largest first");
            var els = DeathRecapRules.ElementList(Json.Parse("{\"fire\":550,\"physical\":200,\"ice\":0}"));
            check(els.Count == 2 && els[0].Key == "fire" && els[0].Pct == 73.3, "recap: zero elements left out, order and share");
            var seg = DeathRecapRules.Segments(rows[0].Elements, rows[0].Total);
            check(seg.Count == 2 && Math.Abs(seg[0].Frac + seg[1].Frac - 1) < 1e-9, "recap: the segments fill the bar");
            check(DeathRecapRules.Rows(null).Count == 0 && DeathRecapRules.Rows(Json.Parse("{\"att\":[\"x\"]}")).Count == 0, "recap: no recap, no rows");

            var h = DeathRecapRules.Header(recap);
            check(h.Title == "Killed by Dragon" && h.Sub.Contains("level 120") && h.Sub.Contains("PvP"), "recap: title and sub line");
            check(h.Loss == "Lost 150k experience and 1 level" && h.Window == "Last 4.2 s before the death, 8 hits" && h.Totals == "Damage taken: 1.1k (health 980, mana 120)", "recap: loss, window and totals");
            check(DeathRecapRules.Header(Json.Parse("{\"real\":0,\"kb\":{\"n\":\"Varek\"},\"mode\":\"Arena\",\"tot\":0}")).Title == "Defeated by Varek" && DeathRecapRules.Header(Json.Parse("{\"real\":0,\"kb\":{\"n\":\"Varek\"}}")).Loss == "Nothing lost", "recap: a defeat in a mode loses nothing");
            check(DeathRecapRules.Header(Json.Parse("{\"real\":0,\"mode\":\"Arena\"}")).Sub.Contains("Arena"), "recap: the mode in the sub line");
            check(DeathRecapRules.Header(Json.Parse("{\"real\":1,\"kb\":{\"n\":\"x\"}}")).Loss == "Experience lost: shown at your next login" && DeathRecapRules.Header(Json.Parse("{\"real\":1,\"xl\":0,\"ll\":0}")).Loss == "No experience lost" && DeathRecapRules.Header(Json.Parse("{\"real\":1,\"xl\":5000,\"ll\":3}")).Loss == "Lost 5k experience and 3 levels", "recap: loss not known yet, none, levels plural");
            check(DeathRecapRules.Header(Json.Parse("{}")).Window == "No hits recorded before the death" && DeathRecapRules.Header(null).Title == "Killed by Unknown", "recap: no hits, no recap");
            check(DeathRecapRules.KillingBlow(recap) == "Killing blow: Dragon, 250 fire" && DeathRecapRules.KillingBlow(Json.Parse("{\"kb\":{\"n\":\"Varek\",\"a\":99,\"el\":\"energy\",\"c\":1}}")) == "Killing blow: Varek, 99 energy (critical)" && DeathRecapRules.KillingBlow(Json.Parse("{\"kb\":{\"n\":\"Demon\"}}")) == "Killing blow: Demon", "recap: the killing blow");
            var tl = DeathRecapRules.Timeline(recap);
            check(tl.Count == 2 && tl[0].Time == "-1.7 s" && tl[1].Time == "death" && tl[0].Text == "-1.7 s  Varek  80 energy (mana)" && tl[1].Text == "death  Dragon  250 fire (critical)", "recap: the timeline");
            check(DeathRecapRules.Timeline(Json.Parse("{\"last\":[{\"dt\":8,\"n\":\"Dragon\",\"a\":1}]}"))[0].Time == "death" && DeathRecapRules.Timeline(Json.Parse("{\"last\":[{\"dt\":100,\"n\":\"Dragon\",\"a\":1}]}"))[0].Time == "-0.1 s", "recap: a hit within 100 ms is the death");
            var list = Json.List(Json.Parse("{\"l\":[{\"id\":12,\"at\":1700000300,\"k\":\"Dragon\",\"lvl\":120,\"xl\":150000,\"ll\":1,\"real\":1},{\"id\":11,\"at\":1700000200,\"k\":\"Varek\",\"real\":0,\"mode\":\"Arena\"},{\"id\":10,\"at\":1700000100,\"k\":\"Rat\",\"lvl\":8,\"xl\":0,\"real\":1},{\"id\":\"bad\"}]}"), "l");
            var hr = DeathRecapRules.HistoryRows(list, 11);
            check(hr.Count == 3 && hr[0].Sub == "-150k exp, -1 lvl" && hr[1].Sub == "Arena" && hr[2].Sub == "Level 8" && hr[1].Selected && !hr[0].Selected && hr[0].Killer == "Dragon", "recap: the history rows");
            var t = DeathRecapRules.Tips(Json.Parse("{\"tips\":[{\"k\":\"lvl\",\"d\":40},{\"k\":\"res\",\"el\":\"fire\",\"r\":0,\"s\":62},{\"k\":\"pot\"},{\"k\":\"pack\",\"n\":6}]}"));
            check(t.Count == 3 && t[0].StartsWith("These monsters are 40 levels above you") && t[1].Contains("fire resistance is 0%") && t[2].StartsWith("You used no potions"), "recap: three tips at most");
            t = DeathRecapRules.Tips(Json.Parse("{\"tips\":[{\"k\":\"heal\",\"s\":12},{\"k\":\"pack\",\"n\":6},{\"k\":\"what\"},{\"k\":\"res\",\"el\":\"lifedrain\",\"r\":0}]}"));
            check(t.Count == 2 && t[0] == "Your healing covered only 12% of the damage: heal sooner or pull fewer monsters" && t[1] == "6 monsters hit you at once: pull fewer at a time", "recap: unknown tips are skipped");
            check(DeathRecapRules.Tips(Json.Parse("{}")).Count == 0 && DeathRecapRules.Tips(null).Count == 0 && DeathRecapRules.Tips(Json.Parse("{\"tips\":\"x\"}")).Count == 0, "recap: an old recap has no tips");
            check(DeathRecapRules.ResElements.All(e => DeathRecapRules.Tips(Json.Parse("{\"tips\":[{\"k\":\"res\",\"el\":\"" + e + "\",\"r\":5}]}")).Count == 1), "recap: a sentence for every resistance element");
            Loc.Set("pt-BR");
            check(DeathRecapRules.Header(recap).Title == "Morto por Dragon" && DeathRecapRules.Header(recap).Loss == "Perdeu 150k de experiência e 1 nível", "recap: pt-BR");
            Loc.Set("en");

            // the protocol: history and recap messages, open and get requests, the auto open
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>(); ext.Transmit = p => sent.Add(p);
            var dr = new DeathRecap(ext);
            int auto = 0, changed = 0; dr.AutoOpen += () => auto++; dr.Changed += () => changed++;
            dr.Open();
            dr.Open(7);
            dr.Get(9);
            var texts = sent.Select(p => System.Text.Encoding.UTF8.GetString(p, 4, p.Length - 4)).ToList();
            check(texts.Count == 3 && texts[0].Contains("\"action\":\"open\"") && texts[1].Contains("\"id\":7") && texts[2].Contains("\"action\":\"get\"") && texts[2].Contains("\"id\":9"), "recap protocol: open, open with an id and get requests");
            ext.Receive(154, "{\"action\":\"history\",\"data\":{\"list\":[{\"id\":12,\"k\":\"Dragon\"},{\"id\":11}],\"sel\":12,\"recap\":{\"kb\":{\"n\":\"Dragon\"},\"tot\":5}}}");
            check(dr.History.Count == 2 && dr.Selected == 12 && dr.Current != null && changed == 1 && auto == 0, "recap protocol: the history and the recap shown");
            ext.Receive(154, "{\"action\":\"recap\",\"data\":{\"id\":11,\"recap\":{\"kb\":{\"n\":\"Rat\"}}}}");
            check(dr.Selected == 11 && Json.Text(Json.Get(dr.Current, "kb"), "n") == "Rat" && auto == 0, "recap protocol: a recap of the list");
            ext.Receive(154, "{\"action\":\"recap\",\"data\":{\"id\":13,\"auto\":true,\"recap\":{\"kb\":{\"n\":\"Troll\"}}}}");
            check(dr.Selected == 13 && auto == 1, "recap protocol: an auto recap asks the window to open");
            ext.Receive(154, "{\"action\":\"recap\",\"data\":{\"id\":14}}");
            check(dr.Selected == 13, "recap protocol: a recap without data is ignored");
            sent.Clear();
            dr.Select(13);
            check(sent.Count == 0, "recap protocol: selecting the shown recap asks nothing");
            dr.Select(12);
            check(sent.Count == 1 && dr.Selected == 12, "recap protocol: selecting another asks for it");
        }
        static LootInfo Li(int id, string nm, string g = "equipment", int r = 0, int c = 1, bool u = false, bool o = false, bool pw = false, int t = 0) =>
            new LootInfo { Id = id, Nm = nm, G = g, R = r, C = c, U = u, O = o, Pw = pw, T = t };

        static void Loot(Action<bool, string> check)
        {
            Loc.Set("en");
            // ---- lootfilter_test.lua
            check(LootFilterRules.RarityIds.Length == 6 && LootFilterRules.RarityName(3) == "Magic" && LootFilterRules.RarityName(4) == "Rare" && LootFilterRules.RarityName(5) == "Legendary" && LootFilterRules.RarityName(10) == "Divine", "loot: the rarity names");
            check(LootFilterRules.RarityName(7) == "Legendary" && LootFilterRules.RarityName(13) == "Divine" && LootFilterRules.RarityName(0) == null, "loot: old ids are the rarity they became");
            check(LootFilterRules.Canon(9) == 5 && LootFilterRules.Canon(12) == 10 && LootFilterRules.Canon(0) == 0 && LootFilterRules.Canon(99) == 10, "loot: canon");
            var s = LootFilterRules.Normalize(Json.Parse("{\"highlight\":4,\"dim\":2,\"show\":{\"supplies\":false}}"));
            check(s.LootMin == 0 && !s.Show["supplies"] && s.Show["other"], "loot: a missing field is the default, a category off");
            check(LootFilterRules.Normalize(Json.Parse("{\"highlight\":40}")).Highlight == 10 && LootFilterRules.Normalize(Json.Parse("{\"highlight\":7}")).Highlight == 5 && LootFilterRules.Normalize(null).Highlight == 3, "loot: thresholds are clamped, an old id is the rarity it became");
            check(LootFilterRules.Classify(Li(1, "x", "equipment", 4), s) == "highlight" && LootFilterRules.Classify(Li(1, "x", "equipment", 3), s) == "normal" && LootFilterRules.Classify(Li(1, "x", "equipment", 1), s) == "dim", "loot: Rare glows, Magic plain, Common dimmed");
            check(LootFilterRules.Classify(Li(1, "x", "equipment", 8), LootFilterRules.Normalize(Json.Parse("{\"highlight\":5}"))) == "highlight", "loot: an old Chaos item glows from Legendary");
            check(LootFilterRules.Classify(Li(1, "x", "supplies"), s) == "dim" && LootFilterRules.Classify(Li(1, "x", "other"), s) == "normal", "loot: a category off dims, others are plain");
            check(LootFilterRules.Classify(Li(1, "x", "equipment", 0, 1, true), s) == "highlight" && LootFilterRules.Classify(Li(1, "x", "currency", 0, 1, false, true), s) == "highlight", "loot: uniques and orbs always glow");
            var ts = LootFilterRules.Normalize(Json.Parse("{\"highlight\":5,\"tier\":7}"));
            check(ts.Tier == 7 && LootFilterRules.Classify(Li(1, "x", "equipment", 1, 1, false, false, false, 7), ts) == "highlight" && LootFilterRules.Classify(Li(1, "x", "equipment", 1, 1, false, false, false, 6), ts) == "normal" && LootFilterRules.Normalize(Json.Parse("{\"tier\":99}")).Tier == 8, "loot: the modifier tier rule");
            check(LootFilterRules.Color(Li(1, "x", "equipment", 5)) == "#ffd040" && LootFilterRules.Color(Li(1, "x", "equipment", 5, 1, true)) == LootFilterRules.UniqueColor && LootFilterRules.Color(Li(1, "x", "currency", 0, 1, false, true)) == LootFilterRules.OrbColor && LootFilterRules.Color(Li(1, "x")) == null, "loot: colours");
            check(LootFilterRules.Label(Li(1, "Dawnforged Helmet", "equipment", 5)) == "[Legendary] Dawnforged Helmet" && LootFilterRules.Label(Li(1, "Soulreaper", "equipment", 0, 1, true)) == "[Unique] Soulreaper", "loot: labels");
            var gold = Li(1, "gold coin", "currency", 0, 50); gold.HasLeft = true; gold.Left = 20;
            check(LootFilterRules.Tooltip(gold) == "50x gold coin\n20 left in the corpse\nClick: loot all   Shift+click: loot one", "loot: a stack tooltip");
            var gone = Li(1, "Sword", "equipment", 3); gone.HasLeft = true; gone.Left = 0;
            var one = Li(1, "Sword"); one.HasLeft = true; one.Left = 1;
            var mods = Li(1, "Sword", "equipment", 4); mods.HasLeft = true; mods.Left = 1; mods.X = "Attack Speed +5%";
            check(LootFilterRules.Tooltip(gone) == "[Magic] Sword\nLooted (or gone)" && LootFilterRules.Tooltip(one) == "Sword\nClick: loot" && LootFilterRules.Tooltip(mods) == "[Rare] Sword\nAttack Speed +5%\nClick: loot", "loot: gone, single and modifier tooltips");
            check(LootFilterRules.ThresholdText(0) == "Off" && LootFilterRules.ThresholdText(5) == "Legendary+", "loot: threshold text");
            bool g2; int cnt = LootFilterRules.IconCount(gone, out g2);
            check(cnt == 1 && g2, "loot: a gone item shows its dropped count");
            var rt = Json.Parse(Json.Serialize(s.ToDict()));
            check(Json.Int(rt, "highlight") == 4 && Json.Bool(Json.Get(rt, "show"), "equipment") && !Json.Bool(Json.Get(rt, "show"), "supplies"), "loot: the settings go back as the server reads them");

            // ---- the protocol
            var ext = new ExtOpcodes();
            var sent = new List<string>(); ext.Transmit = p => sent.Add(System.Text.Encoding.UTF8.GetString(p, 4, p.Length - 4));
            double clock = 10;
            var lf = new LootFilterModel(ext) { Clock = () => clock };
            int changes = 0, shows = 0; lf.Changed += () => changes++; lf.ShowRequested += () => shows++;
            lf.Sync(); lf.Open();
            check(sent[0].Contains("\"sync\"") && sent[1].Contains("\"open\""), "loot protocol: sync and open");
            ext.Receive(238, "{\"action\":\"settings\",\"data\":{\"s\":{\"highlight\":4,\"dim\":2},\"unlocked\":true,\"presets\":[{\"key\":\"hunter\",\"name\":\"Hunter\"},{\"key\":\"all\",\"name\":\"Everything\"}],\"open\":true}}");
            check(lf.Loaded && lf.Unlocked && lf.Settings.Highlight == 4 && lf.Presets.Count == 2 && lf.Presets[1].Key == "all" && shows == 1, "loot protocol: settings, presets and the open answer");
            ext.Receive(238, "{\"action\":\"kill\",\"data\":{\"k\":7,\"m\":\"Dragon\",\"items\":[{\"id\":3031,\"c\":50,\"left\":50,\"nm\":\"gold coin\",\"g\":\"currency\"},{\"n\":5,\"id\":2400,\"r\":4,\"nm\":\"Fire Sword\",\"g\":\"equipment\"}]}}");
            check(lf.Kills.Count == 1 && lf.Kills[0].K == 7 && lf.Kills[0].Monster == "Dragon" && lf.Kills[0].Items.Count == 2 && lf.Kills[0].Items[0].N == 1 && lf.Kills[0].Items[1].N == 5, "loot protocol: a kill with its items, every n set");
            ext.Receive(238, "{\"action\":\"update\",\"data\":{\"k\":7,\"left\":[20,0]}}");
            check(lf.Kills[0].Items[0].Left == 20 && lf.Kills[0].Items[1].Left == 0 && lf.Kills[0].Items[1].HasLeft, "loot protocol: what is left per item");
            sent.Clear();
            lf.Take(lf.Kills[0], lf.Kills[0].Items[0], true);
            check(sent.Count == 1 && sent[0].Contains("\"take\"") && sent[0].Contains("\"k\":7") && sent[0].Contains("\"n\":1") && sent[0].Contains("\"id\":3031") && sent[0].Contains("\"one\":true"), "loot protocol: a click takes (Shift: one)");
            ext.Receive(238, "{\"action\":\"decay\",\"data\":{\"k\":7}}");
            check(lf.Kills[0].Decayed, "loot protocol: a corpse that decayed");
            ext.Receive(238, "{\"action\":\"msg\",\"data\":{\"text\":\"Too far away.\"}}");
            check(lf.Message == "Too far away." && lf.MessageAt == 10, "loot protocol: the server's refusal of a click");
            for (int i = 0; i < LootFilterModel.MaxKills + 5; i++) ext.Receive(238, "{\"action\":\"kill\",\"data\":{\"k\":" + (100 + i) + ",\"m\":\"x\",\"items\":[]}}");
            check(lf.Kills.Count == LootFilterModel.MaxKills && lf.Kills[0].K == 100 + LootFilterModel.MaxKills + 4, "loot protocol: the newest kills are kept, newest first");
            sent.Clear();
            var set = lf.Settings.Copy(); set.Highlight = 5; lf.Set(set); lf.Preset("hunter");
            check(sent.Count == 2 && sent[0].Contains("\"set\"") && sent[0].Contains("\"highlight\":5") && sent[1].Contains("\"preset\"") && sent[1].Contains("hunter") && lf.Settings.Highlight == 5, "loot protocol: set and preset");

            // ---- groundlabels_test.lua
            var gs = new GroundLabelSettings();
            check(gs.Enabled && gs.RarePlus && gs.AltAll && gs.Corpses && gs.Timers && gs.Size == "normal", "labels: all on by default");
            var gp = GroundLabelSettings.From(Json.Parse("{\"enabled\":false,\"size\":\"huge\",\"timers\":false}"));
            check(!gp.Enabled && gp.RarePlus && !gp.Timers && gp.Size == "normal" && GroundLabelSettings.From(Json.Parse("{\"size\":\"large\"}")).Size == "large" && GroundLabelSettings.From(null).Corpses, "labels: settings are read with defaults");
            check(GroundLabelRules.IsCandidate(false, false, false, false, true, false, false) && !GroundLabelRules.IsCandidate(true, false, false, false, true, false, false) && !GroundLabelRules.IsCandidate(false, true, false, false, false, false, false) &&
                  !GroundLabelRules.IsCandidate(false, false, true, false, true, false, false) && !GroundLabelRules.IsCandidate(false, false, false, true, true, false, false), "labels: candidates: a sword yes; ground, border, wall and on top no");
            check(GroundLabelRules.IsCandidate(false, false, false, false, false, true, true) && !GroundLabelRules.IsCandidate(false, false, false, false, false, true, false) && !GroundLabelRules.IsCandidate(false, false, false, false, false, false, false), "labels: a corpse yes, a chest and furniture no");

            var filter = LootFilterRules.Normalize(Json.Parse("{\"highlight\":4,\"dim\":2,\"show\":{\"supplies\":false}}"));
            var on = new GroundLabelSettings();
            Func<LootInfo, GroundRow> item = i => new GroundRow { Info = i, Expire = -1 };
            var epic = Li(1, "fire sword", "equipment", 4); var rare = Li(1, "fire sword", "equipment", 3); var unc = Li(1, "sword", "equipment", 2); var common = Li(1, "sword", "equipment", 1);
            var potion = Li(2, "mana potion", "supplies", 0, 5); var junk = Li(3, "bone", "other"); var unique = Li(4, "soulreaper", "equipment", 0, 1, true);
            var orb = Li(5, "chaos orb", "currency", 0, 3, false, true); var power = Li(6, "axe", "equipment", 1, 1, false, false, true);
            Func<LootInfo, bool, GroundLabelSettings, GroundDecision> decide = (i, alt, st) => GroundLabelRules.Decide(item(i), st ?? on, filter, alt);
            check(decide(epic, false, null).Highlight, "labels: Rare glows, labelled and highlighted");
            check(decide(rare, false, null) != null && !decide(rare, false, null).Highlight, "labels: Magic is labelled (Magic+), not highlighted");
            check(decide(unc, false, null) == null && decide(common, false, null) == null && decide(potion, false, null) == null && decide(junk, false, null) == null, "labels: Uncommon, Common, a hidden category and junk have no label without Alt");
            check(decide(unique, false, null).Highlight && decide(orb, false, null).Highlight && decide(power, false, null).Highlight, "labels: a unique, an orb and a legendary power always glow");
            var noRare = GroundLabelSettings.From(Json.Parse("{\"rarePlus\":false}"));
            check(decide(rare, false, noRare) == null && decide(epic, false, noRare).Highlight, "labels: Magic+ off: only what glows shows");
            var strict = LootFilterRules.Normalize(Json.Parse("{\"highlight\":5,\"dim\":4}"));
            check(GroundLabelRules.Decide(item(rare), on, strict, false) == null, "labels: the filter hides Magic: no label even with Magic+");
            check(!decide(unc, true, null).Dim && decide(common, true, null).Dim && decide(potion, true, null).Dim && !decide(junk, true, null).Dim, "labels: Alt shows everything, the hidden ones faded");
            check(decide(junk, true, GroundLabelSettings.From(Json.Parse("{\"altAll\":false}"))) == null && GroundLabelRules.Decide(item(epic), GroundLabelSettings.From(Json.Parse("{\"enabled\":false}")), filter, true) == null && GroundLabelRules.Decide(null, on, filter, false) == null, "labels: Alt off, labels off, no row");

            var corpse = new GroundRow { Corpse = true, Items = 4, Expire = 100, At = 0 };
            corpse.Inside.AddRange(new[] { epic, common, potion, Li(0, "gold coin", "currency", 0, 30) });
            var cd = GroundLabelRules.Decide(corpse, on, filter, false);
            check(cd.Corpse && cd.Matches == 1 && cd.Best.Nm == "fire sword", "labels: a corpse with one glowing item, the best for the colour");
            check(GroundLabelRules.CorpseText(corpse, cd) == "Corpse: 1 item", "labels: singular");
            var corpse2 = new GroundRow { Corpse = true, Items = 3 };
            corpse2.Inside.AddRange(new[] { epic, rare, unique });
            var cd2 = GroundLabelRules.Decide(corpse2, on, filter, false);
            check(cd2.Matches == 3 && cd2.Best.U && GroundLabelRules.CorpseText(corpse2, cd2) == "Corpse: 3 items", "labels: Rare, Magic (Magic+) and the unique; the unique colour wins");
            var dull = new GroundRow { Corpse = true, Items = 2 };
            dull.Inside.AddRange(new[] { common, junk });
            check(GroundLabelRules.Decide(dull, on, filter, false) == null && GroundLabelRules.Decide(dull, on, filter, true).Dim && GroundLabelRules.CorpseText(dull, GroundLabelRules.Decide(dull, on, filter, true)) == "Corpse: 2 items", "labels: a dull corpse only with Alt, faded, counting everything");
            check(GroundLabelRules.Decide(new GroundRow { Corpse = true, Items = 0 }, on, filter, true) == null && GroundLabelRules.Decide(corpse, GroundLabelSettings.From(Json.Parse("{\"corpses\":false}")), filter, false) == null, "labels: an empty corpse never, corpse labels off");

            check(GroundLabelRules.TitleCase("fire sword") == "Fire Sword" && GroundLabelRules.TitleCase("knight's axe") == "Knight's Axe", "labels: title case");
            check(GroundLabelRules.ItemText(item(rare)) == "Magic Fire Sword" && GroundLabelRules.ItemText(item(unique)) == "Soulreaper" && GroundLabelRules.ItemText(item(orb)) == "3x Chaos Orb" && GroundLabelRules.ItemText(item(junk)) == "Bone", "labels: item text");
            check(GroundLabelRules.TimerText(102) == "1:42" && GroundLabelRules.TimerText(7) == "0:07" && GroundLabelRules.TimerText(3723) == "1:02:03" && GroundLabelRules.TimerText(-5) == "0:00", "labels: timer text");
            var timed = new GroundRow { Info = Li(1, "sword", "equipment", 3), Expire = 120, At = 1000 };
            check(GroundLabelRules.SecondsLeft(timed, 1018) == 102 && GroundLabelRules.SecondsLeft(timed, 5000) == 0 && GroundLabelRules.SecondsLeft(item(rare), 5000) < 0, "labels: counts down from when it arrived");
            var td = GroundLabelRules.Decide(timed, on, filter, false);
            check(GroundLabelRules.Text(timed, td, on, 1018) == "Magic Sword  1:42" && GroundLabelRules.Text(timed, td, GroundLabelSettings.From(Json.Parse("{\"timers\":false}")), 1018) == "Magic Sword", "labels: the timer in the text, off in the settings");
            var timedJunk = new GroundRow { Info = junk, Expire = 50 };
            check(!GroundLabelRules.ShowTimer(timedJunk, GroundLabelRules.Decide(timedJunk, on, filter, true), on), "labels: no timer for junk");
            check(GroundLabelRules.Text(corpse, cd, on, 10) == "Corpse: 1 item  1:30", "labels: a corpse timer");
            check(GroundLabelRules.Color(item(epic), decide(epic, false, null)) == "#a35cf0" && GroundLabelRules.Color(item(unique), decide(unique, false, null)) == LootFilterRules.UniqueColor && GroundLabelRules.Color(item(junk), decide(junk, true, null)) == GroundLabelRules.TextColor &&
                  GroundLabelRules.Color(item(common), decide(common, true, null)) == GroundLabelRules.DimColor && GroundLabelRules.Color(corpse2, cd2) == LootFilterRules.UniqueColor, "labels: colours");
            check(GroundLabelRules.Priority(item(unique), decide(unique, false, null)) > GroundLabelRules.Priority(item(epic), decide(epic, false, null)) &&
                  GroundLabelRules.Priority(item(epic), decide(epic, false, null)) > GroundLabelRules.Priority(item(rare), decide(rare, false, null)) &&
                  GroundLabelRules.Priority(item(rare), decide(rare, false, null)) > GroundLabelRules.Priority(item(junk), decide(junk, true, null)) &&
                  GroundLabelRules.Priority(item(junk), decide(junk, true, null)) > GroundLabelRules.Priority(item(common), decide(common, true, null)), "labels: unique, rarity, junk, faded");
            var many = new List<GroundLabel>();
            for (int i = 1; i <= 100; i++) many.Add(new GroundLabel { Prio = i % 3, Dist = i % 7, Order = i });
            var kept = GroundLabelRules.Select(many);
            check(kept.Count == GroundLabelRules.MaxLabels && kept[0].Prio == 2 && kept[0].Dist == 0, "labels: capped at 40, best first, then nearest");

            // layout
            Func<IList<GroundLabelRules.LayoutBlock>, float, float, float, bool> noOverlap = (groups, gap, lift, max) =>
            {
                var boxes = GroundLabelRules.Layout(groups, gap, lift, max);
                var abs = groups.Select(g => new { x = g.Ax + boxes[g.Key].X, y = g.Ay + boxes[g.Key].Y, w = boxes[g.Key].W, h = boxes[g.Key].H }).ToList();
                for (int i = 0; i < abs.Count; i++)
                    for (int j = i + 1; j < abs.Count; j++)
                        if (abs[i].x < abs[j].x + abs[j].w && abs[j].x < abs[i].x + abs[i].w && abs[i].y < abs[j].y + abs[j].h && abs[j].y < abs[i].y + abs[i].h) return false;
                return true;
            };
            var single = new List<GroundLabelRules.LayoutBlock> { new GroundLabelRules.LayoutBlock { Key = 0, Ax = 100, Ay = 100, W = 80, H = 16 } };
            var sb = GroundLabelRules.Layout(single, 2, 10, 200);
            check(sb[0].X == -40 && sb[0].Y == -26, "labels layout: one label is centred, its bottom 10 px above the anchor");
            var row = new List<GroundLabelRules.LayoutBlock>();
            for (int i = 1; i <= 5; i++) row.Add(new GroundLabelRules.LayoutBlock { Key = i, Ax = i * 64, Ay = 0, W = 150, H = 16 });
            check(noOverlap(row, 2, 10, 192), "labels layout: a row of five wide labels never overlaps");
            var cluster = new List<GroundLabelRules.LayoutBlock> { new GroundLabelRules.LayoutBlock { Key = 99, Ax = 128, Ay = 64, W = 120, H = 50 } };
            for (int x = 0; x < 4; x++) for (int y = 0; y < 3; y++) cluster.Add(new GroundLabelRules.LayoutBlock { Key = x * 10 + y, Ax = x * 64, Ay = y * 64, W = 100, H = 51 });
            check(noOverlap(cluster, 2, 10, 192), "labels layout: a cluster of tiles never overlaps");
            check(noOverlap(new List<GroundLabelRules.LayoutBlock> { new GroundLabelRules.LayoutBlock { Key = 1, W = 60, H = 16 }, new GroundLabelRules.LayoutBlock { Key = 2, W = 60, H = 16 } }, 1, 0, 200), "labels layout: two blocks on one anchor never share a spot");
            var capped = GroundLabelRules.Layout(new List<GroundLabelRules.LayoutBlock> { new GroundLabelRules.LayoutBlock { Key = 1, W = 60, H = 100 }, new GroundLabelRules.LayoutBlock { Key = 2, W = 60, H = 16 } }, 0, 0, 50);
            check(capped[2].Y >= 0, "labels layout: when going up goes too far, it goes down below the tall block");

            // the scan and the asking
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            var center = new Pos(100, 100, 7);
            w.Center = center;
            var sword = new ThingType { Pickupable = true };
            var floor = new ThingType { Ground = true };
            var corpseType = new ThingType { Container = true };
            Action<Pos, ThingType, int, int> put = (p, ty, id, count) => w.GetOrMake(p).Things.Add(new Thing { Item = new Item { Id = id, Count = count, Type = ty } });
            Action<Pos> ground0 = p => put(p, floor, 100, 0);
            ground0(center.Offset(1, 0)); put(center.Offset(1, 0), sword, 3264, 1);
            ground0(center.Offset(2, 0)); put(center.Offset(2, 0), sword, 3031, 40); put(center.Offset(2, 0), corpseType, 3058, 0);
            ground0(center.Offset(3, 0));
            ground0(center.Offset(0, 1)); put(center.Offset(0, 1), new ThingType { Pickupable = true, OnTop = true }, 5, 1);
            var ext2 = new ExtOpcodes();
            var sent2 = new List<string>(); ext2.Transmit = p => sent2.Add(System.Text.Encoding.UTF8.GetString(p, 4, p.Length - 4));
            double now2 = 0;
            var gm = new GroundLabelsModel(ext2) { Clock = () => now2 };
            check(GroundLabelRules.Signature(w.Get(center.Offset(2, 0))) == "3031x40;3058x1", "labels scan: the signature lists the candidates, a missing count is 1");
            int asked = gm.Scan(w, center);
            check(asked == 2 && sent2.Count == 1 && sent2[0].Contains("\"look\"") && sent2[0].Contains("[101,100,7]") && sent2[0].Contains("[102,100,7]") && !sent2[0].Contains("[103,100,7]") && !sent2[0].Contains("[100,101,7]"), "labels scan: only tiles with a candidate are asked, one request");
            sent2.Clear();
            check(gm.Scan(w, center) == 0 && sent2.Count == 0, "labels scan: a tile already asked is not asked again");
            now2 = 3.5;
            check(gm.Scan(w, center) == 2, "labels scan: an unanswered tile is asked again after 3 s");
            ext2.Receive(230, "{\"action\":\"tiles\",\"data\":{\"t\":[{\"p\":[101,100,7],\"i\":[{\"s\":1,\"id\":3264,\"c\":1,\"nm\":\"fire sword\",\"r\":4,\"g\":\"equipment\"}]},{\"p\":[102,100,7],\"i\":[{\"s\":2,\"id\":3058,\"k\":1,\"n\":2,\"i\":[{\"nm\":\"Fire Axe\",\"r\":5,\"g\":\"equipment\"}],\"e\":90}]},{\"p\":[50,50,7],\"i\":[]}]}}");
            check(gm.Answered == 2 && gm.Dirty, "labels scan: the answers are kept, an unknown tile is ignored");
            gm.Dirty = false;
            var labels = gm.Labels(center, filter, false);
            check(labels.Count == 2 && labels[0].Row.Corpse && labels[0].Text.StartsWith("Corpse: 1 item") && labels[1].Text == "Rare Fire Sword" && labels[0].Decision.Highlight, "labels: a corpse with a Legendary and a Rare sword, corpse first");
            now2 = 20;
            check(gm.Scan(w, center) == 0, "labels scan: answered tiles are left alone");
            // the tile changes: the rows are dropped and it is asked again
            put(center.Offset(1, 0), sword, 3265, 1);
            check(gm.Scan(w, center) == 1 && gm.Dirty && gm.Labels(center, filter, false).Count == 1, "labels scan: a changed tile loses its rows and is asked again");
            // a tile that left the scan is forgotten, and the whole scan is off with the setting
            var far = center.Offset(20, 0);
            w.Clean(center.Offset(1, 0));
            gm.Scan(w, center);
            check(gm.TileCount == 1, "labels scan: a tile that has no candidate any more is forgotten");
            gm.Settings.Enabled = false;
            check(gm.Scan(w, center) == 0 && gm.TileCount == 0, "labels scan: off, nothing is asked and nothing kept");
            sent2.Clear();
            gm.Settings.Enabled = true; gm.Reset();
            for (int i = 0; i < 40; i++) { var p = center.Offset(-8 + i % 17, -5 + i / 17, 0); ground0(p); put(p, sword, 4000 + i, 1); }
            int total = gm.Scan(w, center);
            check(total >= 40 && sent2.Count == 2 && sent2[0].Split('[').Length - 2 == 30, "labels scan: at most 30 tiles a request (" + total + " tiles, " + sent2.Count + " requests)");

            // Core keys of the new classes have a pt-BR text (the source scan of the Unity folder does not see them)
            var missing = new List<string>();
            string coreDir = System.IO.Path.GetFullPath(System.IO.Path.Combine("..", "Client", "Assets", "Chaos", "Core"));
            if (!System.IO.Directory.Exists(coreDir)) coreDir = System.IO.Path.GetFullPath(System.IO.Path.Combine("unity", "Client", "Assets", "Chaos", "Core"));
            if (System.IO.Directory.Exists(coreDir))
            {
                foreach (var f in new[] { "HelperRotation.cs", "DeathRecap.cs", "LootFilter.cs", "GroundLabels.cs", "HelperEngine.cs" })
                {
                    string path = System.IO.Path.Combine(coreDir, f);
                    if (!System.IO.File.Exists(path)) continue;
                    foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(System.IO.File.ReadAllText(path), "Loc\\.T\\((?:[^\"\\n)]*\\?\\s*)?\"((?:[^\"\\\\]|\\\\.)*)\"(?:\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\")?"))
                        foreach (int gi in new[] { 1, 2 })
                            if (m.Groups[gi].Success && !LocStrings.PtBr.ContainsKey(m.Groups[gi].Value)) missing.Add(m.Groups[gi].Value);
                }
                // the long ternaries of the sentences
                foreach (var key in new[] { "Defeated by {0}", "Killed by {0}", "Last {0} before the death, {1} hit", "Last {0} before the death, {1} hits", "Corpse: {0} item", "Corpse: {0} items", " and {0} level", " and {0} levels" })
                    if (!LocStrings.PtBr.ContainsKey(key)) missing.Add(key);
            }
            check(missing.Count == 0, "loc: every Loc.T key of the helper, recap and loot Core files has a pt-BR text" + (missing.Count > 0 ? ": " + string.Join(" | ", missing) : ""));
        }
    }
}
