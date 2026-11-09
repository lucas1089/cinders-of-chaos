// Slow call timers of the player (O433, unity/README.md "Player on a live server (CI)", "First frame stall (2026-11-09)"). The live smoke run showed one frame of 18 to 23 s right after a
// fresh character entered, and the artifacts had no frame times to say which call it was. This file is the cheap tool that names it, pure C# so Core.Tests can run it:
//   - scopes: `using (SlowCalls.Scope("HelperWindow", "OnGUI")) ...` times a call; a call of ThresholdMs (500) or more is written down with its name, phase, total and own time and when it began;
//   - a marker stack the scopes keep, so a watchdog thread can read where the main thread IS while a frame hangs (a frame that never ends writes no scope);
//   - a frame gap record (Beat once per frame): every gap of ThresholdMs or more with the markers the watchdog saw during it and the last call that ended before it.
// Off by default: with `On` false a scope is a default struct (no clock read, no string, no lock), so normal play pays one volatile read per scope. The live smoke turns it on at its start; the app
// turns it on by itself after a frame of ThresholdMs or more (FrameStarted), so a freeze in normal play is measured the second time it happens.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Threading;

namespace Chaos.Core
{
    /// <summary>One call that took ThresholdMs or more. Ms is the whole call, SelfMs without the scopes inside it, AtMs the start in ms after the origin (SetOrigin), Who the tag of that origin.</summary>
    public sealed class SlowCall
    {
        public string Name = "", Phase = "", Who = "";
        public double Ms, SelfMs, AtMs;
    }

    /// <summary>One gap between two frames of ThresholdMs or more: when it began, how long, what the watchdog saw the main thread doing (distinct places, in order) and the last call that ended before.</summary>
    public sealed class StallRecord
    {
        public double AtMs, Ms;
        public string Who = "", LastEnded = "";
        public readonly List<string> Seen = new List<string>();
    }

    /// <summary>The scope of one timed call. Dispose ends it. A default value (the log was off) does nothing.</summary>
    public readonly struct SlowScope : IDisposable
    {
        readonly SlowCallLog log;
        readonly int index;
        readonly double start;

        internal SlowScope(SlowCallLog log, int index, double start) { this.log = log; this.index = index; this.start = start; }

        public void Dispose() { if (log != null) log.End(index, start); }
    }

    public sealed class SlowCallLog
    {
        public const int MaxCalls = 300, MaxStalls = 24, MaxDepth = 48, MaxSeen = 16;
        /// <summary>A call or a frame gap of this many ms is written down.</summary>
        public double ThresholdMs = 500;
        /// <summary>The watchdog starts to look at a frame gap after this long.</summary>
        public double WatchMs = 1000;
        /// <summary>The watchdog writes down the place at most this often.</summary>
        public double SampleMs = 400;
        /// <summary>The clock in ms; the tests replace it.</summary>
        public Func<double> Clock
        {
            get { return clock; }
            set { clock = value; origin = clock(); }   // a new clock starts a new origin
        }
        Func<double> clock = DefaultClock;

        static readonly Stopwatch stopwatch = Stopwatch.StartNew();
        static double DefaultClock() => stopwatch.Elapsed.TotalMilliseconds;

        volatile bool on;
        public bool On { get { return on; } set { on = value; } }

        readonly object gate = new object();
        readonly List<SlowCall> calls = new List<SlowCall>();
        readonly List<StallRecord> stalls = new List<StallRecord>();
        int droppedCalls;

        // the marker stack: written by the main thread only, read by the watchdog thread (a torn read gives a wrong word in a diagnostic line, never a crash)
        readonly string[] names = new string[MaxDepth], phases = new string[MaxDepth];
        readonly double[] children = new double[MaxDepth];
        int depth;
        volatile string endedName = "", endedPhase = "", note = "";
        double origin;
        volatile string who = "";

        // the frame gaps
        double lastBeat = -1, lastSample = -1e9;
        StallRecord open;

        public SlowCallLog() { origin = Clock(); }

        /// <summary>Starts counting "at" from now, with a tag for the part of the run that follows ("login", "new", "main").</summary>
        public void SetOrigin(string tag)
        {
            lock (gate) { origin = Clock(); who = tag ?? ""; }
        }

        public string Who => who;

        /// <summary>Turns the log on after a frame of ThresholdMs or more (dtMs is the frame's length, Time.unscaledDeltaTime * 1000).</summary>
        public void FrameStarted(double dtMs)
        {
            if (!on && dtMs >= ThresholdMs) on = true;
        }

        /// <summary>Starts a timed call. Main thread only. A null name is "?".</summary>
        public SlowScope Begin(string name, string phase)
        {
            if (!on) return default(SlowScope);
            int i = depth;
            if (i >= MaxDepth) return default(SlowScope);
            names[i] = name ?? "?"; phases[i] = phase ?? ""; children[i] = 0;
            Volatile.Write(ref depth, i + 1);
            return new SlowScope(this, i, Clock());
        }

        internal void End(int index, double start)
        {
            double ms = Clock() - start;
            string name = names[index], phase = phases[index];
            double kids = children[index];
            Volatile.Write(ref depth, index);
            if (index > 0) children[index - 1] += ms;
            endedName = name; endedPhase = phase;
            if (ms < ThresholdMs) return;
            lock (gate)
            {
                if (calls.Count >= MaxCalls) { droppedCalls++; return; }
                calls.Add(new SlowCall { Name = name, Phase = phase, Who = who, Ms = ms, SelfMs = Math.Max(0, ms - kids), AtMs = start - origin });
            }
        }

        /// <summary>A word for "the main thread is between scopes, last seen here" (a Unity callback: "Update", "LateUpdate"). Main thread only.</summary>
        public void Note(string what) { if (on) note = what ?? ""; }

        /// <summary>Where the main thread is: the open scopes from the outside in ("OnGUI HelperWindow > load ArtTexture"), or the last note when none is open. Safe from any thread.</summary>
        public string Where()
        {
            int d = Math.Min(Volatile.Read(ref depth), MaxDepth);
            if (d <= 0) return "outside any timed call, after " + (note.Length > 0 ? note : "?");
            var b = new StringBuilder();
            for (int i = 0; i < d; i++)
            {
                if (i > 0) b.Append(" > ");
                string p = phases[i];
                if (!string.IsNullOrEmpty(p)) b.Append(p).Append(' ');
                b.Append(names[i] ?? "?");
            }
            return b.ToString();
        }

        /// <summary>The last call that ended ("phase name"), "" before the first.</summary>
        public string LastEnded => endedPhase.Length > 0 ? endedPhase + " " + endedName : endedName;

        // ------------------------------------------------------------------------------------ frame gaps
        /// <summary>Once per frame, from the main thread (an Update). A gap of ThresholdMs or more since the last beat is a stall record.</summary>
        public void Beat()
        {
            double now = Clock();
            lock (gate)
            {
                if (lastBeat >= 0 && now - lastBeat >= ThresholdMs)
                {
                    var s = open ?? new StallRecord { AtMs = lastBeat - origin, Who = who };
                    s.Ms = now - lastBeat;
                    if (stalls.Count < MaxStalls) stalls.Add(s);
                }
                open = null;
                lastBeat = now;
            }
        }

        /// <summary>From the watchdog thread, a few times a second: while no beat came for WatchMs, writes down where the main thread is. Returns the line to log when the place is new, else null.</summary>
        public string Sample()
        {
            if (!on) return null;
            double now = Clock();
            string place = Where(), ended = LastEnded;
            lock (gate)
            {
                if (lastBeat < 0) return null;
                double gap = now - lastBeat;
                if (gap < WatchMs) return null;
                if (open == null) open = new StallRecord { AtMs = lastBeat - origin, Who = who };
                open.Ms = gap;
                if (now - lastSample < SampleMs) return null;
                lastSample = now;
                open.LastEnded = ended;
                if (open.Seen.Count > 0 && open.Seen[open.Seen.Count - 1] == place) return null;
                if (open.Seen.Count < MaxSeen) open.Seen.Add(place);
                return "stall in progress: " + Math.Round(gap / 1000.0, 1).ToString("0.0", CultureInfo.InvariantCulture) + " s without a frame (began "
                    + Math.Round(open.AtMs / 1000.0, 1).ToString("0.0", CultureInfo.InvariantCulture) + " s after " + who + " start), the main thread is in: " + place + "; the last call that ended: " + (ended.Length > 0 ? ended : "none");
            }
        }

        // ------------------------------------------------------------------------------------ the record
        /// <summary>The slow calls so far, in the order they ended (a copy).</summary>
        public List<SlowCall> Calls() { lock (gate) return new List<SlowCall>(calls); }

        /// <summary>The frame gaps so far; a gap still going on is the last entry (a copy).</summary>
        public List<StallRecord> Stalls()
        {
            lock (gate)
            {
                var list = new List<StallRecord>(stalls);
                if (open != null && open.Ms >= ThresholdMs && !list.Contains(open)) list.Add(open);
                return list;
            }
        }

        public int DroppedCalls { get { lock (gate) return droppedCalls; } }

        /// <summary>How many frame gaps are over (Stalls() lists one more while a gap is still going on).</summary>
        public int ClosedStalls { get { lock (gate) return stalls.Count; } }

        /// <summary>Forgets everything (the tests).</summary>
        public void Clear()
        {
            lock (gate) { calls.Clear(); stalls.Clear(); open = null; lastBeat = -1; droppedCalls = 0; }
            Volatile.Write(ref depth, 0);
            endedName = ""; endedPhase = ""; note = "";
        }

        // ------------------------------------------------------------------------------------ text
        static string Sec(double ms) => Math.Round(ms / 1000.0, 1).ToString("0.0", CultureInfo.InvariantCulture);

        /// <summary>The calls by own time, longest first (the call that did the work, not the ones around it).</summary>
        public static List<SlowCall> Top(IEnumerable<SlowCall> calls, int n)
        {
            var list = new List<SlowCall>(calls);
            list.Sort((a, b) => b.SelfMs.CompareTo(a.SelfMs));
            if (list.Count > n) list.RemoveRange(n, list.Count - n);
            return list;
        }

        /// <summary>"Name (phase) 21.4 s at 2.4 s, ..." for the top n calls; "" when there are none.</summary>
        public static string Summary(IEnumerable<SlowCall> calls, int n)
        {
            var parts = new List<string>();
            foreach (var c in Top(calls, n))
                parts.Add(c.Name + " (" + c.Phase + ") " + Sec(c.SelfMs) + " s" + (c.Ms - c.SelfMs >= 100 ? " of " + Sec(c.Ms) + " s" : "") + " at " + Sec(c.AtMs) + " s" + (c.Who.Length > 0 ? " " + c.Who : ""));
            return string.Join(", ", parts);
        }

        public static string Line(SlowCall c) =>
            "slow call: " + c.Name + " (" + c.Phase + ") " + Math.Round(c.Ms).ToString("0", CultureInfo.InvariantCulture) + " ms, own " + Math.Round(c.SelfMs).ToString("0", CultureInfo.InvariantCulture) + " ms, at " + Sec(c.AtMs) + " s" + (c.Who.Length > 0 ? " (" + c.Who + ")" : "");

        public static string Line(StallRecord s) =>
            "frame gap: " + Sec(s.Ms) + " s at " + Sec(s.AtMs) + " s" + (s.Who.Length > 0 ? " (" + s.Who + ")" : "") + ", the main thread was seen in: " + (s.Seen.Count > 0 ? string.Join(" | ", s.Seen) : "not seen (under " + Sec(1000) + " s)")
            + "; the last call that ended before: " + (s.LastEnded.Length > 0 ? s.LastEnded : "none");
    }

    /// <summary>The one log of the player.</summary>
    public static class SlowCalls
    {
        public static readonly SlowCallLog Log = new SlowCallLog();

        /// <summary>`using (SlowCalls.Scope("name", "phase")) ...`; the name may be null while the log is off (compute a name only under Log.On).</summary>
        public static SlowScope Scope(string name, string phase) => Log.Begin(name, phase);

        static string[] opNames;

        /// <summary>"msg 0xNN" for a server message opcode, cached (only asked while the log is on).</summary>
        public static string MessageName(byte op)
        {
            var t = opNames ?? (opNames = new string[256]);
            return t[op] ?? (t[op] = "msg 0x" + op.ToString("X2", CultureInfo.InvariantCulture));
        }

        static string[] extNames;

        /// <summary>"ext opcode N", cached.</summary>
        public static string ExtendedName(byte op)
        {
            var t = extNames ?? (extNames = new string[256]);
            return t[op] ?? (t[op] = "ext opcode " + op.ToString(CultureInfo.InvariantCulture));
        }
    }
}
