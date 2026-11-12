// Map effects of the main client's visual modules, the engine-free rules (phase 5, track R): game_effectopacity, game_errorcolor, game_levelwings (opcode 191),
// game_lootbeams, game_combatdecals, game_chestaura (opcode 118), game_cosmeticfx (looks on opcode 225), game_groundfx, game_bossanimate, game_visualfx
// (hit flash, screen shake, target outline) and game_nameshaders (opcode 96). Each class is the Lua logic file of its module without engine calls.
// Unity/ChaosApp.Visual.cs draws them over the map in both views (classic MapView and the front-art live view) through TileScreenPx.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    // ============================================================================================================ effect opacity, error colour
    /// <summary>The spell effect opacity option (game_effectopacity): 25 to 100 percent in steps of 5. PlayerPrefs "chaos.effectopacity".</summary>
    public static class EffectOpacity
    {
        public const string Pref = "chaos.effectopacity";
        public const int Min = 25, Max = 100, Step = 5, Default = 100;

        /// <summary>Any stored value to a whole percent on the grid (junk: the default).</summary>
        public static int Clamp(double v)
        {
            if (double.IsNaN(v) || double.IsInfinity(v)) return Default;
            int n = (int)(Math.Floor(v / Step + 0.5) * Step);
            return Math.Max(Min, Math.Min(Max, n));
        }

        public static float Alpha(int percent) => Clamp(percent) / 100f;
    }

    /// <summary>The colour of the server's error lines (game_errorcolor). The failure texts come as message kind 21 (status small) and were white.</summary>
    public static class ErrorColor
    {
        public const string Pref = "chaos.errorcolor";
        public const string Hex = "#ff7a5c";
        public const uint Rgb = 0xFF7A5C;
        public static bool Enabled = true;

        public static bool IsError(byte kind) => kind == 21;

        /// <summary>The console colour of a text kind: the error colour for an error line when the option is on, else the one given.</summary>
        public static uint Tint(byte kind, uint plain) => Enabled && IsError(kind) ? Rgb : plain;
    }

    // ============================================================================================================ level wings
    /// <summary>The level-up effect (game_levelwings): the server sends {action "play", data {id, lv, n}} on opcode 191 to every viewer.</summary>
    public sealed class LevelWingsState
    {
        public const byte Opcode = 191;
        public const double LifeMs = 1750;   // 25 frames of 70 ms, as the pack effect
        public const string OwnPref = "chaos.levelwings.own", OthersPref = "chaos.levelwings.others";
        public bool Own = true, Others = true;
        public Func<double> Clock = () => 0;
        public Func<uint> SelfId = () => 0;
        public Action<uint> Played = delegate { };
        public sealed class Play { public uint Creature; public double Start; public int Level, Levels; }
        public readonly List<Play> Active = new List<Play>();

        public LevelWingsState(ExtOpcodes e) { e.On(Opcode, m => Handle(m.Action, m.Data)); }

        /// <summary>The creature id of a play message, 0 for a bad one.</summary>
        public static uint PlayId(string action, object data)
        {
            if (action != "play" || !(data is Dictionary<string, object>)) return 0;
            double d = Json.Number(data, "id", 0);
            return d > 0 && d == Math.Floor(d) && d < uint.MaxValue ? (uint)d : 0;
        }

        public bool Wanted(bool isLocal) => isLocal ? Own : Others;

        public void Handle(string action, object data)
        {
            uint id = PlayId(action, data);
            if (id == 0) return;
            bool mine = id == SelfId();
            if (!Wanted(mine)) return;
            Active.Add(new Play { Creature = id, Start = Clock(), Level = Json.Int(data, "lv"), Levels = Math.Max(1, Json.Int(data, "n", 1)) });
            while (Active.Count > 8) Active.RemoveAt(0);
            Played(id);
        }

        /// <summary>Drops the plays that are over.</summary>
        public void Tick(double now) { Active.RemoveAll(p => now - p.Start >= LifeMs); }

        /// <summary>0..1 into the effect, -1 when over.</summary>
        public static float Progress(double now, double start) { double t = (now - start) / LifeMs; return t < 0 || t >= 1 ? -1f : (float)t; }
        public void Clear() { Active.Clear(); }
    }

    // ============================================================================================================ loot beams
    public sealed class BeamLook { public string Group = "", Color = ""; public float Height, Intensity; public int Rank; }

    /// <summary>Loot beams over corpses and ground items (game_lootbeams): the colour of the best item the loot filter makes glow.</summary>
    public sealed class LootBeamSettings
    {
        public const string Pref = "chaos.lootbeams";
        public bool Enabled = true, Orbs, Ground = true;
        public string Height = "normal", Intensity = "normal";

        public static LootBeamSettings From(object o)
        {
            var s = new LootBeamSettings();
            if (!(o is Dictionary<string, object>)) return s;
            s.Enabled = !(Json.Get(o, "enabled") is bool e) || e;
            s.Orbs = Json.Get(o, "orbs") is bool b && b;
            s.Ground = !(Json.Get(o, "ground") is bool g) || g;
            string h = Json.Text(o, "height", "normal"), i = Json.Text(o, "intensity", "normal");
            s.Height = LootBeams.Heights.ContainsKey(h) ? h : "normal";
            s.Intensity = LootBeams.Intensities.ContainsKey(i) ? i : "normal";
            return s;
        }

        public string ToJson() { return Json.Serialize(new Dictionary<string, object> { { "enabled", Enabled }, { "orbs", Orbs }, { "ground", Ground }, { "height", Height }, { "intensity", Intensity } }); }
    }

    public static class LootBeams
    {
        public const int MaxBeams = 24;
        public static readonly Dictionary<string, float> Heights = new Dictionary<string, float> { { "short", 2.5f }, { "normal", 3.5f }, { "tall", 4.5f } };
        public static readonly Dictionary<string, float> Intensities = new Dictionary<string, float> { { "soft", 0.55f }, { "normal", 0.8f }, { "bright", 1f } };
        public static readonly string[] HeightOrder = { "short", "normal", "tall" }, IntensityOrder = { "soft", "normal", "bright" };

        /// <summary>The beam groups: colour, share of the height, and which wins on a tile.</summary>
        public static readonly Dictionary<string, string> Colors = new Dictionary<string, string>
        {
            { "white", "#eef3f8" }, { "blue", "#3d8bff" }, { "orange", "#ff8c1a" }, { "divine", "#7fe3ff" }, { "unique", "#2bff7a" }, { "orb", "#39e0c8" },
        };
        public static readonly Dictionary<string, float> GroupHeight = new Dictionary<string, float>
        {
            { "white", 0.75f }, { "blue", 0.85f }, { "orange", 1f }, { "divine", 1.1f }, { "unique", 1.15f }, { "orb", 0.8f },
        };

        /// <summary>A rarity id (1 Common, 2 Uncommon, 3 Magic, 4 Rare, 5 to 9 Legendary, 10 to 15 Divine) to its beam group; null for none.</summary>
        public static string RarityGroup(int r)
        {
            if (r >= 1 && r <= 2) return "white";
            if (r >= 3 && r <= 4) return "blue";
            if (r >= 5 && r <= 9) return "orange";
            if (r >= 10 && r <= 15) return "divine";
            return null;
        }

        /// <summary>The group of one item, null when it has no beam colour (no rarity, not unique, not an orb).</summary>
        public static string GroupOf(LootInfo i)
        {
            if (i.U) return "unique";
            string g = RarityGroup(i.R);
            if (g != null) return g;
            if (i.Pw) return "orange";   // a legendary power on gear without a rarity
            return i.O ? "orb" : null;
        }

        /// <summary>Higher wins on a tile: uniques, then the rarity (a power counts as Legendary), orbs last.</summary>
        public static float Rank(LootInfo i)
        {
            if (i.U) return 100;
            if (i.R >= 1) return i.R + (i.Pw ? 0.5f : 0f);
            if (i.Pw) return 5;
            return i.O ? 0.5f : 0f;
        }

        /// <summary>Does this item give its tile a beam: the filter makes it glow (a legendary power always does); orbs only when the player wants them.</summary>
        public static bool Wants(LootInfo i, LootFilterSettings filter, LootBeamSettings s)
        {
            if (GroupOf(i) == null) return false;
            if (i.O && !i.U && i.R < 1) return s.Orbs;
            if (i.Pw) return true;
            return LootFilterRules.Classify(i, filter) == "highlight";
        }

        /// <summary>The beam of a list of items, null when none glows.</summary>
        public static BeamLook BeamOf(IEnumerable<LootInfo> items, LootFilterSettings filter, LootBeamSettings s)
        {
            if (items == null) return null;
            bool have = false; float best = 0; LootInfo bi = default(LootInfo);
            foreach (var i in items)
            {
                if (!Wants(i, filter, s)) continue;
                float r = Rank(i);
                if (!have || r > best) { have = true; best = r; bi = i; }
            }
            if (!have) return null;
            string g = GroupOf(bi);
            return new BeamLook { Group = g, Color = Colors[g], Height = Heights[s.Height] * GroupHeight[g], Intensity = Intensities[s.Intensity], Rank = (int)best };
        }

        /// <summary>The beams to draw: at most MaxBeams, the best groups first, then the nearest. dist(tile) in tiles.</summary>
        public static List<KeyValuePair<Pos, BeamLook>> Cap(List<KeyValuePair<Pos, BeamLook>> all, Func<Pos, double> dist, int max = MaxBeams)
        {
            var l = new List<KeyValuePair<Pos, BeamLook>>(all);
            l.Sort((a, b) =>
            {
                int c = b.Value.Rank.CompareTo(a.Value.Rank);
                return c != 0 ? c : dist(a.Key).CompareTo(dist(b.Key));
            });
            if (l.Count > max) l.RemoveRange(max, l.Count - max);
            return l;
        }
    }

    // ============================================================================================================ combat decals
    /// <summary>Stains on the ground (game_combatdecals): blood where a creature dies, scorch under fire, frost cracks under ice, a green stain under poison.</summary>
    public sealed class CombatDecal { public string Kind = ""; public Pos Pos; public double Born, Life; public int Variant; public float Alpha; }

    public static class CombatDecals
    {
        public const string Pref = "chaos.combatdecals";
        public const int Max = 24, LifeMinMs = 20000, LifeMaxMs = 30000, HitGapMs = 250, Variants = 2;
        public const float Start = 0.8f, Hold = 0.2f;
        public const double MinSat = 0.45, MinValue = 90;
        static readonly string[] Bloodless =
        {
            "skeleton", "bonelord", "ghost", "spectre", "wraith", "banshee", "lich", "mummy", "golem", "elemental", "slime",
            "ooze", "construct", "statue", "phantom", "shade", "djinn", "wisp", "revenant", "undead", "bone",
        };

        /// <summary>The 8-bit palette colour of a text (TFS TextColor_t: 6 x 6 x 6 steps of 51) to r, g, b 0..255.</summary>
        public static void PaletteRgb(int c, out int r, out int g, out int b)
        {
            if (c < 0 || c > 215) { r = g = b = 255; return; }
            r = c / 36 % 6 * 51; g = c / 6 % 6 * 51; b = c % 6 * 51;
        }

        /// <summary>"fire", "ice" or "poison" for the colour of a damage number (by hue); null for the rest.</summary>
        public static string KindOfColor(int r, int g, int b)
        {
            double mx = Math.Max(r, Math.Max(g, b)), mn = Math.Min(r, Math.Min(g, b)), d = mx - mn;
            if (mx <= 0 || d <= 0) return null;
            double h = mx == r ? (((g - b) / d) % 6 + 6) % 6 : mx == g ? (b - r) / d + 2 : (r - g) / d + 4;
            h *= 60;
            double sat = d / mx;
            if (sat < MinSat || mx < MinValue) return null;
            if (h >= 15 && h <= 55) return "fire";
            if (h >= 80 && h <= 160) return "poison";
            if (h >= 165 && h <= 200) return "ice";
            return null;
        }

        /// <summary>The decal a damage number (kind 23, 24, 27; impact 0 plain, 1 critical, 2 tick) asks for, null for none.</summary>
        public static string HitKind(int kind, int impact, long value, int textColor)
        {
            if (kind != 23 && kind != 24 && kind != 27) return null;
            if (impact < 0 || impact > 2 || value <= 0) return null;
            PaletteRgb(textColor, out int r, out int g, out int b);
            return KindOfColor(r, g, b);
        }

        /// <summary>The picture name of a decal kind ("blood", "scorch", "frost", "stain") and its variant 1 or 2.</summary>
        public static string Art(string kind, int variant)
        {
            string n = kind == "fire" ? "scorch" : kind == "ice" ? "frost" : kind == "poison" ? "stain" : "blood";
            return n + (1 + Math.Abs(variant) % Variants);
        }

        /// <summary>A guess from the name: ghosts, golems and bones bleed no red.</summary>
        public static bool Bleeds(string name)
        {
            if (string.IsNullOrEmpty(name)) return true;
            string l = name.ToLowerInvariant();
            foreach (string p in Bloodless) if (l.Contains(p)) return false;
            return true;
        }

        public static double LifeFor(double rnd)
        {
            if (rnd < 0) rnd = 0; else if (rnd >= 1) rnd = 0.999999;
            return Math.Floor(LifeMinMs + (LifeMaxMs - LifeMinMs) * rnd);
        }

        /// <summary>The opacity age ms into a life: holds at Start, then falls to 0 (smoothstep). -1 when gone.</summary>
        public static float AlphaAt(double age, double life)
        {
            if (life <= 0) return -1f;
            if (age < 0) age = 0;
            if (age >= life) return -1f;
            double hold = life * Hold;
            if (age <= hold) return Start;
            double u = (age - hold) / (life - hold);
            return (float)(Start * (1 - u * u * (3 - 2 * u)));
        }
    }

    public sealed class DecalField
    {
        public readonly List<CombatDecal> Decals = new List<CombatDecal>();
        double lastHit = -1e9;
        int seq;

        public bool MayAdd(string kind, double now) => kind == "blood" || (Decals.Count < CombatDecals.Max && now - lastHit >= CombatDecals.HitGapMs);

        /// <summary>Puts a decal down when the rules allow; a death stain pushes the oldest out.</summary>
        public CombatDecal Add(string kind, Pos at, double now, double rnd)
        {
            if (!MayAdd(kind, now)) return null;
            while (Decals.Count >= CombatDecals.Max) Decals.RemoveAt(0);
            var d = new CombatDecal { Kind = kind, Pos = at, Born = now, Life = CombatDecals.LifeFor(rnd), Variant = seq++ };
            Decals.Add(d);
            if (kind != "blood") lastHit = now;
            return d;
        }

        public void Step(double now)
        {
            for (int i = Decals.Count - 1; i >= 0; i--)
            {
                float a = CombatDecals.AlphaAt(now - Decals[i].Born, Decals[i].Life);
                if (a < 0) Decals.RemoveAt(i); else Decals[i].Alpha = a;
            }
        }

        public void Clear() { Decals.Clear(); }
    }

    // ============================================================================================================ chest and Templar auras
    public sealed class AuraRow { public uint Id; public int Line, Radius; public bool Party; }

    public sealed class ChestAuraDef { public string Art = ""; public int Px; public bool Big; }

    /// <summary>Auras under chests and the Templar line's foot aura (game_chestaura, opcode 118 sync and cursed). The strips come from client/tools/gen_aura_art.py.</summary>
    public sealed class ChestAuraState
    {
        public const byte Opcode = 118;
        public const string Pref = "chaos.chestauras";
        public const int Sprite = 32, ChestFrames = 12, ChestFrameMs = 200, FootFrames = 24, FootFrameMs = 250, FootPx = 64, FramePx = 96, MaxRows = 64, MaxRadius = 8, CursedMax = 32;
        public static readonly string[] Lines = { "templar", "inquisitor", "sentinel" };

        /// <summary>Client item ids of the chests with an aura, and the strip each wears.</summary>
        public static readonly Dictionary<int, ChestAuraDef> Chests = new Dictionary<int, ChestAuraDef>
        {
            { 38758, new ChestAuraDef { Art = "reward_sigil", Px = 64 } },
            { 38642, new ChestAuraDef { Art = "cursed_smoke", Px = 64 } },
            { 38657, new ChestAuraDef { Art = "coffer_smoke", Px = 128, Big = true } },
        };

        public bool Enabled = true;
        public readonly Dictionary<uint, AuraRow> Rows = new Dictionary<uint, AuraRow>();
        public readonly HashSet<uint> Cursed = new HashSet<uint>();

        // Pyre Oath (O518, game_chestaura): the ember ring under a holder ("pyre": id -> radius in sqm, the whole list) and the burn on the monsters
        // the aura struck ("burn": id -> ms of the tick that began it). Strips from client/tools/gen_pyre_art.py.
        public const int PyreFrames = 12, PyreFrameMs = 83, PyreRingPx = 160, PyreReachSqm = 2, PyreMaxRadius = 8, PyreMaxRows = 32;
        public const int BurnFrames = 8, BurnFrameMs = 125, BurnHoldMs = 1250, BurnPx = 64, BurnMax = 40;
        public Func<double> Clock = () => 0;
        public readonly Dictionary<uint, int> Pyre = new Dictionary<uint, int>();
        public readonly Dictionary<uint, double> Burning = new Dictionary<uint, double>();

        public ChestAuraState(ExtOpcodes e) { e.On(Opcode, m => Handle(m.Action, m.Data)); }

        public void Handle(string action, object data)
        {
            if (action == "sync")
            {
                Rows.Clear();
                foreach (object row in Json.List(data, "t"))
                {
                    if (Rows.Count >= MaxRows) break;
                    double id = Json.Number(row, "i"), line = Json.Number(row, "l"), r = Json.Number(row, "r");
                    if (id <= 0 || line < 1 || line > Lines.Length || r < 1) continue;
                    object p = Json.Get(row, "p");
                    bool party = p is bool b ? b : Json.Number(row, "p") == 1;
                    Rows[(uint)id] = new AuraRow { Id = (uint)id, Line = (int)line, Radius = (int)Math.Min(Math.Floor(r), MaxRadius), Party = party };
                }
            }
            else if (action == "cursed")
            {
                Cursed.Clear();
                foreach (object o in Json.List(data, "c"))
                    if (o is double d && d > 0 && Cursed.Count < CursedMax) Cursed.Add((uint)d);
            }
            else if (action == "pyre")
            {
                Pyre.Clear();
                foreach (object row in Json.List(data, "p"))
                {
                    if (Pyre.Count >= PyreMaxRows) break;
                    double id = Json.Number(row, "i"), r = Json.Number(row, "r");
                    if (id > 0 && r >= 1) Pyre[(uint)id] = (int)Math.Min(Math.Floor(r), PyreMaxRadius);
                }
            }
            else if (action == "burn")
            {
                double now = Clock();
                foreach (object o in Json.List(data, "b"))
                    if (o is double d && d > 0 && (Burning.ContainsKey((uint)d) || Burning.Count < BurnMax)) Burning[(uint)d] = now;
            }
        }

        /// <summary>The frame (0-based) of a burn that began sinceMs ago: one per BurnFrameMs, the last held until BurnHoldMs, then -1 (over).</summary>
        public static int BurnFrame(double sinceMs)
        {
            if (sinceMs < 0) sinceMs = 0;
            return sinceMs >= BurnHoldMs ? -1 : Math.Min(BurnFrames - 1, (int)(sinceMs / BurnFrameMs));
        }

        /// <summary>Forget the burns that are over at now.</summary>
        public void PruneBurns(double now)
        {
            List<uint> gone = null;
            foreach (var kv in Burning) if (BurnFrame(now - kv.Value) < 0) (gone ?? (gone = new List<uint>())).Add(kv.Key);
            if (gone != null) foreach (uint id in gone) Burning.Remove(id);
        }

        public static string PyreRingPath => "game_chestaura/images/pyre/ring.png";
        public static string BurnPath => "game_chestaura/images/pyre/burn.png";

        /// <summary>The loop frame (0-based) at a time: the same for every aura of a kind, so two chests are in step.</summary>
        public static int FrameIndex(double nowMs, int frameMs, int frames) => frameMs <= 0 || frames <= 0 ? 0 : (int)(Math.Floor(nowMs / frameMs) % frames);

        public static bool InSquare(Pos p, Pos center, int r) => p.Z == center.Z && Math.Max(Math.Abs(p.X - center.X), Math.Abs(p.Y - center.Y)) <= r;

        /// <summary>Strip path under client/overlay/modules.</summary>
        public static string ChestPath(string art) => "game_chestaura/images/chest/" + art + ".png";
        public static string FootPath(int line) => line >= 1 && line <= Lines.Length ? "game_chestaura/images/foot/" + Lines[line - 1] + "_sigil.png" : null;
        public static string FramePath(int line) => line >= 1 && line <= Lines.Length ? "game_chestaura/images/frame/" + Lines[line - 1] + ".png" : null;
        public void Clear() { Rows.Clear(); Cursed.Clear(); Pyre.Clear(); Burning.Clear(); }
    }

    // ============================================================================================================ cosmetic footprints and outlines
    public sealed class CosmeticLook { public string Print, Glow; public bool Pulse; }

    /// <summary>Footprints and outlines of bought cosmetics (game_cosmeticfx): the server's looks on opcode 225 ("looks": names, full), the prints on the ground.</summary>
    public sealed class CosmeticFxState
    {
        public const byte Opcode = 225;
        public const string OthersPrintsPref = "chaos.cosmeticfx.prints", OthersGlowPref = "chaos.cosmeticfx.glows";
        public const double PrintLifeMs = 3200, PrintStart = 0.9, PreviewMs = 6000, PulseMs = 1800, PulseLow = 0.45;
        public const int MaxPrints = 160, MaxPerCreature = 8;
        public bool OthersPrints = true, OthersOutlines = true;
        public readonly Dictionary<string, CosmeticLook> Looks = new Dictionary<string, CosmeticLook>();
        public sealed class Print { public string Owner = "", Art = ""; public Pos Pos; public double Born; public int Rotation; }
        public readonly List<Print> Prints = new List<Print>();

        public CosmeticFxState(ExtOpcodes e) { e.On(Opcode, m => { if (m.Action == "looks") Merge(m.Data); }); }

        public static bool ValidArt(string s)
        {
            if (string.IsNullOrEmpty(s) || s.Length > 24) return false;
            foreach (char c in s) if (!(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_')) return false;
            return true;
        }

        public static CosmeticLook Clean(object v)
        {
            if (!(v is Dictionary<string, object>)) return null;
            string f = Json.Text(v, "f"), o = Json.Text(v, "o");
            var l = new CosmeticLook { Print = ValidArt(f) ? f : null, Glow = ValidArt(o) ? o : null };
            object p = Json.Get(v, "p");
            l.Pulse = (p is bool b && b || Json.Number(v, "p") == 1) && l.Glow != null;
            return l.Print == null && l.Glow == null ? null : l;
        }

        /// <summary>A full list replaces, else entries are added (a bad one removes that name).</summary>
        public void Merge(object data)
        {
            if (!(data is Dictionary<string, object>)) return;
            if (Json.Truthy(data, "full")) Looks.Clear();
            if (Json.Get(data, "names") is Dictionary<string, object> names)
                foreach (var kv in names)
                {
                    var look = Clean(kv.Value);
                    if (look == null) Looks.Remove(kv.Key); else Looks[kv.Key] = look;
                }
        }

        public bool Allowed(bool footprint, bool isLocal) => isLocal || (footprint ? OthersPrints : OthersOutlines);

        /// <summary>Rotation in degrees (north 0, clockwise) of one step a to b; -1 unless it is one step on one floor.</summary>
        public static int StepRotation(Pos a, Pos b)
        {
            if (a.Z != b.Z) return -1;
            int dx = b.X - a.X, dy = b.Y - a.Y;
            if ((dx == 0 && dy == 0) || Math.Abs(dx) > 1 || Math.Abs(dy) > 1) return -1;
            int deg = (int)Math.Floor(Math.Atan2(dx, -dy) * 180 / Math.PI + 0.5);
            return (deg % 360 + 360) % 360;
        }

        public static float PrintOpacity(double age)
        {
            if (age < 0) age = 0;
            return age >= PrintLifeMs ? -1f : (float)(PrintStart * (1 - age / PrintLifeMs));
        }

        public static float PulseOpacity(double t)
        {
            double phase = t % PulseMs / PulseMs, wave = 0.5 - 0.5 * Math.Cos(phase * 2 * Math.PI);
            return (float)(PulseLow + (1 - PulseLow) * wave);
        }

        /// <summary>Adds a print; the oldest of that owner past the per-creature cap and the oldest overall past the total go first.</summary>
        public void AddPrint(string owner, string art, Pos at, int rotation, double now)
        {
            int mine = 0;
            foreach (var p in Prints) if (p.Owner == owner) mine++;
            for (int i = 0; mine >= MaxPerCreature && i < Prints.Count; i++)
                if (Prints[i].Owner == owner) { Prints.RemoveAt(i); mine--; i--; }
            while (Prints.Count >= MaxPrints) Prints.RemoveAt(0);
            Prints.Add(new Print { Owner = owner, Art = art, Pos = at, Born = now, Rotation = rotation });
        }

        public void Tick(double now) { Prints.RemoveAll(p => PrintOpacity(now - p.Born) < 0); }
        public void Clear() { Looks.Clear(); Prints.Clear(); }
    }

    // ============================================================================================================ ground effects, boss looks
    /// <summary>Effect ids drawn under the creatures (game_groundfx; the list is client/tools/sprites/gen_ground_fx.py's groundfx_data.lua): rune circles, seals, novas, rings.</summary>
    public static class GroundFx
    {
        // runs "a-b" and "a" of the ids of client/overlay/modules/game_groundfx/groundfx_data.lua (a test compares them)
        public const string Runs =
            "8,185,205,221,244,264,291,372,378,380,383,388-389,392,395,399-400,406-407,414,430-456,458-463,465,467,470,472,474-480,482-483," +
            "516-530,536,542-545,548,550,553-554,558,585,587-589,592-597,601-602,604-607,609,612,614,616,618-627,630,632-633,635-655," +
            "674-683,686-694,696,701,708-709,713-718,741-745,748-755,757,761-764,766-769,772-775,779,797,809,830-835,837-850";
        static HashSet<int> ids;

        public static HashSet<int> Ids
        {
            get
            {
                if (ids != null) return ids;
                var s = new HashSet<int>();
                foreach (string run in Runs.Split(','))
                {
                    int dash = run.IndexOf('-');
                    int a = int.Parse(dash < 0 ? run : run.Substring(0, dash)), b = dash < 0 ? a : int.Parse(run.Substring(dash + 1));
                    for (int i = a; i <= b; i++) s.Add(i);
                }
                return ids = s;
            }
        }

        public static bool IsGround(int effectId) => Ids.Contains(effectId);
    }

    /// <summary>Boss looks the main client fixes by engine patch (game_bossanimate): an idle animation for walk-frames-only looks, and a shift for art that sits off its tile.</summary>
    public static class BossAnimate
    {
        public static readonly int[] AlwaysAnimate = { 1534 };   // Skaldra the Rime Queen (wing beat)
        public static readonly Dictionary<int, int[]> Shifts = new Dictionary<int, int[]> { { 2127, new[] { -28, -28 } } };   // Gravewarden Ulthar, px

        /// <summary>The clock the standing look plays on (ms); the app sets it to the session clock.</summary>
        public static Func<double> Clock = () => Environment.TickCount;
        public static double NowMs() => Clock();

        public static bool Animates(int lookType) => Array.IndexOf(AlwaysAnimate, lookType) >= 0;

        /// <summary>The displacement in sprite pixels (dx, dy; negative moves the art down and right), 0 0 when none.</summary>
        public static void Shift(int lookType, out int dx, out int dy)
        {
            if (Shifts.TryGetValue(lookType, out var s)) { dx = s[0]; dy = s[1]; } else dx = dy = 0;
        }

        /// <summary>The phase of an always-animated look at a time (ms), the frame count given: the clock the standing look plays on.</summary>
        public static int Phase(double nowMs, int frames, int frameMs = 140) => frames <= 1 ? 0 : (int)(Math.Floor(nowMs / frameMs) % frames);
    }

    // ============================================================================================================ visual effects: hit flash, shake, outline
    /// <summary>The options of game_visualfx that Unity draws (the rest are engine shaders of the main client): the names are the main client's.</summary>
    public sealed class VisualFxOptions
    {
        public const string Pref = "chaos.visualfx";
        public static readonly string[] Names = { "hitFlash", "screenShake", "targetOutline", "numberMotion", "deathFade", "hoverOutline", "spellLight" };
        public bool HitFlash = true, ScreenShake = true, TargetOutline = true, NumberMotion = true, DeathFade = true;
        /// <summary>Phase 9 track D: the faint outline of the creature under the mouse (off by default, as in the main client) and the light round spell effects (on).</summary>
        public bool HoverOutline, SpellLight = true;

        public bool Get(string n)
        {
            switch (n) { case "hitFlash": return HitFlash; case "screenShake": return ScreenShake; case "targetOutline": return TargetOutline; case "numberMotion": return NumberMotion; case "deathFade": return DeathFade; case "hoverOutline": return HoverOutline; case "spellLight": return SpellLight; default: return false; }
        }

        public void Set(string n, bool on)
        {
            switch (n) { case "hitFlash": HitFlash = on; break; case "screenShake": ScreenShake = on; break; case "targetOutline": TargetOutline = on; break; case "numberMotion": NumberMotion = on; break; case "deathFade": DeathFade = on; break; case "hoverOutline": HoverOutline = on; break; case "spellLight": SpellLight = on; break; }
        }

        public static VisualFxOptions From(object o)
        {
            var s = new VisualFxOptions();
            if (!(o is Dictionary<string, object>)) return s;
            foreach (string n in Names) if (Json.Get(o, n) is bool b) s.Set(n, b);
            return s;
        }

        public string ToJson()
        {
            var d = new Dictionary<string, object>();
            foreach (string n in Names) d[n] = Get(n);
            return Json.Serialize(d);
        }
    }

    public sealed class FlashPlan { public bool Red; public double Ms; }

    /// <summary>The hit flash and the screen shake (visualfx_logic.lua).</summary>
    public sealed class HitFlasher
    {
        public const double Ms = 80, CritMs = 110, Gap = 140;
        public const int MaxActive = 8;
        readonly Dictionary<uint, double> last = new Dictionary<uint, double>(), ends = new Dictionary<uint, double>();

        /// <summary>Whether a damage number makes its creature flash: red when the player is hit, white otherwise. Only plain and critical hits (impact 0, 1).</summary>
        public FlashPlan Plan(double now, uint creature, int kind, int impact, long value, bool mine)
        {
            if (kind != 23 && kind != 24 && kind != 27) return null;
            if (impact != 0 && impact != 1) return null;
            if (creature == 0 || value <= 0) return null;
            if (last.TryGetValue(creature, out double l) && now - l < Gap) return null;
            var gone = new List<uint>();
            foreach (var kv in ends) if (kv.Value <= now) gone.Add(kv.Key);
            foreach (uint id in gone) ends.Remove(id);
            if (ends.Count >= MaxActive) return null;
            double ms = impact == 1 ? CritMs : Ms;
            last[creature] = now; ends[creature] = now + ms;
            if (last.Count > 64) { var old = new List<uint>(); foreach (var kv in last) if (now - kv.Value > 2000) old.Add(kv.Key); foreach (uint id in old) last.Remove(id); }
            return new FlashPlan { Red = mine, Ms = ms };
        }

        /// <summary>0..1 strength of a flash that began at start and lasts ms (a quick fade out); 0 when over.</summary>
        public static float Strength(double now, double start, double ms) { double t = (now - start) / ms; return t < 0 || t >= 1 ? 0f : (float)(1 - t); }
    }

    public sealed class ScreenShake
    {
        public const int MaxPx = 4;
        public const double Ms = 180, Gap = 300;
        public const int BigPercent = 1500, CritPercent = 300;
        double startAt, endAt, lastAt = -1e9;
        int amp;

        /// <summary>The strength in pixels a received hit asks for, 0 for none. percent is x100 (10000 = 100).</summary>
        public static int Amp(int impact, int percent)
        {
            if (percent <= 0) return 0;
            bool big = percent >= BigPercent, crit = impact == 1 && percent >= CritPercent;
            if (!big && !crit) return 0;
            return Math.Min(MaxPx, percent >= 5000 ? 4 : percent >= 3000 ? 3 : 2);
        }

        public int Now(double now)
        {
            if (now >= endAt) return 0;
            return Math.Min(MaxPx, (int)Math.Ceiling(amp * ((endAt - now) / Ms)));
        }

        public bool Start(double now, int a)
        {
            if (a <= 0) return false;
            a = Math.Min(a, MaxPx);
            bool running = now < endAt;
            if (running && a <= Now(now)) return false;
            if (!running && now - lastAt < Gap) return false;
            startAt = now; endAt = now + Ms; amp = a; lastAt = now;
            return true;
        }

        /// <summary>The shift of this frame in 1x sprite pixels; rnd gives 0..1.</summary>
        public void Offset(double now, Func<double> rnd, out int x, out int y)
        {
            int mag = Now(now);
            if (mag <= 0) { x = y = 0; return; }
            x = Math.Max(-mag, Math.Min(mag, (int)Math.Floor(rnd() * (2 * mag + 1)) - mag));
            y = Math.Max(-mag, Math.Min(mag, (int)Math.Floor(rnd() * (2 * mag + 1)) - mag));
            if (x == 0 && y == 0) x = rnd() < 0.5 ? -mag : mag;
        }

        public bool Running(double now) => now < endAt;
    }

    // ============================================================================================================ name shaders
    public sealed class NameShader { public int Id; public string Name = ""; public bool Available; public int DescriptionId; }

    /// <summary>Name shaders (game_nameshaders, opcode 96): the list the server sends, the one worn, select and the unlock notices. Unity draws a name as a moving two colour gradient chosen by the shader's name.</summary>
    public sealed class NameShaderState
    {
        public const byte Opcode = 96;
        public readonly List<NameShader> Shaders = new List<NameShader>();
        public int Current;
        public bool OpenRequested;
        public string Notice = "";
        public Action<string, bool> Notified = delegate { };
        readonly ExtOpcodes ext;

        public NameShaderState(ExtOpcodes e) { ext = e; e.On(Opcode, m => Handle(m.Action, m.Data, m.Root)); }

        public void Handle(string action, object data, object root)
        {
            // the server's messages carry the fields at the top level: {action, shaders, current, id, name}
            object src = root;
            switch (action)
            {
                case "open": OpenRequested = true; break;
                case "update":
                    if (Json.Get(src, "shaders") is List<object> list)
                    {
                        Shaders.Clear();
                        foreach (object s in list)
                        {
                            if (Json.Get(s, "id") == null) continue;
                            object a = Json.Get(s, "available");
                            Shaders.Add(new NameShader { Id = Json.Int(s, "id"), Name = Json.Text(s, "name"), Available = a is bool b ? b : Json.Number(s, "available") == 1, DescriptionId = Json.Int(s, "descriptionId") });
                        }
                    }
                    if (Json.Get(src, "current") != null) Current = Json.Int(src, "current");
                    break;
                case "selected":
                    if (Json.Get(src, "id") != null) Current = Json.Int(src, "id");
                    if (Json.Text(src, "name").Length > 0) Notified(Json.Text(src, "name"), true);
                    break;
                case "unlocked":
                    int id = Json.Int(src, "id", -1);
                    foreach (var s in Shaders) if (s.Id == id) s.Available = true;
                    if (Json.Text(src, "name").Length > 0) Notified(Json.Text(src, "name"), false);
                    break;
            }
        }

        public void Open() { ext.Send(Opcode, "open", null); }
        public void Select(int id) { ext.Send(Opcode, "select", new Dictionary<string, object> { { "id", id } }); }
        public NameShader Find(int id) { foreach (var s in Shaders) if (s.Id == id) return s; return null; }

        /// <summary>The shaders matching a search text (name, case blind), the ones the account has first.</summary>
        public List<NameShader> Filter(string text)
        {
            var have = new List<NameShader>(); var rest = new List<NameShader>();
            string q = (text ?? "").Trim().ToLowerInvariant();
            foreach (var s in Shaders)
            {
                if (q.Length > 0 && s.Name.ToLowerInvariant().IndexOf(q, StringComparison.Ordinal) < 0) continue;
                (s.Available ? have : rest).Add(s);
            }
            have.AddRange(rest);
            return have;
        }

        /// <summary>Two colours (0xRRGGBB) of a shader by its name: a fixed hue pair per name, so the same shader always looks the same.</summary>
        public static void Colors(string name, out uint a, out uint b)
        {
            uint h = 2166136261;
            foreach (char c in name ?? "") h = (h ^ char.ToLowerInvariant(c)) * 16777619;
            float h1 = (h & 0xFFF) / 4096f, h2 = (h1 + 0.12f + ((h >> 12) & 0xFF) / 255f * 0.25f) % 1f;
            a = Hsv(h1, 0.65f, 1f); b = Hsv(h2, 0.9f, 0.85f);
        }

        /// <summary>The colour at a time (ms) of a name drawn with a shader: a slow swing between the two colours.</summary>
        public static uint At(string name, double ms)
        {
            Colors(name, out uint a, out uint b);
            double t = 0.5 - 0.5 * Math.Cos(ms / 1400.0 * Math.PI);
            Func<int, uint> ch = sh => (uint)Math.Round(((a >> sh) & 255) * (1 - t) + ((b >> sh) & 255) * t);
            return ch(16) << 16 | ch(8) << 8 | ch(0);
        }

        static uint Hsv(float h, float s, float v)
        {
            float r = 0, g = 0, b = 0;
            int i = (int)(h * 6) % 6; float f = h * 6 - (int)(h * 6), p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
            switch (i) { case 0: r = v; g = t; b = p; break; case 1: r = q; g = v; b = p; break; case 2: r = p; g = v; b = t; break; case 3: r = p; g = q; b = v; break; case 4: r = t; g = p; b = v; break; default: r = v; g = p; b = q; break; }
            return (uint)(r * 255 + 0.5f) << 16 | (uint)(g * 255 + 0.5f) << 8 | (uint)(b * 255 + 0.5f);
        }

        public void Clear() { Shaders.Clear(); Current = 0; OpenRequested = false; }
    }
}
