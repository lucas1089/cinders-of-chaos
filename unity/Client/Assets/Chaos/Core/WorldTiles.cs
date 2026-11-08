// Things drawn over the map (client game_tileoverlays 156, game_chaosweather 114, game_nameplate 248). Pure models.
//
// tileoverlays 156  client hello {} (every game start); server bars {s = [{i, p = [x, y, z], n, c, v | l + t}], d = [ids]} | clear {}. Field timers (seconds left over magic
//                   walls and timed fields) come from the tiles themselves: Unity has no add/remove tile hooks, so the world is scanned about 4 times a second.
// chaosweather 114  client hello; server set {k = rain | none, i = level 1..3, f = fade ms, a = embers | motes | dust, m = ice | swamp | desert | fire | crypt}
// nameplate 248     plain text. server: one plate a line "cid|title|color|guild|frame"; client "q|id,id,...".
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    // ------------------------------------------------------------------------------------------------ tile overlays
    public sealed class FieldRecord
    {
        public string Key = "", Name = "";
        public Pos Pos;
        public int Id, Total;
        public double Start = -1;   // ms, -1 unknown
    }

    public sealed class TileBar
    {
        public string Id = "", Label = "", Color = "#d8b45a";
        public Pos Pos;
        public double EndMs = -1, TotalMs, V;
        public bool Countdown => EndMs >= 0;
    }

    public sealed class TileOverlays
    {
        public const byte Opcode = 156;
        public const double GraceMs = 250;
        public const string Unknown = "~", DefaultColor = "#d8b45a";
        public const int BarW = 66, BarH = 20, BarGap = 2, BarInner = 64;

        readonly ExtOpcodes ext;
        public readonly Dictionary<string, FieldRecord> Recs = new Dictionary<string, FieldRecord>();
        readonly Dictionary<string, KeyValuePair<FieldRecord, double>> ghosts = new Dictionary<string, KeyValuePair<FieldRecord, double>>();
        public readonly Dictionary<string, TileBar> Bars = new Dictionary<string, TileBar>();
        HashSet<Pos> prevTiles = new HashSet<Pos>();
        public bool FieldsOn = true;
        public Func<double> Clock = () => 0;
        public Action Changed = delegate { };

        public TileOverlays(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        public void Hello() { ext.Send(Opcode, "hello", new Dictionary<string, object>()); }

        // ---- text
        /// <summary>Seconds as the text over a tile: "9", "45", "1:05", "12:00".</summary>
        public static string FormatSeconds(double s)
        {
            int n = (int)Math.Max(0, Math.Floor(s));
            if (n < 60) return n.ToString(CultureInfo.InvariantCulture);
            return (n / 60).ToString(CultureInfo.InvariantCulture) + ":" + (n % 60).ToString("00", CultureInfo.InvariantCulture);
        }

        /// <summary>Ms left to whole seconds, rounded up: "1" until the very end, never "0" while time is left.</summary>
        public static int SecondsLeft(double ms) => ms <= 0 ? 0 : (int)Math.Floor((ms + 999) / 1000);

        public static bool ValidPos(int x, int y, int z) => x >= 0 && y >= 0 && x < 65535 && y < 65535 && z >= 0 && z <= 15;

        public static bool InRange(Pos p, Pos refPos) =>
            p.Z == refPos.Z && p.X - refPos.X >= -World.RangeLeft && p.X - refPos.X <= World.RangeRight && p.Y - refPos.Y >= -World.RangeTop && p.Y - refPos.Y <= World.RangeBottom;

        static string RecKey(Pos p, int id) => p.X + "," + p.Y + "," + p.Z + "#" + id;

        // ---- field timers
        public FieldRecord FieldAdd(Pos pos, int id, double now, bool known)
        {
            if (!FieldData.Fields.TryGetValue(id, out var def) || !ValidPos(pos.X, pos.Y, pos.Z)) return null;
            string key = RecKey(pos, id);
            if (Recs.TryGetValue(key, out var cur)) return cur;
            FieldRecord rec;
            if (ghosts.TryGetValue(key, out var g) && now - g.Value <= GraceMs && known) rec = g.Key;   // the tile was rebuilt: same field, same timer
            else rec = new FieldRecord { Key = key, Pos = pos, Id = id, Total = def.Key, Name = def.Value, Start = known ? now : -1 };
            ghosts.Remove(key);
            Recs[key] = rec;
            return rec;
        }

        public FieldRecord FieldRemove(Pos pos, int id, double now)
        {
            string key = RecKey(pos, id);
            if (!Recs.TryGetValue(key, out var rec)) return null;
            Recs.Remove(key);
            ghosts[key] = new KeyValuePair<FieldRecord, double>(rec, now);
            return rec;
        }

        /// <summary>Drops old ghosts and the records that left the player's view (they come back as "~").</summary>
        public List<FieldRecord> FieldSweep(double now, Pos player)
        {
            foreach (string k in new List<string>(ghosts.Keys)) if (now - ghosts[k].Value > GraceMs) ghosts.Remove(k);
            var dropped = new List<FieldRecord>();
            foreach (var kv in new List<KeyValuePair<string, FieldRecord>>(Recs))
                if (!InRange(kv.Value.Pos, player)) { dropped.Add(kv.Value); Recs.Remove(kv.Key); }
            dropped.Sort((a, b) => string.CompareOrdinal(a.Key, b.Key));
            return dropped;
        }

        public static double FieldLeft(FieldRecord r, double now) => r.Start < 0 ? double.NaN : r.Start + r.Total - now;

        public static string FieldText(FieldRecord r, double now)
        {
            double left = FieldLeft(r, now);
            if (double.IsNaN(left) || left < -2000) return Unknown;
            return FormatSeconds(SecondsLeft(left));
        }

        /// <summary>White, orange in the last 5 s, grey when unknown.</summary>
        public static string FieldColor(FieldRecord r, double now)
        {
            double left = FieldLeft(r, now);
            if (double.IsNaN(left) || left < -2000) return "#bfb6a6";
            return left <= 5000 ? "#ffa040" : "#ffffff";
        }

        /// <summary>Reads the world: a field seen appearing on a tile that was in the last scan starts its timer, one that came with its tile shows "~".</summary>
        public void Scan(World w, double now)
        {
            var me = w?.Player;
            if (me == null) return;
            var seen = new HashSet<string>();
            var tiles = new HashSet<Pos>();
            if (FieldsOn)
                foreach (var t in w.Tiles.Values)
                {
                    tiles.Add(t.Pos);
                    foreach (var th in t.Things)
                    {
                        if (th.IsCreature || th.Item == null || !FieldData.Fields.ContainsKey(th.Item.Id)) continue;
                        string key = RecKey(t.Pos, th.Item.Id);
                        seen.Add(key);
                        if (!Recs.ContainsKey(key)) FieldAdd(t.Pos, th.Item.Id, now, prevTiles.Contains(t.Pos));
                    }
                }
            foreach (var kv in new List<KeyValuePair<string, FieldRecord>>(Recs))
                if (!seen.Contains(kv.Key)) FieldRemove(kv.Value.Pos, kv.Value.Id, now);
            FieldSweep(now, me.Position);
            prevTiles = tiles;
        }

        // ---- server bars
        public static string BarColor(string c) => c != null && c.Length == 7 && c[0] == '#' && IsHex(c) ? c.ToLowerInvariant() : DefaultColor;
        static bool IsHex(string s) { for (int i = 1; i < s.Length; i++) if (!Uri.IsHexDigit(s[i])) return false; return true; }

        public static TileBar ParseBar(object w, double now)
        {
            if (!(w is Dictionary<string, object>)) return null;
            string id = Json.Text(w, "i");
            var p = Json.Get(w, "p") as List<object>;
            if (id.Length == 0 || p == null || p.Count < 3 || !(p[0] is double x) || !(p[1] is double y) || !(p[2] is double z)) return null;
            if (!ValidPos((int)x, (int)y, (int)z)) return null;
            var bar = new TileBar { Id = id, Pos = new Pos((int)x, (int)y, (int)z), Label = Json.Text(w, "n"), Color = BarColor(Json.Text(w, "c")) };
            if (Json.Get(w, "l") is double l)
            {
                bar.EndMs = now + Math.Max(0, l);
                bar.TotalMs = Math.Max(1, Json.Get(w, "t") is double t ? t : l);
            }
            else bar.V = Math.Min(1, Math.Max(0, Json.Number(w, "v")));
            return bar;
        }

        /// <summary>A bars message into the store; returns the ids set (sorted).</summary>
        public static List<string> ApplyBars(Dictionary<string, TileBar> store, object data, double now, List<string> deleted = null)
        {
            var set = new List<string>();
            if (!(data is Dictionary<string, object>)) return set;
            foreach (object id in Json.List(data, "d"))
                if (id is string s && store.Remove(s)) deleted?.Add(s);
            foreach (object w in Json.List(data, "s"))
            {
                var bar = ParseBar(w, now);
                if (bar == null) continue;
                store[bar.Id] = bar;
                set.Add(bar.Id);
            }
            set.Sort(string.CompareOrdinal);
            deleted?.Sort(string.CompareOrdinal);
            return set;
        }

        public static double BarProgress(TileBar b, double now) => b.Countdown ? Math.Min(1, Math.Max(0, (b.EndMs - now) / b.TotalMs)) : b.V;

        public static string BarText(TileBar b, double now)
        {
            if (!b.Countdown) return b.Label;
            string t = FormatSeconds(SecondsLeft(b.EndMs - now));
            return b.Label.Length > 0 ? b.Label + " " + t : t;
        }

        /// <summary>Countdowns that ended more than graceMs ago (the server drops them too).</summary>
        public static List<string> ExpiredBars(Dictionary<string, TileBar> store, double now, double graceMs = 1500)
        {
            var o = new List<string>();
            foreach (var kv in store) if (kv.Value.Countdown && now > kv.Value.EndMs + graceMs) o.Add(kv.Key);
            o.Sort(string.CompareOrdinal);
            return o;
        }

        public static int FillWidth(double progress, int inner = BarInner) => Math.Min(inner, Math.Max(0, (int)Math.Floor(progress * inner + 0.5)));
        public static int BarWidth(double textWidth) => Math.Max(BarW, (int)Math.Floor(textWidth + 12));
        public static int BarLift(double th, int i) => (int)Math.Floor(th / 2 + BarH / 2.0 + 4) + (i - 1) * (BarH + BarGap);

        /// <summary>The bars of one tile in drawing order (by id); the place of each is its index + 1 (1 = lowest).</summary>
        public static List<TileBar> Stack(Dictionary<string, TileBar> store, Pos pos)
        {
            var list = new List<TileBar>();
            foreach (var b in store.Values) if (b.Pos == pos) list.Add(b);
            list.Sort((a, b) => string.CompareOrdinal(a.Id, b.Id));
            return list;
        }

        public void Tick(double now)
        {
            foreach (string id in ExpiredBars(Bars, now)) Bars.Remove(id);
        }

        public void Handle(string action, object data)
        {
            if (action == "bars") { ApplyBars(Bars, data, Clock()); Changed(); }
            else if (action == "clear") { Bars.Clear(); Changed(); }
        }

        public void Clear() { Recs.Clear(); ghosts.Clear(); Bars.Clear(); prevTiles = new HashSet<Pos>(); }
    }

    // ------------------------------------------------------------------------------------------------ weather
    public sealed class WeatherLayer
    {
        public string Name = "", Kind = "";
        public double Speed, Phase, Vx, Vy, Sway, SwayY, Period, Pulse, PulseMs, Max;
    }

    /// <summary>Rain over the game view, ambient specks (embers, motes, dust) and the colour mood of the area. Drawn procedurally by Unity/ChaosApp.World.cs.</summary>
    public sealed class WeatherState
    {
        public const byte Opcode = 114;
        public const double DefaultFadeMs = 2500, MaxFadeMs = 10000, MinOpacity = 0.01, CoveredFadeMs = 600, MoodEaseMs = 2000;
        public const int MaxLevel = 3;
        public static readonly WeatherLayer[] RainLayers =
        {
            new WeatherLayer { Name = "far", Speed = 360, Phase = 0 }, new WeatherLayer { Name = "mid", Speed = 480, Phase = 83 }, new WeatherLayer { Name = "near", Speed = 640, Phase = 171 },
        };
        /// <summary>The opacity every rain layer reaches at each level (2 is the level of the base server's rain).</summary>
        public static readonly Dictionary<int, Dictionary<string, double>> Plan = new Dictionary<int, Dictionary<string, double>>
        {
            { 1, new Dictionary<string, double> { { "far", 0.6 } } },
            { 2, new Dictionary<string, double> { { "far", 1 }, { "near", 1 } } },
            { 3, new Dictionary<string, double> { { "far", 1 }, { "mid", 1 }, { "near", 1 } } },
        };
        public static readonly WeatherLayer[] AmbientLayers =
        {
            new WeatherLayer { Name = "embers_far", Kind = "embers", Vx = 5, Vy = -13, Sway = 10, SwayY = 3, Period = 5200, Phase = 0, Pulse = 0.15, PulseMs = 1700, Max = 0.9 },
            new WeatherLayer { Name = "embers_near", Kind = "embers", Vx = 9, Vy = -24, Sway = 16, SwayY = 4, Period = 3800, Phase = 97, Pulse = 0.20, PulseMs = 1300, Max = 1 },
            new WeatherLayer { Name = "motes_far", Kind = "motes", Vx = 3, Vy = -3, Sway = 14, SwayY = 9, Period = 7000, Phase = 41, Pulse = 0.60, PulseMs = 4700, Max = 0.9 },
            new WeatherLayer { Name = "motes_near", Kind = "motes", Vx = -4, Vy = 2, Sway = 22, SwayY = 12, Period = 5600, Phase = 211, Pulse = 0.70, PulseMs = 3300, Max = 1 },
            new WeatherLayer { Name = "dust_far", Kind = "dust", Vx = 3, Vy = 2, Sway = 8, SwayY = 5, Period = 9000, Phase = 133, Pulse = 0, PulseMs = 1000, Max = 0.8 },
            new WeatherLayer { Name = "dust_near", Kind = "dust", Vx = 6, Vy = 4, Sway = 12, SwayY = 7, Period = 7400, Phase = 301, Pulse = 0, PulseMs = 1000, Max = 0.9 },
        };
        /// <summary>The mood tint offsets (r, g, b), saturation and contrast change (game_visualfx grademood_logic.lua).</summary>
        public static readonly Dictionary<string, double[]> Moods = new Dictionary<string, double[]>
        {
            { "ice", new[] { -0.020, 0.004, 0.034, -0.02, 0.00 } }, { "swamp", new[] { -0.012, 0.026, -0.018, -0.03, 0.01 } },
            { "desert", new[] { 0.032, 0.016, -0.022, 0.02, 0.01 } }, { "fire", new[] { 0.036, 0.004, -0.030, 0.02, 0.03 } },
            { "crypt", new[] { -0.006, -0.002, 0.004, -0.10, 0.02 } },
        };

        readonly ExtOpcodes ext;
        public string Kind = "none", Ambient = "", Mood = "";
        public int Level;
        public double FadeMs = DefaultFadeMs, AmbientFadeMs = DefaultFadeMs;
        public bool OptionOn = true, AmbientOn = true, Covered;
        public readonly Dictionary<string, double> Cur = new Dictionary<string, double>(), AmbientCur = new Dictionary<string, double>();
        /// <summary>Eased mood tint: r, g, b, sat, con.</summary>
        public readonly double[] Grade = new double[5];
        double lastTick = -1;
        public Action Changed = delegate { };

        public WeatherState(ExtOpcodes e)
        {
            ext = e;
            foreach (var l in RainLayers) Cur[l.Name] = 0;
            foreach (var l in AmbientLayers) AmbientCur[l.Name] = 0;
            ext.On(Opcode, m => Handle(m.Action, m.Data));
        }

        public void Hello() { ext.Send(Opcode, "hello", new Dictionary<string, object>()); }

        public static double ClampFade(object v, double fallback = DefaultFadeMs)
        {
            double f = v is double d && !double.IsNaN(d) ? d : fallback;
            return Math.Max(0, Math.Min(MaxFadeMs, Math.Floor(f)));
        }

        /// <summary>The message of the server: kind "rain" or "none", level 1..3, fade ms. False for a message that is no "set".</summary>
        public static bool Parse(string action, object data, out string kind, out int level, out double fade)
        {
            kind = "none"; level = 0; fade = DefaultFadeMs;
            if (action != "set" || !(data is Dictionary<string, object>)) return false;
            fade = ClampFade(Json.Get(data, "f"));
            if (Json.Text(data, "k") == "rain")
            {
                kind = "rain";
                level = Math.Max(1, Math.Min(MaxLevel, (int)Math.Floor(Json.Get(data, "i") is double d ? d : 2)));
            }
            return true;
        }

        /// <summary>The opacity every rain layer should reach: all 0 when it does not rain, the option is off or the player is under a roof.</summary>
        public Dictionary<string, double> Targets()
        {
            var t = new Dictionary<string, double>();
            foreach (var l in RainLayers) t[l.Name] = 0;
            if (!OptionOn || Covered || Kind != "rain") return t;
            if (!Plan.TryGetValue(Level, out var plan)) plan = Plan[2];
            foreach (var kv in plan) t[kv.Key] = kv.Value;
            return t;
        }

        public Dictionary<string, double> AmbientTargets()
        {
            var t = new Dictionary<string, double>();
            foreach (var l in AmbientLayers) t[l.Name] = AmbientOn && OptionOn && l.Kind == Ambient ? l.Max : 0;
            return t;
        }

        public double EffectiveFadeMs() => Covered ? Math.Min(FadeMs, CoveredFadeMs) : FadeMs;

        public static double Step(double cur, double tgt, double dtMs, double fadeMs)
        {
            if (fadeMs <= 0 || dtMs >= fadeMs) return tgt;
            double delta = dtMs / fadeMs;
            return cur < tgt ? Math.Min(tgt, cur + delta) : Math.Max(tgt, cur - delta);
        }

        /// <summary>The rain picture scrolls down and to the right along the slant of its streaks: whole pixels in 0..tile-1.</summary>
        public static void Offset(WeatherLayer l, double tMs, int tile, out int ox, out int oy)
        {
            long d = (long)Math.Floor(l.Speed * tMs / 1000);
            ox = (int)(((long)Math.Floor(d * 0.30) + (long)l.Phase) % tile);
            oy = (int)((d + (long)l.Phase) % tile);
        }

        public static void AmbientOffset(WeatherLayer l, double tMs, out double x, out double y)
        {
            double s = tMs / 1000, w = 2 * Math.PI * tMs / l.Period + l.Phase;
            x = l.Vx * s + l.Sway * Math.Sin(w);
            y = l.Vy * s + l.SwayY * Math.Cos(w * 0.77);
        }

        public static double AmbientPulse(WeatherLayer l, double tMs)
        {
            if (l.Pulse <= 0) return 1;
            double wave = 0.5 + 0.5 * Math.Sin(2 * Math.PI * tMs / l.PulseMs + l.Phase);
            return 1 - l.Pulse * wave;
        }

        /// <summary>Fades every layer toward its target by the time since the last tick; returns whether anything is visible.</summary>
        public bool Tick(double nowMs)
        {
            double dt = lastTick < 0 ? 0 : Math.Max(0, nowMs - lastTick);
            lastTick = nowMs;
            bool any = false;
            var tgt = Targets();
            double fade = EffectiveFadeMs();
            foreach (var l in RainLayers)
            {
                double v = Step(Cur[l.Name], tgt[l.Name], dt, fade);
                Cur[l.Name] = v;
                if (v > MinOpacity) any = true;
            }
            var at = AmbientTargets();
            foreach (var l in AmbientLayers)
            {
                double v = Step(AmbientCur[l.Name], at[l.Name], dt, AmbientFadeMs);
                AmbientCur[l.Name] = v;
                if (v > MinOpacity) any = true;
            }
            // the mood eases over 2 s
            double[] want = Moods.TryGetValue(Mood, out var m) ? m : new double[5];
            double k = dt <= 0 ? 0 : Math.Min(1, dt / MoodEaseMs);
            for (int i = 0; i < 5; i++) Grade[i] += (want[i] - Grade[i]) * k;
            return any;
        }

        public bool Raining => Kind == "rain";

        /// <summary>The mood colour over the view and its alpha (0 when the grade is neutral).</summary>
        public void MoodTint(out float r, out float g, out float b, out float alpha)
        {
            double mag = Math.Abs(Grade[0]) + Math.Abs(Grade[1]) + Math.Abs(Grade[2]) + Math.Abs(Grade[3]);
            r = (float)Math.Max(0, Math.Min(1, 0.5 + Grade[0] * 14)); g = (float)Math.Max(0, Math.Min(1, 0.5 + Grade[1] * 14)); b = (float)Math.Max(0, Math.Min(1, 0.5 + Grade[2] * 14));
            alpha = (float)Math.Min(0.18, mag * 2.2);
        }

        public void Handle(string action, object data)
        {
            if (!Parse(action, data, out string kind, out int level, out double fade)) return;
            string a = Json.Text(data, "a"), m = Json.Text(data, "m");
            Ambient = a == "embers" || a == "motes" || a == "dust" ? a : "";
            AmbientFadeMs = fade;
            Mood = Moods.ContainsKey(m) ? m : "";
            Kind = kind; Level = level; FadeMs = fade;
            Changed();
        }

        public void Clear()
        {
            Kind = "none"; Ambient = ""; Mood = ""; Level = 0; lastTick = -1;
            foreach (var l in RainLayers) Cur[l.Name] = 0;
            foreach (var l in AmbientLayers) AmbientCur[l.Name] = 0;
            for (int i = 0; i < 5; i++) Grade[i] = 0;
        }
    }

    // ------------------------------------------------------------------------------------------------ name plates
    public sealed class Nameplate
    {
        public uint Cid;
        public string Title = "", Color = "#d6c9ae", Guild = "", Frame = "default";
        public double At;
        public bool Stale;
    }

    public sealed class NameplateState
    {
        public const byte Opcode = 248;
        public const double StaleSeconds = 60, RetrySeconds = 3, FlushMs = 250, TryMs = 10000;
        public const int Batch = 30, MaxTries = 4;
        public const string NameColor = "#e8c372", GuildColor = "#d9a441", WarGuildColor = "#e8643c", TitleColor = "#d6c9ae";
        public static readonly string[] Frames =
        {
            "default", "gold", "crimson", "violet", "frost", "ember", "verdant", "bone", "ashen", "sapphire", "rose", "jade", "copper", "obsidian", "amber", "storm", "laurel",
            "sepulchre", "infernal", "cinderwrought", "gallery", "pactbound", "founder",
        };
        /// <summary>The accent of each frame (the border drawn round the name; the main client has a 9-slice picture per frame).</summary>
        public static readonly Dictionary<string, string> FrameColors = new Dictionary<string, string>
        {
            { "default", "#7a6a4a" }, { "gold", "#e8b84a" }, { "crimson", "#c03030" }, { "violet", "#9a5ae0" }, { "frost", "#7ad0f0" }, { "ember", "#f07a2a" }, { "verdant", "#5ac05a" },
            { "bone", "#d8d0b8" }, { "ashen", "#9a9a9a" }, { "sapphire", "#3a6ae0" }, { "rose", "#f07aa0" }, { "jade", "#3ac0a0" }, { "copper", "#c0783a" }, { "obsidian", "#4a3a5a" },
            { "amber", "#e0a020" }, { "storm", "#6a8ae0" }, { "laurel", "#8ac040" }, { "sepulchre", "#6a7a6a" }, { "infernal", "#e03a1a" }, { "cinderwrought", "#f0a050" },
            { "gallery", "#c0a0e0" }, { "pactbound", "#a05ae0" }, { "founder", "#f0d070" },
        };

        readonly ExtOpcodes ext;
        public readonly Dictionary<uint, Nameplate> Cache = new Dictionary<uint, Nameplate>();
        public readonly Dictionary<uint, KeyValuePair<double, int>> Pending = new Dictionary<uint, KeyValuePair<double, int>>();   // cid -> asked at, tries
        readonly SortedSet<uint> queue = new SortedSet<uint>();
        double nextFlush;
        public uint TryCid;
        public string TryFrame = "";
        public double TryUntil = -1;
        public Func<double> Clock = () => 0;   // ms
        public Action Changed = delegate { };

        public NameplateState(ExtOpcodes e) { ext = e; ext.OnText(Opcode, OnText); }

        public static bool KnownFrame(string f) => Array.IndexOf(Frames, f ?? "") >= 0;

        /// <summary>The buffer of the server (a plate a line) to plates; malformed lines are skipped.</summary>
        public static List<Nameplate> Parse(string buffer)
        {
            var list = new List<Nameplate>();
            if (buffer == null) return list;
            foreach (string line in buffer.Split('\n'))
            {
                if (line.Length == 0) continue;
                var f = line.Split('|');
                if (f.Length < 5 || !uint.TryParse(f[0], NumberStyles.None, CultureInfo.InvariantCulture, out uint cid) || cid == 0) continue;
                string color = f[2];
                bool hex = color.Length == 6;
                for (int i = 0; hex && i < 6; i++) if (!Uri.IsHexDigit(color[i])) hex = false;
                list.Add(new Nameplate { Cid = cid, Title = f[1], Color = hex ? "#" + color : TitleColor, Guild = f[3], Frame = KnownFrame(f[4]) ? f[4] : "default" });
            }
            return list;
        }

        public static string GuildText(string guild) => string.IsNullOrEmpty(guild) ? "" : "{" + guild + "}";
        /// <summary>Emblem 2 is red (a war enemy).</summary>
        public static string GuildColorFor(int emblem) => emblem == 2 ? WarGuildColor : GuildColor;
        public static string FallbackText(Nameplate r)
        {
            if (r == null) return "";
            var lines = new List<string>();
            if (r.Title.Length > 0) lines.Add(r.Title);
            if (r.Guild.Length > 0) lines.Add(GuildText(r.Guild));
            return string.Join("\n", lines);
        }
        public static string FrameColor(string frame) => FrameColors.TryGetValue(frame ?? "", out string c) ? c : FrameColors["default"];

        /// <summary>Does this creature id need a query? entry is the cached plate or null.</summary>
        public static bool NeedsQuery(Nameplate entry, double nowSec, bool pending)
        {
            if (pending) return false;
            if (entry == null) return true;
            return entry.Stale && nowSec - entry.At >= StaleSeconds;
        }

        /// <summary>The queue as "q|id,id,..." messages of at most 30 ids, sorted.</summary>
        public static List<string> Queries(IEnumerable<uint> ids)
        {
            var sorted = new List<uint>(ids);
            sorted.Sort();
            var o = new List<string>();
            for (int i = 0; i < sorted.Count; i += Batch)
            {
                var part = new List<string>();
                for (int j = i; j < Math.Min(sorted.Count, i + Batch); j++) part.Add(sorted[j].ToString(CultureInfo.InvariantCulture));
                o.Add("q|" + string.Join(",", part));
            }
            return o;
        }

        /// <summary>Ids to ask again (unanswered for 3 s, under 4 tries, still on screen); ids given up or gone are removed from pending.</summary>
        public static List<uint> Retries(Dictionary<uint, KeyValuePair<double, int>> pending, double nowSec, Func<uint, bool> visible)
        {
            var o = new List<uint>();
            foreach (var kv in new List<KeyValuePair<uint, KeyValuePair<double, int>>>(pending))
            {
                if (kv.Value.Value >= MaxTries || (visible != null && !visible(kv.Key))) pending.Remove(kv.Key);
                else if (nowSec - kv.Value.Key >= RetrySeconds) o.Add(kv.Key);
            }
            o.Sort();
            return o;
        }

        /// <summary>A store frame drawn on the own plate for 10 s (this client only).</summary>
        public bool BeginTry(uint cid, string frame, double nowMs)
        {
            if (cid == 0 || !KnownFrame(frame)) return false;
            TryCid = cid; TryFrame = frame; TryUntil = nowMs + TryMs;
            return true;
        }

        /// <summary>The plate to draw for cid: the tried frame while a try runs on it, else the real one (null: none known).</summary>
        public Nameplate Shown(uint cid, double nowMs)
        {
            Cache.TryGetValue(cid, out var rec);
            if (TryCid == cid && nowMs < TryUntil)
            {
                var o = new Nameplate { Cid = cid, Title = rec?.Title ?? "", Color = rec?.Color ?? TitleColor, Guild = rec?.Guild ?? "", Frame = TryFrame };
                return o;
            }
            return rec;
        }

        void OnText(string buffer)
        {
            double nowSec = Clock() / 1000.0;
            foreach (var p in Parse(buffer))
            {
                p.At = nowSec;
                Cache[p.Cid] = p;
                Pending.Remove(p.Cid);
            }
            Changed();
        }

        /// <summary>Marks players that appeared (called each frame with the player creatures in view): asks for plates in batches every 250 ms, repeats unanswered ones.</summary>
        public void Tick(IEnumerable<uint> playersInView)
        {
            double nowMs = Clock(), nowSec = nowMs / 1000.0;
            var inView = new HashSet<uint>();
            foreach (uint id in playersInView)
            {
                inView.Add(id);
                Cache.TryGetValue(id, out var e);
                if (NeedsQuery(e, nowSec, Pending.ContainsKey(id))) queue.Add(id);
            }
            if (nowMs < nextFlush) return;
            nextFlush = nowMs + FlushMs;
            foreach (uint id in Retries(Pending, nowSec, x => inView.Contains(x))) queue.Add(id);
            if (queue.Count == 0) return;
            foreach (string q in Queries(queue)) ext.SendText(Opcode, q);
            foreach (uint id in queue)
            {
                Pending.TryGetValue(id, out var p);
                Pending[id] = new KeyValuePair<double, int>(nowSec, p.Value + 1);
            }
            queue.Clear();
        }

        /// <summary>A player left the view: its plate stays cached but is asked again when it reappears after a minute.</summary>
        public void MarkStale(uint cid) { if (Cache.TryGetValue(cid, out var e)) e.Stale = true; }

        public void Clear() { Cache.Clear(); Pending.Clear(); queue.Clear(); TryCid = 0; TryUntil = -1; }
    }
}
