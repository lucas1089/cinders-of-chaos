// Journey bot decision logic (O542, unity/README.md "Journey bots (O542)"): hunt pick, thresholds, town trip trigger, the progress watchdog, the activity chooser, the map memory with its
// path finder, the metrics maths and the coverage table. Core/Journey.cs on synthetic numbers; no server.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class JourneyTests
    {
        public static void Run(Action<bool, string> check)
        {
            Rng(check);
            Hunts(check);
            Rules(check);
            Watch(check);
            Activities(check);
            Map(check);
            Metrics(check);
            Coverage(check);
        }

        static MapMark Hunt(string name, int x, int y, int z) => new MapMark { Kind = "hunt", Name = name, X = x, Y = y, Z = z };

        static void Rng(Action<bool, string> check)
        {
            var a = new JourneyRng(7); var b = new JourneyRng(7); var c = new JourneyRng(8);
            bool same = true, diff = false;
            for (int i = 0; i < 50; i++) { ulong x = a.NextU(); same &= x == b.NextU(); diff |= x != c.NextU(); }
            check(same && diff, "journey rng: a seed repeats, another seed differs");
            var r = new JourneyRng(1);
            bool inRange = true;
            for (int i = 0; i < 500; i++) { int v = r.Range(3, 9); inRange &= v >= 3 && v <= 9; double u = r.Unit(); inRange &= u >= 0 && u < 1; }
            check(inRange && new JourneyRng(0).Next(10) >= 0, "journey rng: range and unit stay inside, seed 0 works");
        }

        static void Hunts(Action<bool, string> check)
        {
            var h = JourneyHunts.ParseHunt(Hunt("Hunting: Rat, Cave Rat (level 1-10)", 32378, 32226, 8));
            check(h != null && h.Lo == 1 && h.Hi == 10 && h.Monsters.Count == 2 && h.Monsters[1] == "Cave Rat" && h.At.Z == 8, "hunt mark parsed: bands, monsters, position");
            check(JourneyHunts.ParseHunt(new MapMark { Kind = "shop", Name = "Jakesh (shop)" }) == null && JourneyHunts.ParseHunt(Hunt("Hunting: nothing", 1, 1, 7)) == null, "hunt mark: other kinds and odd names are no hunt");
            check(JourneyHunts.Wants(h, "Rat [4]") && JourneyHunts.Wants(h, "cave rat") && !JourneyHunts.Wants(h, "Troll [9]") && JourneyHunts.Wants(null, "x"), "hunt wants its monsters by base name, level tag cut");
            string lua = "marks = {\n\t\t{k = \"hunt\", x = 33395, y = 31816, z = 2, n = \"Hunting: Aeliana, Sagittarius (level 260-310)\", r = 1},\n\t\t{k = \"shop\", x = 33045, y = 32620, z = 2, n = \"Jakesh (shop)\", r = 1},\n}";
            var marks = JourneyHunts.ParsePoiLua(lua);
            check(marks.Count == 2 && marks[0].Kind == "hunt" && marks[0].X == 33395 && marks[1].Name == "Jakesh (shop)" && JourneyHunts.FromMarks(marks).Count == 1, "chaos_poi.lua rows parse into marks and hunts");

            var all = JourneyHunts.FromMarks(new[]
            {
                Hunt("Hunting: Rat (level 1-10)", 32378, 32226, 8), Hunt("Hunting: Troll (level 10-30)", 32400, 32250, 7), Hunt("Hunting: Wasp (level 20-40)", 32390, 32230, 7),
                Hunt("Hunting: Dragon (level 100-150)", 32380, 32230, 7), Hunt("Hunting: Far (level 10-30)", 33900, 32230, 7),
            });
            var from = new Pos(32369, 32241, 7);
            check(JourneyHunts.Pick(all, 5, from, null, null).Monsters[0] == "Rat", "pick: level 5 takes the rats");
            check(JourneyHunts.Pick(all, 12, from, null, null).Monsters[0] == "Troll", "pick: level 12 takes the trolls, not the far hunt of the same band");
            var avoid = new HashSet<string> { JourneyHunts.Pick(all, 12, from, null, null).Key };
            check(JourneyHunts.Pick(all, 12, from, avoid, null).Monsters[0] != "Troll", "pick: a given up hunt is not picked again");
            check(JourneyHunts.Pick(all, 300, from, null, null).Monsters[0] == "Dragon", "pick: no band holds level 300, the closest band below comes");
            check(JourneyHunts.Pick(all, 12, from, null, null, 5) == null, "pick: nothing within a tiny travel limit");
            var r1 = new JourneyRng(3); var r2 = new JourneyRng(3);
            check(JourneyHunts.Pick(all, 25, from, null, r1).Key == JourneyHunts.Pick(all, 25, from, null, r2).Key, "pick: the noise follows the seed");
        }

        static void Rules(Action<bool, string> check)
        {
            var v = new JourneyVitals { Health = 30, MaxHealth = 100, Mana = 50, MaxMana = 100, Level = 10, FreeCap = 300, TotalCap = 400, HealthPotions = 5, ManaPotions = 5, CanCast = true, Gold = 1000 };
            check(JourneyRules.DrinkHealth(v) && !JourneyRules.DrinkMana(v), "thresholds: 30 percent health drinks, 50 percent mana does not");
            v.Health = 40; v.Mana = 20;
            check(!JourneyRules.DrinkHealth(v) && JourneyRules.DrinkMana(v), "thresholds: 40 percent health is not under 40, 20 percent mana drinks");
            v.HealthPotions = 0; v.Health = 10;
            check(!JourneyRules.DrinkHealth(v), "thresholds: no potion, no drink");
            v.CanCast = false; v.Mana = 1;
            check(!JourneyRules.DrinkMana(v), "thresholds: a class without mana never drinks mana");

            var t = new JourneyVitals { FreeCap = 200, TotalCap = 400, BackpackFree = 10, HealthPotions = 10, Gold = 5000 };
            check(JourneyRules.TownTrip(t, 1e9, 50) == "", "town trip: nothing wrong, no trip");
            t.FreeCap = 20;
            check(JourneyRules.TownTrip(t, 0, 50) == "cap", "town trip: 20 oz of 400 left is the cap trigger, cooldown or not");
            t.FreeCap = 200; t.BackpackFree = 2;
            check(JourneyRules.TownTrip(t, 0, 50) == "backpack", "town trip: two free slots is the backpack trigger");
            t.BackpackFree = 10; t.HealthPotions = 1;
            check(JourneyRules.TownTrip(t, JourneyRules.TripCooldownMs - 1, 50) == "" && JourneyRules.TownTrip(t, JourneyRules.TripCooldownMs, 50) == "potions", "town trip: low potions wait for the cooldown");
            t.Gold = 100;
            check(JourneyRules.TownTrip(t, 1e9, 50) == "", "town trip: no gold for ten potions, no trip for potions");
            t.Gold = 5000; t.CanCast = true; t.ManaPotions = 5;
            check(JourneyRules.TownTrip(t, 1e9, 50) == "", "town trip: a caster counts its mana potions too");
            check(JourneyRules.TownTrip(t, 1e9, 0) == "", "town trip: no known potion price, no potion trip");
            check(JourneyRules.BuyCount(1000, 0, 50) == 10 && JourneyRules.BuyCount(100000, 0, 50) == JourneyRules.PotionsWanted && JourneyRules.BuyCount(100000, 25, 50) == 0 && JourneyRules.BuyCount(5, 0, 50) == 0 && JourneyRules.BuyCount(100, 0, 0) == 0, "buy count: half the gold at most, up to the wanted number");
        }

        static void Watch(Action<bool, string> check)
        {
            var w = new StuckWatch();
            var p = new Pos(10, 10, 7);
            check(w.Observe(0, p, 100, true) == 0, "watchdog: the first look is fine");
            check(w.Observe(StuckWatch.ReplanMs - 1, p, 100, true) == 0, "watchdog: not yet");
            check(w.Observe(StuckWatch.ReplanMs, p, 100, true) == 1, "watchdog: no progress for 7 s asks for a re-plan");
            check(w.Observe(StuckWatch.ReplanMs + 100, p, 100, true) == 0, "watchdog: the re-plan is asked once");
            check(w.Observe(StuckWatch.GiveUpMs, p, 100, true) == 2 && w.GiveUps == 1, "watchdog: 24 s gives the spot up");
            check(w.Observe(StuckWatch.GiveUpMs + StuckWatch.GiveUpMs, p, 100, true) == 2 && w.GiveUps == 2, "watchdog: the same spot again counts a second give up");
            check(w.Observe(1e6, p.Offset(1, 0), 100, true) == 0, "watchdog: a step is progress");
            double t = 1e6;
            w.Observe(t, p, 100, true);
            check(w.Observe(t + StuckWatch.ReplanMs, p, 101, true) == 0, "watchdog: experience gained is progress");
            check(w.Observe(t + 1e5, p, 101, false) == 0 && w.GiveUps == 0, "watchdog: not busy (idle on purpose) is never stuck and clears the count");
        }

        static void Activities(Action<bool, string> check)
        {
            var rng = new JourneyRng(5);
            var ctx = new JourneyActivities.Context { Level = 10, TripReason = "cap" };
            check(JourneyActivities.Choose(ctx, rng) == JourneyActivity.Town, "activity: a due trip is always the town");
            ctx.TripReason = "";
            var count = new Dictionary<JourneyActivity, int>();
            ctx.UnvisitedTowns = 5; ctx.UntouchedSystems = 30; ctx.UntalkedNpcs = 3; ctx.MinutesSinceExplore = 20; ctx.MinutesSinceSystem = 10; ctx.MinutesSinceTalk = 15;
            for (int i = 0; i < 4000; i++) { var a = JourneyActivities.Choose(ctx, rng); count[a] = count.TryGetValue(a, out int n) ? n + 1 : 1; }
            check(count[JourneyActivity.Hunt] > count[JourneyActivity.Explore] && count[JourneyActivity.Hunt] > count[JourneyActivity.System] && count[JourneyActivity.Hunt] > 4000 * 0.3, "activity: hunting is the main thing");
            check(new[] { JourneyActivity.Explore, JourneyActivity.Talk, JourneyActivity.System, JourneyActivity.Idle }.All(a => count.TryGetValue(a, out int n) && n > 40), "activity: explore, talk, system and idle all happen");
            var quiet = new JourneyActivities.Context { Level = 2 };
            var qc = new HashSet<JourneyActivity>();
            for (int i = 0; i < 500; i++) qc.Add(JourneyActivities.Choose(quiet, rng));
            check(qc.All(a => a == JourneyActivity.Hunt || a == JourneyActivity.Idle), "activity: nothing to explore, nothing to open, nobody to talk to: hunt or stand");
            var a1 = new List<JourneyActivity>(); var a2 = new List<JourneyActivity>();
            var s1 = new JourneyRng(11); var s2 = new JourneyRng(11);
            for (int i = 0; i < 50; i++) { a1.Add(JourneyActivities.Choose(ctx, s1)); a2.Add(JourneyActivities.Choose(ctx, s2)); }
            check(a1.SequenceEqual(a2), "activity: the same seed makes the same day");
            bool ok = true;
            for (int i = 0; i < 300; i++)
            {
                double idle = JourneyActivities.IdleMs(rng), react = JourneyActivities.ReactionMs(rng), slice = JourneyActivities.HuntSliceMs(rng);
                ok &= idle >= 2000 && idle <= 25000 && react >= 120 && react <= 120 + 400 + 1700 && slice >= 180000 && slice <= 540000;
            }
            check(ok, "timing: idle 2-25 s, reaction 0.12-2.2 s, hunt slice 3-9 min");
            var rs = Enumerable.Range(0, 400).Select(i => JourneyActivities.ReactionMs(rng)).ToList();
            check(rs.Distinct().Count() > 100 && rs.Max() > 700, "timing: imperfect, uneven, now and then a long one");
        }

        static JourneyMap Grid(int w, int h, int z, params (int x, int y)[] walls)
        {
            var m = new JourneyMap();
            var wall = new HashSet<(int, int)>(walls);
            for (int x = 0; x < w; x++) for (int y = 0; y < h; y++) m.Set(new Pos(100 + x, 100 + y, z), wall.Contains((x, y)) ? JourneyMap.Cell.Blocked : JourneyMap.Cell.Walk);
            return m;
        }

        static void Map(Action<bool, string> check)
        {
            var m = Grid(10, 10, 7, (5, 0), (5, 1), (5, 2), (5, 3), (5, 4), (5, 5), (5, 6), (5, 7), (5, 8));
            var path = m.Path(new Pos(100, 100, 7), new Pos(109, 100, 7), 0);
            check(path != null && path.Count > 10 && path[path.Count - 1].X == 109 && path.All(p => !(p.X == 105 && p.Y < 109)), "map: the path goes round the wall through its gap");
            check(m.Path(new Pos(100, 100, 7), new Pos(109, 100, 8), 0) == null, "map: no path to another floor");
            var closed = Grid(10, 10, 7, Enumerable.Range(0, 10).Select(y => (5, y)).ToArray());
            check(closed.Path(new Pos(100, 100, 7), new Pos(109, 100, 7), 0) == null, "map: a closed wall has no path");
            var near = m.Path(new Pos(100, 100, 7), new Pos(108, 100, 7), 0, 12000, 2);
            check(near != null && near[near.Count - 1].X >= 106, "map: range counts as arrived");
            var corner = Grid(3, 3, 7, (1, 0), (0, 1));
            check(corner.Path(new Pos(100, 100, 7), new Pos(101, 101, 7), 0) == null, "map: no diagonal squeeze between two blocked tiles");
            var bad = Grid(5, 1, 7);
            bad.MarkBad(new Pos(102, 100, 7), 0);
            check(bad.Path(new Pos(100, 100, 7), new Pos(104, 100, 7), 1000) == null && bad.Path(new Pos(100, 100, 7), new Pos(104, 100, 7), JourneyMap.BadMs + 1) != null, "map: a tile that failed is avoided for 3 minutes");

            var seen = Grid(5, 5, 7);
            var fr = seen.ExploreToward(new Pos(102, 102, 7), new Pos(200, 102, 7), 0, null);
            check(fr.HasValue && fr.Value.X == 104, "explore: the frontier tile on the goal's side");
            var fr2 = seen.ExploreToward(new Pos(102, 102, 7), new Pos(200, 102, 7), 0, new HashSet<Pos> { fr.Value });
            check(fr2.HasValue && !fr2.Value.Equals(fr.Value), "explore: a visited frontier is skipped");
            var plan = JourneyNav.Next(seen, new Pos(102, 102, 7), new Pos(200, 102, 7), 0, 0, null, null);
            check(plan.What == JourneyPlan.Kind.Explore && plan.Target.X == 104, "next: a goal outside the known map explores toward it");
            plan = JourneyNav.Next(seen, new Pos(102, 102, 7), new Pos(104, 102, 7), 0, 0, null, null);
            check(plan.What == JourneyPlan.Kind.Walk && plan.Target.X == 104, "next: a known goal is a walk");
            plan = JourneyNav.Next(seen, new Pos(102, 102, 7), new Pos(103, 102, 7), 0, 1, null, null);
            check(plan.What == JourneyPlan.Kind.Arrived, "next: within range is arrived");
            var sealedRoom = Grid(3, 3, 7);
            for (int x = 99; x <= 103; x++) for (int y = 99; y <= 103; y++) if (!sealedRoom.Cells.ContainsKey(new Pos(x, y, 7))) sealedRoom.Set(new Pos(x, y, 7), JourneyMap.Cell.Blocked);
            plan = JourneyNav.Next(sealedRoom, new Pos(101, 101, 7), new Pos(300, 101, 7), 0, 0, null, null);
            check(plan.What == JourneyPlan.Kind.NoWay, "next: a sealed room has no way and no frontier");

            var f = Grid(6, 3, 7);
            f.Set(new Pos(105, 101, 7), JourneyMap.Cell.Change, 1);
            f.Set(new Pos(100, 100, 7), JourneyMap.Cell.Change, -1);
            plan = JourneyNav.Next(f, new Pos(101, 101, 7), new Pos(103, 101, 8), 0, 2, null, null);
            check(plan.What == JourneyPlan.Kind.Walk && plan.Target.X == 104 && plan.Path.All(p => p.X != 105), "next: to go down, walk beside the stair that goes down, not onto it");
            plan = JourneyNav.Next(f, new Pos(104, 101, 7), new Pos(103, 101, 8), 0, 2, null, null);
            check(plan.What == JourneyPlan.Kind.Step && plan.Target.X == 105, "next: next to the stair, step onto it");
            var skip = new HashSet<Pos> { new Pos(105, 101, 7) };
            plan = JourneyNav.Next(f, new Pos(104, 101, 7), new Pos(103, 101, 8), 0, 2, null, skip);
            check(plan.What != JourneyPlan.Kind.Step, "next: a stair that failed is skipped");
            check(JourneyNav.DirOf(new Pos(5, 5, 7), new Pos(5, 4, 7)) == Dir.North && JourneyNav.DirOf(new Pos(5, 5, 7), new Pos(6, 6, 7)) == Dir.SouthEast && JourneyNav.DirOf(new Pos(5, 5, 7), new Pos(4, 5, 7)) == Dir.West, "dir of a step");
        }

        static void Metrics(Action<bool, string> check)
        {
            var m = new JourneyMetrics();
            m.Begin(1000, 8, 4200, 500);
            m.Observe(1000 + 60000, 8, 4300, 500);
            m.Observe(1000 + 120000, 9, 6500, 700);
            m.Observe(1000 + 300000, 11, 12000, 650);
            check(m.Level == 11 && m.LevelAtMin[8] == 0 && Math.Abs(m.LevelAtMin[9] - 2) < 1e-9 && Math.Abs(m.LevelAtMin[10] - 5) < 1e-9 && Math.Abs(m.LevelAtMin[11] - 5) < 1e-9, "metrics: a level is stamped at the minute it was first seen, two levels at once share it");
            var per = m.MinutesPerLevel();
            check(per.Count == 3 && Math.Abs(per[8] - 2) < 1e-9 && Math.Abs(per[9] - 3) < 1e-9 && per[10] == 0, "metrics: minutes per level from the stamps");
            for (int i = 0; i < 30; i++) m.Kill(i % 3 == 0 ? "Rat [4]" : "Cave Rat [5]");
            check(m.Kills == 30 && m.KillsBy["Rat"] == 10 && m.KillsBy["Cave Rat"] == 20, "metrics: kills by base name");
            check(Math.Abs(m.Minutes - 5) < 1e-9 && Math.Abs(m.KillsPerHour - 360) < 1e-6 && Math.Abs(m.XpPerHour - (12000 - 4200) * 12) < 1e-6, "metrics: kills and experience per hour of the run");
            check(m.GoldEarned == 200 && m.GoldSpent == 50 && m.GoldNow == 650 && Math.Abs(m.GoldPerHour - 2400) < 1e-6, "metrics: gold earned and spent, per hour");
            m.Observe(1000 + 301000, 11, 11000, 650);
            check(m.Exp == 12000, "metrics: experience never goes back");
            m.Died("Troll", new Pos(1, 2, 7)); m.Stuck_("walk", new Pos(3, 4, 8), "Rat");
            m.Trips.Add(new JourneyMetrics.Trip { Reason = "cap", AtMin = 3, LevelAt = 10, Minutes = 1.5, Sold = 90 });
            var j = m.ToJson();
            check(j.ContainsKey("minutesPerLevel") && j.ContainsKey("deaths") && j.ContainsKey("stuck") && j.ContainsKey("trips") && j.ContainsKey("coverage") && (int)j["kills"] == 30, "metrics: the json carries every number the report needs");
            string text = Json.Serialize(j);
            var back = Json.Parse(text);
            check(Json.Int(back, "level") == 11 && Json.List(back, "deaths").Count == 1 && Json.Text(Json.List(back, "deaths")[0], "cause") == "Troll" && Json.List(Json.List(back, "stuck")[0], "pos").Count == 3, "metrics: the json parses back (deaths with cause and position, stuck with position)");
            var empty = new JourneyMetrics();
            check(empty.KillsPerHour == 0 && empty.XpPerHour == 0 && empty.Minutes == 0, "metrics: nothing before the first observation");
        }

        static void Coverage(Action<bool, string> check)
        {
            var c = new JourneyCoverage();
            c.Declare("opcode", "60 bank"); c.Declare("opcode", "65 passivetree"); c.Declare("town", "Cinderhold");
            c.Touch("opcode", "60 bank", 2.5, "open");
            c.Fail("opcode", "65 passivetree", 3, "no reply to requestPoints");
            check(c.Count("opcode", JourneyCoverage.State.Touched) == 1 && c.Count("opcode", JourneyCoverage.State.Failed) == 1 && c.Count("town", JourneyCoverage.State.NotTouched) == 1, "coverage: touched, failed and not touched are counted per group");
            c.Touch("opcode", "65 passivetree", 9);
            check(c.Get("opcode", "65 passivetree").What == JourneyCoverage.State.Touched && c.Get("opcode", "65 passivetree").Count == 2 && c.Get("opcode", "65 passivetree").FirstMin == 3, "coverage: a later success turns a failure into touched, the first minute stays");
            c.Fail("opcode", "60 bank", 10, "x");
            check(c.Get("opcode", "60 bank").What == JourneyCoverage.State.Failed && c.Get("opcode", "60 bank").Detail == "x", "coverage: a failure is kept with its error");
            string table = c.Table();
            check(table.Contains("opcode: 1 touched, 0 not touched, 1 failed") && table.Contains("Cinderhold: not touched") && table.Contains("(x)"), "coverage: the table lists every row with its state");
            check(c.ToJson().Count == 3 && JourneyCoverage.StateName(JourneyCoverage.State.NotTouched) == "not touched", "coverage: the json has every row");
        }
    }
}
