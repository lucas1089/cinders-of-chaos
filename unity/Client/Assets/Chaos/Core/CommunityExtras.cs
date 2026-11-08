// Community modules, part 3 (O433 phase 5, track S): game_cardborder (opcode 172), game_dropfeed (the option on 229), client_chaos_credits (data: Core/CreditsData.cs, generated),
// client_chaos_streamer (streamer and cinema mode), client_chaos_perf (performance overlay and record), game_chaosshots (automatic screenshots),
// game_outfitextras (the extras of Customise Character). Pure C#: the app (Unity/ChaosApp.Community.cs) feeds the frame data and does the file and screen work.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    // ====================================================================================================== game_cardborder (172)
    /// <summary>Card borders in deck bags. server -> client: state {on [card ids], cards [every card id], decks [every deck id]}; client -> server: sync (once after the login; the server also pushes the set).
    /// A card gets a border only while it sits in a deck container: lit when its id is in `on`, dim otherwise. Before the first message nothing is drawn.</summary>
    public sealed class CardBorderState
    {
        public const byte Opcode = 172;
        public const string OnColor = "#7fe05a", OffColor = "#6a3a3a";
        readonly ExtOpcodes ext;
        public bool Known;
        public HashSet<int> On = new HashSet<int>(), Cards = new HashSet<int>(), Decks = new HashSet<int>();
        public Action Changed = delegate { };

        public CardBorderState(ExtOpcodes e) { ext = e; e.On(Opcode, m => Handle(m.Action, m.Data)); }

        public void Sync() { ext.Send(Opcode, "sync", new Dictionary<string, object>()); }

        static HashSet<int> Set(object list)
        {
            var s = new HashSet<int>();
            if (list is List<object> l) foreach (object o in l) if (o is double d && d == Math.Floor(d)) s.Add((int)d);
            return s;
        }

        void Handle(string action, object data)
        {
            if (action != "state") return;
            On = Set(Json.Get(data, "on")); Cards = Set(Json.Get(data, "cards")); Decks = Set(Json.Get(data, "decks"));
            Known = true;
            Changed();
        }

        public void Clear() { Known = false; On = new HashSet<int>(); Cards = new HashSet<int>(); Decks = new HashSet<int>(); }

        /// <summary>"on" or "off" for a card in a deck container; null for anything else.</summary>
        public string Kind(int deckId, int itemId)
        {
            if (!Known || !Decks.Contains(deckId) || !Cards.Contains(itemId)) return null;
            return On.Contains(itemId) ? "on" : "off";
        }

        public static string ColorOf(string kind) => kind == "on" ? OnColor : kind == "off" ? OffColor : null;
    }

    // ====================================================================================================== game_dropfeed (229)
    /// <summary>Which drop lines this client gets: off, unique and divine only, legendary and better. client -> server: feedopt {mode} on opcode 229 (at the login and when it changes);
    /// the server filters. Saved by the app (PlayerPrefs).</summary>
    public sealed class DropFeedPanel : SocialPanel
    {
        public const byte Opcode = 229;
        public static readonly string[] Modes = { "off", "unique", "legendary" };
        public const string Default = "legendary";
        readonly ExtOpcodes ext;
        public string Mode = Default;
        bool sent;
        public Func<string> Load = () => null;
        public Action<string> Save = delegate { };

        public DropFeedPanel(ExtOpcodes e) { ext = e; }

        public static bool Valid(string mode) => Array.IndexOf(Modes, mode) >= 0;
        public static string Normalize(string mode) => Valid(mode) ? mode : Default;
        public static int IndexOf(string mode) { int i = Array.IndexOf(Modes, mode); return i < 0 ? Modes.Length - 1 : i; }
        public static string NameOf(string mode) => mode == "off" ? Loc.T("Off") : mode == "unique" ? Loc.T("Unique and Divine only") : Loc.T("Legendary and better");
        public static Dictionary<string, object> Packet(string mode) => SFmt.Map("mode", Normalize(mode));

        public void SendMode() { ext.Send(Opcode, "feedopt", Packet(Mode)); }

        /// <summary>After the login: reads the saved choice and tells the server once.</summary>
        public void Poll(bool inGame)
        {
            if (!inGame || sent) return;
            sent = true;
            Mode = Normalize(Load());
            SendMode();
        }

        public override void Clear() { base.Clear(); sent = false; }

        public override void OnForm(string key)
        {
            if (key != "mode") return;
            string m = Modes[Math.Max(0, Math.Min(Modes.Length - 1, Index("mode")))];
            if (m == Mode) return;
            Mode = m; Save(m); SendMode();
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = Loc.T("Drop Feed");
            Header2 = Loc.T("A line in the chat for each rare drop of a player. Choose which ones this client shows.");
            Form["mode"] = IndexOf(Mode).ToString(CultureInfo.InvariantCulture);
            var names = new List<string>();
            foreach (string m in Modes) names.Add(NameOf(m));
            l.Combo(Loc.T("Show drops"), "mode", names);
            return l.Rows;
        }
    }

    // ====================================================================================================== client_chaos_credits
    /// <summary>The Credits window: the sections of docs/CREDITS.md (Core/CreditsData.cs, generated by unity/tools/gen_unity_credits.py), headings in the player's language.</summary>
    public sealed class CreditsPanel : SocialPanel
    {
        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = Loc.T("Credits");
            Header2 = "";
            l.Text(Loc.T("Cinders of Chaos is made with the work of these people and projects. Thank you!"), "text");
            foreach (var s in CreditsData.All)
            {
                l.Section(Loc.Language == Loc.Portuguese && !string.IsNullOrEmpty(s.Pt) ? s.Pt : s.Title);
                if (!string.IsNullOrEmpty(s.Note)) l.Text(s.Note, "dim");
                foreach (var e in s.Entries)
                {
                    var r = l.Row(e.Name, "", "gold");
                    var lines = new List<string>();
                    if (e.Author != null) lines.Add(Loc.T("Author: {0}", e.Author));
                    if (e.Licence != null) lines.Add(Loc.T("Licence: {0}", e.Licence));
                    if (e.Use != null) lines.Add(Loc.T("Used for: {0}", e.Use));
                    if (e.Source != null) lines.Add(Loc.T("Source: {0}", e.Source));
                    r.Tip = string.Join("\n", lines);
                    if (e.Credit != null) r.Sub = e.Credit;
                    else if (lines.Count > 0) r.Sub = lines[0];
                    for (int i = 1; i < lines.Count && e.Credit == null; i++) l.Text("    " + lines[i], "dim");
                    if (e.Credit != null) foreach (string line in lines) l.Text("    " + line, "dim");
                }
            }
            return l.Rows;
        }

        /// <summary>The required credit lines, word for word (a licence asks for them).</summary>
        public static List<string> RequiredCredits()
        {
            var o = new List<string>();
            foreach (var s in CreditsData.All) foreach (var e in s.Entries) if (e.Credit != null) o.Add(e.Credit);
            return o;
        }
    }

    // ====================================================================================================== client_chaos_streamer
    /// <summary>Streamer mode (private messages, the other characters of the list, IP addresses in server messages and, as a sub-option, the own name hidden) and cinema mode (every window and
    /// HUD hidden, the map alone). Options in PlayerPrefs through Load / Save; hotkeys Ctrl+Shift+S and Ctrl+Shift+H.</summary>
    public sealed class StreamerState
    {
        public static readonly string[] Keys = { "streamerMode", "streamerHideSender", "streamerHideOwnName", "cinemaHideOthers" };
        public const string HiddenSender = "[hidden]", IpMask = "***.***.***.***";
        public bool Streamer, HideSender, HideOwnName, CinemaHideOthers, Cinema;
        public Func<string, bool> Load = k => false;
        public Action<string, bool> Save = delegate { };
        public Action Changed = delegate { };

        public void LoadAll()
        {
            Streamer = Load(Keys[0]); HideSender = Load(Keys[1]); HideOwnName = Load(Keys[2]); CinemaHideOthers = Load(Keys[3]);
        }

        public bool Get(string key) { switch (key) { case "streamerMode": return Streamer; case "streamerHideSender": return HideSender; case "streamerHideOwnName": return HideOwnName; case "cinemaHideOthers": return CinemaHideOthers; } return false; }

        public void Set(string key, bool on)
        {
            switch (key) { case "streamerMode": Streamer = on; break; case "streamerHideSender": HideSender = on; break; case "streamerHideOwnName": HideOwnName = on; break; case "cinemaHideOthers": CinemaHideOthers = on; break; default: return; }
            Save(key, on);
            Changed();
        }

        public void ToggleStreamer() { Set("streamerMode", !Streamer); }
        public void ToggleCinema() { Cinema = !Cinema; Changed(); }

        /// <summary>An incoming private message from a player (a gamemaster's red private message stays readable). Replaces the text, and the sender with the sub-option.</summary>
        public bool MaskTalk(byte type, ref string speaker, ref string text)
        {
            if (!Streamer || type != TalkType.PrivateFrom) return false;
            if (HideSender) speaker = Loc.T(HiddenSender);
            text = Loc.T("(private message hidden: streamer mode)");
            return true;
        }

        /// <summary>IPv4 addresses (with an optional :port) in a text, masked while streamer mode is on.</summary>
        public string MaskIps(string text)
        {
            if (!Streamer || string.IsNullOrEmpty(text)) return text;
            var sb = new StringBuilder();
            int i = 0;
            while (i < text.Length)
            {
                if (char.IsDigit(text[i]) && (i == 0 || !char.IsDigit(text[i - 1])))
                {
                    int end;
                    if (IpAt(text, i, out end))
                    {
                        sb.Append(IpMask);
                        if (end < text.Length && text[end] == ':') { int p = end + 1; while (p < text.Length && char.IsDigit(text[p])) p++; if (p > end + 1) end = p; }
                        i = end;
                        continue;
                    }
                }
                sb.Append(text[i]);
                i++;
            }
            return sb.ToString();
        }

        static bool IpAt(string s, int start, out int end)
        {
            end = start;
            int p = start;
            for (int part = 0; part < 4; part++)
            {
                int b = p;
                while (p < s.Length && char.IsDigit(s[p])) p++;
                if (p == b || p - b > 3 || int.Parse(s.Substring(b, p - b), CultureInfo.InvariantCulture) > 255) return false;
                if (part < 3) { if (p >= s.Length || s[p] != '.') return false; p++; }
            }
            if (p < s.Length && char.IsDigit(s[p])) return false;
            end = p;
            return true;
        }

        /// <summary>A character's name in a list: the chosen one stays, the others are masked while streamer mode is on.</summary>
        public string ListName(string name, bool selected) => !Streamer || selected ? name : Loc.T("Hidden character");

        /// <summary>The own name over the character is not drawn (sub-option of streamer mode).</summary>
        public bool HideOwnNameNow => Streamer && HideOwnName;
        /// <summary>The names and bars of other players are not drawn in cinema mode (sub-option).</summary>
        public bool HideOthersNow => Cinema && CinemaHideOthers;
    }

    public sealed class StreamerPanel : SocialPanel
    {
        readonly StreamerState st;
        public StreamerPanel(StreamerState s) { st = s; }

        public override void OnForm(string key)
        {
            if (key.StartsWith("o_", StringComparison.Ordinal)) st.Set(key.Substring(2), Text(key) == "1");
        }

        void Opt(RowList l, string key, string label)
        {
            Form["o_" + key] = st.Get(key) ? "1" : "0";
            l.Combo(label, "o_" + key, new[] { Loc.T("Off"), Loc.T("On") });
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = Loc.T("Streamer and cinema mode");
            Header2 = Loc.T("For videos and streams. Streamer mode: Ctrl+Shift+S. Cinema mode: Ctrl+Shift+H.");
            l.Section(Loc.T("Streamer mode"));
            Opt(l, "streamerMode", Loc.T("Streamer mode"));
            Opt(l, "streamerHideSender", Loc.T("Also hide who sent a private message"));
            Opt(l, "streamerHideOwnName", Loc.T("Also hide my name above my character"));
            l.Text(Loc.T("Private message text, the other characters of the list and IP addresses in server messages are hidden."), "dim");
            l.Section(Loc.T("Cinema mode"));
            Opt(l, "cinemaHideOthers", Loc.T("Also hide the names and bars of other players"));
            var r = l.Row(st.Cinema ? Loc.T("Cinema mode is on") : Loc.T("Cinema mode is off"), "", st.Cinema ? "good" : "dim");
            r.Btn(st.Cinema ? Loc.T("Show the interface") : Loc.T("Hide the interface"), true, st.ToggleCinema);
            return l.Rows;
        }
    }

    // ====================================================================================================== client_chaos_perf
    public struct PerfStats { public int N; public double Min, Max, Avg, Median, P5, P95; }

    public sealed class PerfSample
    {
        public double T, Fps, Gap, MemKb;
        public int? Creatures;
        public List<string> Windows = new List<string>();
    }

    public sealed class PerfRecording
    {
        public double Start;
        public int Seconds = PerfCore.RecordS;
        public readonly List<PerfSample> Samples = new List<PerfSample>();
        public readonly Dictionary<string, int> Windows = new Dictionary<string, int>();
        public bool Done;
    }

    public sealed class PerfSummary
    {
        public int Seconds;
        public PerfStats Fps, Gap, Mem, Creatures;
        public bool HasCreatures;
        public double FrameAvgMs, MemStart, MemEnd, MemGrowthKbPerMin;
        public List<KeyValuePair<string, int>> Windows = new List<KeyValuePair<string, int>>();
        public string Verdict = "low";
    }

    /// <summary>The pure part of the performance overlay (perf_core.lua): statistics, the record, its verdict, the CSV and the text report.</summary>
    public static class PerfCore
    {
        public const int WindowS = 10, RecordS = 60, MaxWindows = 40;
        public const double GoodFps = 60, LowFps = 30;

        public static double Percentile(List<double> sorted, double p)
        {
            int n = sorted.Count;
            if (n == 0) return 0;
            int k = (int)Math.Ceiling(p / 100 * n);
            return sorted[Math.Max(1, Math.Min(n, k)) - 1];
        }

        public static PerfStats Stats(IEnumerable<double> values)
        {
            var s = new List<double>();
            foreach (double v in values) if (!double.IsNaN(v) && !double.IsInfinity(v)) s.Add(v);
            s.Sort();
            if (s.Count == 0) return new PerfStats();
            double sum = 0;
            foreach (double v in s) sum += v;
            return new PerfStats { N = s.Count, Min = s[0], Max = s[s.Count - 1], Avg = sum / s.Count, Median = Percentile(s, 50), P5 = Percentile(s, 5), P95 = Percentile(s, 95) };
        }

        /// <summary>"good", "ok" or "low" against the target (60 FPS average, the lowest 5 % at least 30).</summary>
        public static string Verdict(double avg, double p5)
        {
            if (avg >= GoodFps * 0.95 && p5 >= LowFps) return "good";
            if (avg >= LowFps && p5 >= LowFps * 0.5) return "ok";
            return "low";
        }

        public static bool AddSample(PerfRecording rec, PerfSample s)
        {
            var row = new PerfSample { T = s.T - rec.Start, Fps = s.Fps, Gap = s.Gap, MemKb = s.MemKb, Creatures = s.Creatures };
            var seen = new HashSet<string>();
            foreach (string id in s.Windows)
            {
                if (!seen.Add(id) || row.Windows.Count >= MaxWindows) continue;
                row.Windows.Add(id);
                rec.Windows[id] = (rec.Windows.TryGetValue(id, out int c) ? c : 0) + 1;
            }
            row.Windows.Sort(string.CompareOrdinal);
            rec.Samples.Add(row);
            if (rec.Samples.Count >= rec.Seconds) rec.Done = true;
            return rec.Done;
        }

        public static PerfSummary Summarize(PerfRecording rec)
        {
            var fps = new List<double>(); var gaps = new List<double>(); var mem = new List<double>(); var cr = new List<double>();
            foreach (var s in rec.Samples) { fps.Add(s.Fps); gaps.Add(s.Gap); mem.Add(s.MemKb); if (s.Creatures.HasValue) cr.Add(s.Creatures.Value); }
            int n = rec.Samples.Count;
            var f = Stats(fps);
            var sum = new PerfSummary { Seconds = n, Fps = f, Gap = Stats(gaps), Mem = Stats(mem), FrameAvgMs = f.Avg > 0 ? 1000 / f.Avg : 0, Verdict = Verdict(f.Avg, f.P5) };
            if (cr.Count > 0) { sum.Creatures = Stats(cr); sum.HasCreatures = true; }
            if (n > 0) { sum.MemStart = rec.Samples[0].MemKb; sum.MemEnd = rec.Samples[n - 1].MemKb; }
            if (n > 1)
            {
                double span = (rec.Samples[n - 1].T - rec.Samples[0].T) / 1000;
                if (span > 0) sum.MemGrowthKbPerMin = (sum.MemEnd - sum.MemStart) / span * 60;
            }
            foreach (var kv in rec.Windows) sum.Windows.Add(kv);
            sum.Windows.Sort((a, b) => a.Value != b.Value ? b.Value.CompareTo(a.Value) : string.CompareOrdinal(a.Key, b.Key));
            return sum;
        }

        static string Cell(string v) => v.IndexOfAny(new[] { '"', ',', '\n' }) >= 0 ? "\"" + v.Replace("\"", "\"\"") + "\"" : v;
        static string F(double v, string fmt = "0") => v.ToString(fmt, CultureInfo.InvariantCulture);

        public static string Csv(PerfRecording rec)
        {
            var sb = new StringBuilder("second,fps,frame_ms,worst_frame_ms,managed_kb,creatures,windows\n");
            int i = 0;
            foreach (var s in rec.Samples)
            {
                i++;
                sb.Append(i).Append(',').Append(F(Math.Floor(s.Fps + 0.5))).Append(',').Append(s.Fps > 0 ? F(1000 / s.Fps, "0.0") : "").Append(',').Append(F(Math.Floor(s.Gap + 0.5)))
                  .Append(',').Append(F(Math.Floor(s.MemKb + 0.5))).Append(',').Append(s.Creatures.HasValue ? s.Creatures.Value.ToString(CultureInfo.InvariantCulture) : "").Append(',')
                  .Append(Cell(string.Join(" ", s.Windows))).Append('\n');
            }
            return sb.ToString();
        }

        public static string Report(PerfSummary sum, string stamp, string version, string os, string screen)
        {
            var sb = new StringBuilder();
            Action<string> add = t => sb.Append(t).Append('\n');
            add("Cinders of Chaos Unity client performance record");
            add("when: " + stamp + "  client: " + version + "  os: " + os + "  screen: " + screen);
            add("seconds: " + sum.Seconds);
            add("verdict: " + sum.Verdict + " (target avg " + F(GoodFps) + " FPS, lowest 5% at least " + F(LowFps) + ")");
            add("");
            add("FPS: avg " + F(sum.Fps.Avg, "0.0") + "  min " + F(sum.Fps.Min) + "  p5 " + F(sum.Fps.P5) + "  median " + F(sum.Fps.Median) + "  max " + F(sum.Fps.Max));
            add("frame time: avg " + F(sum.FrameAvgMs, "0.0") + " ms (from FPS)");
            add("worst frame of a second: worst " + F(sum.Gap.Max) + " ms  p95 " + F(sum.Gap.P95) + " ms  median " + F(sum.Gap.Median) + " ms");
            add("managed memory: start " + F(sum.MemStart) + " KB  end " + F(sum.MemEnd) + " KB  max " + F(sum.Mem.Max) + " KB  growth " + F(sum.MemGrowthKbPerMin) + " KB/min");
            if (sum.HasCreatures) add("creatures on screen: avg " + F(sum.Creatures.Avg, "0.0") + "  max " + F(sum.Creatures.Max));
            add("");
            add("open windows (seconds visible of " + sum.Seconds + "):");
            if (sum.Windows.Count == 0) add("  none");
            for (int i = 0; i < sum.Windows.Count; i++)
            {
                if (i >= 25) { add("  ... " + (sum.Windows.Count - 25) + " more"); break; }
                add("  " + sum.Windows[i].Key + " " + sum.Windows[i].Value);
            }
            return sb.ToString();
        }

        public static string Stamp(DateTime d) => d.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
        public static string CsvName(string stamp) => "chaos-perf-" + stamp + ".csv";
        public static string TextName(string stamp) => "chaos-perf-" + stamp + ".txt";
    }

    /// <summary>The running overlay: one sample a second from the frames the app reports, the last 10 seconds for the overlay and an optional 60 second record.</summary>
    public sealed class PerfState
    {
        public readonly List<PerfSample> Recent = new List<PerfSample>();
        public PerfRecording Recording;
        public string LastReport = "", LastFiles = "";
        public Action<string, string, string> WriteFiles = delegate { };   // stamp, csv, report text
        public Func<DateTime> UtcNow = () => DateTime.UtcNow;
        public string Version = "Unity prototype", Os = "", Screen = "";
        double secStart = -1, worst;
        int frames;

        /// <summary>Once per frame: the time now and the length of the last frame (ms), the managed memory (KB), the creatures in view and the names of the open windows.</summary>
        public void Frame(double nowMs, double dtMs, double memKb, int creatures, IEnumerable<string> windows)
        {
            if (secStart < 0) secStart = nowMs;
            frames++;
            if (dtMs > worst) worst = dtMs;
            double span = nowMs - secStart;
            if (span < 1000) return;
            var s = new PerfSample { T = nowMs, Fps = frames * 1000.0 / span, Gap = worst, MemKb = memKb, Creatures = creatures };
            if (windows != null) s.Windows.AddRange(windows);
            frames = 0; worst = 0; secStart = nowMs;
            Recent.Add(s);
            while (Recent.Count > PerfCore.WindowS) Recent.RemoveAt(0);
            if (Recording != null && PerfCore.AddSample(Recording, s)) Finish();
        }

        public void Record()
        {
            Recording = new PerfRecording { Start = Recent.Count > 0 ? Recent[Recent.Count - 1].T : 0 };
            if (Recent.Count > 0) Recording.Start = Recent[Recent.Count - 1].T;
            else Recording.Start = secStart < 0 ? 0 : secStart;
        }

        void Finish()
        {
            var rec = Recording;
            Recording = null;
            var sum = PerfCore.Summarize(rec);
            string stamp = PerfCore.Stamp(UtcNow());
            LastReport = PerfCore.Report(sum, stamp, Version, Os, Screen);
            LastFiles = PerfCore.CsvName(stamp) + ", " + PerfCore.TextName(stamp);
            WriteFiles(stamp, PerfCore.Csv(rec), LastReport);
        }

        public int RecordedSeconds => Recording == null ? 0 : Recording.Samples.Count;

        public PerfStats Fps() { var l = new List<double>(); foreach (var s in Recent) l.Add(s.Fps); return PerfCore.Stats(l); }
        public double WorstFrame() { double m = 0; foreach (var s in Recent) m = Math.Max(m, s.Gap); return m; }
    }

    public sealed class PerfPanel : SocialPanel
    {
        readonly PerfState perf;
        public Action<string> Copy = delegate { };
        public PerfPanel(PerfState p) { perf = p; }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = Loc.T("Performance");
            Header2 = Loc.T("The last 10 seconds. Record 60 s writes a CSV and a text summary in the client's data folder.");
            if (perf.Recent.Count == 0) { l.Text(Loc.T("Measuring..."), "dim"); }
            else
            {
                var last = perf.Recent[perf.Recent.Count - 1];
                var f = perf.Fps();
                l.Row(Loc.T("FPS"), PerfCore.Stats(new[] { last.Fps }).Avg.ToString("0", CultureInfo.InvariantCulture), f.Avg >= PerfCore.GoodFps * 0.95 ? "good" : f.Avg >= PerfCore.LowFps ? "warn" : "bad");
                l.Row(Loc.T("Average and lowest"), f.Avg.ToString("0.0", CultureInfo.InvariantCulture) + " / " + f.Min.ToString("0", CultureInfo.InvariantCulture));
                l.Row(Loc.T("Frame time"), (f.Avg > 0 ? 1000 / f.Avg : 0).ToString("0.0", CultureInfo.InvariantCulture) + " ms");
                l.Row(Loc.T("Worst frame"), perf.WorstFrame().ToString("0", CultureInfo.InvariantCulture) + " ms");
                l.Row(Loc.T("Managed memory"), (last.MemKb / 1024).ToString("0.0", CultureInfo.InvariantCulture) + " MB");
                if (last.Creatures.HasValue) l.Row(Loc.T("Creatures on screen"), last.Creatures.Value.ToString(CultureInfo.InvariantCulture));
                l.Row(Loc.T("Open windows"), last.Windows.Count.ToString(CultureInfo.InvariantCulture));
            }
            var r = l.Row(perf.Recording != null ? Loc.T("Recording: {0} of {1} s", perf.RecordedSeconds, PerfCore.RecordS) : Loc.T("Record"), "", perf.Recording != null ? "warn" : "text");
            r.Btn(Loc.T("Record 60 s"), perf.Recording == null, () => { perf.Record(); Changed(); });
            r.Btn(Loc.T("Copy summary"), perf.LastReport.Length > 0, () => { Copy(perf.LastReport); Say(Loc.T("Summary copied."), true); });
            if (perf.LastFiles.Length > 0) l.Text(Loc.T("Last record: {0}", perf.LastFiles), "dim");
            return l.Rows;
        }
    }

    // ====================================================================================================== game_chaosshots
    /// <summary>Automatic screenshots of the Chaos moments (shots_core.lua): level up, valuable loot, boss defeated, achievement, new record. The app takes the picture 0.3 s after the event into a
    /// local "screenshots" folder; the options are saved by the app. Boss defeated needs the monster tiers of the main client's health event and is not ported yet.</summary>
    public sealed class ShotEvent { public string Key, Label, File; public bool Default; public int Rank; }

    public sealed class ShotsState
    {
        public const double DelayMs = 300, SameEventMs = 3000;
        public const string Folder = "screenshots", MasterKey = "autoScreenshot";
        public const int LootMinRank = 5;
        public static readonly string[] RecordPrefixes = { "New record: ", "Novo recorde: " };

        public static readonly ShotEvent[] Events =
        {
            new ShotEvent { Key = "level", Label = "Level Up", File = "levelup", Default = true, Rank = 2 },
            new ShotEvent { Key = "loot", Label = "Valuable Loot", File = "loot", Default = false, Rank = 3 },
            new ShotEvent { Key = "boss", Label = "Boss Defeated", File = "boss", Default = false, Rank = 4 },
            new ShotEvent { Key = "achievement", Label = "Achievement", File = "achievement", Default = true, Rank = 1 },
            new ShotEvent { Key = "record", Label = "New Record", File = "record", Default = true, Rank = 5 },
        };

        public static ShotEvent Find(string key) { foreach (var e in Events) if (e.Key == key) return e; return null; }

        readonly Dictionary<string, bool> opts = new Dictionary<string, bool>();
        public Func<string, bool?> Load = k => null;
        public Action<string, bool> Save = delegate { };
        public string Pending;
        double pendingAt;
        readonly Dictionary<string, double> last = new Dictionary<string, double>();
        public int LastLevel;
        public bool Streamer;
        /// <summary>The app takes the picture: event key, the file name (with the folder) it should have.</summary>
        public Action<string, string> Shoot = delegate { };
        public Func<string> CharName = () => "";
        public Func<int> LevelNow = () => 0;
        public Func<DateTime> UtcNow = () => DateTime.UtcNow;
        public Func<string, bool> Exists = p => false;
        public Action<string> Saved = delegate { };
        /// <summary>Boss Defeated: the bosses in view with their health, and the creature being attacked (set by the session).</summary>
        public Func<IEnumerable<KeyValuePair<uint, int>>> BossesNow;
        public Func<uint> TargetNow = () => 0u;
        public readonly BossKillWatch Boss = new BossKillWatch();

        public ShotsState(ExtOpcodes e)
        {
            e.On(250, m => { if (m.Action == "unlock") Request("achievement", Clock); });
            e.On(238, m => { if (m.Action == "kill") OnKill(m.Data); });
        }

        public bool Option(string key, bool fallback)
        {
            if (!opts.TryGetValue(key, out bool v)) { var l = Load(key); v = l ?? fallback; opts[key] = v; }
            return v;
        }

        public void SetOption(string key, bool on) { opts[key] = on; Save(key, on); }
        public bool Master => Option(MasterKey, true);
        public bool Wants(string ev) { var e = Find(ev); return e != null && Master && Option("shots_" + ev, e.Default); }

        public double Clock;

        /// <summary>An event at time now (ms): "shoot" (the delay starts), "merged" (a picture is coming: it names the higher event), "repeat" (the same event a moment ago), "off".</summary>
        public string Request(string ev, double now)
        {
            if (!Wants(ev)) return "off";
            if (last.TryGetValue(ev, out double at) && now - at < SameEventMs) return "repeat";
            last[ev] = now;
            if (Pending != null)
            {
                var cur = Find(Pending); var nw = Find(ev);
                if (nw != null && cur != null && nw.Rank > cur.Rank) Pending = ev;
                return "merged";
            }
            Pending = ev; pendingAt = now;
            return "shoot";
        }

        static string Clean(string s)
        {
            var sb = new StringBuilder();
            foreach (char c in s ?? "") sb.Append(char.IsLetterOrDigit(c) && c < 128 || c == '-' ? c : '_');
            return sb.ToString();
        }

        /// <summary>"screenshots/name_level_event_date.png"; streamer mode leaves the name out; exists picks a free name.</summary>
        public static string FileName(string ev, string charName, int level, string dateText, bool streamer, Func<string, bool> exists)
        {
            var e = Find(ev);
            var parts = new List<string>();
            if (!streamer && !string.IsNullOrEmpty(charName)) parts.Add(Clean(charName));
            parts.Add(level.ToString(CultureInfo.InvariantCulture));
            parts.Add(e != null ? e.File : Clean(ev));
            parts.Add(Clean(dateText));
            string basePath = Folder + "/" + string.Join("_", parts);
            string name = basePath + ".png";
            int n = 0;
            while (exists != null && exists(name) && n < 1000) { n++; name = basePath + "_" + n + ".png"; }
            return name;
        }

        public static string ToastText(string folderPath, bool streamer) => Loc.T("Screenshot saved in {0}", streamer || string.IsNullOrEmpty(folderPath) ? Folder : folderPath);

        public static bool ValuableLoot(int rarity, bool unique) => unique || rarity >= LootMinRank;
        public static bool IsRecordMessage(string text) { if (text == null) return false; foreach (string p in RecordPrefixes) if (text.StartsWith(p, StringComparison.Ordinal)) return true; return false; }
        public static bool IsLevelUp(int now, int old) => old > 0 && now > old;

        void OnKill(object data)
        {
            foreach (object row in Json.List(data, "items"))
            {
                var info = LootInfo.From(row);
                if (ValuableLoot(info.R, info.U)) { Request("loot", Clock); return; }
            }
        }

        public void OnServerText(string text) { if (IsRecordMessage(text)) Request("record", Clock); }

        /// <summary>Per frame: the level up check and the delayed picture.</summary>
        public void Poll(double now, bool inGame)
        {
            Clock = now;
            if (!inGame) { LastLevel = 0; Pending = null; return; }
            int level = LevelNow();
            if (IsLevelUp(level, LastLevel)) Request("level", now);
            if (level > 0) LastLevel = level;
            if (BossesNow != null && Boss.Step(now, TargetNow(), BossesNow()) > 0) Request("boss", now);   // Boss Defeated (BossKillWatch, Core/Phase7Q.cs)
            if (Pending != null && now - pendingAt >= DelayMs)
            {
                string ev = Pending;
                Pending = null;
                var d = UtcNow();
                Shoot(ev, FileName(ev, CharName(), level, d.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture), Streamer, Exists));
            }
        }
    }

    public sealed class ShotsPanel : SocialPanel
    {
        readonly ShotsState st;
        public ShotsPanel(ShotsState s) { st = s; }

        public override void OnForm(string key)
        {
            if (!key.StartsWith("s_", StringComparison.Ordinal)) return;
            string k = key.Substring(2);
            st.SetOption(k == "master" ? ShotsState.MasterKey : "shots_" + k, Text(key) == "1");
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = Loc.T("Screenshots");
            Header2 = Loc.T("A picture of the game window at the great moments, saved in the screenshots folder of the client's data folder.");
            Form["s_master"] = st.Master ? "1" : "0";
            l.Combo(Loc.T("Automatic screenshots"), "s_master", new[] { Loc.T("Off"), Loc.T("On") });
            foreach (var e in ShotsState.Events)
            {
                Form["s_" + e.Key] = st.Option("shots_" + e.Key, e.Default) ? "1" : "0";
                l.Combo(Loc.T(e.Label), "s_" + e.Key, new[] { Loc.T("Off"), Loc.T("On") });
            }
            l.Text(Loc.T("Boss Defeated is not available in this client yet."), "dim");
            return l.Rows;
        }
    }

    // ====================================================================================================== game_outfitextras
    /// <summary>The extras of Customise Character: outline, footprints, kill effect, loot label, chat colour, spell effect (the cosmetics the account owns, opcode 225), the plate frame
    /// (Info and Services) and the pet. One combo per row; Apply sends the changed rows through the same calls the Cosmetics, Info and Pets windows use. Wings, outfit, mount, aura and shader stay in the
    /// Outfit window (their packet). Rules: outfitextrascore.lua.</summary>
    public sealed class OutfitExtrasPanel : SocialPanel
    {
        public static readonly string[] Keys = { "outline", "footprint", "killfx", "lootbeam", "chatcolor", "spellskin", "frame", "pet" };
        public static readonly string[] CosmeticKinds = { "outline", "footprint", "killfx", "lootbeam", "chatcolor", "spellskin" };

        public sealed class Option { public string Text = ""; public string Value = ""; public CosRow Row; }
        public sealed class ExtraRow { public string Key = "", Label = ""; public List<Option> Options = new List<Option>(); public string Current = ""; public int Locked; public string Line; }

        readonly Func<CosmeticsState> cos;
        readonly Func<PetsState> pets;
        readonly Func<ChaosInfo> info;

        public OutfitExtrasPanel(Func<CosmeticsState> c, Func<PetsState> p, Func<ChaosInfo> i) { cos = c; pets = p; info = i; }

        public static string Label(string key)
        {
            switch (key)
            {
                case "outline": return Loc.T("Outline"); case "footprint": return Loc.T("Footprints"); case "killfx": return Loc.T("Kill effect"); case "lootbeam": return Loc.T("Loot label");
                case "chatcolor": return Loc.T("Chat colour"); case "spellskin": return Loc.T("Spell effect"); case "frame": return Loc.T("Plate frame"); case "pet": return Loc.T("Pet");
            }
            return key;
        }

        /// <summary>A cosmetic kind: the default, then the rows of the kind the account owns (spell skins: of the character's line only).</summary>
        public static ExtraRow CosmeticRow(object state, string kind)
        {
            if (!Cm.IsMap(state) || !(Json.Get(state, "rows") is List<object>)) return null;
            var row = new ExtraRow { Key = kind, Label = Label(kind), Current = "0", Line = kind == "spellskin" ? Json.Text(state, "line") : null };
            row.Options.Add(new Option { Text = Loc.T("Default"), Value = "0" });
            foreach (var r in SFmt.Rows(state, "rows"))
            {
                if (Json.Text(r, "kind") != kind || (kind == "spellskin" && Json.Text(r, "line") != Json.Text(state, "line"))) continue;
                if (Json.Bool(r, "owned"))
                {
                    var cr = CosmeticsLogic.FromServer((Dictionary<string, object>)r);
                    row.Options.Add(new Option { Text = Json.Text(r, "name", Json.Text(r, "key", Json.Text(r, "id"))), Value = Json.Text(r, "id", Json.Int(r, "id").ToString(CultureInfo.InvariantCulture)), Row = cr });
                    if (Json.Bool(r, "selected")) row.Current = row.Options[row.Options.Count - 1].Value;
                }
                else row.Locked++;
            }
            return row;
        }

        /// <summary>Plate frame: the title's own, then the frames the character owns.</summary>
        public static ExtraRow FrameRow(object services)
        {
            if (!Cm.IsMap(services)) return null;
            var row = new ExtraRow { Key = "frame", Label = Label("frame"), Current = "" };
            row.Options.Add(new Option { Text = Loc.T("Title frame"), Value = "" });
            foreach (object f in Json.List(services, "frames")) if (f is string s && s.Length > 0) row.Options.Add(new Option { Text = char.ToUpperInvariant(s[0]) + s.Substring(1), Value = s });
            string cur = Json.Text(services, "activeFrame");
            row.Current = row.Options.Exists(o => o.Value == cur) ? cur : "";
            return row;
        }

        /// <summary>Pet: none (dismissed), then the pets the character owns, with their level.</summary>
        public static ExtraRow PetRow(object state)
        {
            if (!Cm.IsMap(state) || !(Json.Get(state, "pets") is List<object>)) return null;
            var row = new ExtraRow { Key = "pet", Label = Label("pet"), Current = "" };
            row.Options.Add(new Option { Text = Loc.T("None"), Value = "" });
            var known = new HashSet<string>();
            foreach (var p in SFmt.Rows(state, "pets"))
            {
                string sp = Json.Text(p, "species");
                if (sp.Length == 0) continue;
                known.Add(sp);
                string name = Json.Text(p, "name", Json.Text(p, "speciesName", sp));
                row.Options.Add(new Option { Text = Json.Get(p, "level") != null ? Loc.T("{0} (level {1})", name, Json.Int(p, "level")) : name, Value = sp });
            }
            string active = Json.Text(state, "active");
            row.Current = known.Contains(active) ? active : "";
            foreach (var c in SFmt.Rows(state, "catalog")) if (!Json.Bool(c, "owned") && !known.Contains(Json.Text(c, "key"))) row.Locked++;
            return row;
        }

        public List<ExtraRow> Rows()
        {
            var o = new List<ExtraRow>();
            var c = cos();
            foreach (string kind in CosmeticKinds) { var r = CosmeticRow(c?.State, kind); if (r != null) o.Add(r); }
            var fr = FrameRow(info()?.Services); if (fr != null) o.Add(fr);
            var pr = PetRow(pets()?.State); if (pr != null) o.Add(pr);
            return o;
        }

        public sealed class PlanAction { public string Act = "", Kind = "", Value = "", Line; public CosRow Row; }

        /// <summary>The actions for the rows whose chosen option differs from the shown one, in order. chosen: row key -> option index.</summary>
        public static List<PlanAction> Plan(List<ExtraRow> rows, Func<string, int> chosen)
        {
            var o = new List<PlanAction>();
            foreach (var row in rows)
            {
                int idx = chosen(row.Key);
                if (idx < 0 || idx >= row.Options.Count) continue;
                var opt = row.Options[idx];
                if (opt.Value == row.Current) continue;
                if (Array.IndexOf(CosmeticKinds, row.Key) >= 0) o.Add(new PlanAction { Act = "cosmetic", Kind = row.Key, Value = opt.Value, Line = row.Line, Row = opt.Row });
                else if (row.Key == "frame") o.Add(new PlanAction { Act = "frame", Value = opt.Value });
                else if (row.Key == "pet") o.Add(new PlanAction { Act = "pet", Value = opt.Value });
            }
            return o;
        }

        public void Apply()
        {
            var rows = Rows();
            var plan = Plan(rows, k => Form.ContainsKey("x_" + k) ? Index("x_" + k) : -1);
            int n = 0;
            foreach (var a in plan)
            {
                n++;
                if (a.Act == "cosmetic")
                {
                    var row = a.Row ?? new CosRow { Kind = a.Kind, Id = "0", Line = a.Line, Owned = true };
                    cos()?.Select(row);
                }
                else if (a.Act == "frame") info()?.Run("services", new List<string> { "plateframe" }, new List<string> { a.Value.Length == 0 ? "off" : a.Value });
                else if (a.Act == "pet") { if (a.Value.Length == 0) pets()?.Dismiss(); else pets()?.Summon(a.Value); }
            }
            Say(n == 0 ? Loc.T("Nothing to change.") : Loc.T("Applied {0} change(s).", n), n > 0);
            foreach (var row in rows) Form.Remove("x_" + row.Key);
        }

        public override void Show() { Visible = true; cos()?.Hello(); pets()?.Show(); info()?.RequestServices(); }
        public override void Hide() { Visible = false; pets()?.Hide(); }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = Loc.T("Customise Character");
            Header2 = Loc.T("The cosmetics you own. Outfit, mount, wings, aura and shader are in the Outfit window.");
            var rows = Rows();
            if (rows.Count == 0) { l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            foreach (var row in rows)
            {
                string key = "x_" + row.Key;
                if (!Form.ContainsKey(key)) { int cur = row.Options.FindIndex(o => o.Value == row.Current); Form[key] = Math.Max(0, cur).ToString(CultureInfo.InvariantCulture); }
                var names = new List<string>();
                foreach (var o in row.Options) names.Add(o.Text);
                var c = l.Combo(row.Label, key, names);
                if (row.Locked > 0) c.Tip = Loc.T("{0} more not unlocked yet. See Character > Cosmetics and the Store.", row.Locked);
            }
            l.Row(Loc.T("Apply the changes")).Btn(Loc.T("Apply"), true, Apply);
            return l.Rows;
        }
    }
}
