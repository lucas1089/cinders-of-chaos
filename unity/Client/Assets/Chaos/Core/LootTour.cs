// The loot explosion video (O675, unity/README.md "Loot explosion video"): `ChaosUnity -chaosLootTour OUT_DIR` plays on a REAL server (the one of tools/ci/unity_live_check.sh
// --serve-only) as a tester character, stands outside a protection zone, has the server explode a loot bag of the character's own (the TEST ONLY helper command
// `!tester explode run`, server/tools/tester_helper.lua: the real rule of loot_explosion.lua, gold in one stack, the items on free tiles within 2, owned by the character),
// records PNG frames of the burst, the items on the ground with their labels, then takes everything with Loot all (opcode 230, "lootall").
// Pure logic, no engine API, tested in Core.Tests/LootTourTests.cs:
//   LootTourEnv    where to go (the variables of the live smoke, the account of the tester in CHAOS_LOOT_*)
//   LootTourPlan   sizes, the frame names, the words said, the item count round the hero, the ffconcat list the workflow encodes (real time stamps, so the burst plays as it happened)
//   LootTourStep   the state machine: warm-up (steps out of the protection zone, clears the ground), intro, burst, hold, second burst, hold, Loot all, tail; the pass rule
// The frames carry the wall clock of the frame, not a fixed rate: the server's drops are staggered in real time (50 to 80 ms apart, 80 ms + 40 ms a tile in the air) and a software
// rendered frame takes longer than that, so a fixed frame rate would run the burst faster than it happened. ffmpeg reads the list (-f concat) and writes 30 frames a second.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    /// <summary>The environment of the run: the variables of the live smoke (CHAOS_LIVE_HOST, _PORT, _IDENTITY, CHAOS_CLIENT_KEY, CHAOS_RSA_PUBLIC) and the tester character
    /// in CHAOS_LOOT_ACCOUNT, CHAOS_LOOT_PASSWORD and CHAOS_LOOT_CHARACTER (a name "Tester Xxx": the helper acts for those only).</summary>
    public sealed class LootTourEnv
    {
        public LiveSmokeEnv Live;
        public bool Ok => Live.Ok;
        public List<string> Errors => Live.Errors;

        public static LootTourEnv Read(Func<string, string> get)
        {
            string V(string n) { string v = get(n); return v == null ? "" : v.Trim(); }
            string Map(string name)
            {
                switch (name)
                {
                    case "CHAOS_LIVE_ACCOUNT": return V("CHAOS_LOOT_ACCOUNT");
                    case "CHAOS_LIVE_PASSWORD": return get("CHAOS_LOOT_PASSWORD");   // the password is what it is
                    case "CHAOS_LIVE_CHARACTER": return V("CHAOS_LOOT_CHARACTER");
                    case "CHAOS_LIVE_NEW_ACCOUNT": case "CHAOS_LIVE_NEW_PASSWORD": case "CHAOS_LIVE_NEW_CHARACTER": case "CHAOS_LIVE_SAY": return "";
                    default: return get(name);
                }
            }
            var e = new LootTourEnv { Live = LiveSmokeEnv.Read(Map) };
            // the live smoke's own messages name its variables: the tester's are CHAOS_LOOT_*
            e.Live.Errors.Remove("set CHAOS_LIVE_ACCOUNT");
            e.Live.Errors.Remove("set CHAOS_LIVE_PASSWORD");
            if (V("CHAOS_LOOT_ACCOUNT").Length == 0) e.Live.Errors.Add("set CHAOS_LOOT_ACCOUNT");
            if ((get("CHAOS_LOOT_PASSWORD") ?? "").Length == 0) e.Live.Errors.Add("set CHAOS_LOOT_PASSWORD");
            if (V("CHAOS_LOOT_CHARACTER").Length == 0) e.Live.Errors.Add("set CHAOS_LOOT_CHARACTER");
            else if (!LootTourPlan.IsTesterName(V("CHAOS_LOOT_CHARACTER"))) e.Live.Errors.Add("CHAOS_LOOT_CHARACTER must be a tester name (Tester, a space, a capital and two lower case letters)");
            return e;
        }
    }

    public static class LootTourPlan
    {
        public const int Width = 1280, Height = 720, OutFps = 30;
        /// <summary>The words the character says: the helper's command (server/tools/tester_helper.lua commands.explode). A tester only; any other character gets no answer.</summary>
        public const string SayExplode = "!tester explode run";
        public const string FramePrefix = "loot_tour_", FramesFile = "loot_tour_frames.txt", ReportFile = "loot_tour.json", Video = "loot_tour.mp4";
        /// <summary>Tiles round the hero whose items are counted (the explosion's ring is 2).</summary>
        public const int Radius = 4;
        /// <summary>A frame that stays on the screen longer than this in the list is shortened (a stall of the player is not a still of the video).</summary>
        public const double MaxFrameMs = 1500;
        public const int MaxFrames = 1500;

        public static string FrameName(int i) { return FramePrefix + i.ToString("0000", CultureInfo.InvariantCulture) + ".png"; }

        /// <summary>The helper's name rule (tester_helper_core.lua): "Tester", a space, a capital and two lower case letters.</summary>
        public static bool IsTesterName(string n)
        {
            if (n == null || n.Length != 10 || !n.StartsWith("Tester ", StringComparison.Ordinal)) return false;
            return n[7] >= 'A' && n[7] <= 'Z' && n[8] >= 'a' && n[8] <= 'z' && n[9] >= 'a' && n[9] <= 'z';
        }

        /// <summary>The things lying on the tiles within `radius` of `center` that a label is about (GroundLabelRules.IsCandidate: no ground, border or bottom item, pickupable, not on top).</summary>
        public static int CountItems(World w, Pos center, int radius)
        {
            int n = 0;
            if (w == null) return 0;
            for (int dx = -radius; dx <= radius; dx++)
                for (int dy = -radius; dy <= radius; dy++)
                {
                    var t = w.Get(new Pos(center.X + dx, center.Y + dy, center.Z));
                    if (t == null) continue;
                    foreach (var th in t.Things)
                        if (!th.IsCreature && th.Item != null && GroundLabelRules.IsCandidate(th.Item)) n++;
                }
            return n;
        }

        /// <summary>The ffconcat list of the frames: frame i stays until frame i + 1 was taken (at least 1 ms, at most MaxFrameMs); the last file is listed again without a duration (the demuxer drops the last duration otherwise).</summary>
        public static string Concat(IList<double> atMs, double lastMs = 100)
        {
            var sb = new StringBuilder("ffconcat version 1.0\n");
            int n = atMs.Count;
            for (int i = 0; i < n; i++)
            {
                double d = i + 1 < n ? atMs[i + 1] - atMs[i] : lastMs;
                d = Math.Min(MaxFrameMs, Math.Max(1.0, d));
                sb.Append("file '").Append(FrameName(i)).Append("'\nduration ").Append((d / 1000.0).ToString("0.000", CultureInfo.InvariantCulture)).Append('\n');
            }
            if (n > 0) sb.Append("file '").Append(FrameName(n - 1)).Append("'\n");
            return sb.ToString();
        }

        /// <summary>The seconds of the video the list makes.</summary>
        public static double VideoSeconds(IList<double> atMs, double lastMs = 100)
        {
            double s = 0;
            for (int i = 0; i < atMs.Count; i++) s += Math.Min(MaxFrameMs, Math.Max(1.0, i + 1 < atMs.Count ? atMs[i + 1] - atMs[i] : lastMs));
            return s / 1000.0;
        }
    }

    /// <summary>What the player sees of the ground this frame.</summary>
    public struct LootTourView
    {
        /// <summary>Items within LootTourPlan.Radius of the hero.</summary>
        public int Items;
        /// <summary>Ground labels the model gives for the hero's place.</summary>
        public int Labels;
    }

    public enum LootTourAction { None, Explode, LootAll, Finish, Fail }

    /// <summary>The run, a frame at a time. `ms` is the wall time since the run's start; the timeline of the video starts at the intro. A fault is `Error` with the action Fail, the run goes on
    /// to write the frames it has. Phases: Prep (the warm-up: the first explosion steps the hero out of a protection zone and its loot is taken, so the video starts on a clean spot), Intro
    /// (the quiet ground), Burst (the explosion asked, items wait), Hold (items on the ground, labels), Burst2, Hold2, Take (Loot all until the ring is empty), Tail, Done.</summary>
    public sealed class LootTourStep
    {
        public const double PrepWaitMs = 20000, IntroMs = 2500, BurstWaitMs = 8000, HoldMs = 4500, TakeWaitMs = 8000, TakeRetryMs = 1200, TailMs = 3500, LimitMs = 120000;
        public const int MinItems = 3, TakeTries = 4;

        public enum Phase { PrepAsk, PrepWait, PrepTake, Intro, Burst, Hold, Burst2, Hold2, Take, Tail, Done }

        public Phase State { get; private set; } = Phase.PrepAsk;
        public string Error = "";
        public readonly List<string> Notes = new List<string>();
        /// <summary>Items near the hero before the first explosion and at the intro (the ground the video starts on).</summary>
        public int Start = -1, Baseline;
        public int Peak, Peak2, MaxLabels, LootAllTries, Explosions;
        public bool BurstSeen, Burst2Seen, LabelsSeen, Taken;
        /// <summary>The video's own clock: ms since the intro began, -1 before it.</summary>
        public double VideoMs { get; private set; } = -1;

        double phaseAt, introAt = -1, lastAsk;

        /// <summary>True from the intro to the end: the frames of the video.</summary>
        public bool Recording => State >= Phase.Intro && State < Phase.Done;
        public bool Pass => Error.Length == 0 && BurstSeen && LabelsSeen && Taken;

        void Go(Phase p, double ms) { State = p; phaseAt = ms; }

        LootTourAction Bad(string why, double ms)
        {
            if (Error.Length == 0) Error = why;
            Go(Phase.Done, ms);
            return LootTourAction.Fail;
        }

        public LootTourAction Update(double ms, LootTourView v)
        {
            if (State == Phase.Done) return LootTourAction.None;
            if (introAt >= 0) VideoMs = ms - introAt;
            if (v.Labels > MaxLabels) MaxLabels = v.Labels;
            if (v.Labels > 0 && State >= Phase.Burst && State <= Phase.Take) LabelsSeen = true;
            if (ms > LimitMs) return Bad("the loot tour ran over " + (int)(LimitMs / 1000) + " s (phase " + State + ")", ms);
            switch (State)
            {
                case Phase.PrepAsk:
                    Start = v.Items;
                    lastAsk = ms; Explosions++;
                    Go(Phase.PrepWait, ms);
                    return LootTourAction.Explode;
                case Phase.PrepWait:
                    if (v.Items < Start) Start = v.Items;   // the step out of a protection zone changes the ground the count is made on
                    if (v.Items >= Start + MinItems) { Go(Phase.PrepTake, ms); lastAsk = ms - TakeRetryMs; }   // the first Loot all goes out at once
                    else if (ms - phaseAt > PrepWaitMs) return Bad("the warm-up explosion put no items on the ground (the helper answers a tester only, and needs an open spot within 20 tiles)", ms);
                    return LootTourAction.None;
                case Phase.PrepTake:
                    if (v.Items <= Start) { Baseline = v.Items; introAt = ms; VideoMs = 0; Go(Phase.Intro, ms); return LootTourAction.None; }
                    if (ms - phaseAt > TakeWaitMs) return Bad("the warm-up Loot all did not clear the ground (" + v.Items + " items, " + Start + " before)", ms);
                    if (ms - lastAsk >= TakeRetryMs) { lastAsk = ms; return LootTourAction.LootAll; }
                    return LootTourAction.None;
                case Phase.Intro:
                    if (ms - phaseAt >= IntroMs) { Baseline = v.Items; lastAsk = ms; Explosions++; Go(Phase.Burst, ms); return LootTourAction.Explode; }
                    return LootTourAction.None;
                case Phase.Burst:
                    if (v.Items > Peak) Peak = v.Items;
                    if (v.Items >= Baseline + MinItems) { BurstSeen = true; Go(Phase.Hold, ms); }
                    else if (ms - phaseAt > BurstWaitMs) return Bad("no items on the ground " + (int)(BurstWaitMs / 1000) + " s after the explosion", ms);
                    return LootTourAction.None;
                case Phase.Hold:
                    if (v.Items > Peak) Peak = v.Items;
                    if (ms - phaseAt >= HoldMs) { lastAsk = ms; Explosions++; Go(Phase.Burst2, ms); return LootTourAction.Explode; }
                    return LootTourAction.None;
                case Phase.Burst2:
                    if (v.Items > Peak2) Peak2 = v.Items;
                    if (v.Items >= Peak + MinItems) { Burst2Seen = true; Go(Phase.Hold2, ms); }
                    else if (ms - phaseAt > BurstWaitMs) { Notes.Add("the second explosion added no items within " + (int)(BurstWaitMs / 1000) + " s"); Go(Phase.Hold2, ms); }
                    return LootTourAction.None;
                case Phase.Hold2:
                    if (v.Items > Peak2) Peak2 = v.Items;
                    if (ms - phaseAt >= HoldMs) { lastAsk = ms - TakeRetryMs; Go(Phase.Take, ms); }
                    return LootTourAction.None;
                case Phase.Take:
                    if (v.Items <= Baseline) { Taken = true; Go(Phase.Tail, ms); return LootTourAction.None; }
                    if (ms - phaseAt > TakeWaitMs) return Bad("Loot all did not clear the ground (" + v.Items + " items left, " + Baseline + " before the explosion, " + LootAllTries + " asks)", ms);
                    if (ms - lastAsk >= TakeRetryMs && LootAllTries < TakeTries) { lastAsk = ms; LootAllTries++; return LootTourAction.LootAll; }
                    return LootTourAction.None;
                case Phase.Tail:
                    if (ms - phaseAt >= TailMs) { Go(Phase.Done, ms); return LootTourAction.Finish; }
                    return LootTourAction.None;
            }
            return LootTourAction.None;
        }

        /// <summary>The report written next to the frames (no account, password or character).</summary>
        public string ToJson(int frames, double videoSeconds, bool slow)
        {
            var inv = CultureInfo.InvariantCulture;
            var sb = new StringBuilder("{\n");
            sb.Append("  \"pass\": ").Append(Pass ? "true" : "false").Append(",\n");
            sb.Append("  \"error\": \"").Append(Esc(Error)).Append("\",\n");
            sb.Append("  \"burstSeen\": ").Append(BurstSeen ? "true" : "false").Append(", \"secondBurstSeen\": ").Append(Burst2Seen ? "true" : "false").Append(",\n");
            sb.Append("  \"labelsSeen\": ").Append(LabelsSeen ? "true" : "false").Append(", \"maxLabels\": ").Append(MaxLabels.ToString(inv)).Append(",\n");
            sb.Append("  \"taken\": ").Append(Taken ? "true" : "false").Append(", \"lootAllAsks\": ").Append(LootAllTries.ToString(inv)).Append(",\n");
            sb.Append("  \"itemsBefore\": ").Append(Baseline.ToString(inv)).Append(", \"peak\": ").Append(Peak.ToString(inv)).Append(", \"peakAfterSecond\": ").Append(Peak2.ToString(inv)).Append(",\n");
            sb.Append("  \"explosions\": ").Append(Explosions.ToString(inv)).Append(", \"frames\": ").Append(frames.ToString(inv)).Append(", \"videoSeconds\": ").Append(videoSeconds.ToString("0.0", inv)).Append(", \"slowFrames\": ").Append(slow ? "true" : "false").Append(",\n");
            sb.Append("  \"notes\": [");
            for (int i = 0; i < Notes.Count; i++) sb.Append(i > 0 ? ", " : "").Append('"').Append(Esc(Notes[i])).Append('"');
            sb.Append("]\n}\n");
            return sb.ToString();
        }

        static string Esc(string s) { return (s ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", " "); }
    }
}
