// Phase 30 (2026-11-09): the tester bot system checks driven through the Unity core, part 2: rifts, waystones, content rewards, chests, the line spell quest, unique passives, dual wield
// and Auto setup (O433, unity/README.md "Tester checks on the Unity core (phase 30)"). Same rules as LiveScenarios11.cs: the TEST ONLY helper (`!tester ...`) gives the facts, Core/TesterChecks.cs
// holds them to the rules of tools/tester_checks.py, and the Unity core adds the player's view where it has one (the atlas and weekly chest models, the spell list and Auto setup data, the stats and
// inventory packets, the creatures in the world).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using Chaos.Core;

namespace Chaos.Core.LiveCheck
{
    public sealed partial class LiveRun
    {
        /// <summary>The first extended message of `op` after `action` was sent; null when none came in time.</summary>
        ExtMessage TExt(LiveClient who, byte op, string action, Dictionary<string, object> data, int waitMs)
        {
            ExtMessage got = null;
            bool on = true;
            who.S.Ext.On(op, m => { if (on && got == null) got = m; });
            who.S.Ext.Send(op, action, data ?? new Dictionary<string, object>());
            WaitFor(waitMs, () => got != null);
            on = false;
            return got;
        }

        static string ExtErr(ExtMessage m)
        {
            if (m == null) return "";
            var d = m.Data as Dictionary<string, object>;
            return d != null ? TesterChecks.Err(d) : "";
        }

        // ------------------------------------------------------------------------------------ rift, rift_layout
        void ScTRift(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            var mark = Mark.Of(me);
            var problems = new StringBuilder();
            var riftOps = new List<string>();
            bool watching = true;
            s.Ext.On(228, m => { if (watching && riftOps.Count < 30) riftOps.Add(m.Action); });
            var start = me.Pos;
            // rift: the helper gives a rift key and enters; the answer must say so, then back to the hunt
            int say0 = me.Said.Count;
            var k = TSay(me, "enter rift 1", "enter", 9000);
            TGo("hunt", out _);
            string keyPart;
            if (k == null) keyPart = "skip: no answer to !tester enter rift";
            else if (TesterChecks.Err(k).Length > 0) { problems.Append("enter rift: " + Cut80(TesterChecks.Err(k)) + "; "); keyPart = "fail"; }
            else if (TesterChecks.False(k, "held") && TesterChecks.True(k, "bagFull")) keyPart = "skip: the bag is full: the key went to the inbox or the ground by design";
            else if (TesterChecks.False(k, "held")) { problems.Append("a rift key of tier " + TesterChecks.Int(k, "tier") + " was given, the backpack holds none; "); keyPart = "fail"; }
            else if (!TesterChecks.Has(k, "held")) keyPart = "skip: key given, the helper does not read it back (old helper file)";
            else keyPart = "pass: a tier " + TesterChecks.Int(k, "tier") + " key reached the backpack";
            r.Note("rift: " + keyPart + "; server lines after the command: " + me.ServerTexts(say0).Count(t => t.IndexOf("[tester-helper]", StringComparison.Ordinal) < 0));
            // rift_layout: a real run opened as a player does, read back
            int walk0 = world.Tiles.Count;
            var a = TSay(me, "riftrun layout", "riftrun", 24000);
            Pump(1500, () => false);
            watching = false;
            string layoutPart;
            if (a == null) layoutPart = "skip: no answer to !tester riftrun";
            else if (TesterChecks.Err(a).Length > 0 && !TesterChecks.Has(a, "theme")) layoutPart = "skip: " + Cut80(TesterChecks.Err(a));
            else
            {
                var bad = TesterChecks.RiftLayoutProblems(a);
                if (bad.Count > 0) { problems.Append(string.Join("; ", bad.Take(3))).Append("; "); layoutPart = "fail"; }
                else layoutPart = "pass: tier " + TesterChecks.Int(a, "tier") + " " + TesterChecks.Str(a, "theme") + " (" + TesterChecks.Str(a, "kind") + "), band " + Convert.ToString(TesterChecks.Get(a, "band"), CultureInfo.InvariantCulture) + ", " + TesterChecks.Int(a, "walkable") + " walkable, route " + TesterChecks.Int(a, "route") + ", " + TesterChecks.Int(TesterChecks.Obj(a, "sample"), "n") + " sampled tiles on the ground";
            }
            r.Note("rift_layout: " + layoutPart);
            r.Note("Unity view: the character was at " + P(start) + " before and is at " + P(me.Pos) + " after; the rift opcode (228) carried " + riftOps.Count + " message(s) (" + string.Join(",", riftOps.Distinct()) + "); map tiles known " + walk0 + " to " + world.Tiles.Count);
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) { r.Fail(problems.ToString().Trim()); return; }
            if (layoutPart.StartsWith("skip", StringComparison.Ordinal) && keyPart.StartsWith("skip", StringComparison.Ordinal)) { r.Skip(keyPart + "; " + layoutPart); return; }
            r.Pass(keyPart + "; " + layoutPart);
        }

        // ------------------------------------------------------------------------------------ waystone (atlas opcode), waystone_run
        void ScTWaystone(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            var mark = Mark.Of(me);
            var problems = new StringBuilder();
            // waystone: the atlas answers a request (opcode 159, from level 1100) without an error, and the Unity model reads it
            var atlas = s.Endgame.WaystoneAtlas;
            ExtMessage first = null;
            bool on = true;
            s.Ext.On(159, m => { if (on && first == null) first = m; });
            atlas.Tree = null; atlas.State = null;
            atlas.Open();
            WaitFor(6000, () => first != null && atlas.State != null);
            on = false;
            string atlasPart;
            if (first == null) atlasPart = "skip: waystoneAtlas open: no answer (level gate " + s.Parser.Level + " of 1100, or not installed)";
            else if (ExtErr(first).Length > 0) { problems.Append("waystoneAtlas open answered an error: " + Cut80(ExtErr(first)) + "; "); atlasPart = "fail"; }
            else
            {
                atlasPart = "pass: the atlas answered '" + first.Action + "', the Unity model holds " + (atlas.Tree != null ? "the tree" : "no tree") + " and " + (atlas.State != null ? "the state (" + atlas.Points.ToString("0", CultureInfo.InvariantCulture) + " points)" : "no state");
                if (atlas.State == null) problems.Append("the Unity atlas model read no state from the server's answer; ");
            }
            atlas.Hide();
            r.Note("waystone: " + atlasPart);
            // waystone_run: one tier of each band; the helper does what the device does (a Rare waystone, the take, the run on a map of the band)
            int seen = 0;
            var notes = new List<string>();
            string skip = null;
            foreach (int t in TesterChecks.WaystoneTiers)
            {
                var a = TSay(me, "waystone " + t, "waystone", 17000);
                if (a == null) { skip = "no answer to !tester waystone " + t; break; }
                string err = TesterChecks.Err(a);
                if (err.StartsWith("startRun", StringComparison.Ordinal)) { problems.Append("tier " + t + ": ChaosWaystoneTiers." + Cut(err, 90) + "; "); notes.Add("tier " + t + ": fail"); break; }
                if (err.Length > 0)
                {
                    if (err == "no waystone system") { skip = err; break; }
                    notes.Add("tier " + t + ": " + Cut(err, 40));
                    continue;
                }
                var bad = TesterChecks.WaystoneProblems(a);
                if (bad.Count > 0) { problems.Append("tier " + t + ": " + string.Join("; ", bad.Take(3))).Append("; "); notes.Add("tier " + t + ": fail"); break; }
                seen++;
                notes.Add("tier " + t + ": " + TesterChecks.Int(a, "nrolled") + " mods, " + TesterChecks.Rows(a, "monsters").Count + " monster(s) sampled");
            }
            r.Note("waystone_run: " + string.Join("; ", notes));
            Pump(1500, () => false);
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) { r.Fail(problems.ToString().Trim()); return; }
            if (seen == 0) { r.Skip((skip ?? string.Join("; ", notes)) + " (waystone_run); " + atlasPart); return; }
            r.Pass(atlasPart.StartsWith("pass", StringComparison.Ordinal) ? "atlas answered and read by the Unity model; " + string.Join("; ", notes) : string.Join("; ", notes) + " (" + atlasPart + ")");
        }

        static string Cut(string t, int n) => t != null && t.Length > n ? t.Substring(0, n) : t ?? "";

        // ------------------------------------------------------------------------------------ content_rewards
        void ScTLoot(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            var mark = Mark.Of(me);
            var parts = new List<string>();
            int ran = 0;
            var a = TSay(me, "waystone " + TesterChecks.LootTier + " loot", "waystone", 17000);
            if (a == null) { r.Skip("no answer to !tester waystone " + TesterChecks.LootTier + " loot"); return; }
            var loot = TesterChecks.Obj(a, "loot");
            if (TesterChecks.Err(a).Length > 0 || loot.Count == 0) parts.Add("waystone boss not checked: " + Cut(TesterChecks.Err(a).Length > 0 ? TesterChecks.Err(a) : "no loot answer", 50));
            else if (TesterChecks.Err(loot).Length > 0) parts.Add("waystone boss not checked: " + Cut(TesterChecks.Err(loot), 50));
            else
            {
                var bad = TesterChecks.WaystoneLootProblems(loot);
                if (bad.Count > 0) { r.Fail("waystone boss: " + string.Join("; ", bad.Take(3))); return; }
                ran++;
                parts.Add("waystone boss: " + TesterChecks.Int(loot, "pieces") + " piece(s), " + TesterChecks.Rows(loot, "orbs").Count + " sure orb kinds, " + TesterChecks.Int(loot, "waystones") + " waystone(s)");
            }
            var g = TSay(me, "riftrun loot", "riftrun", 24000);
            var rl = TesterChecks.Obj(g, "loot");
            if (g == null || rl.Count == 0 || TesterChecks.Err(rl).Length > 0)
                parts.Add("rift guardian not checked: " + Cut(g == null ? "no answer" : TesterChecks.Err(g).Length > 0 ? TesterChecks.Err(g) : TesterChecks.Err(rl).Length > 0 ? TesterChecks.Err(rl) : "no loot answer", 50));
            else
            {
                if (!TesterChecks.True(rl, "paid") || TesterChecks.Int(rl, "orbs") < TesterChecks.Int(rl, "minOrbs"))
                {
                    r.Fail("rift guardian: " + TesterChecks.Int(rl, "orbs") + " orb(s) (paid " + TesterChecks.True(rl, "paid") + "), the config guarantees " + TesterChecks.Int(rl, "minOrbs") + " (run tier " + TesterChecks.Int(rl, "runTier") + ", quantity " + TesterChecks.Int(rl, "quantity") + ")");
                    return;
                }
                ran++;
                parts.Add("rift guardian: " + TesterChecks.Int(rl, "orbs") + " orbs");
            }
            Pump(1500, () => false);
            string diff = mark.Diff(me, "primary");
            if (diff.Length > 0) { r.Fail(diff.Trim()); return; }
            if (ran == 0) r.Skip(string.Join("; ", parts)); else r.Pass(string.Join("; ", parts));
        }

        // ------------------------------------------------------------------------------------ reward_chest, cursed_chest
        /// <summary>How many items of each id lie on the tiles within `reach` of the player, as the Unity world shows them.</summary>
        Dictionary<int, int> NearItems(int reach)
        {
            var o = new Dictionary<int, int>();
            var at = me.Pos;
            for (int dx = -reach; dx <= reach; dx++)
                for (int dy = -reach; dy <= reach; dy++)
                {
                    var t = world.Get(new Pos(at.X + dx, at.Y + dy, at.Z));
                    if (t != null) foreach (var th in t.Things) if (!th.IsCreature && th.Item != null) { o.TryGetValue(th.Item.Id, out int n); o[th.Item.Id] = n + 1; }
                }
            return o;
        }

        void ScTChests(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            var mark = Mark.Of(me);
            var problems = new StringBuilder();
            // reward_chest: the weekly chest window answers (opcode 117) without an error, and the Unity model reads the state
            var weekly = s.Weekly;
            weekly.State = null;
            ExtMessage first = null;
            bool on = true;
            s.Ext.On(117, m => { if (on && first == null) first = m; });
            weekly.Show();
            WaitFor(6000, () => first != null);
            on = false;
            string weeklyPart;
            if (first == null) weeklyPart = "skip: weeklyChest open: no answer (level gate, or not installed)";
            else if (ExtErr(first).Length > 0) { problems.Append("weeklyChest open answered an error: " + Cut80(ExtErr(first)) + "; "); weeklyPart = "fail"; }
            else weeklyPart = "pass: the weekly chest answered '" + first.Action + "', the Unity model " + (weekly.State != null ? "read the state" : "read no state");
            weekly.Hide();
            r.Note("reward_chest: " + weeklyPart);
            // cursed_chest: a chest next to the bot: spawn, use (the horde starts), abort; nothing may be left. The Unity world shows the chest and the horde.
            if (!TGo("hunt", out _)) { r.Note("cursed_chest: the helper could not bring the bot to its hunt spot"); }
            var before = NearItems(2);
            var monstersBefore = new HashSet<uint>(world.Creatures.Values.Where(c => c.Type == 1).Select(c => c.Id));
            var spawn = TSay(me, "chest spawn", "chest", 6000);
            string chestPart;
            var chestIds = new List<int>();
            if (spawn == null) chestPart = "skip: no answer to !tester chest";
            else if (TesterChecks.Err(spawn).Length > 0) chestPart = "skip: " + Cut80(TesterChecks.Err(spawn));
            else
            {
                Pump(1200, () => false);
                var appeared = NearItems(2).Where(kv => !before.TryGetValue(kv.Key, out int n0) || kv.Value > n0).Select(kv => kv.Key).ToList();   // the hunt spot is a rat cave: corpses of the bot's own kills come and go, only the ids that appeared with the spawn count
                bool idle = TesterChecks.Str(spawn, "state") == "idle";
                var use = idle ? TSay(me, "chest use", "chest", 6000) : null;
                Pump(3000, () => false);
                var state = idle ? TSay(me, "chest state", "chest", 6000) : null;
                int horde = world.Creatures.Values.Count(c => c.Type == 1 && c.Position.X > 0 && !monstersBefore.Contains(c.Id));
                var abort = TSay(me, "chest abort", "chest", 6000);
                Pump(1000, () => false);
                var z = TSay(me, "chest state", "chest", 6000) ?? abort;
                var bad = TesterChecks.ChestProblems(spawn, use, state, z);
                chestIds.AddRange(appeared);
                if (!idle) { TSay(me, "chest abort", "chest", 6000); }
                if (appeared.Count == 0) bad.Add("the Unity world shows no new item next to the character after the chest spawned");
                r.Note("cursed_chest: spawned (" + TesterChecks.Str(spawn, "state") + "), Unity saw " + appeared.Count + " new item(s) near the bot (ids " + string.Join(",", appeared.Take(4)) + "), after use '" + TesterChecks.Str(use, "state") + "' with horde " + TesterChecks.Int(state, "horde") + " made " + TesterChecks.Int(state, "made") + ", Unity saw " + horde + " new monster(s), after abort '" + TesterChecks.Str(z, "state") + "'");
                if (bad.Count > 0) { problems.Append(string.Join("; ", bad)).Append("; "); chestPart = "fail"; }
                else chestPart = "pass: spawn, use, abort: the chest and its monsters are gone";
            }
            Pump(800, () => false);
            var now = NearItems(2);
            var leftOver = chestIds.Where(id => now.TryGetValue(id, out int n1) && n1 > (before.TryGetValue(id, out int n0) ? n0 : 0)).ToList();
            if (chestPart.StartsWith("pass", StringComparison.Ordinal) && leftOver.Count > 0) problems.Append("the Unity world still shows the chest item(s) " + string.Join(",", leftOver) + " next to the character after the chest was aborted; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) { r.Fail(problems.ToString().Trim()); return; }
            if (weeklyPart.StartsWith("skip", StringComparison.Ordinal) && chestPart.StartsWith("skip", StringComparison.Ordinal)) { r.Skip(weeklyPart + "; " + chestPart); return; }
            r.Pass(weeklyPart + "; " + chestPart);
        }

        // ------------------------------------------------------------------------------------ spell_quest
        static bool SameValue(object got, object want)
        {
            if (want is bool wb) return got is bool gb && gb == wb;
            if (want is string ws) return got is string gs && gs == ws;
            if (want is int || want is long) return got is double gd && Math.Abs(gd - Convert.ToInt64(want, CultureInfo.InvariantCulture)) < 0.5;
            return Equals(got, want);
        }

        /// <summary>One `!tester spellquest COMMAND`; the problem names the first wrong field of `want` (a value, or a rule as Func).</summary>
        Dictionary<string, object> QStep(string command, out string problem, params (string Key, object Want)[] want)
        {
            var a = TSay(me, "spellquest " + command, "spellquest", 7000);
            problem = null;
            if (a == null) { problem = "no answer to !tester spellquest " + command; return null; }
            if (TesterChecks.Err(a).Length > 0) { problem = "spellquest " + command + ": " + Cut80(TesterChecks.Err(a)); return a; }
            foreach (var (key, val) in want)
            {
                if (val is Func<Dictionary<string, object>, bool> rule) { if (!rule(a)) { problem = "spellquest " + command + ": " + key + " is " + TesterChecks.Get(a, key); return a; } }
                else if (!SameValue(TesterChecks.Get(a, key), val)) { problem = "spellquest " + command + ": " + key + " is " + TesterChecks.Get(a, key) + ", expected " + val; return a; }
            }
            return a;
        }

        void ScTSpellQuest(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            if (s.Parser.Level < TesterChecks.QuestLevel) { r.Skip("the first quest opens at level " + TesterChecks.QuestLevel + " (the bot is level " + s.Parser.Level + ")"); return; }
            var mark = Mark.Of(me);
            var a = QStep("reset", out string bad);
            if (bad != null)
            {
                if (a == null || bad.Contains("no spell quest system") || bad.Contains("no class line")) { r.Skip(bad); return; }
                r.Fail(bad);
                return;
            }
            int lv = (int)TesterChecks.Int(a, "level", s.Parser.Level);
            if (lv < TesterChecks.QuestLevel) { r.Skip("the first quest opens at level " + TesterChecks.QuestLevel + " (the bot is level " + lv + " now)"); return; }
            var done = new List<string>();
            string failure = null, skip = null;
            try
            {
                for (int n = 1; n <= TesterChecks.QuestLevels.Length; n++)
                {
                    if (lv < TesterChecks.QuestLevels[n - 1]) break;
                    string res = OneSpellQuest(r, lv, n, out string detail);
                    if (res == "fail") { failure = detail; break; }
                    if (res == "skip") { if (done.Count > 0) break; skip = detail; break; }
                    done.Add(detail);
                }
            }
            finally
            {
                QStep("reset", out _);
                TGo("hunt", out _);
            }
            string diff = mark.Diff(me, "primary");
            if (failure != null || diff.Length > 0) { r.Fail(((failure ?? "") + " " + diff).Trim()); return; }
            if (skip != null && done.Count == 0) { r.Skip(skip); return; }
            var later = TesterChecks.QuestLevels.Skip(done.Count).ToList();
            r.Pass(string.Join(" | ", done) + (later.Count > 0 ? "; quests at level " + string.Join(", ", later) + " not reached (level " + lv + ")" : ""));
        }

        /// <summary>One line spell quest of the character's class, end to end: "pass", "skip" or "fail" with the text.</summary>
        string OneSpellQuest(ScenarioResult r, int lv, int n, out string detail)
        {
            string F(string text) => "quest " + n + ": " + text;
            var a = QStep("state", out string bad, ("quest", n), ("code", "ok"), ("step", 0));
            if (bad != null) { detail = F("level " + lv + ", " + (n == 1 ? "fresh" : "after quest " + (n - 1)) + ": " + bad); return "fail"; }
            string spell = TesterChecks.Str(a, "spell");
            var need = TesterChecks.Obj(a, "need");
            if (spell.Length == 0 || TesterChecks.Int(need, "kills") == 0) { detail = F("the state names no spell or hunt"); return "fail"; }
            QStep("set " + n + " 1 0 0", out bad, ("step", 1), ("kills", 0), ("fragments", 0));
            if (bad != null) { detail = F(bad); return "fail"; }
            QStep("kill 3", out bad, ("counted", 3), ("kills", 3));
            if (bad != null) { detail = F("kills do not count: " + bad); return "fail"; }
            Func<Dictionary<string, object>, bool> fragment = x => TesterChecks.Int(x, "fragments") >= 1;
            QStep("kill 45", out bad, ("counted", 45), ("kills", 48), ("fragments", fragment));
            if (bad != null) { detail = F("no fragment within 41 counted kills (pity): " + bad); return "fail"; }
            QStep("kill boss", out bad, ("weight", 25), ("kills", 73));
            if (bad != null) { detail = F("a boss kill does not count 25: " + bad); return "fail"; }
            QStep("set " + n + " 2", out bad, ("step", 2), ("kills", TesterChecks.Int(need, "kills")), ("fragments", TesterChecks.Int(need, "fragments")));
            if (bad != null) { detail = F("the trial step: " + bad); return "fail"; }
            // Archivist Odrenna stands in the world (placed at startup in her stall); the helper takes the bot to her
            int modal0 = Seen(0xFA);
            var at = TSay(me, "enter npc Archivist Odrenna", "enter", 9000);
            if (at == null) { detail = F("no answer to !tester enter npc Archivist Odrenna"); return "skip"; }
            if (TesterChecks.Err(at).Length > 0) { detail = F("Archivist Odrenna is not in the game (" + Cut(TesterChecks.Err(at), 60) + "): placement at startup failed or her XML did not load"); return "fail"; }
            Pump(1200, () => false);
            var trial = QStep("trial", out bad, ("near", true), ("entered", true), ("running", true));
            if (bad != null) { detail = F("the trial does not open at Odrenna (" + Cut(TesterChecks.Str(trial, "text"), 60) + "): " + bad); return "fail"; }
            r.Note("quest " + n + ": trial opened at the Archivist; Unity saw " + (Seen(0xFA) - modal0) + " modal window(s) meanwhile and is at " + P(me.Pos));
            QStep("leave", out bad, ("left", true), ("running", false));
            if (bad != null) { detail = F("the trial run could not be left: " + bad); return "fail"; }
            Func<Dictionary<string, object>, bool> gold = x => TesterChecks.Int(x, "gold") == TesterChecks.QuestGold * lv;
            QStep("complete", out bad, ("completed", n), ("taught", spell), ("taughtKnown", true), ("gold", gold));
            if (bad != null) { detail = F("the reward: " + bad); return "fail"; }
            // the spell is on the server for the class and in the Auto setup data, seen as the Unity client sees them: the spell list (reloaded) and the rotation data
            var book = s.Spells;
            bool reloaded = false;
            book.Changed += () => reloaded = true;
            book.Sig = null;
            book.Open(true);
            WaitFor(6000, () => reloaded);
            var sp = book.Spells.FirstOrDefault(x => string.Equals(x.Name, spell, StringComparison.OrdinalIgnoreCase));
            int voc = book.Vocation != 0 ? book.Vocation : vocation;
            var row = HelperRotation.ClassOf(voc);
            var problems = sp == null ? null : TesterChecks.QuestSpellProblems(sp, lv, book.Status(sp) != SpellStatus.Vocation, row, id => HelperSupport.Kinds.TryGetValue(id, out var k) && (k.Auto == "timer" || (k.Auto == "support" && k.Fight)));
            if (problems == null) { detail = F(spell + " is learned but not in the spell list the Unity client got from the server"); return "fail"; }
            if (book.Status(sp) != SpellStatus.Ready) problems.Add(spell + " is " + book.Status(sp) + " in the Unity spell list after the quest, expected Ready");
            if (problems.Count > 0) { detail = F(string.Join("; ", problems.Take(3))); return "fail"; }
            var parts = new List<string>();
            if (n == 1) { parts.Add("48 kills, fragment, boss 25"); parts.Add("trial opened at Odrenna"); parts.Add(spell + " learned"); }
            else parts.Add("quest " + n + " (level " + TesterChecks.QuestLevels[n - 1] + "): " + spell + " learned");
            parts.Add("Ready in the Unity spell list");
            if (row != null) parts.Add("in the Auto setup data");
            detail = string.Join(", ", parts);
            return "pass";
        }

        // ------------------------------------------------------------------------------------ unique_passive
        void ScTUnique(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            var mark = Mark.Of(me);
            int set0 = Seen(0x78), clear0 = Seen(0x79);
            var u = TSay(me, "unique", "unique", 8000);
            Pump(1500, () => false);
            if (u == null) { r.Skip("no answer to !tester unique (an old helper file, or the bot died)"); return; }
            if (TesterChecks.Err(u).Length > 0) { r.Skip(TesterChecks.Err(u)); return; }
            if (TesterChecks.Int(u, "lostBefore") == 0) { r.Skip("the hit before the unique was worn took no health"); return; }
            var bad = TesterChecks.UniqueProblems(u);
            int set = Seen(0x78) - set0, clear = Seen(0x79) - clear0;
            r.Note("unique: family " + TesterChecks.Str(u, "family") + ", item " + TesterChecks.Int(u, "id") + ", slot " + TesterChecks.Int(u, "slot") + ", health lost before " + TesterChecks.Int(u, "lostBefore") + " after " + TesterChecks.Int(u, "lostAfter") + " (hit " + TesterChecks.Int(u, "hit") + (TesterChecks.Has(u, "lostFirst") ? ", first plain hit " + TesterChecks.Int(u, "lostFirst") : "") + "), rule m " + TesterChecks.Num(u, "m").ToString("0.000", CultureInfo.InvariantCulture) + ", crit " + TesterChecks.True(u, "crit") + "; the Unity client read " + set + " inventory set (0x78) and " + clear + " clear (0x79) packet(s) meanwhile");
            if (bad.Count == 0 && (set < 1 || clear < 1)) bad.Add("the helper wore and removed the unique, the Unity client read " + set + " inventory set and " + clear + " clear packet(s)");
            string diff = mark.Diff(me, "primary");
            if (bad.Count > 0 || diff.Length > 0) { r.Fail((string.Join("; ", bad) + " " + diff).Trim()); return; }
            r.Pass(TesterChecks.Str(u, "family") + " (item " + TesterChecks.Int(u, "id") + ", " + TesterChecks.Str(u, "line") + " line): hit " + TesterChecks.Int(u, "lostBefore") + " -> " + TesterChecks.Int(u, "lostAfter") + ", rule x" + TesterChecks.Num(u, "m").ToString("0.000", CultureInfo.InvariantCulture) + (TesterChecks.True(u, "crit") ? " (critical)" : "") + "; worn and removed as the Unity client saw it");
        }

        // ------------------------------------------------------------------------------------ dual_fists, dual_blades
        void ScTDual(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            var mark = Mark.Of(me);
            var problems = new StringBuilder();
            var lines = new List<string>();
            int skips = 0;
            foreach (string kind in new[] { "fists", "blades" })
            {
                int set0 = Seen(0x78);
                bool demon = false;
                // the Demon the helper makes next to the bot while it watches is seen in the Unity world
                var f = TSay(me, kind, kind, 20000, () => { if (!demon && world.Creatures.Values.Any(c => c.Type == 1 && c.Position.X > 0 && BaseName(c.Name) == "Demon")) demon = true; });
                Pump(800, () => false);
                if (f == null) { lines.Add(kind + ": skip, no answer"); skips++; continue; }
                if (TesterChecks.Err(f).Length > 0) { lines.Add(kind + ": skip, " + Cut80(TesterChecks.Err(f))); skips++; continue; }
                var bad = TesterChecks.DualProblems(f, kind);
                if (bad.Count > 0) { problems.Append(kind + ": " + string.Join("; ", bad)).Append("; "); continue; }
                int set = Seen(0x78) - set0;
                if (!TesterChecks.True(f, "able"))
                {
                    lines.Add(kind + ": " + (kind == "fists" ? "a fist weapon is refused outside the Monk line (code " + TesterChecks.Int(f, "left") + ")" : "a dagger is refused in the shield hand (code " + TesterChecks.Int(f, "right") + ")"));
                    continue;
                }
                if (TesterChecks.Int(f, "melee") == 0) { lines.Add(kind + ": skip, both worn but no melee hit landed in the watch"); skips++; continue; }
                // both items went into the hands: the Unity client read the inventory sets
                if (set < 2) problems.Append(kind + ": both items were worn, the Unity client read " + set + " inventory set packet(s)" + "; ");
                lines.Add(kind + ": both worn; " + TesterChecks.Int(f, "melee") + " melee hits, " + TesterChecks.Int(f, "off") + " off-hand strikes (" + TesterChecks.Int(f, "offSum") + " damage); Unity read " + set + " inventory sets" + (demon ? ", saw the Demon" : ", the Demon was gone by the end of the watch"));
            }
            foreach (var l in lines) r.Note(l);
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) { r.Fail(problems.ToString().Trim()); return; }
            if (skips == 2) { r.Skip(string.Join("; ", lines)); return; }
            r.Pass(string.Join("; ", lines));
        }

        // ------------------------------------------------------------------------------------ auto_setup
        void ScTAuto(ScenarioResult r)
        {
            if (!TesterReady(r)) return;
            var mark = Mark.Of(me);
            var book = s.Spells;
            if (!book.Loaded) { book.Open(true); WaitFor(6000, () => book.Loaded); }
            if (!book.Loaded || book.Spells.Count == 0) { r.Skip("the spell list did not come"); return; }
            int voc = book.Vocation != 0 ? book.Vocation : vocation;
            var row = HelperRotation.ClassOf(voc);
            int lv = s.Parser.Level;
            var bad = TesterChecks.AutoSetupProblems(row, lv, book.ById, book.Status);
            if (bad == null) { r.Skip("the class is not in the rotation data"); return; }
            // the Helper engine the way the Unity window makes it: Auto setup picks the rotation from the same list, and every slot it fills is a spell the list says is ready
            var engine = new HelperEngine(book, new SessionHelperHost(s));
            string msg = engine.AutoSetup(voc);
            var slots = engine.Config.Shooter.Where(x => x.Id > 0).Select(x => x.Id).ToList();
            foreach (int id in slots)
            {
                var sp = book.ById(id);
                if (sp == null) bad.Add("the Helper's Auto setup put spell " + id + " in a slot, the server's list does not hold it");
                else if (book.Status(sp) != SpellStatus.Ready) bad.Add("the Helper's Auto setup put " + sp.Name + " (" + id + ") in a slot, the list says " + book.Status(sp));
            }
            var preset = HelperRotation.PresetFor(voc, lv, out int idx);
            r.Note("class " + row.Name + ", level " + lv + ": preset " + (preset != null ? "#" + idx + " of level " + preset.Level : "none") + ", Auto setup message '" + (msg ?? "none") + "', " + slots.Count + " shooter slot(s)");
            string diff = mark.Diff(me, "primary");
            if (bad.Count > 0 || diff.Length > 0) { r.Fail((string.Join("; ", bad.Take(3)) + " " + diff).Trim()); return; }
            r.Pass("the preset of level " + lv + " is castable (every spell is in the server's list and ready), and the Unity Helper's Auto setup filled " + slots.Count + " slot(s) from it");
        }
    }
}
