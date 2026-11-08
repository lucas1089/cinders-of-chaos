// Phase 7, track Q: the pure parts of the UI, map and visual rows that were partial (docs/UNITY_PARITY.md): the interface scale option (game_chaosuiscale),
// the dark fantasy window theme and its skins (client_chaos_theme), the picture names of the map marks, the map overlay and the name plates (game_mapmarkers,
// game_mapoverlay, game_nameplate), the explored map kept over a relog (game_minimapsync), the death note that reopens the windows (game_mapoverlay,
// game_minimapsync) and the tiled weather pictures (game_chaosweather). No UnityEngine types; the drawing is in Unity/ChaosApp.Phase7Q.cs.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace Chaos.Core
{
    // ============================================================================================================ interface scale
    /// <summary>The interface scale option (game_chaosuiscale). The main client scales in whole steps because its bitmap fonts are pixel art; Unity draws its text from
    /// a font at any size, so the option is a percentage of the automatic scale (the one that follows the window height). A step that would leave less than
    /// 960 x 540 UI units is lowered to what the window allows (the limit of uiscale_logic.lua PHONE_W and PHONE_H).</summary>
    public static class UiScaleOption
    {
        public const string Pref = "chaos.uiscale";
        public const float MinW = 960f, MinH = 540f, Floor = 0.5f;
        /// <summary>Percent of the automatic scale; 100 is the automatic scale itself.</summary>
        public static readonly int[] Steps = { 75, 100, 125, 150, 200, 300 };
        public const int DefaultIndex = 1;

        public static int ClampIndex(int i) => Math.Max(0, Math.Min(Steps.Length - 1, i));

        /// <summary>The saved value as a step index: an index, or a percent (50 and above) that takes the nearest step; anything else the default.</summary>
        public static int ParseSaved(int v)
        {
            if (v < 0) return DefaultIndex;
            if (v < 50) return ClampIndex(v);
            int best = DefaultIndex, bestD = int.MaxValue;
            for (int i = 0; i < Steps.Length; i++) { int d = Math.Abs(Steps[i] - v); if (d < bestD) { best = i; bestD = d; } }
            return best;
        }

        public static int Percent(int index) => Steps[ClampIndex(index)];

        /// <summary>The highest step whose interface still has MinW x MinH units on a window of w x h (the step of 100 percent always counts as fitting).</summary>
        public static int MaxIndex(float w, float h, float baseScale)
        {
            if (w <= 0 || h <= 0 || baseScale <= 0) return DefaultIndex;
            int best = DefaultIndex;
            for (int i = 0; i < Steps.Length; i++)
            {
                float s = baseScale * Steps[i] / 100f;
                if (w / s >= MinW && h / s >= MinH) best = i;
            }
            return Math.Max(best, DefaultIndex);
        }

        public static int Effective(int wanted, float w, float h, float baseScale)
        {
            int i = ClampIndex(wanted), m = MaxIndex(w, h, baseScale);
            return i > m && Steps[i] > 100 ? m : i;
        }

        /// <summary>The scale to draw with: the automatic one at 100 percent, else the step of the option within what the window allows.</summary>
        public static float Factor(int wanted, float w, float h, float baseScale)
        {
            int i = Effective(wanted, w, h, baseScale);
            if (Steps[i] == 100) return baseScale;
            float s = baseScale * Steps[i] / 100f;
            if (Steps[i] < 100) return Math.Max(Floor, s);
            return s;
        }
    }

    // ============================================================================================================ theme
    /// <summary>The window theme and its skins (client_chaos_theme, skin_core.lua): blackened iron, dried blood and ember gold. A skin is a set of pictures under
    /// data/skins/id (the classic one is the main set under data/images/chaos/skin); the palette names the colours that code draws. The window frame is the
    /// main client's skin/window.png cut in nine, its corner pieces and its crest.</summary>
    public static class UiTheme
    {
        public const string Pref = "chaos.theme", SkinPref = "chaos.skin";
        public static readonly string[] Skins = { "classic", "forge", "abyss" };
        public static readonly Dictionary<string, string> SkinNames = new Dictionary<string, string>
        {
            { "classic", "Classic" }, { "forge", "Forge and Embers" }, { "abyss", "Abyssal Arcane" },
        };
        // window.png is 128 x 128 with the borders left 12, top 32, right 12, bottom 12 (gen_skin.py; chaos_theme.lua)
        public const int ArtSize = 128, BorderL = 12, BorderT = 32, BorderR = 12, BorderB = 12;
        public const int CornerSize = 44, CrestW = 84, CrestH = 30;
        /// <summary>The Unity title bar is 24 units high and the body starts 4 units in, so the frame is drawn thinner than the art: left, right and bottom 4, top 24.</summary>
        public const float EdgeSide = 4f, EdgeTop = 24f, EdgeBottom = 4f, CornerDraw = 20f, CornerInset = 2f, CrestDrawW = 56f, CrestDrawH = 20f, CrestUp = 12f;
        public const float CrestMinWidth = 170f, CornerMinW = 90f, CornerMinH = 70f;

        public sealed class Palette
        {
            public string Bg, Iron, IronLight, Text, TextDim, Gold, GoldBright, Blood, Title, Accent, Accent2;
        }

        static readonly Dictionary<string, Palette> palettes = new Dictionary<string, Palette>
        {
            { "classic", new Palette { Bg = "#0d0b0e", Iron = "#3a3339", IronLight = "#7d7176", Text = "#d6c9ae", TextDim = "#8c8070", Gold = "#e8b84a", GoldBright = "#f6cf72", Blood = "#b8160f", Title = "#e8c477", Accent = "#e8b84a", Accent2 = "#f6cf72" } },
            { "forge", new Palette { Bg = "#0b0908", Iron = "#2f2a26", IronLight = "#5c544b", Text = "#d8ccb8", TextDim = "#9a8f7e", Gold = "#ff7a1a", GoldBright = "#ffb347", Blood = "#c2260f", Title = "#ffb347", Accent = "#ff7a1a", Accent2 = "#ffb347" } },
            { "abyss", new Palette { Bg = "#06070b", Iron = "#0d1019", IronLight = "#1c2234", Text = "#d9d6e6", TextDim = "#8d89a3", Gold = "#c9a45a", GoldBright = "#e8cf8a", Blood = "#d23a5a", Title = "#e8cf8a", Accent = "#8a5cf0", Accent2 = "#2fd0c0" } },
        };

        public static bool Known(string id) => id != null && palettes.ContainsKey(id);
        public static string Normalize(string id) => Known(id) ? id : "classic";
        public static Palette PaletteOf(string id) => palettes[Normalize(id)];

        /// <summary>The next skin in the list (the options button cycles through them).</summary>
        public static string Next(string id)
        {
            int i = Array.IndexOf(Skins, Normalize(id));
            return Skins[(i + 1) % Skins.Length];
        }

        /// <summary>A picture of the skin: the main set for classic, the skin's folder otherwise ("../data/..." paths, read through the overlay folders).</summary>
        public static string Art(string skin, string name)
        {
            skin = Normalize(skin);
            return skin == "classic" ? ArtPaths.Data("images/chaos/skin/" + name + ".png") : ArtPaths.Data("skins/" + skin + "/images/chaos/skin/" + name + ".png");
        }

        // the button sheet skin/button.png: four states stacked from the top (normal, hover, pressed, disabled), 64 x 24 each, border 5; the text field picture is 32 x 22, border 4
        public const int SheetW = 64, StateH = 24, SheetStates = 4, ButtonBorder = 5, FieldW = 32, FieldH = 22, FieldBorder = 4;
        public static readonly string[] ButtonStates = { "normal", "hover", "pressed", "disabled" };
        public static string ButtonSheet(string skin) => Art(skin, "button");
        public static string FieldPicture(bool focus) => ArtPaths.Data("images/chaos/" + (focus ? "textedit_focus" : "textedit") + ".png");
        /// <summary>The bottom row (texture rows count from the bottom) of a state of the sheet: the first state sits at the top.</summary>
        public static int StateRow(int sheetHeight, int state) => sheetHeight - StateH * (Math.Max(0, Math.Min(SheetStates - 1, state)) + 1);

        public static readonly List<string> Corners = new List<string> { "tl", "tr", "bl", "br" };
        public static string Window(string skin) => Art(skin, "window");
        public static string Corner(string skin, string which) => Art(skin, "orn_corner_" + (Corners.Contains(which) ? which : "tl"));
        public static string Crest(string skin) => Art(skin, "orn_crest");

        public static bool ShowCrest(float width) => width >= CrestMinWidth;
        public static bool ShowCorners(float width, float height) => width >= CornerMinW && height >= CornerMinH;
    }

    // ============================================================================================================ picture names
    /// <summary>The picture of each map mark (game_mapmarkers, game_mapoverlay): data/images/chaos/mapmarkers and mapoverlay of the main client, 14, 16 and 12 pixels.</summary>
    public static class MarkArt
    {
        public static readonly HashSet<string> PoiKinds = new HashSet<string>
        {
            "bank", "bless", "boss", "craft", "depot", "dungeon", "guild", "hunt", "npc", "portal", "quest", "questgoal", "shop", "temple", "travel",
        };
        public static readonly HashSet<string> OverlayKinds = new HashSet<string>
        {
            "boss", "chest", "coffer", "depot", "entry", "goblin", "guardian", "invasion", "npc", "party", "self", "temple", "worldboss",
        };
        public static readonly HashSet<string> Directions = new HashSet<string> { "n", "ne", "e", "se", "s", "sw", "w", "nw" };
        public const int PoiPx = 14, OverlayPx = 16, ArrowPx = 12, FloorPx = 8;

        public static string Poi(string kind) => PoiKinds.Contains(kind ?? "") ? ArtPaths.Data("images/chaos/mapmarkers/poi_" + kind + ".png") : null;
        public static string Overlay(string kind) => OverlayKinds.Contains(kind ?? "") ? ArtPaths.Data("images/chaos/mapoverlay/" + kind + ".png") : null;
        public static string PartyArrow(string dir) => Directions.Contains(dir ?? "") ? ArtPaths.Data("images/chaos/mapmarkers/party_arrow_" + dir + ".png") : null;
        public static string PartyPin => ArtPaths.Data("images/chaos/mapmarkers/party_pin.png");
        public static string Floor(string arrow) => arrow == "up" ? ArtPaths.Data("images/chaos/mapmarkers/floor_up.png") : arrow == "down" ? ArtPaths.Data("images/chaos/mapmarkers/floor_down.png") : null;
        /// <summary>The mark over an NPC head (16 x 24): new, ready or locked.</summary>
        public static string NpcMark(string mark) => mark == "new" || mark == "ready" || mark == "locked" ? ArtPaths.Data("images/chaos/mapmarkers/npcmark_" + mark + ".png") : null;

        /// <summary>A picture drawn at a whole multiple of its own size that fits the room (pixel art stays sharp): 1x, 2x, 3x ... but never below 1x.</summary>
        public static float Fit(int px, float room)
        {
            if (room < px) return room;
            return px * (float)Math.Floor(room / px);
        }
    }

    /// <summary>The name plate pictures (game_nameplate): plate_frame.png of 16 x 15 cut in nine with a border of 6 (nameplate.lua BORDER).</summary>
    public static class PlateArt
    {
        public const int Border = 6, Width = 16, Height = 15;
        public static string Path(string frame) => "game_nameplate/images/plate_" + (NameplateState.KnownFrame(frame) ? frame : "default") + ".png";
        /// <summary>The border drawn: the picture's own at the size of a plate, less when the box is small so the corners never cross.</summary>
        public static float Edge(float boxW, float boxH) => Math.Min(Border, Math.Max(1f, Math.Min(boxW, boxH) / 2f - 1f));
    }

    // ============================================================================================================ explored map kept
    /// <summary>The explored minimap of a character kept over a relog and a restart (game_minimapsync keeps it in the main client's own minimap file): per floor the
    /// tiles with their colour byte, tile keys as sorted deltas in variable length numbers. Files are small: a typical walk is a few hundred KB.</summary>
    public static class MinimapStore
    {
        public const string Magic = "CMM1";
        public const int MaxTiles = 4000000;

        public static string FileName(string character)
        {
            if (string.IsNullOrEmpty(character)) return null;
            var sb = new StringBuilder("minimap_");
            foreach (char c in character.ToLowerInvariant()) sb.Append(char.IsLetterOrDigit(c) ? c : '_');
            return sb.Append(".bin").ToString();
        }

        static void PutVar(BinaryWriter w, long v)
        {
            ulong u = (ulong)v;
            while (u >= 0x80) { w.Write((byte)(u | 0x80)); u >>= 7; }
            w.Write((byte)u);
        }

        static long GetVar(BinaryReader r)
        {
            ulong u = 0; int shift = 0;
            while (true)
            {
                byte b = r.ReadByte();
                u |= (ulong)(b & 0x7F) << shift;
                if ((b & 0x80) == 0) break;
                shift += 7;
                if (shift > 63) throw new InvalidDataException("number too long");
            }
            return (long)u;
        }

        public static byte[] Save(MinimapMemory mem)
        {
            var ms = new MemoryStream();
            using (var w = new BinaryWriter(ms, Encoding.ASCII, true))
            {
                w.Write(Encoding.ASCII.GetBytes(Magic));
                var floors = new List<int>();
                for (int z = 0; z <= 15; z++) if (mem.Count(z) > 0) floors.Add(z);
                w.Write((byte)floors.Count);
                foreach (int z in floors)
                {
                    var keys = new List<long>(mem.Keys(z));
                    keys.Sort();
                    w.Write((byte)z);
                    PutVar(w, keys.Count);
                    long prev = 0;
                    foreach (long k in keys)
                    {
                        PutVar(w, k - prev);
                        w.Write(mem.GetKey(z, k));
                        prev = k;
                    }
                }
            }
            return ms.ToArray();
        }

        /// <summary>Reads a saved map into mem; false (and mem left as it was) for anything that is not a file of this format.</summary>
        public static bool Load(byte[] data, MinimapMemory mem)
        {
            if (data == null || data.Length < 5) return false;
            try
            {
                using (var r = new BinaryReader(new MemoryStream(data), Encoding.ASCII))
                {
                    if (Encoding.ASCII.GetString(r.ReadBytes(4)) != Magic) return false;
                    int n = r.ReadByte();
                    var staged = new List<KeyValuePair<int, List<KeyValuePair<long, byte>>>>();
                    long total = 0;
                    for (int i = 0; i < n; i++)
                    {
                        int z = r.ReadByte();
                        if (z > 15) return false;
                        long count = GetVar(r);
                        total += count;
                        if (count < 0 || total > MaxTiles) return false;
                        var list = new List<KeyValuePair<long, byte>>((int)Math.Min(count, 1 << 20));
                        long k = 0;
                        for (long j = 0; j < count; j++)
                        {
                            k += GetVar(r);
                            byte c = r.ReadByte();
                            list.Add(new KeyValuePair<long, byte>(k, c));
                        }
                        staged.Add(new KeyValuePair<int, List<KeyValuePair<long, byte>>>(z, list));
                    }
                    foreach (var f in staged) foreach (var kv in f.Value) mem.SetKey(f.Key, kv.Key, kv.Value);
                }
                return true;
            }
            catch (EndOfStreamException) { return false; }
            catch (InvalidDataException) { return false; }
            catch (IOException) { return false; }
        }

        /// <summary>Save again only when the map changed and a minute passed since the last save (the main client writes its map at the end of a session).</summary>
        public static bool DueForSave(int version, int savedVersion, double now, double savedAt, double everyMs = 60000) => version != savedVersion && now - savedAt >= everyMs;
    }

    // ============================================================================================================ death note
    /// <summary>The windows that come back after a death (game_mapoverlay reopens the overlay, game_minimapsync the minimap window): the note is kept for the same
    /// character and used when it comes back within two minutes (MapOverlayState.DeathReopenMs).</summary>
    public sealed class DeathNote
    {
        public const string Pref = "chaos.deathnote";
        public string Name = "";
        public double AtMs;
        public bool Overlay, Minimap;

        public bool Any => Overlay || Minimap;

        public string Serialize() => Name.Replace('|', ' ') + "|" + ((long)AtMs).ToString(System.Globalization.CultureInfo.InvariantCulture) + "|" + (Overlay ? "1" : "0") + (Minimap ? "1" : "0");

        public static DeathNote Parse(string s)
        {
            var n = new DeathNote();
            if (string.IsNullOrEmpty(s)) return n;
            var p = s.Split('|');
            if (p.Length != 3 || p[2].Length != 2 || !long.TryParse(p[1], System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out long at)) return n;
            n.Name = p[0]; n.AtMs = at; n.Overlay = p[2][0] == '1'; n.Minimap = p[2][1] == '1';
            return n;
        }

        /// <summary>True when the windows of this note should open now for this character.</summary>
        public bool Reopens(string name, double nowMs) => Any && MapOverlayState.ReopenAfterDeath(Name, AtMs, name, nowMs);
    }

    // ============================================================================================================ name plate try-on
    /// <summary>The TRY ON of a store name plate (game_shop tryon.lua plateFrame): the frame an offer shows on the own plate for ten seconds, on this client only.</summary>
    public static class PlateTry
    {
        /// <summary>The frame of a name plate offer, or of the plate part of a bundle; null for any other look.</summary>
        public static string Frame(PreviewOption o)
        {
            if (o == null) return null;
            if (o.Kind == "nameplate") return NameplateState.KnownFrame(o.Frame) && !string.IsNullOrEmpty(o.Frame) ? o.Frame : null;
            if (o.Kind == "bundle" && o.Parts != null)
                foreach (var p in o.Parts)
                {
                    string f = p != null && p.Kind == "nameplate" ? Frame(p) : null;
                    if (f != null) return f;
                }
            return null;
        }
    }

    // ============================================================================================================ boss defeated picture
    /// <summary>Boss Defeated of game_chaosshots (shots_core.lua isBossKill): a boss-tier monster you attacked within two minutes drops to 0 percent. Unity reads the health of the bosses
    /// in view every frame: a boss that reaches 0, or that leaves the view at 10 percent or less, counts as dead.</summary>
    public sealed class BossKillWatch
    {
        public const double EngagedMs = 120000;
        public const int GoneBelow = 10;
        readonly Dictionary<uint, double> engaged = new Dictionary<uint, double>();
        readonly Dictionary<uint, int> last = new Dictionary<uint, int>();
        readonly HashSet<uint> counted = new HashSet<uint>();   // killed and still in view at 0 percent: counted once

        /// <summary>One frame: target is the creature you attack (0 for none), bosses the boss-tier monsters in view with their health percent. Returns how many bosses of yours died.</summary>
        public int Step(double now, uint target, IEnumerable<KeyValuePair<uint, int>> bosses)
        {
            if (target != 0) engaged[target] = now;
            var seen = new HashSet<uint>();
            int dead = 0;
            foreach (var kv in bosses)
            {
                seen.Add(kv.Key);
                if (kv.Value > 0) counted.Remove(kv.Key);
                if (counted.Contains(kv.Key)) continue;
                last[kv.Key] = kv.Value;
                if (kv.Value <= 0 && Mine(kv.Key, now)) { dead++; counted.Add(kv.Key); engaged.Remove(kv.Key); last.Remove(kv.Key); }
            }
            var gone = new List<uint>();
            foreach (var kv in last) if (!seen.Contains(kv.Key)) gone.Add(kv.Key);
            foreach (uint id in gone)
            {
                int hp = last[id];
                last.Remove(id);
                if (hp <= GoneBelow && Mine(id, now)) { dead++; engaged.Remove(id); }
            }
            counted.RemoveWhere(id => !seen.Contains(id));
            var old = new List<uint>();
            foreach (var kv in engaged) if (now - kv.Value > EngagedMs) old.Add(kv.Key);
            foreach (uint id in old) engaged.Remove(id);
            return dead;
        }

        bool Mine(uint id, double now) => engaged.TryGetValue(id, out double at) && now - at <= EngagedMs;
        public void Clear() { engaged.Clear(); last.Clear(); counted.Clear(); }
    }

    // ============================================================================================================ chat name colour
    /// <summary>The chat colour cosmetic (game_cosmetics 225 "colors", cosmeticslogic.lua colorLine): the speaker's name in a chat line takes the colour the server sent for it.</summary>
    public static class ChatTint
    {
        /// <summary>The name of a speaker as "Name [level]" gives it.</summary>
        public static string SpeakerName(string speaker)
        {
            if (string.IsNullOrEmpty(speaker)) return "";
            int i = speaker.IndexOf(" [", StringComparison.Ordinal);
            return i > 0 ? speaker.Substring(0, i) : speaker;
        }

        static string Escape(string t) => (t ?? "").Replace("<", "<​");

        /// <summary>The line (stamp, space, display) as rich text with the speaker's name in its colour and the rest in baseHex; null when the speaker has no colour or the name is not found.</summary>
        public static string Rich(string stamp, string display, string speaker, IDictionary<string, string> colors, string baseHex)
        {
            if (colors == null || colors.Count == 0) return null;
            string name = SpeakerName(speaker);
            if (name.Length == 0 || !colors.TryGetValue(name, out string col) || !CosmeticsLogic.ValidColor(col)) return null;
            string full = (stamp ?? "") + " " + display;
            if (!CosmeticsLogic.NameRange(full, name, out int first, out int last)) return null;
            string a = full.Substring(0, first - 1), n = full.Substring(first - 1, last - first + 1), b = full.Substring(last);
            string c = col.Length == 9 ? col.Substring(0, 7) : col;   // #rrggbbaa: the alpha has no meaning in text
            return "<color=" + baseHex + ">" + Escape(a) + "</color><color=" + c + ">" + Escape(n) + "</color><color=" + baseHex + ">" + Escape(b) + "</color>";
        }
    }

    // ============================================================================================================ tiled weather art
    /// <summary>How a tiled picture (rain 256, ambient specks 512) is drawn over a box: the texture coordinates of the repeated tile for an offset, as the main client's repeated image does.</summary>
    public static class TiledArt
    {
        public const int RainTile = 256, AmbientTile = 512;
        public static readonly Dictionary<string, string> RainImage = new Dictionary<string, string> { { "far", "rain_far" }, { "mid", "rain_mid" }, { "near", "rain_near" } };
        public static readonly Dictionary<string, string> AmbientImage = new Dictionary<string, string>
        {
            { "embers_far", "ember_far" }, { "embers_near", "ember_near" }, { "motes_far", "mote_far" }, { "motes_near", "mote_near" }, { "dust_far", "dust_far" }, { "dust_near", "dust_near" },
        };

        public static string Path(string image) => "game_chaosweather/images/" + image + ".png";

        static double Wrap(double v) { return v - Math.Floor(v); }

        /// <summary>The source rectangle (u, v, width, height in texture units, v up) that shows a w x h box with the tile scrolled by (ox, oy) pixels down and right.</summary>
        public static void Uv(int tile, double ox, double oy, double w, double h, out double u, out double v, out double du, out double dv)
        {
            du = w / tile; dv = h / tile;
            u = Wrap(-ox / tile);
            double vTop = 1.0 - Wrap(-oy / tile);
            v = vTop - dv;
        }
    }
}
