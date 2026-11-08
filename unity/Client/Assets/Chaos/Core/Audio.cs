// Game sounds and region music, the engine-free part (phase 5, track R). The rules are the ones of the main client modules
// game_chaossound (soundlogic.lua) and game_chaosmusic (musiclogic.lua): which sound an event plays, how loud, whether it plays at all
// (gap, burst, cap, distance), the region the music follows with its hysteresis, the volume curve and the saved settings.
// The files are the ones of client/overlay/modules/game_chaossound/sounds and game_chaosmusic/music (OverlayFiles finds them);
// Unity/ChaosApp.Audio.cs plays them. Pure C#, no Unity types.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    /// <summary>One sound set: the files (without .ogg), the gain before volume and distance, the gap between two of it in ms, how long the longest file sounds, the priority 0..5.</summary>
    public sealed class SoundSet
    {
        public string Group = "";
        public string[] Files = new string[0];
        public float Gain;
        public int Gap, Ms, Prio;
    }

    /// <summary>The sound options (PlayerPrefs "chaos.sound", JSON): the main switch, the volume word, and the four groups.</summary>
    public sealed class SoundSettings
    {
        public const string Pref = "chaos.sound";
        public bool Enabled = true, Combat = true, Spells = true, Events = true, Ui;
        public string Volume = "normal";

        public bool Group(string g)
        {
            switch (g) { case "combat": return Combat; case "spells": return Spells; case "events": return Events; case "ui": return Ui; default: return false; }
        }

        public void SetGroup(string g, bool on)
        {
            switch (g) { case "combat": Combat = on; break; case "spells": Spells = on; break; case "events": Events = on; break; case "ui": Ui = on; break; }
        }

        static bool Flag(object o, string key, bool def) { var v = Json.Get(o, key); return v is bool b ? b : def; }

        /// <summary>Settings from any parsed JSON (null or junk: the defaults); an unknown volume word is "normal".</summary>
        public static SoundSettings From(object o)
        {
            var s = new SoundSettings();
            if (!(o is Dictionary<string, object>)) return s;
            s.Enabled = Flag(o, "enabled", true); s.Combat = Flag(o, "combat", true); s.Spells = Flag(o, "spells", true);
            s.Events = Flag(o, "events", true); s.Ui = Flag(o, "ui", false);
            string v = Json.Text(o, "volume", "normal");
            s.Volume = SoundLogic.Volumes.ContainsKey(v) ? v : "normal";
            return s;
        }

        public string ToJson()
        {
            return Json.Serialize(new Dictionary<string, object>
            {
                { "enabled", Enabled }, { "volume", Volume }, { "combat", Combat }, { "spells", Spells }, { "events", Events }, { "ui", Ui },
            });
        }
    }

    /// <summary>The answer of the mixer: the file name (no folder, no extension) and the gain 0..1.</summary>
    public struct SoundPick
    {
        public string File;
        public float Gain;
    }

    /// <summary>The mixer state: gaps per event, the sounds that sound now and those that started in the last second, the last variant per event.</summary>
    public sealed class SoundMixer
    {
        readonly Dictionary<string, double> last = new Dictionary<string, double>();
        readonly List<double> active = new List<double>();   // the end of each sounding file
        readonly List<double> started = new List<double>();
        readonly Dictionary<string, int> variant = new Dictionary<string, int>();
        /// <summary>Why the last Request said no: unknown, off, mute, far, gap, burst, second or cap.</summary>
        public string Reason = "";

        void Prune(double now)
        {
            active.RemoveAll(a => a <= now);
            started.RemoveAll(t => now - t >= 1000);
        }

        /// <summary>Asks for an event. dist: tiles from the player, volume: a further 0..1 (the channel gain), rand(n): 0..n-1.</summary>
        public bool Request(string key, double now, SoundSettings st, out SoundPick pick, double dist = 0, float volume = 1f, Func<int, int> rand = null)
        {
            pick = default(SoundPick);
            if (!SoundLogic.Sets.TryGetValue(key, out var set)) { Reason = "unknown"; return false; }
            if (st == null) st = new SoundSettings();
            if (!st.Enabled || !st.Group(set.Group)) { Reason = "off"; return false; }
            float level = SoundLogic.Volumes[st.Volume] * volume;
            if (level <= 0) { Reason = "mute"; return false; }
            float fade = SoundLogic.DistanceGain(dist);
            if (fade < 0) { Reason = "far"; return false; }
            if (last.TryGetValue(key, out double at) && now - at < set.Gap) { Reason = "gap"; return false; }
            Prune(now);
            bool important = set.Prio >= SoundLogic.Important;
            int burst = 0;
            foreach (double t in started) if (now - t < SoundLogic.BurstMs) burst++;
            if (burst >= SoundLogic.BurstMax + (important ? SoundLogic.BurstBonus : 0)) { Reason = "burst"; return false; }
            if (!important && started.Count >= SoundLogic.SecondMax) { Reason = "second"; return false; }
            if (active.Count >= (important ? SoundLogic.HardCap : SoundLogic.MaxActive)) { Reason = "cap"; return false; }
            int n = set.Files.Length, idx = 0;
            if (n > 1)
            {
                idx = (rand ?? (k => 0))(n - 1);
                if (idx < 0) idx = 0;
                if (variant.TryGetValue(key, out int prev) && idx >= prev) idx++;
                if (idx >= n) idx = n - 1;
            }
            variant[key] = idx;
            last[key] = now;
            started.Add(now);
            active.Add(now + set.Ms);
            pick = new SoundPick { File = set.Files[idx], Gain = Math.Max(0f, Math.Min(1f, set.Gain * level * fade)) };
            Reason = "";
            return true;
        }

        public int Active => active.Count;
    }

    public static class SoundLogic
    {
        public const string Dir = "game_chaossound/sounds/";
        public const double MaxDist = 9, Near = 1, MinFade = 0.35;
        public const int BurstMs = 400, BurstMax = 3, BurstBonus = 2, Important = 3, MaxActive = 6, HardCap = 8, SecondMax = 10;
        public const double KillWindow = 2500;

        public static readonly Dictionary<string, float> Volumes = new Dictionary<string, float> { { "quiet", 0.35f }, { "normal", 0.7f }, { "loud", 1f } };
        public static readonly string[] VolumeOrder = { "quiet", "normal", "loud" };
        public static readonly string[] Groups = { "combat", "spells", "events", "ui" };

        static SoundSet S(string group, float gain, int gap, int ms, int prio, params string[] files)
        {
            return new SoundSet { Group = group, Files = files, Gain = gain, Gap = gap, Ms = ms, Prio = prio };
        }

        static string[] N(string stem, int n)
        {
            var a = new string[n];
            for (int i = 0; i < n; i++) a[i] = stem + "_" + (i + 1);
            return a;
        }

        public static readonly Dictionary<string, SoundSet> Sets = new Dictionary<string, SoundSet>
        {
            { "hit", S("combat", 0.55f, 90, 140, 1, N("hit", 3)) }, { "crit", S("combat", 0.80f, 150, 500, 3, N("crit", 2)) },
            { "hurt", S("combat", 0.60f, 350, 400, 2, N("hurt", 2)) }, { "dodge", S("combat", 0.60f, 300, 450, 2, N("dodge", 2)) },
            { "block", S("combat", 0.70f, 300, 350, 2, N("block", 2)) }, { "kill", S("combat", 0.55f, 250, 500, 3, N("kill", 2)) },
            { "fire", S("spells", 0.60f, 160, 650, 1, N("fire", 3)) }, { "ice", S("spells", 0.60f, 160, 210, 1, N("ice", 3)) },
            { "energy", S("spells", 0.60f, 160, 600, 1, N("energy", 3)) }, { "holy", S("spells", 0.60f, 160, 800, 1, N("holy", 3)) },
            { "death", S("spells", 0.60f, 160, 800, 1, N("death", 3)) }, { "earth", S("spells", 0.60f, 160, 600, 1, N("earth", 3)) },
            { "physical", S("spells", 0.70f, 160, 480, 1, N("physical", 3)) }, { "heal", S("spells", 0.70f, 300, 540, 1, N("heal", 3)) },
            { "levelup", S("events", 0.90f, 3000, 1000, 5, "levelup") }, { "loot_rare", S("events", 0.70f, 400, 850, 4, "loot_rare") },
            { "loot_great", S("events", 0.80f, 400, 850, 4, "loot_great") }, { "loot_unique", S("events", 0.90f, 400, 900, 4, "loot_unique") },
            { "goal", S("events", 0.80f, 800, 500, 4, "goal") },
            { "ui_open", S("ui", 0.50f, 120, 150, 0, "ui_open") }, { "ui_close", S("ui", 0.50f, 120, 150, 0, "ui_close") },
            { "ui_click", S("ui", 0.50f, 60, 100, 0, "ui_click") },
        };

        /// <summary>All the file names of the sets, sorted (the tests check them against the files of the module).</summary>
        public static List<string> AllFiles()
        {
            var seen = new HashSet<string>();
            foreach (var s in Sets.Values) foreach (string f in s.Files) seen.Add(f);
            var l = new List<string>(seen);
            l.Sort(StringComparer.Ordinal);
            return l;
        }

        /// <summary>The sound set a front-art element plays; null for blood, water and the rest (a stock puff on every blow would be noise).</summary>
        public static string ElementSound(FxElement e)
        {
            switch (e)
            {
                case FxElement.Fire: return "fire";
                case FxElement.Ice: return "ice";
                case FxElement.Energy: case FxElement.Arcane: return "energy";
                case FxElement.Holy: return "holy";
                case FxElement.Death: case FxElement.Shadow: return "death";
                case FxElement.Earth: case FxElement.Poison: return "earth";
                case FxElement.Physical: return "physical";
                case FxElement.Heal: return "heal";
                default: return null;
            }
        }

        /// <summary>The event of a magic effect id: the stock block hit (3) and the dodge whoosh (416) only on the player's own tile; else the element's set.</summary>
        public static string EffectEvent(int effectId, out bool own)
        {
            own = false;
            if (effectId == 3) { own = true; return "block"; }
            if (effectId == 416) { own = true; return "dodge"; }
            return FrontFx.EffectTable.TryGetValue(effectId, out var el) ? ElementSound(el) : null;
        }

        /// <summary>The event of a damage number of the server (kind 23 dealt, 24 received; impact 0 plain, 1 critical): your hit, a hit you take. Burn and poison ticks, mana and others stay silent.</summary>
        public static string ImpactEvent(int kind, int impact, long value, bool typed)
        {
            if (value <= 0) return null;
            if (typed && impact != 0 && impact != 1) return null;
            if (kind == 23) return typed && impact == 1 ? "crit" : "hit";
            if (kind == 24) return "hurt";
            return null;
        }

        /// <summary>The loot event of a kill's best item: rare 4, great 5 or 10 (divine), unique. alerted: the loot filter's own rule sound played, so this stays silent.</summary>
        public static string LootEvent(IEnumerable<LootInfo> items, bool alerted)
        {
            if (alerted || items == null) return null;
            int best = 0;
            foreach (var i in items)
            {
                int r = i.U ? 100 : i.R;
                if (r > best) best = r;
            }
            if (best >= 100) return "loot_unique";
            if (best >= 5) return "loot_great";
            if (best >= 4) return "loot_rare";
            return null;
        }

        /// <summary>1 near, falling to MinFade at MaxDist; -1 when too far.</summary>
        public static float DistanceGain(double dist)
        {
            if (dist > MaxDist) return -1f;
            if (dist <= Near) return 1f;
            double f = (dist - Near) / (MaxDist - Near);
            return (float)(1 - (1 - MinFade) * f);
        }

        /// <summary>Tiles between two positions (the larger axis); another floor is out of reach.</summary>
        public static double Distance(Pos a, Pos b) => a.Z != b.Z ? MaxDist + 1 : Math.Max(Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));

        /// <summary>The hits of the player on creatures, to know a kill (a creature that dies while you hit it, or just after).</summary>
        public sealed class Hits
        {
            readonly Dictionary<uint, double> at = new Dictionary<uint, double>();
            public void Note(uint id, double now) { if (id != 0) at[id] = now; }
            public bool IsMyKill(uint id, double now)
            {
                if (!at.TryGetValue(id, out double t)) return false;
                at.Remove(id);
                return now - t <= KillWindow;
            }
            public void Prune(double now)
            {
                List<uint> old = null;
                foreach (var kv in at) if (now - kv.Value > KillWindow) (old ?? (old = new List<uint>())).Add(kv.Key);
                if (old != null) foreach (uint id in old) at.Remove(id);
            }
            public int Count => at.Count;
            public IEnumerable<uint> Ids => at.Keys;
            public void Clear() { at.Clear(); }
        }
    }

    // ============================================================================================================ music
    /// <summary>The music options (PlayerPrefs "chaos.music", JSON): on, volume 0..100, keep playing when the window is not focused.</summary>
    public sealed class MusicSettings
    {
        public const string Pref = "chaos.music";
        public bool Enabled = true, Background;
        public int Volume = 50;

        public static MusicSettings From(object o)
        {
            var s = new MusicSettings();
            if (!(o is Dictionary<string, object>)) return s;
            s.Enabled = !(Json.Get(o, "enabled") is bool e) || e;
            s.Background = Json.Get(o, "background") is bool b && b;
            double v = Json.Number(o, "volume", 50);
            s.Volume = (int)Math.Max(0, Math.Min(100, Math.Floor(double.IsNaN(v) ? 50 : v + 0.5)));
            return s;
        }

        public string ToJson() { return Json.Serialize(new Dictionary<string, object> { { "enabled", Enabled }, { "volume", Volume }, { "background", Background } }); }

        /// <summary>0..1 on a curve that sounds even (half way is about -9 dB).</summary>
        public float Gain => !Enabled || Volume <= 0 ? 0f : Math.Min(1f, (float)Math.Pow(Volume / 100.0, 1.5));
    }

    /// <summary>What the music needs to know about the game now.</summary>
    public struct MusicSnap
    {
        public bool Online, Boss, ProtectionZone;
        public string Activity;   // "arena" or "dungeon" while an activity HUD shows, else null
        public Pos Pos;
        public List<MapMark> Pois;
    }

    public sealed class MusicState
    {
        public string Current, Pending;
        public double Since, SwitchedAt = double.NegativeInfinity;
    }

    public static class MusicLogic
    {
        public const string Dir = "game_chaosmusic/music/";
        public static readonly string[] Regions = { "login", "town", "hunt", "dungeon", "boss", "arena" };
        public const double Crossfade = 2.5, FirstFade = 1.5, MuteFade = 1.0, MinHoldMs = 3000, TickMs = 500;
        public const int BossRange = 8, TownRange = 18, DungeonRange = 14;
        /// <summary>The server's PZ bit in the player's status icons (0xA2).</summary>
        public const int PzFlag = 16384;

        /// <summary>The file of a region (music_town.ogg), or null for an unknown one.</summary>
        public static string File(string region)
        {
            foreach (string r in Regions) if (r == region) return Dir + "music_" + region + ".ogg";
            return null;
        }

        static bool Near(Pos a, int x, int y, int z, int range) => a.Z == z && Math.Abs(a.X - x) <= range && Math.Abs(a.Y - y) <= range;

        /// <summary>"town" near a temple, depot or bank, "dungeon" near a dungeon entrance, else null.</summary>
        public static string PoiRegion(Pos pos, List<MapMark> pois)
        {
            if (pois == null) return null;
            bool dungeon = false;
            foreach (var p in pois)
            {
                if ((p.Kind == "temple" || p.Kind == "depot" || p.Kind == "bank") && Near(pos, p.X, p.Y, p.Z, TownRange)) return "town";
                if (p.Kind == "dungeon" && Near(pos, p.X, p.Y, p.Z, DungeonRange)) dungeon = true;
            }
            return dungeon ? "dungeon" : null;
        }

        /// <summary>A boss fight: the target is a boss with health, or a boss near the player is hurt (health 1..99).</summary>
        public static bool BossEngaged(bool targetIsBoss, int targetHealth, IEnumerable<KeyValuePair<Pos, int>> bosses, Pos pos)
        {
            if (targetIsBoss && targetHealth > 0) return true;
            if (bosses == null) return false;
            foreach (var b in bosses) if (b.Value > 0 && b.Value < 100 && Near(pos, b.Key.X, b.Key.Y, b.Key.Z, BossRange)) return true;
            return false;
        }

        public static string Wanted(MusicSnap s)
        {
            if (!s.Online) return "login";
            if (s.Boss) return "boss";
            if (s.Activity != null) return s.Activity;
            if (s.ProtectionZone) return "town";
            return PoiRegion(s.Pos, s.Pois) ?? "hunt";
        }

        /// <summary>ms the wanted region must hold before the music follows.</summary>
        public static double Delay(string from, string to)
        {
            if (from == null || from == "login" || to == "login") return 0;
            if (to == "boss") return 0;
            if (from == "boss") return 10000;
            if (from == "town") return 8000;
            if (to == "town") return 3000;
            if (to == "arena" || to == "dungeon") return 1000;
            return 4000;
        }

        /// <summary>One tick: the region to play and whether it changed.</summary>
        public static string Step(MusicState st, string wanted, double now, out bool changed)
        {
            changed = false;
            if (wanted == st.Current) { st.Pending = null; return st.Current; }
            if (st.Pending != wanted) { st.Pending = wanted; st.Since = now; }
            bool login = st.Current == null || st.Current == "login" || wanted == "login";
            if (!login && now - st.SwitchedAt < MinHoldMs) return st.Current;
            if (now - st.Since >= Delay(st.Current, wanted))
            {
                st.Current = wanted; st.Pending = null; st.SwitchedAt = now;
                changed = true;
            }
            return st.Current;
        }

        /// <summary>Why nothing plays now, or null when the music should sound.</summary>
        public static string SilentReason(MusicSettings s, bool visible, bool focused, bool haveFile)
        {
            if (!s.Enabled) return "off";
            if (s.Gain <= 0) return "volume";
            if (!visible) return "hidden";
            if (s.Background && !focused) return "unfocused";
            if (!haveFile) return "file";
            return null;
        }

        /// <summary>The volume of the old and the new track part-way through a cross-fade (t seconds in): a straight fade.</summary>
        public static void Fade(double t, double length, out float outGain, out float inGain)
        {
            float f = length <= 0 ? 1f : (float)Math.Max(0, Math.Min(1, t / length));
            inGain = f; outGain = 1f - f;
        }
    }

    /// <summary>Where the files of the main client's modules are. The sounds, the music, the aura and decal pictures stay in client/overlay/modules
    /// (not copied into Unity, no new binaries): the player reads them from the first folder of Candidates that has the module.</summary>
    public static class OverlayFiles
    {
        public const string EnvVar = "CHAOS_OVERLAY_DIR";

        /// <summary>The folders to try for the "modules" folder, in order: the environment, StreamingAssets/overlay/modules, beside the executable
        /// (overlay/modules), and the repository's own client/overlay/modules above the Unity project (the editor and a CI run).</summary>
        public static List<string> Candidates(string env, string streamingAssets, string exeDir, string projectDir)
        {
            var l = new List<string>();
            if (!string.IsNullOrEmpty(env)) l.Add(env);
            if (!string.IsNullOrEmpty(streamingAssets)) l.Add(Combine(streamingAssets, "overlay/modules"));
            if (!string.IsNullOrEmpty(exeDir)) l.Add(Combine(exeDir, "overlay/modules"));
            if (!string.IsNullOrEmpty(projectDir))
            {
                // unity/Client -> unity -> the repository
                string p = projectDir.Replace('\\', '/').TrimEnd('/');
                for (int up = 0; up < 2; up++)
                {
                    int cut = p.LastIndexOf('/');
                    if (cut <= 0) { p = null; break; }
                    p = p.Substring(0, cut);
                }
                if (p != null) l.Add(p + "/client/overlay/modules");
            }
            return l;
        }

        static string Combine(string a, string b) => a.Replace('\\', '/').TrimEnd('/') + "/" + b;

        /// <summary>The first existing path of rel (like "game_chaossound/sounds/hit_1.ogg") under the candidate folders; exists says whether a file is there.</summary>
        public static string Find(IEnumerable<string> roots, string rel, Func<string, bool> exists)
        {
            foreach (string r in roots)
            {
                string p = r.Replace('\\', '/').TrimEnd('/') + "/" + rel;
                if (exists(p)) return p;
            }
            return null;
        }
    }
}
