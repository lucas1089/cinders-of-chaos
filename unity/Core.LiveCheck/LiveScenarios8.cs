// The first hour gaps of phase 28 (O433): questlog (the base quest log, the client's requests 0xF0 and 0xF1 and the server's answers, read to the last byte) and firstunlock (a fresh
// character kills the first weak monsters until its class opens a new spell, and the unlock is read by the spell's name: the spell list, the Helper's level up notice, a toast).
// Same rules as LiveScenarios.cs: opt-in by --scenario, a time limit, a pass, fail or skip with the reason, names scrubbed from the reports. Neither needs a staff right or a local
// script. unity/README.md "First hour gaps (phase 28)".
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace Chaos.Core.LiveCheck
{
    public sealed partial class LiveRun
    {
        // ------------------------------------------------------------------------------------ questlog
        /// <summary>The base quest log on the wire: 0xF0 asks for the log (the server's list of started quests: u16 count, per quest u16 id, name, completed), 0xF1 with a quest id asks
        /// for its mission lines (the started missions: name and description). The scenario sends both the way the Quest Log window does (request on open, a pick asks the lines), checks
        /// that each answer came, that the log and the lines were read to the last byte (no parse failure, no unknown packet) and that a second request gives the same log. A new
        /// character has no started quest: the log is empty and the lines of the first quest of the base server (id 1) are an empty list, which is read as such.</summary>
        void ScQuestLog(ScenarioResult r)
        {
            var p = s.Parser;
            var problems = new StringBuilder();
            var mark = Mark.Of(me);
            int unknown0 = p.Failures.Count(f => f.Unknown);
            // the log
            int n0 = Seen(0xF0);
            p.Quests.Request();
            bool got = WaitFor(4000, () => Seen(0xF0) > n0);
            if (!got) { r.Fail("no answer to the quest log request (0xF0) in 4 s"); return; }
            Pump(300, () => false);
            var log = p.Quests.Quests.Select(q => (q.Id, q.Name, q.Completed)).ToList();
            string names = string.Join(", ", log.Take(4).Select(q => q.Name + (q.Completed ? " (done)" : "")));
            r.Note("0xF0 answered: " + log.Count + " quest(s), " + p.Quests.Done() + " done" + (log.Count > 0 ? " [" + names + "]" : " (a character that started no quest has an empty log)") + ", summary '" + p.Quests.Summary() + "'");
            if (!p.Quests.Loaded) problems.Append("the quest log answered and the state is not loaded; ");
            foreach (var q in log) if (q.Name.Length == 0 || q.Id == 0) problems.Append("a quest of the log has no name or no id (" + q.Id + "); ");
            if (log.Select(q => q.Id).Distinct().Count() != log.Count) problems.Append("a quest id comes twice in the log; ");
            // the lines of one quest: the first of the log, else the first quest of the base server
            ushort id = log.Count > 0 ? (log.Any(q => !q.Completed) ? log.First(q => !q.Completed).Id : log[0].Id) : (ushort)1;
            int l0 = Seen(0xF1);
            p.Quests.Select(id);
            bool gotLine = WaitFor(4000, () => Seen(0xF1) > l0);
            Pump(300, () => false);
            var lines = p.Quests.Missions(id);
            if (!gotLine) problems.Append("no answer to the quest line request (0xF1, quest " + id + ") in 4 s; ");
            else if (lines == null) problems.Append("0xF1 came and the lines of quest " + id + " are not kept (an answer for another quest id?); ");
            else
            {
                r.Note("0xF1 answered for quest " + id + (log.Count > 0 ? " '" + log.First(q => q.Id == id).Name + "'" : " (the first quest of the base server; the log was empty)") + ": " + lines.Count + " mission line(s)" + (lines.Count > 0 ? " [" + string.Join(" | ", lines.Take(3).Select(m => m.Name + ": " + (m.Description.Length > 60 ? m.Description.Substring(0, 60) + "..." : m.Description))) + "]" : ""));
                foreach (var m in lines) if (m.Name.Length == 0) problems.Append("a mission line of quest " + id + " has no name; ");
            }
            // a completed quest (phase 29): the log's flag is read, and the line of it names its done missions "... (completed)" (base Mission::getName). A new character has none: its
            // quests need NPC chains far from the temple, so a completed one is seen only on a character whose storage rows were set in the local db (not play), and only noted here
            var done = log.Where(q => q.Completed).ToList();
            if (done.Count > 0)
            {
                ushort did = done[0].Id;
                int l1 = Seen(0xF1);
                p.Quests.Select(did);
                bool gotDone = WaitFor(4000, () => Seen(0xF1) > l1);
                Pump(300, () => false);
                var dl = p.Quests.Missions(did);
                if (!gotDone || dl == null) problems.Append("no line for the completed quest " + did + "; ");
                else
                {
                    int marked = dl.Count(m => m.Name.EndsWith("(completed)", StringComparison.Ordinal));
                    r.Note("completed quest " + did + " '" + done[0].Name + "': " + dl.Count + " mission line(s), " + marked + " marked (completed) [" + string.Join(" | ", dl.Take(3).Select(m => m.Name)) + "], hide completed leaves " + (p.Quests.Quests.Count - done.Count) + " of " + p.Quests.Quests.Count + ", summary '" + p.Quests.Summary() + "'");
                    if (dl.Count == 0) problems.Append("the completed quest " + did + " lists no mission; ");
                    else if (marked == 0) problems.Append("the completed quest " + did + " has no mission marked (completed); ");
                    p.Quests.HideCompleted = true;
                    if (p.Quests.Visible().Count != p.Quests.Quests.Count - done.Count) problems.Append("hide completed leaves " + p.Quests.Visible().Count + " rows; ");
                    p.Quests.HideCompleted = false;
                }
            }
            else r.Note("no completed quest in the log: a new character has none (the base quests need NPC chains far from the temple; a completed one is checked on a character with its storage rows set in the local db)");
            // the same request again: the same log (the server's state did not change)
            int n1 = Seen(0xF0);
            p.Quests.Request();
            bool again = WaitFor(4000, () => Seen(0xF0) > n1);
            Pump(300, () => false);
            if (!again) problems.Append("no answer to the second quest log request; ");
            else if (p.Quests.Quests.Count != log.Count) problems.Append("the second quest log holds " + p.Quests.Quests.Count + " quest(s), the first held " + log.Count + "; ");
            r.Note("packets: 0xF0 x" + (Seen(0xF0) - n0) + ", 0xF1 x" + (Seen(0xF1) - l0) + ", unknown packet types +" + (p.Failures.Count(f => f.Unknown) - unknown0) + ", parse failures +" + (p.FailureCount - mark.Failures));
            if (p.Failures.Count(f => f.Unknown) > unknown0) problems.Append("an unknown packet type came after the quest requests; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("0xF0 and 0xF1 answered and read to the last byte: " + log.Count + " quest(s) in the log, " + (lines == null ? 0 : lines.Count) + " mission line(s) of quest " + id + ", the same log on the second request, no unread packet");
        }

        // ------------------------------------------------------------------------------------ firstunlock
        /// <summary>The time a first spell unlock may take for the scenario to be honest: three minutes from the temple, walk included.</summary>
        public const int FirstUnlockLimitMs = 170000;

        /// <summary>The first class spell that opens by level: a fresh character (raised to level 8 by its first login) hunts the Rats of the cellars under Cinderhold with its first attack spell
        /// until its level reaches the level of the lowest spell that waits for a level (every spell that opens at that level counts), at most three minutes. Each unlock is read by the
        /// spell's name: the spell list shows the spell as ready (it waited for its level before), the Helper's level up notice (the main client's autorotation_ui.lua box, Core
        /// HelperEngine.LevelWatch after an Auto setup) names an attack spell when the rotation takes it, and the toast text carries the name. Opcode 115 'new' (a system unlock of that
        /// level) is read next to it. A character whose next spell is too far to reach in the time skips, with the experience rate it measured (the Rat spawns are the limit: the first
        /// ones fall in seconds, then the hunt waits for respawns). No staff command, no calm, no loot.</summary>
        void ScFirstUnlock(ScenarioResult r)
        {
            var p = s.Parser;
            if (p.Level > 150) { r.Skip("character level " + p.Level + ": the first hour scenarios are for a new character; run them on a character made for the run"); return; }
            if (floorChanges == null) { r.Skip("no items.xml: the stairs down to the first hunt come from it (--items-xml, or the file beside items.otb)"); return; }
            var problems = new StringBuilder();
            var mark = Mark.Of(me);
            if (!s.Spells.Loaded) { s.Spells.Open(); WaitFor(5000, () => s.Spells.Loaded); }
            if (!s.Spells.Loaded) { r.Skip("the spell list (opcode 219) did not arrive in 5 s"); return; }
            int voc = s.Spells.Vocation != 0 ? s.Spells.Vocation : world.PlayerVocation;
            var book = s.Spells;
            // the lowest spell that waits for its level (an attack spell first when two share the level) and the others that open at the same level
            var waiting = book.Spells.Where(x => !x.IsRune && book.Status(x) == SpellStatus.Level && x.Level > p.Level && x.MagicLevel <= p.MagicLevel).OrderBy(x => x.Level).ThenBy(x => x.Kind == "attack" ? 0 : 1).ToList();
            var first = waiting.FirstOrDefault();
            if (first == null) { r.Skip("no spell waits for a level above " + p.Level + " in the list of " + book.Spells.Count + " (vocation " + voc + ")"); return; }
            var targets = waiting.Where(x => x.Level == first.Level).ToList();
            var attack = book.Spells.Where(x => !x.IsRune && x.Kind == "attack" && book.Status(x) == SpellStatus.Ready).OrderBy(x => x.Level).ThenBy(x => x.Mana).FirstOrDefault();
            var readyBefore = book.Visible(SpellBook.FilterLearned, "all", "").Select(x => x.Name).ToList();
            long exp0 = (long)p.Experience;
            int level0 = p.Level;
            r.Note("character level " + level0 + ", " + readyBefore.Count + " spell(s) ready; the spells that wait for a level, next first: " + string.Join(", ", waiting.Take(4).Select(x => "'" + x.Name + "' (" + x.Kind + ") L" + x.Level)) + "; targets: " + string.Join(", ", targets.Select(x => "'" + x.Name + "' at " + x.Level)) + "; first attack spell: " + (attack == null ? "none (melee only)" : attack.Name));
            // the Helper after its first Auto setup (the welcome toast opens it on that button): a level up asks about new spells by name
            var engine = new HelperEngine(book, new SessionHelperHost(s));
            engine.LevelWatch(voc);
            string setup = engine.AutoSetup(voc);
            r.Note("Auto setup before the hunt: " + (setup == null ? "no rotation for this class and level" : setup));
            var notices = new List<(int level, string names, string line)>();
            int unlocks0 = ops.TryGetValue(115, out var u0) ? u0.Replies : 0;
            var announced = new List<string>();
            object lastAnn = null;
            long t0 = 0;
            var reached = new Dictionary<Spell, (double secs, SpellStatus status, int ready, List<string> added)>();
            void Watch()
            {
                engine.LevelWatch(voc);
                if (engine.LevelNotice != null)
                {
                    notices.Add((p.Level, engine.LevelNotice.List, engine.LevelNotice.Line));
                    engine.LevelNotice = null;   // answered (Ignore): the next level asks again
                }
                var ann = s.Progress?.Unlocks?.Announcement;
                if (ann != null && !ReferenceEquals(ann, lastAnn)) { lastAnn = ann; announced.Add("L" + ann.Level + " " + ann.Key + " '" + ann.Title + "'"); }
                foreach (var t in targets)
                {
                    if (reached.ContainsKey(t) || p.Level < t.Level) continue;
                    var now = book.Visible(SpellBook.FilterLearned, "all", "").Select(x => x.Name).ToList();
                    reached[t] = ((Tick - t0) / 1000.0, book.Status(t), now.Count, now.Where(x => !readyBefore.Contains(x)).ToList());
                }
            }
            s.SetFightModes(new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = true });
            Pump(300, () => false);
            t0 = Tick;
            var mon = ReachMonster(r, "Rat", problems);
            if (mon == null)
            {
                r.Skip("no Rat in view after going down and walking to the known grounds (at " + P(me.Pos) + ")" + (problems.Length > 0 ? ": " + problems.ToString().Trim() : ""));
                return;
            }
            int kills = 0, waits = 0;
            while (Tick - t0 < FirstUnlockLimitMs && reached.Count < targets.Count && s.Closed == null)
            {
                if (mon == null || !world.Creatures.ContainsKey(mon.Id)) mon = NearestMonster(me, "Rat", true);
                if (mon == null)
                {
                    // the spawns are empty until they respawn: wait a little, then try the other grounds (the loop ends with the time limit)
                    waits++;
                    if (waits <= 3 || waits % 4 != 0) { Pump(2000, () => NearestMonster(me, "Rat", true) != null); mon = NearestMonster(me, "Rat", true); if (mon != null) continue; }
                    foreach (var g in RatGrounds.Where(g => g.Z == me.Pos.Z)) { WalkTo(me, g, 3, 20000, false, out _); mon = NearestMonster(me, "Rat", true); if (mon != null) break; if (Tick - t0 >= FirstUnlockLimitMs) break; }
                    if (mon == null) continue;
                }
                var log = FightOne(mon, attack, 30000);
                mon = null;
                if (log.Died) { problems.Append("the character died fighting a Rat; "); break; }
                if (log.Killed) kills++;
                Watch();
            }
            Pump(1500, () => false);
            Watch();
            double secs = (Tick - t0) / 1000.0;
            long expGain = (long)p.Experience - exp0;
            r.Note("hunt: " + kills + " kill(s) in " + secs.ToString("0.0", CultureInfo.InvariantCulture) + " s (" + waits + " wait(s) for a respawn), experience " + exp0 + " to " + (long)p.Experience + " (+" + expGain + "), level " + level0 + " to " + p.Level + ", health " + p.Health + "/" + p.MaxHealth);
            if (!reached.ContainsKey(first))
            {
                double perLevel = p.Level > level0 ? secs / (p.Level - level0) : double.NaN;
                string rate = expGain > 0 ? ", " + (expGain / Math.Max(1.0, secs)).ToString("0.0", CultureInfo.InvariantCulture) + " experience a second" : "";
                problems.Append(mark.Diff(me, "primary"));
                if (problems.Length > 0) { r.Fail(problems.ToString().Trim()); return; }
                r.Skip("level " + p.Level + " after " + secs.ToString("0", CultureInfo.InvariantCulture) + " s of the " + (FirstUnlockLimitMs / 1000) + " s allowed: '" + first.Name + "' opens at level " + first.Level + " (" + (first.Level - p.Level) + " more)" + rate + (double.IsNaN(perLevel) ? "" : ", " + perLevel.ToString("0", CultureInfo.InvariantCulture) + " s a level") + "; not reachable honestly in this time by this class");
                return;
            }
            // each unlock, by name
            r.Note("Helper notices (" + notices.Count + "): " + (notices.Count == 0 ? "none" : string.Join(" | ", notices.Select(n => "L" + n.level + " " + n.line))));
            var summary = new List<string>();
            foreach (var t in targets)
            {
                if (!reached.TryGetValue(t, out var rt))
                {
                    r.Note("'" + t.Name + "' (" + t.Kind + ", level " + t.Level + ") not reached: level " + p.Level + " after " + secs.ToString("0", CultureInfo.InvariantCulture) + " s (" + "the time ran out" + ")");
                    if (t == first) problems.Append("the first target was not reached; ");
                    continue;
                }
                r.Note("'" + t.Name + "' (" + t.Kind + ") level " + t.Level + " reached after " + rt.secs.ToString("0.0", CultureInfo.InvariantCulture) + " s: list status " + rt.status + ", " + rt.ready + " spell(s) ready (was " + readyBefore.Count + "), new in the list [" + string.Join(", ", rt.added) + "]");
                if (rt.status != SpellStatus.Ready) problems.Append("the spell list does not show '" + t.Name + "' as ready at level " + t.Level + " (status " + rt.status + "); ");
                if (!rt.added.Contains(t.Name)) problems.Append("'" + t.Name + "' is not among the new learned spells of the list at level " + t.Level + "; ");
                if (readyBefore.Contains(t.Name)) problems.Append("'" + t.Name + "' was ready before its level; ");
                var named = notices.Where(n => n.names.IndexOf(t.Name, StringComparison.OrdinalIgnoreCase) >= 0).ToList();
                if (named.Count > 0)
                {
                    var toast = s.Hud.Toasts.Add("MILESTONE", named[0].line);
                    r.Note("the toast of the glue for the notice: '" + (toast == null ? "(none)" : toast.Message) + "'");
                    if (toast == null || toast.Message.IndexOf(t.Name, StringComparison.OrdinalIgnoreCase) < 0) problems.Append("the toast for the notice does not carry '" + t.Name + "'; ");
                }
                else if (t.Kind == "attack") r.Note("the rotation did not take '" + t.Name + "' (the preset of this class at level " + p.Level + " is a different set), so the Helper asks nothing about it; the spell list shows it");
                else r.Note("'" + t.Name + "' is a support spell: the Helper's rotation notice is about attack spells, the spell list is where it shows");
                summary.Add("'" + t.Name + "' (L" + t.Level + ") " + (named.Count > 0 ? "ready in the list, named by the notice and the toast" : "ready in the list") + " at " + rt.secs.ToString("0", CultureInfo.InvariantCulture) + " s");
            }
            int unlocks = (ops.TryGetValue(115, out var u1) ? u1.Replies : 0) - unlocks0;
            r.Note("opcode 115 messages during the hunt: " + unlocks + (announced.Count > 0 ? ", system unlocks announced [" + string.Join("; ", announced) + "]" : ", no system unlock announced") + "; level lines [" + string.Join(" | ", me.ServerTexts(0).Where(x => x.IndexOf("advanced from", StringComparison.OrdinalIgnoreCase) >= 0).TakeLast(3)) + "]");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("level " + level0 + " to " + p.Level + " in " + secs.ToString("0", CultureInfo.InvariantCulture) + " s with " + kills + " Rat kill(s): " + string.Join("; ", summary) + ", no parse failure");
        }
    }
}
