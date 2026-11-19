// The loot explosion video (Core/LootTour.cs): the environment, the frame names, the ffconcat list, the item count round the hero, and the state machine on a simulated ground:
// warm-up, intro, burst, labels, second burst, Loot all, tail, and each fault (no items, no labels, Loot all that does nothing, a silent helper, over time).
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class LootTourTests
    {
        public static void Run(Action<bool, string> check)
        {
            EnvChecks(check);
            PlanChecks(check);
            CountChecks(check);
            StepChecks(check);
        }

        static Func<string, string> Env(params string[] kv)
        {
            var d = new Dictionary<string, string>();
            for (int i = 0; i + 1 < kv.Length; i += 2) d[kv[i]] = kv[i + 1];
            return n => d.TryGetValue(n, out var v) ? v : null;
        }

        static void EnvChecks(Action<bool, string> check)
        {
            var ok = LootTourEnv.Read(Env("CHAOS_LIVE_PORT", "7171", "CHAOS_LIVE_IDENTITY", "chaos", "CHAOS_LIVE_ACCOUNT", "main", "CHAOS_LIVE_PASSWORD", "mainpw", "CHAOS_LIVE_CHARACTER", "Live Main",
                "CHAOS_LIVE_NEW_ACCOUNT", "n", "CHAOS_LIVE_NEW_PASSWORD", "np", "CHAOS_LIVE_NEW_CHARACTER", "Live New", "CHAOS_LIVE_SAY", "/testkit",
                "CHAOS_LOOT_ACCOUNT", "lct1", "CHAOS_LOOT_PASSWORD", "pw 1", "CHAOS_LOOT_CHARACTER", "Tester Aka"));
            check(ok.Ok && ok.Live.Account == "lct1" && ok.Live.Password == "pw 1" && ok.Live.Character == "Tester Aka" && ok.Live.Identity == "chaos" && ok.Live.Port == 7171,
                "loot tour env: the tester of CHAOS_LOOT_* is the one that logs in, the host, port and identity are the live smoke's (" + string.Join("; ", ok.Errors) + ")");
            check(!ok.Live.HasNewPlayer && ok.Live.Say.Count == 0, "loot tour env: no new player first minute and no CHAOS_LIVE_SAY lines");
            var sec = ok.Live.Secrets();
            check(sec.Contains("lct1") && sec.Contains("pw 1") && sec.Contains("Tester Aka") && !sec.Contains("main") && !sec.Contains("mainpw"), "loot tour env: the secrets are the tester's, not the main character's");
            var none = LootTourEnv.Read(Env());
            check(!none.Ok && none.Errors.Contains("set CHAOS_LOOT_ACCOUNT") && none.Errors.Contains("set CHAOS_LOOT_PASSWORD") && none.Errors.Contains("set CHAOS_LOOT_CHARACTER") && !none.Errors.Any(e => e.Contains("CHAOS_LIVE_ACCOUNT")),
                "loot tour env: an empty environment names the CHAOS_LOOT variables (" + string.Join("; ", none.Errors) + ")");
            var live = LootTourEnv.Read(Env("CHAOS_LIVE_ACCOUNT", "a", "CHAOS_LIVE_PASSWORD", "b", "CHAOS_LIVE_CHARACTER", "Live Main"));
            check(!live.Ok, "loot tour env: the live smoke's account alone is not enough");
            var bad = LootTourEnv.Read(Env("CHAOS_LOOT_ACCOUNT", "a", "CHAOS_LOOT_PASSWORD", "b", "CHAOS_LOOT_CHARACTER", "Live Main"));
            check(!bad.Ok && bad.Errors.Any(e => e.Contains("tester name")), "loot tour env: a character that is not a tester name is refused (the helper answers testers only)");
            var port = LootTourEnv.Read(Env("CHAOS_LOOT_ACCOUNT", "a", "CHAOS_LOOT_PASSWORD", "b", "CHAOS_LOOT_CHARACTER", "Tester Bel", "CHAOS_LIVE_IDENTITY", "other"));
            check(!port.Ok, "loot tour env: a wrong identity is refused as in the live smoke");
        }

        static void PlanChecks(Action<bool, string> check)
        {
            check(LootTourPlan.Width == 1280 && LootTourPlan.Height == 720 && LootTourPlan.OutFps == 30, "loot tour plan: 1280x720, 30 frames a second out");
            check(LootTourPlan.FrameName(0) == "loot_tour_0000.png" && LootTourPlan.FrameName(123) == "loot_tour_0123.png" && LootTourPlan.FrameName(12345) == "loot_tour_12345.png", "loot tour plan: frame names loot_tour_NNNN.png");
            check(LootTourPlan.SayExplode == "!tester explode run", "loot tour plan: the helper's words");
            foreach (var n in new[] { "Tester Aka", "Tester Zyx" }) check(LootTourPlan.IsTesterName(n), "loot tour plan: " + n + " is a tester name");
            foreach (var n in new[] { "", "Tester", "Tester aka", "Tester AKa", "Tester Akaa", "tester Aka", "Live Main", "Tester Ak1" }) check(!LootTourPlan.IsTesterName(n), "loot tour plan: '" + n + "' is not a tester name");

            var at = new List<double> { 1000, 1100, 1350, 1350, 5000 };
            string list = LootTourPlan.Concat(at, 120);
            var lines = list.Split('\n');
            check(lines[0] == "ffconcat version 1.0" && lines[1] == "file 'loot_tour_0000.png'" && lines[2] == "duration 0.100" && lines[4] == "duration 0.250", "loot tour list: header, file, duration of the gap to the next frame");
            check(lines[6] == "duration 0.001", "loot tour list: two frames taken at once get 1 ms (never 0 or negative)");
            check(lines[8] == "duration 1.500", "loot tour list: a stall of 3.65 s is cut to " + LootTourPlan.MaxFrameMs + " ms (got " + lines[8] + ")");
            check(list.Contains("duration 0.120\nfile 'loot_tour_0004.png'\n") && list.EndsWith("file 'loot_tour_0004.png'\n"), "loot tour list: the last frame is listed again without a duration (the demuxer drops the last duration)");
            check(Math.Abs(LootTourPlan.VideoSeconds(at, 120) - (0.1 + 0.25 + 0.001 + 1.5 + 0.12)) < 1e-9, "loot tour list: the seconds of the video are the sum of the durations");
            check(LootTourPlan.Concat(new List<double>()) == "ffconcat version 1.0\n" && LootTourPlan.VideoSeconds(new List<double>()) == 0, "loot tour list: no frame, no file");
        }

        static void CountChecks(Action<bool, string> check)
        {
            var types = new Dictionary<int, ThingType>
            {
                { 100, new ThingType { Id = 100, Ground = true } },
                { 200, new ThingType { Id = 200, Pickupable = true } },
                { 201, new ThingType { Id = 201, Pickupable = true, OnTop = true } },
                { 202, new ThingType { Id = 202 } },
            };
            var w = new World(null);
            var c = new Pos(100, 100, 7);
            void Put(Pos p, params int[] ids)
            {
                var t = w.GetOrMake(p);
                foreach (int id in ids) t.Things.Add(new Thing { Item = new Item { Id = id, Count = 1, Type = types[id] } });
            }
            Put(c, 100, 200);                              // ground and one loose item
            Put(new Pos(102, 101, 7), 100, 200, 200);      // two on one tile
            Put(new Pos(104, 100, 7), 100, 200);           // the edge of the radius
            Put(new Pos(105, 100, 7), 100, 200);           // outside it
            Put(new Pos(99, 99, 6), 100, 200);             // another floor
            Put(new Pos(98, 100, 7), 100, 201, 202);       // on top and a plain static item: no label
            int n = LootTourPlan.CountItems(w, c, LootTourPlan.Radius);
            check(n == 4, "loot tour count: items within 4 tiles on the floor, ground, on-top and static things left out (got " + n + ")");
            check(LootTourPlan.CountItems(w, c, 1) == 1 && LootTourPlan.CountItems(null, c, 4) == 0, "loot tour count: a smaller radius counts fewer, no world counts none");
        }

        // ---------------------------------------------------------------------------------------------------- the state machine on a simulated ground
        /// <summary>The server of the test: an explosion adds `Drop` items after `Delay` ms, Loot all brings the ground back to `Warm` after `TakeDelay` ms. Time is the loop's clock in 33 ms frames.</summary>
        sealed class Sim
        {
            public int Items, Drop = 6, Explodes, Takes, Warm;
            public double Delay = 150, TakeDelay = 200, Now;
            public bool Helper = true, Taker = true, ShowLabels = true;
            readonly List<KeyValuePair<double, int>> due = new List<KeyValuePair<double, int>>();

            public LootTourView View() { return new LootTourView { Items = Items, Labels = ShowLabels && Items > Warm ? Items - Warm : 0 }; }

            public void Apply(LootTourAction a)
            {
                if (a == LootTourAction.Explode) { Explodes++; if (Helper) due.Add(new KeyValuePair<double, int>(Now + Delay, Drop)); }
                if (a == LootTourAction.LootAll) { Takes++; if (Taker) due.Add(new KeyValuePair<double, int>(Now + TakeDelay, -1)); }
            }

            public void Advance(double to)
            {
                Now = to;
                for (int i = 0; i < due.Count; i++)
                    if (due[i].Key <= Now)
                    {
                        if (due[i].Value < 0) Items = Warm; else Items += due[i].Value;
                        due.RemoveAt(i--);
                    }
            }
        }

        static LootTourStep Drive(Sim sim, double limitMs, out int frames, out List<LootTourAction> acts)
        {
            var step = new LootTourStep();
            acts = new List<LootTourAction>();
            frames = 0;
            for (double t = 0; t < limitMs; t += 33)
            {
                sim.Advance(t);
                var a = step.Update(t, sim.View());
                if (a != LootTourAction.None) acts.Add(a);
                sim.Apply(a);
                if (step.Recording) frames++;
                if (step.State == LootTourStep.Phase.Done) break;
            }
            return step;
        }

        static void StepChecks(Action<bool, string> check)
        {
            var sim = new Sim();
            var step = Drive(sim, 100000, out int frames, out var acts);
            check(step.Pass && step.State == LootTourStep.Phase.Done && step.Error.Length == 0, "loot tour step: the whole run passes on a working server (" + step.Error + ")");
            var expect = new[] { LootTourAction.Explode, LootTourAction.LootAll, LootTourAction.Explode, LootTourAction.Explode };
            check(acts.Take(4).SequenceEqual(expect), "loot tour step: warm-up explosion, its Loot all, then the two explosions of the video (" + string.Join(",", acts) + ")");
            check(acts.Skip(4).Take(1).SequenceEqual(new[] { LootTourAction.LootAll }) && acts.Last() == LootTourAction.Finish, "loot tour step: Loot all after the second hold, then Finish");
            check(sim.Explodes == 3 && step.Explosions == 3, "loot tour step: three explosions in all (one warm-up, two in the video)");
            check(step.BurstSeen && step.Burst2Seen && step.LabelsSeen && step.Taken && step.Peak >= 6 && step.Peak2 >= 12 && step.Baseline == 0, "loot tour step: both bursts, the labels and the take are seen (peak " + step.Peak + ", " + step.Peak2 + ")");
            double videoMs = frames * 33.0;
            check(videoMs > 14000 && videoMs < 20000, "loot tour step: about 15 to 20 s of video (" + Math.Round(videoMs / 1000, 1) + " s)");
            check(step.VideoMs > 14000, "loot tour step: the video clock runs from the intro (" + Math.Round(step.VideoMs) + " ms)");

            // the video starts after the warm-up: no frame while the hero is stepped out and the ground cleared
            var rec = new LootTourStep();
            var s2 = new Sim();
            bool recBefore = false;
            for (double t = 0; t < 3000; t += 33)
            {
                s2.Advance(t);
                var a = rec.Update(t, s2.View());
                s2.Apply(a);
                if (rec.State < LootTourStep.Phase.Intro && rec.Recording) recBefore = true;
            }
            check(!recBefore && rec.Recording, "loot tour step: no frame is recorded before the intro, frames run in the intro");

            // a ground that has items already (the baseline is what Loot all must reach)
            var s3 = new Sim { Warm = 2, Items = 2 };
            var st3 = Drive(s3, 100000, out _, out _);
            check(st3.Pass && st3.Baseline == 2, "loot tour step: items lying before the run are the baseline, Loot all must bring the ground back to them");

            // the hero stepped to another spot: the count drops once, the explosion still reads
            var s4 = new Sim { Warm = 3, Items = 3 };
            var st4 = new LootTourStep();
            int asked4 = 0;
            for (double t = 0; t < 100000 && st4.State != LootTourStep.Phase.Done; t += 33)
            {
                s4.Advance(t);
                if (asked4 == 1 && s4.Warm == 3) { s4.Items = 0; s4.Warm = 0; }   // the step out of the protection zone, on the frame after the first ask
                var a = st4.Update(t, s4.View());
                if (a == LootTourAction.Explode) asked4++;
                s4.Apply(a);
            }
            check(st4.Pass && st4.Start == 0, "loot tour step: the warm-up's start count follows the hero to the spot outside the protection zone (start " + st4.Start + ")");

            // faults
            var mute = new Sim { Helper = false };
            var stm = Drive(mute, 100000, out _, out var am);
            check(!stm.Pass && stm.Error.Contains("warm-up") && am.Last() == LootTourAction.Fail && stm.State == LootTourStep.Phase.Done, "loot tour step: a helper that does not answer fails the warm-up (" + stm.Error + ")");

            var nolabel = new Sim { ShowLabels = false };
            var stn = Drive(nolabel, 100000, out _, out _);
            check(!stn.Pass && stn.Error.Length == 0 && !stn.LabelsSeen && stn.Taken, "loot tour step: no ground label fails the pass rule without stopping the run");

            var nottaken = new Sim { Taker = false };
            var stt = Drive(nottaken, 100000, out _, out var at2);
            check(!stt.Pass && stt.Error.Contains("warm-up") && at2.Last() == LootTourAction.Fail, "loot tour step: a Loot all that does nothing fails (" + stt.Error + ")");

            // Loot all that works only from the third ask in the video: the retries are spaced and capped
            var late = new Sim();
            var stl = new LootTourStep();
            int asks = 0; double lastAsk = -1; bool spaced = true;
            for (double t = 0; t < 100000 && stl.State != LootTourStep.Phase.Done; t += 33)
            {
                late.Advance(t);
                var a = stl.Update(t, late.View());
                if (a == LootTourAction.LootAll && stl.State == LootTourStep.Phase.Take)
                {
                    asks++;
                    if (lastAsk >= 0 && t - lastAsk < LootTourStep.TakeRetryMs - 1) spaced = false;
                    lastAsk = t;
                    late.Taker = asks >= 3;
                    if (asks == 1) late.Taker = false;
                }
                late.Apply(a);
            }
            check(stl.Pass && asks == 3 && spaced && stl.LootAllTries == 3, "loot tour step: Loot all is asked again every " + LootTourStep.TakeRetryMs + " ms until it works (" + asks + " asks)");

            // a second explosion that adds nothing is a note, not a failure
            var one = new Sim();
            var sto = new LootTourStep();
            int boom = 0;
            for (double t = 0; t < 100000 && sto.State != LootTourStep.Phase.Done; t += 33)
            {
                one.Advance(t);
                var a = sto.Update(t, one.View());
                if (a == LootTourAction.Explode) { boom++; one.Helper = boom != 3; }
                one.Apply(a);
            }
            check(sto.Pass && !sto.Burst2Seen && sto.Notes.Count == 1, "loot tour step: a second burst that adds nothing is a note (" + string.Join("; ", sto.Notes) + ")");

            // over time
            var slow = new LootTourStep();
            var r = LootTourAction.None;
            for (double t = 0; t <= 130000 && r != LootTourAction.Fail; t += 1000) r = slow.Update(t, new LootTourView());
            check(r == LootTourAction.Fail && slow.Error.Length > 0, "loot tour step: a run over " + (int)(LootTourStep.LimitMs / 1000) + " s fails");
            check(slow.Update(200000, new LootTourView()) == LootTourAction.None, "loot tour step: nothing more is asked after the end");

            // the report
            string json = step.ToJson(450, 14.7, false);
            check(json.Contains("\"pass\": true") && json.Contains("\"frames\": 450") && json.Contains("\"videoSeconds\": 14.7") && json.Contains("\"explosions\": 3") && json.Contains("\"taken\": true"), "loot tour report: the numbers of the run");
            string bad2 = stm.ToJson(0, 0, true);
            check(bad2.Contains("\"pass\": false") && bad2.Contains("\"slowFrames\": true") && bad2.Contains("warm-up"), "loot tour report: a failed run says why");
            check(!json.Contains("Tester") && !json.Contains("lct"), "loot tour report: no account and no character in it");
        }
    }
}
