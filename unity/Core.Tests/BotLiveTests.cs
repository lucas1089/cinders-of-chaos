// The live state of the journey bot for the staff's bot map (O727): Core/BotLive.cs. The one JSON line of the format shared with server/tools/bot_live.py (keys, limits, the log of 50 lines,
// no secret), the rate of the writer (3 s when changed, 15 s heartbeat, atomic, removed with the bot), the tester-name rule and the texts of the reasons. A temp folder, a mocked clock.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class BotLiveTests
    {
        public static void Run(Action<bool, string> check)
        {
            Names(check);
            Format(check);
            Limits(check);
            Writer(check);
            Texts(check);
        }

        static Dictionary<string, object> Parse(string line) => (Dictionary<string, object>)Json.Parse(line.TrimEnd('\n'));

        static void Names(Action<bool, string> check)
        {
            check(BotLiveState.IsTester("Tester Abc") && BotLiveState.Slug("Tester Abc") == "tester-abc", "bot live: a tester name and its file name part");
            bool bad = false;
            foreach (string n in new[] { "", null, "Tester", "tester Abc", "Tester ABC", "Tester Abcd", "Grimtooth", "../etc", "Tester Ab" })
                bad |= BotLiveState.IsTester(n) || BotLiveState.Slug(n).Length != 0;
            check(!bad, "bot live: no other name is ever published");
            check(BotLiveState.Clean("a\n\tb\u0000  c", 100) == "a b c" && BotLiveState.Clean(new string('x', 500), 160).Length == 160 && BotLiveState.Clean(null, 10) == "", "bot live: text is one clean line, cut to its limit");
        }

        static void Format(Action<bool, string> check)
        {
            var s = new BotLiveState("Tester Abc", 1000);
            s.SetClass("Ranger"); s.SetLevel(120); s.SetPos(32369, 32241, 7);
            s.SetGoal("Hunt", "level 120 is inside levels 90-160", "Cave Rats (levels 90-160)", new[] { "Keep hunting", "Trip to town" }, 1000);
            s.Log("hunt: Cave Rats", 1005);
            string line = s.ToLine(1010);
            check(line.EndsWith("\n") && line.IndexOf('\n') == line.Length - 1, "bot live: one JSON line");
            var d = Parse(line);
            check(Convert.ToInt32(d["v"]) == 1 && (string)d["name"] == "Tester Abc" && (string)d["class"] == "Ranger" && Convert.ToInt32(d["level"]) == 120 && (string)d["src"] == "cs", "bot live: version, name, class, level, source");
            var pos = (List<object>)d["pos"];
            check(pos.Count == 3 && Convert.ToInt32(pos[0]) == 32369 && Convert.ToInt32(pos[2]) == 7, "bot live: the position");
            check((string)d["goal"] == "Hunt" && Convert.ToInt64(d["goal_since"]) == 1000 && Convert.ToInt64(d["t"]) == 1010, "bot live: goal, since when, update time");
            check((string)d["why"] == "level 120 is inside levels 90-160" && (string)d["spot"] == "Cave Rats (levels 90-160)" && (string)d["now"] == "hunt: Cave Rats", "bot live: why, spot, now (the last log line)");
            var plan = (List<object>)d["plan"];
            var log = (List<object>)d["log"];
            check(plan.Count == 2 && (string)plan[1] == "Trip to town" && log.Count == 1 && Convert.ToInt64(((List<object>)log[0])[0]) == 1005 && (string)((List<object>)log[0])[1] == "hunt: Cave Rats", "bot live: plan and log");
            var keys = d.Keys.OrderBy(k => k, StringComparer.Ordinal).ToList();
            var want = new[] { "v", "name", "class", "level", "pos", "goal", "goal_since", "why", "spot", "now", "plan", "log", "t", "src" }.OrderBy(k => k, StringComparer.Ordinal).ToList();
            check(keys.SequenceEqual(want), "bot live: exactly the keys of the Python writer: " + string.Join(",", keys));
            string low = line.ToLowerInvariant();
            check(!low.Contains("password") && !low.Contains("account") && !low.Contains("tstbot") && !low.Contains("token"), "bot live: no secret in the file");
            var noPos = new BotLiveState("Tester Bcd", 5);
            check(Parse(noPos.ToLine(6))["pos"] == null, "bot live: no position yet is null");
            noPos.SetPos(70000, 5, 7); noPos.SetPos(5, 5, 16); noPos.SetPos(-1, 5, 7);
            check(noPos.Pos == null, "bot live: a position out of range is ignored");
            s.SetGoal("Town trip", "x", "", new string[0], 1100);
            check(s.GoalSince == 1100, "bot live: a new goal restarts since");
            s.SetGoal("Town trip", "y", "", new string[0], 1200);
            check(s.GoalSince == 1100, "bot live: the same goal keeps it");
            var u = new BotLiveState("Tester Abc", 1);
            u.Log("café — ok", 2);
            string uline = u.ToLine(3);
            check(uline.All(c => c < 0x80) && (string)((List<object>)((List<object>)Parse(uline)["log"])[0])[1] == "café — ok", "bot live: non-ASCII leaves as \\u escapes and reads back");
        }

        static void Limits(Action<bool, string> check)
        {
            var s = new BotLiveState("Tester Abc", 0);
            for (int i = 0; i < 80; i++) s.Log("line " + i, 100 + i);
            check(s.Lines.Count == 50 && s.Lines[0].Value == "line 30" && s.Lines[49].Value == "line 79" && s.Now == "line 79", "bot live: the last 50 log lines, newest last");
            s.SetGoal("Hunt", new string('w', 999), new string('s', 999), Enumerable.Repeat(new string('p', 999), 20), 5);
            check(s.Why.Length == 240 && s.Spot.Length == 240 && s.Plan.Count == 8 && s.Plan.All(p => p.Length == 240), "bot live: why, spot and plan are cut");
            s.Dirty = false;
            s.SetLevel(5); s.SetLevel(5);
            check(s.Dirty, "bot live: a changed level is a change");
            s.Dirty = false;
            s.SetLevel(5); s.SetClass(""); s.Log("   ", 1);
            check(!s.Dirty, "bot live: the same values and an empty line are no change");
        }

        static string Temp()
        {
            string d = Path.Combine(Path.GetTempPath(), "botlive_" + Guid.NewGuid().ToString("N"));
            return d;
        }

        static void Writer(Action<bool, string> check)
        {
            string dir = Temp();
            try
            {
                long clock = 1000;
                var w = new BotLiveWriter(dir, () => clock);
                var s = new BotLiveState("Tester Abc", 1000);
                s.SetLevel(3);
                check(w.Flush(s) && File.Exists(Path.Combine(dir, "tester-abc.json")), "bot live writer: the first write makes the folder and the file");
                s.Log("one", clock);
                clock += 1;
                check(!w.Flush(s), "bot live writer: a change within 3 s waits");
                clock += 3;
                check(w.Flush(s) && !s.Dirty, "bot live writer: then it is written");
                clock += 4;
                check(!w.Flush(s), "bot live writer: nothing changed, nothing written");
                clock += 15;
                check(w.Flush(s), "bot live writer: the heartbeat keeps the time fresh");
                check(Convert.ToInt64(Parse(File.ReadAllText(Path.Combine(dir, "tester-abc.json")))["t"]) == clock, "bot live writer: the file carries the time of the write");
                check(Directory.GetFiles(dir).All(f => !f.EndsWith(".tmp")) && Directory.GetFiles(dir).Length == 1, "bot live writer: no temp file is left");
                s.Log("two", clock);
                check(w.Flush(s, true), "bot live writer: force writes at once");
                w.Remove(s);
                check(Directory.GetFiles(dir).Length == 0, "bot live writer: the file goes with the bot");
                var other = new BotLiveState("Grimtooth", 1);
                check(!w.Flush(other, true) && Directory.GetFiles(dir).Length == 0, "bot live writer: a name that is not a tester's is never written");
            }
            finally { try { Directory.Delete(dir, true); } catch (Exception) { } }
            // a folder that cannot be made is no error of the bot
            string blocked = Temp();
            File.WriteAllText(blocked, "a file where the folder should be");
            try
            {
                var w2 = new BotLiveWriter(Path.Combine(blocked, "sub"), () => 5);
                check(!w2.Flush(new BotLiveState("Tester Abc", 1), true), "bot live writer: an unwritable folder returns false, no exception");
            }
            finally { try { File.Delete(blocked); } catch (Exception) { } }
        }

        static void Texts(Action<bool, string> check)
        {
            var h = new JourneyHunt { Name = "Cave Rats", Lo = 90, Hi = 160, At = new Pos(32400, 32300, 8) };
            string t = BotLiveText.WhyHunt(h, 120, new Pos(32369, 32241, 7), 45300);
            check(t.StartsWith("level 120 is inside levels 90-160 of Cave Rats, 59 tiles away and 1 floor(s) off") && t.EndsWith("about 45 300 exp/h so far"), "bot live text: why a hunt, with the distance and the measured experience: " + t);
            check(!BotLiveText.WhyHunt(h, 120, new Pos(32400, 32300, 8), 0).Contains("exp/h") && !BotLiveText.WhyHunt(h, 120, new Pos(32400, 32300, 8), 0).Contains("floor"), "bot live text: no figure and no floor when there is none");
            check(BotLiveText.WhyHunt(h, 200, new Pos(32400, 32300, 8), 0).Contains("above levels 90-160: the closest band below it"), "bot live text: a level above the band");
            check(BotLiveText.WhyHunt(h, 40, new Pos(32400, 32300, 8), 0).Contains("below levels 90-160: the closest band above it"), "bot live text: a level below the band");
            check(BotLiveText.WhyHunt(null, 5, new Pos(1, 1, 7), 0) == "", "bot live text: no hunt, no reason");
            check(BotLiveText.WhyTrip("cap").Contains("capacity") && BotLiveText.WhyTrip("backpack").Contains("backpack") && BotLiveText.WhyTrip("potions").Contains("potions") && BotLiveText.WhyTrip("x") == "town trip: x" && BotLiveText.WhyTrip("") == "town trip", "bot live text: why a trip");
            var plan = BotLiveText.HuntPlan(h);
            check(plan.Count == 4 && plan[0] == "Keep hunting Cave Rats while level 90-160 holds" && plan[1].Contains("40%"), "bot live text: the plan of a hunt");
            check(BotLiveText.HuntPlan(null)[0].StartsWith("Keep hunting here"), "bot live text: the plan without a hunt");
            check(BotLiveText.Spaced(1234567) == "1 234 567", "bot live text: numbers with spaces");
        }
    }
}
