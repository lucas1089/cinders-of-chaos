// Phase 7, track Y (P1 systems): pure rules for the loot filter rule sounds, the rarity outline of items on the map, the monster bar's world side (tier
// labels over the head, oversized monsters), the main client's bitmap fonts (damage numbers by type), the toast plate and button art, the store's
// look icons. Ports of game_lootfilter lootfilterlogic.lua (pickSound), game_itemrarity, game_monsterbar monsterbarmath.lua / monsterbar.lua,
// game_damagescatter scatterlogic.lua (fontFor), game_chaosnotify toastbuttons.otui, game_shop shopicon.lua. No engine types.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    // ------------------------------------------------------------------------------------------------ loot filter rule sounds
    /// <summary>The sound of a kill's loot rule (lootfilterlogic.lua L.pickSound): the first rule, in the rules' order, that matched an item of the kill and has a sound.</summary>
    public static class LootRuleSounds
    {
        public const string Dir = "game_lootfilter/sounds/";

        /// <summary>The file of a sound id (1 .. 5) under the modules folder, null for none (0) or a bad id.</summary>
        public static string File(int id) => id >= 1 && id <= LootRules.Sounds.Length ? Dir + LootRules.Sounds[id - 1].ToLowerInvariant() + ".ogg" : null;

        /// <summary>The file, the gain (0..1) and the rule of a kill; false when the settings are muted, the volume is 0, no rule matched or the matching rules have no sound.</summary>
        public static bool Pick(IDictionary<string, int> hits, LootSoundSettings snd, out string file, out float gain, out string rule)
        {
            file = null; gain = 0f; rule = null;
            if (snd == null || hits == null || snd.Mute || snd.Volume <= 0) return false;
            foreach (var r in LootRules.All)
            {
                int id;
                if (!snd.Rules.TryGetValue(r.Key, out id)) continue;
                string f = File(id);
                int n;
                if (f != null && hits.TryGetValue(r.Key, out n) && n > 0)
                {
                    file = f; gain = Math.Max(0f, Math.Min(1f, snd.Volume / 100f)); rule = r.Key;
                    return true;
                }
            }
            return false;
        }
    }

    /// <summary>One loot filter rule counter row of the Hunt Tracker's Chaos Drops tab (lootfilterlogic.lua L.huntRows).</summary>
    public sealed class HuntRuleRow
    {
        public string Key = "", Name = "", Color = "";
        public int Session, Total;
        public string Text => Loc.T("Filter rule: {0}", Loc.T(Name));
        public string Tip => Loc.T("Since login: {0}   Total: {1}", LootRules.Number(Session), LootRules.Number(Total));
    }

    public static class LootHuntRows
    {
        /// <summary>The rule counters for the Hunt Tracker: every rule in order, only while the filter's "Show the counters in the Hunt Tracker" option is on and the settings are loaded.</summary>
        public static List<HuntRuleRow> Rows(LootFilterModel f)
        {
            var rows = new List<HuntRuleRow>();
            if (f == null || !f.Loaded || !f.Sound.Hunt) return rows;
            foreach (var r in LootRules.All)
            {
                int s, t;
                f.CountSession.TryGetValue(r.Key, out s); f.CountTotal.TryGetValue(r.Key, out t);
                rows.Add(new HuntRuleRow { Key = r.Key, Name = r.Name, Color = r.Color, Session = s, Total = t });
            }
            return rows;
        }
    }

    // ------------------------------------------------------------------------------------------------ rarity outline on the map
    /// <summary>The outline of an item lying on the map (game_itemrarity: the world rarity shader; Unity draws the sprite again, tinted, one pixel to every side behind itself).</summary>
    public static class MapItemOutline
    {
        public const string PrefKey = "chaos.itemoutline";
        /// <summary>Common items get none (no colour worth the pixels on every loose item); every other rarity and a unique one do.</summary>
        public const int MinRarity = 2;
        public const float PixelsPerTile = 32f;
        public static readonly int[][] Offsets = { new[] { -1, 0 }, new[] { 1, 0 }, new[] { 0, -1 }, new[] { 0, 1 } };

        /// <summary>The outline colour (hex) of an item, null for none.</summary>
        public static string Color(Item it)
        {
            if (it == null || it.Type == null) return null;
            if (ItemRarity.IsUnique(it)) return ItemRarity.UniqueColor;
            int r = ItemRarity.Of(it);
            return r >= MinRarity ? ItemRarity.Color(r) : null;
        }

        /// <summary>Opacity 0..1: a steady 0.85 up to Rare, a slow pulse (0.6 .. 1) for Legendary, Divine and unique items.</summary>
        public static float Alpha(Item it, double nowMs)
        {
            if (it == null) return 0f;
            int r = ItemRarity.Of(it);
            if (!ItemRarity.IsUnique(it) && r < 5) return 0.85f;
            return 0.8f + 0.2f * (float)Math.Sin(nowMs / 450.0);
        }
    }

    // ------------------------------------------------------------------------------------------------ monster bar, world side
    /// <summary>The opaque bounds of a creature's body in pixels (the outfit anchors of the main client, measured from the sprites).</summary>
    public struct BodyBox
    {
        public int MinX, MinY, MaxX, MaxY;   // inclusive, rows top first, relative to the first sprite
        public bool Empty => MaxX < MinX;
        public int Width => Empty ? 0 : MaxX - MinX + 1;
        public int Height => Empty ? 0 : MaxY - MinY + 1;
        public static BodyBox None => new BodyBox { MinX = int.MaxValue, MinY = int.MaxValue, MaxX = -1, MaxY = -1 };

        /// <summary>Adds a w x h sprite (RGBA, rows top first) placed at (ox, oy) pixels.</summary>
        public void Add(byte[] rgba, int w, int h, int ox, int oy)
        {
            if (rgba == null || rgba.Length < w * h * 4) return;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    if (rgba[(y * w + x) * 4 + 3] < 16) continue;
                    if (ox + x < MinX) MinX = ox + x;
                    if (ox + x > MaxX) MaxX = ox + x;
                    if (oy + y < MinY) MinY = oy + y;
                    if (oy + y > MaxY) MaxY = oy + y;
                }
        }
    }

    /// <summary>What the monster bar does in the world (monsterbarmath.lua drawScale / isOversized, monsterbar.lua labelCreature).</summary>
    public static class MonsterWorld
    {
        public const float BossScale = 1.5f, ScaleMin = 0.5f;
        public const int BodyMaxH = 68, BodyMaxW = 96;

        /// <summary>The draw size of a monster: a boss or an omen guardian bigger, a rift guardian as drawn, any other monster shrunk until its body fits (never below ScaleMin).</summary>
        public static float DrawScale(int bodyW, int bodyH, string tier, string role)
        {
            if (tier == "boss" || role == "omen") return BossScale;
            if (role == "guardian") return 1f;
            if (bodyW <= 0 || bodyH <= 0 || (bodyH <= BodyMaxH && bodyW <= BodyMaxW)) return 1f;
            double f = Math.Min((double)BodyMaxH / Math.Max(bodyH, 1), (double)BodyMaxW / Math.Max(bodyW, 1));
            return (float)Math.Max(ScaleMin, Math.Floor(f * 100 + 0.5) / 100);
        }

        public static float DrawScale(BodyBox b, string tier, string role) => DrawScale(b.Width, b.Height, tier, role);

        /// <summary>A body too big for an ordinary monster: the tier is asked for at once, so a boss is never left shrunk.</summary>
        public static bool IsOversized(BodyBox b) => DrawScale(b.Width, b.Height, null, null) < 1f;

        /// <summary>The modifier lines over the name: two modifiers to a line, joined with " - ", each with a capital.</summary>
        public static List<string> ModLines(IList<string> mods)
        {
            var lines = new List<string>();
            if (mods == null) return lines;
            for (int i = 0; i < mods.Count; i += 2)
            {
                string a = Cap(mods[i]);
                lines.Add(i + 1 < mods.Count ? a + " - " + Cap(mods[i + 1]) : a);
            }
            return lines;
        }

        static string Cap(string s) => string.IsNullOrEmpty(s) ? "" : char.ToUpperInvariant(s[0]) + s.Substring(1);

        /// <summary>The colour of the name (and the small bar) of a tiered monster, null for the plain tier (the name keeps its colour).</summary>
        public static string NameColor(MonsterInfo info)
        {
            if (info == null) return null;
            var st = MonsterBar.Styles[MonsterBar.StyleKey(info.Tier, info.Role)];
            return st.world;
        }

        /// <summary>The tier word over the name ("Magic", "Rare", "Legendary", a role's tag), empty for none: the label of the server when it sent one.</summary>
        public static string TierWord(MonsterInfo info)
        {
            if (info == null) return "";
            string key = MonsterBar.StyleKey(info.Tier, info.Role);
            var st = MonsterBar.Styles[key];
            if (!st.role && !string.IsNullOrEmpty(info.Label)) return info.Label;
            return st.label ?? "";
        }
    }

    // ------------------------------------------------------------------------------------------------ bitmap fonts (damage numbers)
    /// <summary>A font of the main client (data/fonts/chaos/*.otfont and its sheet): fixed cells of a sheet; the glyph width is the last opaque column of its cell, as the engine measures it.</summary>
    public sealed class BitmapFont
    {
        public string Name = "";
        public int CellW, CellH, FirstGlyph = 32, YOffset, SpacingX, SpacingY, SpaceWidth = 4;
        public int SheetW, SheetH;
        readonly int[] widths = new int[256];
        byte[] sheet;   // RGBA, rows top first

        public bool Ready => sheet != null && CellW > 0 && CellH > 0;

        /// <summary>Reads the .otfont text: "name: value" lines under "Font". Returns null when it has no glyph size.</summary>
        public static BitmapFont ParseDef(string text)
        {
            if (text == null) return null;
            var f = new BitmapFont();
            foreach (string raw in text.Split('\n'))
            {
                string line = raw.Trim();
                int c = line.IndexOf(':');
                if (c <= 0 || line.StartsWith("//")) continue;
                string key = line.Substring(0, c).Trim(), val = line.Substring(c + 1).Trim();
                var nums = new List<int>();
                foreach (string part in val.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries)) { int n; if (int.TryParse(part, NumberStyles.Integer, CultureInfo.InvariantCulture, out n)) nums.Add(n); }
                switch (key)
                {
                    case "name": f.Name = val; break;
                    case "glyph-size": if (nums.Count >= 2) { f.CellW = nums[0]; f.CellH = nums[1]; } break;
                    case "first-glyph": if (nums.Count >= 1) f.FirstGlyph = nums[0]; break;
                    case "y-offset": if (nums.Count >= 1) f.YOffset = nums[0]; break;
                    case "spacing": if (nums.Count >= 2) { f.SpacingX = nums[0]; f.SpacingY = nums[1]; } break;
                    case "space-width": if (nums.Count >= 1) f.SpaceWidth = nums[0]; break;
                }
            }
            return f.CellW > 0 && f.CellH > 0 ? f : null;
        }

        /// <summary>Gives the sheet (RGBA, rows top first) and measures the glyphs.</summary>
        public void SetSheet(byte[] rgba, int w, int h)
        {
            sheet = null;
            if (rgba == null || rgba.Length < w * h * 4 || CellW <= 0 || CellH <= 0) return;
            sheet = rgba; SheetW = w; SheetH = h;
            int cols = Math.Max(1, w / CellW);
            for (int g = FirstGlyph; g < 256; g++)
            {
                int cx = ((g - FirstGlyph) % cols) * CellW, cy = ((g - FirstGlyph) / cols) * CellH;
                int width = 0;
                if (cy + CellH <= h)
                    for (int x = 0; x < CellW; x++)
                    {
                        bool filled = false;
                        for (int y = 0; y < CellH && !filled; y++) filled = rgba[((cy + y) * w + cx + x) * 4 + 3] != 0;
                        if (filled) width = x + 1;
                    }
                widths[g] = width;
            }
            widths[32] = SpaceWidth;
        }

        int Glyph(char ch)
        {
            int g = ch < 256 ? ch : '?';
            return g >= FirstGlyph ? g : '?';
        }

        public int GlyphWidth(char ch) { int g = Glyph(ch); return g < 256 ? widths[g] : 0; }

        /// <summary>The width of a text in pixels (glyph widths plus the spacing).</summary>
        public int Measure(string text)
        {
            if (string.IsNullOrEmpty(text)) return 0;
            int w = 0;
            foreach (char ch in text) w += GlyphWidth(ch) + SpacingX;
            return Math.Max(0, w - SpacingX);
        }

        /// <summary>The text as a picture (RGBA, rows bottom first as a Unity texture wants them), each pixel's colour times the tint (0..1). w x h out.</summary>
        public byte[] Render(string text, float tr, float tg, float tb, out int w, out int h)
        {
            w = Math.Max(1, Measure(text)); h = CellH;
            var px = new byte[w * h * 4];
            if (!Ready || string.IsNullOrEmpty(text)) return px;
            int cols = Math.Max(1, SheetW / CellW);
            int x0 = 0;
            foreach (char ch in text)
            {
                int g = Glyph(ch);
                int gw = g < 256 ? widths[g] : 0;
                if (g != 32 && gw > 0)
                {
                    int cx = ((g - FirstGlyph) % cols) * CellW, cy = ((g - FirstGlyph) / cols) * CellH;
                    for (int y = 0; y < CellH; y++)
                        for (int x = 0; x < gw && x0 + x < w; x++)
                        {
                            int s = ((cy + y) * SheetW + cx + x) * 4;
                            byte a = sheet[s + 3];
                            if (a == 0) continue;
                            int d = (((h - 1 - y) * w) + x0 + x) * 4;
                            px[d] = Mul(sheet[s], tr); px[d + 1] = Mul(sheet[s + 1], tg); px[d + 2] = Mul(sheet[s + 2], tb); px[d + 3] = a;
                        }
                }
                x0 += gw + SpacingX;
            }
            return px;
        }

        static byte Mul(byte v, float t) => (byte)Math.Max(0, Math.Min(255, (int)(v * Math.Max(0f, Math.Min(1f, t)) + 0.5f)));
    }

    /// <summary>The font per damage number type (scatterlogic.lua L.FONTS): a critical hit in the big bordered display font, a condition tick in the small bordered one.</summary>
    public static class ScatterFonts
    {
        public const string Dir = "fonts/chaos/";

        /// <summary>The font name of an impact type (ImpactType), null for the stock number.</summary>
        public static string FontFor(int impact)
        {
            if (impact == ImpactType.Critical) return "chaos-display-16px";
            if (impact == ImpactType.Condition) return "chaos-outline-11px";
            return null;
        }

        public static string DefPath(string font) => ArtPaths.Data(Dir + font + ".otfont");
        public static string SheetPath(string font) => ArtPaths.Data(Dir + font + ".png");

        /// <summary>How big a number drawn with a font is, in tiles per font pixel: the typed size factor of the stock number is taken out (the font has its own size).</summary>
        public const float TilesPerPixel = 1f / 26f;

        public static float SizeFactor(int impact) => impact == ImpactType.Critical ? ImpactType.CritSize : impact == ImpactType.Condition ? ImpactType.ConditionSize : 1f;
    }

    // ------------------------------------------------------------------------------------------------ tooltip side plates
    public struct PlateRect { public float x, y, width, height; }

    /// <summary>Where the compare plates of an item tooltip go (item_tooltip.lua: the main tooltip right of the cursor when it fits, the compare plates on the side with room).</summary>
    public static class TooltipPlates
    {
        public const float Gap = 6f, Margin = 4f;

        /// <summary>The rectangles of n plates as wide as the main one: in a row to the right of it when they fit, else to the left, else on the side with more room (pushed inside the screen); top with the main plate, moved up to fit.</summary>
        public static List<PlateRect> Place(float mx, float my, float width, float mainHeight, float screenW, float screenH, int n, Func<int, float> heightOf)
        {
            var list = new List<PlateRect>();
            if (n <= 0) return list;
            float need = n * (width + Gap);
            float rightRoom = screenW - Margin - (mx + width), leftRoom = mx - Margin;
            bool right = rightRoom >= need || (leftRoom < need && rightRoom >= leftRoom);
            for (int i = 0; i < n; i++)
            {
                float x = right ? mx + width + Gap + i * (width + Gap) : mx - (i + 1) * (width + Gap);
                x = Math.Max(Margin, Math.Min(screenW - Margin - width, x));
                float h = heightOf != null ? heightOf(i) : mainHeight;
                float y = Math.Max(Margin, Math.Min(my, screenH - Margin - h));
                list.Add(new PlateRect { x = x, y = y, width = width, height = h });
            }
            return list;
        }
    }

    // ------------------------------------------------------------------------------------------------ toast art
    /// <summary>The toast's pictures of game_chaosnotify: the plate, the answer buttons (four 80 x 24 states in a strip), the monster look over the icon.</summary>
    public static class ToastArt
    {
        public const string Plate = "game_chaosnotify/images/Background.png";
        public const string AcceptStrip = "game_chaosnotify/images/toast/accept.png", DeclineStrip = "game_chaosnotify/images/toast/decline.png";
        public const int ButtonW = 80, ButtonH = 24, MonsterBox = 48;
        public const string PlateTint = "#ccbebb", PlateBorder = "#6a5632";

        public enum ButtonState { Normal = 0, Hover = 1, Pressed = 2, Disabled = 3 }

        /// <summary>The strip row of a state, in pixels from the top of the strip.</summary>
        public static int ClipY(ButtonState s) => (int)s * ButtonH;

        public static ButtonState StateOf(bool enabled, bool hover, bool pressed) => !enabled ? ButtonState.Disabled : pressed ? ButtonState.Pressed : hover ? ButtonState.Hover : ButtonState.Normal;

        /// <summary>The label colour of a state (toastbuttons.otui).</summary>
        public static string LabelColor(ButtonState s)
        {
            switch (s) { case ButtonState.Hover: return "#fff3cf"; case ButtonState.Pressed: return "#d6c9ae"; case ButtonState.Disabled: return "#7d7176"; default: return "#e9dcc0"; }
        }

        /// <summary>A toast shows the creature's look over its icon when the server sent one (taskComplete, bounty, bestiary, battle pass); the look of a creature is a looktype above 0.</summary>
        public static bool HasMonsterLook(Toast t) => t != null && t.MonsterLook > 0;
    }

    // ------------------------------------------------------------------------------------------------ store look icons
    /// <summary>What an offer's icon is (shopicon.lua ShopIcon.plan) for the looks that are no creature: a footprint's print, a plate frame, a colour sample.</summary>
    public sealed class StoreLookIcon
    {
        public const string Native = "native", Image = "image", Swatch = "swatch";
        public string Mode = Native, Path = "", Color = "";
        public bool Accent, Fixed;

        public const string Prints = "game_cosmeticfx/images/prints/", Plates = "game_nameplate/images/plate_";

        static string ArtName(string v)
        {
            if (string.IsNullOrEmpty(v) || v.Length > 40) return null;
            foreach (char c in v) if (!(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_')) return null;
            return v;
        }

        public static StoreLookIcon Plan(object look)
        {
            var p = new StoreLookIcon();
            if (!(look is Dictionary<string, object>)) return p;
            string kind = Json.Text(look, "kind");
            string art;
            if (kind == "footprint" && (art = ArtName(Json.Text(look, "art"))) != null) { p.Mode = Image; p.Path = Prints + art + ".png"; }
            else if (kind == "nameplate" && (art = ArtName(Json.Text(look, "frame"))) != null) { p.Mode = Image; p.Path = Plates + art + ".png"; p.Fixed = true; }
            else if (kind == "swatch")
            {
                string c = StoreTryOn.HexOrEmpty(Json.Text(look, "color"), true);
                if (c.Length > 0) { p.Mode = Swatch; p.Color = c; p.Accent = Json.Truthy(look, "accent"); }
            }
            return p;
        }

        /// <summary>The text of a colour sample ("Aa" in the colour, nothing for a loot label accent, which is a bar).</summary>
        public static string SampleText(StoreLookIcon p) => p != null && p.Accent ? "" : "Aa";
    }
}
