// Phase 9, track E (outfit and look UI): pure rules of the rows game_outfitextras, game_lookpreview, client_chaos_topbar (login screen) and game_chaoslayout (window sizes). No UnityEngine.
// Tests: Core.Tests/Phase9ETests.cs. pt-BR texts: LocPhase9E.cs.
// Sources: client/overlay/modules/game_outfitextras/customisecore.lua (categories, cards, colour tabs), game_lookpreview/lookpreview_core.lua (the effect stage, list cards),
// client_chaos_topbar/chaos_topbar.lua (entries marked `offline`), game_chaoslayout/layout_logic.lua (the saved window layout).
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    // ============================================================================================================ game_outfitextras: the look categories and the colour palette
    /// <summary>A card of the Outfit, Mount, Wings, Aura or Shader category of the Customise Character window: an owned or locked entry of the server's list, or "None".</summary>
    public sealed class LookCard
    {
        public int Id;
        public string Name = "", Tip;
        public bool Locked, None;
    }

    /// <summary>The categories the Customise Character window has besides the cosmetic rows (customisecore.lua C.SLOTS, C.TABS): outfit, mount, wings, aura and shader from the outfit
    /// window's packet and the wardrobe, and the colour palette with its four tabs.</summary>
    public static class ExtrasLook
    {
        public static readonly string[] LookKeys = { "outfit", "mount", "wings", "aura", "shader" };
        public const string ColorsKey = "colors";
        public const int ColorColumns = 19, ColorRows = 7, ColorCount = ColorColumns * ColorRows;

        /// <summary>The four colour tabs and the outfit field each paints (head, body, legs, feet).</summary>
        public static readonly string[] ColorTabs = { "head", "primary", "secondary", "detail" };

        public static bool IsLook(string key) => Array.IndexOf(LookKeys, key) >= 0;

        /// <summary>Wings, aura and shader come only with the Chaos lists of the outfit window (an Identity.Chaos connection).</summary>
        public static bool NeedsExtras(string key) => key == "wings" || key == "aura" || key == "shader";

        public static string Label(string key)
        {
            switch (key)
            {
                case "outfit": return Loc.T("Outfit");
                case "mount": return Loc.T("Mount");
                case "wings": return Loc.T("Wings");
                case "aura": return Loc.T("Aura");
                case "shader": return Loc.T("Shader");
                case ColorsKey: return Loc.T("Colors");
            }
            return key;
        }

        public static string TabLabel(string tab)
        {
            switch (tab)
            {
                case "head": return Loc.T("Head");
                case "primary": return Loc.T("Primary");
                case "secondary": return Loc.T("Secondary");
                case "detail": return Loc.T("Detail");
            }
            return tab;
        }

        /// <summary>The category keys in window order: the look categories (wings, aura and shader only with the extras), the colours, then the cosmetic rows.</summary>
        public static List<string> Categories(bool hasExtras, IEnumerable<string> rowKeys)
        {
            var o = new List<string>();
            foreach (string k in LookKeys) if (!NeedsExtras(k) || hasExtras) o.Add(k);
            o.Add(ColorsKey);
            if (rowKeys != null) foreach (string k in rowKeys) if (!o.Contains(k)) o.Add(k);
            return o;
        }

        /// <summary>The key of a category that exists: the asked one, else the first.</summary>
        public static string Known(string key, IList<string> categories) => categories.Contains(key) ? key : categories.Count > 0 ? categories[0] : key;

        /// <summary>The (id, name) pairs of the packet's list of a look category, in the server's order.</summary>
        public static List<KeyValuePair<int, string>> Stock(string kind, OutfitWindowState st)
        {
            var o = new List<KeyValuePair<int, string>>();
            if (st == null) return o;
            switch (kind)
            {
                case "outfit": foreach (var x in st.Outfits) o.Add(new KeyValuePair<int, string>(x.LookType, x.Name)); break;
                case "mount": foreach (var x in st.Mounts) o.Add(new KeyValuePair<int, string>(x.Id, x.Name)); break;
                case "wings": foreach (var x in st.Wings) o.Add(new KeyValuePair<int, string>(x.Id, x.Name)); break;
                case "aura": foreach (var x in st.Auras) o.Add(new KeyValuePair<int, string>(x.Id, x.Name)); break;
                case "shader": foreach (var x in st.Shaders) o.Add(new KeyValuePair<int, string>(0, x.Name)); break;
            }
            return o;
        }

        /// <summary>The rows of one category: the owned entries, then the wardrobe's locked ones unless onlyMine (game_unlocks), shared with the Outfit window.</summary>
        public static List<WardrobeRow> Rows(string kind, OutfitWindowState st, IList<WardrobeEntry> catalogue, bool onlyMine)
            => WardrobeView.Display(kind, Stock(kind, st), catalogue, onlyMine);

        /// <summary>The cards of a category: "None" first for mount, wings, aura and shader (when it matches the search), then the rows; the search keeps the names that hold every word.</summary>
        public static List<LookCard> Cards(string kind, OutfitWindowState st, IList<WardrobeEntry> catalogue, bool onlyMine, string search)
        {
            var o = new List<LookCard>();
            var words = Words(search);
            if (kind != "outfit" && Matches(Loc.T("None"), words)) o.Add(new LookCard { Name = Loc.T("None"), None = true });
            foreach (var r in Rows(kind, st, catalogue, onlyMine))
            {
                if (!Matches(r.Name, words)) continue;
                o.Add(new LookCard { Id = r.Id, Name = r.Name, Locked = r.Locked, Tip = r.Tip });
            }
            return o;
        }

        static List<string> Words(string search)
        {
            var w = new List<string>();
            foreach (var x in (search ?? "").ToLowerInvariant().Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries)) w.Add(x);
            return w;
        }

        static bool Matches(string name, List<string> words)
        {
            string n = (name ?? "").ToLowerInvariant();
            foreach (string w in words) if (n.IndexOf(w, StringComparison.Ordinal) < 0) return false;
            return true;
        }

        /// <summary>Owned and all cards of a category (the "have / all" count of its title line); "None" counts for neither.</summary>
        public static void Count(IList<LookCard> cards, out int have, out int all)
        {
            have = all = 0;
            foreach (var c in cards) { if (c.None) continue; all++; if (!c.Locked) have++; }
        }

        /// <summary>The outfit with a card applied (C.applyCard): an outfit card sets the look and keeps the addons the new look allows, the others set their field; None clears it.</summary>
        public static Outfit Apply(Outfit o, OutfitWindowState st, string kind, LookCard c)
        {
            var n = OutfitWindowState.Copy(o ?? new Outfit());
            if (c == null) return n;
            switch (kind)
            {
                case "outfit": return st != null ? st.WithLook(n, c.Id) : n;
                case "mount": n.Mount = c.None ? 0 : c.Id; break;
                case "wings": n.Wings = c.None ? 0 : c.Id; break;
                case "aura": n.Aura = c.None ? 0 : c.Id; break;
                case "shader": n.Shader = c.None ? "" : c.Name; break;
            }
            return n;
        }

        /// <summary>Is this card the one worn in the outfit being edited (C.isCurrent)?</summary>
        public static bool IsCurrent(Outfit o, string kind, LookCard c)
        {
            if (o == null || c == null) return false;
            switch (kind)
            {
                case "outfit": return !c.None && o.LookType == c.Id;
                case "mount": return c.None ? o.Mount == 0 : o.Mount == c.Id;
                case "wings": return c.None ? o.Wings == 0 : o.Wings == c.Id;
                case "aura": return c.None ? o.Aura == 0 : o.Aura == c.Id;
                case "shader": return c.None ? string.IsNullOrEmpty(o.Shader) : o.Shader == c.Name;
            }
            return false;
        }

        /// <summary>The look a card draws (C.cardLook): an outfit card the look in the colours being edited, a mount card the mount alone, wings, aura and shader the outfit with that part; null for "None".</summary>
        public static Outfit CardLook(Outfit o, string kind, LookCard c)
        {
            if (c == null || c.None) return null;
            o = o ?? new Outfit();
            switch (kind)
            {
                case "outfit": return new Outfit(c.Id, o.Head, o.Body, o.Legs, o.Feet, 0);
                case "mount": return new Outfit(c.Id, 0, 0, 0, 0);
                case "wings": case "aura": case "shader":
                    var n = new Outfit(o.LookType, o.Head, o.Body, o.Legs, o.Feet, o.Addons) { Shader = "" };
                    if (kind == "wings") n.Wings = c.Id; else if (kind == "aura") n.Aura = c.Id; else n.Shader = c.Name;
                    return n;
            }
            return null;
        }

        /// <summary>The name of the worn entry of a look category for the Equipped now strip; "-" when none, the id when the list has not come yet.</summary>
        public static string Equipped(string kind, Outfit o, OutfitWindowState st)
        {
            if (o == null) return "-";
            string name = null;
            switch (kind)
            {
                case "outfit": name = st?.FindOutfit(o.LookType)?.Name ?? (o.LookType > 0 ? o.LookType.ToString(CultureInfo.InvariantCulture) : null); break;
                case "mount": if (o.Mount > 0) name = Find(st?.Mounts, o.Mount) ?? o.Mount.ToString(CultureInfo.InvariantCulture); break;
                case "wings": if (o.Wings > 0) name = Find(st?.Wings, o.Wings) ?? o.Wings.ToString(CultureInfo.InvariantCulture); break;
                case "aura": if (o.Aura > 0) name = Find(st?.Auras, o.Aura) ?? o.Aura.ToString(CultureInfo.InvariantCulture); break;
                case "shader": if (!string.IsNullOrEmpty(o.Shader)) name = o.Shader; break;
            }
            return Label(kind) + ": " + (name ?? "-");
        }

        static string Find(List<NamedId> list, int id)
        {
            if (list != null) foreach (var n in list) if (n.Id == id) return n.Name;
            return null;
        }

        /// <summary>The outfit to send with Apply: a layer left off is none (C.outfitToSend).</summary>
        public static Outfit ToSend(Outfit o, bool mount, bool wings, bool aura, bool shader)
        {
            var n = OutfitWindowState.Copy(o ?? new Outfit());
            if (!mount) n.Mount = 0;
            if (!wings) n.Wings = 0;
            if (!aura) n.Aura = 0;
            if (!shader) n.Shader = "";
            return n;
        }

        /// <summary>Did the look change from the one the server last sent? Then Apply sends it.</summary>
        public static bool Changed(Outfit a, Outfit b) => LookPreview.Key(a) != LookPreview.Key(b);

        // ---- the colour palette
        public static int ColorOf(Outfit o, string tab)
        {
            switch (tab) { case "head": return o.Head; case "primary": return o.Body; case "secondary": return o.Legs; case "detail": return o.Feet; }
            return 0;
        }

        /// <summary>The outfit with one palette cell picked on a tab (C.setColor); a cell outside the 7 x 19 grid changes nothing.</summary>
        public static Outfit SetColor(Outfit o, string tab, int index)
        {
            var n = OutfitWindowState.Copy(o ?? new Outfit());
            if (index < 0 || index >= ColorCount) return n;
            switch (tab) { case "head": n.Head = index; break; case "primary": n.Body = index; break; case "secondary": n.Legs = index; break; case "detail": n.Feet = index; break; }
            return n;
        }

        /// <summary>The cell of a pointer position in the palette grid (cell + gap pixels each), -1 outside.</summary>
        public static int CellAt(float x, float y, float cell, float gap)
        {
            if (x < 0 || y < 0) return -1;
            float step = cell + gap;
            int col = (int)(x / step), row = (int)(y / step);
            if (col >= ColorColumns || row >= ColorRows) return -1;
            if (x - col * step > cell || y - row * step > cell) return -1;
            return row * ColorColumns + col;
        }

        /// <summary>The addon bits the look allows are set or cleared (C.setAddon): bit 0 addon 1, bit 1 addon 2.</summary>
        public static Outfit SetAddon(Outfit o, OutfitWindowState st, int bit, bool on)
        {
            var n = OutfitWindowState.Copy(o ?? new Outfit());
            int allowed = st != null ? st.AddonsOf(n.LookType) : 3;
            if ((allowed & (1 << bit)) == 0) on = false;
            n.Addons = on ? n.Addons | (1 << bit) : n.Addons & ~(1 << bit);
            return n;
        }
    }

    // ============================================================================================================ game_lookpreview: list cards
    /// <summary>The list cards of the main client (lookpreview_core.lua cardLayout): the look facing south, as large as fits the card's picture part, feet centred.</summary>
    public struct CardFigure
    {
        public float Fx, Fy, Top, Left, Right;
    }

    public struct CardLayout
    {
        public float Scale, X, Y, Size, FeetY;
        /// <summary>The tile size in pixels (32 * Scale, rounded): the cell a thing's sprite is drawn at.</summary>
        public float Tile;
    }

    public static class LookCards
    {
        public static readonly float[] Scales = { 3f, 2f, 1.5f, 1f };
        public const float Fill = 0.96f;
        public const float Rider = 22f;

        /// <summary>The figure of the stock 2 x 2 player look: feet and reach in sprite pixels from its tile's top left (P.FALLBACK).</summary>
        public static readonly CardFigure Fallback = new CardFigure { Fx = 12, Fy = 19, Top = -22, Left = -13, Right = 24 };

        /// <summary>The figure of a look of w x h tiles: the stock figure for up to 2 x 2, taller or wider things reach one more tile per extra size; a rider reaches Rider pixels above its mount.</summary>
        public static CardFigure Figure(int w, int h, bool mounted)
        {
            var f = Fallback;
            if (w > 2) f.Left -= (w - 2) * 32;
            if (h > 2) f.Top -= (h - 2) * 32;
            if (mounted) f.Top -= Rider;
            return f;
        }

        /// <summary>A card of w x h pixels (the picture part): the scale, the rect of the creature square (x, y, size = 2 tiles) that puts the feet at the card's centre.</summary>
        public static CardLayout Layout(CardFigure fig, float w, float h)
        {
            float tall = Math.Max(1f, fig.Fy - fig.Top), wide = Math.Max(1f, fig.Right - fig.Left);
            float s = Scales[Scales.Length - 1];
            foreach (float sc in Scales)
                if (tall * sc <= h * Fill && wide * sc <= w * Fill) { s = sc; break; }
            float t = (float)Math.Floor(32 * s + 0.5);
            float feetY = (float)Math.Floor((h + tall * s) / 2 + 0.5);
            float cx = (float)Math.Floor(w / 2 + ((fig.Left + fig.Right) / 2 - fig.Fx) * -s + 0.5);
            float k = t / 32f;
            return new CardLayout
            {
                Scale = s, Tile = t, Size = 2 * t, FeetY = feetY,
                X = (float)Math.Floor(cx - (fig.Fx + 32) * k + 0.5), Y = (float)Math.Floor(feetY - (fig.Fy + 32) * k + 0.5),
            };
        }
    }

    // ============================================================================================================ game_lookpreview: the effect stage
    public sealed class FxSpec
    {
        public int Id, Dx, Dy, Ms;
        public bool Missile;
        public string Name = "";
    }

    /// <summary>One step of a skin's effects: the stock effect (A) and the skin's (B), either may be missing.</summary>
    public sealed class FxStep { public FxSpec A, B; }

    public struct StageTile { public double X, Y; }

    /// <summary>The scene of an effects option: a spell skin plays on a caster (the player, tile 0,0) and a troll two tiles east; a kill effect on the troll alone.</summary>
    public sealed class StageScene
    {
        public bool Kill, HasCaster;
        public StageTile Caster, Target;
    }

    public sealed class FxItem
    {
        public FxSpec Spec;
        public double Start, Dur;
        public char Side;
        public int Step;
        public string At = "target";
    }

    public sealed class FxTimeline
    {
        public List<FxItem> Items = new List<FxItem>();
        public double Total, Lead;
    }

    public struct FxActive { public FxItem Item; public double Ms, Frac; }

    public struct StageBox { public double Left, Top, Right, Bottom; }

    public struct StageLayout
    {
        public double Scale, T, TileX, TileY, X, Y, Size, FeetY;
    }

    /// <summary>The effect stage of the look preview (lookpreview_core.lua): the steps a spell skin or kill effect plays in a loop round the preview creature, placed the way the map
    /// places an effect (its bottom right tile on the target tile plus the step's offset). The timeline, the pattern of a missile, the extent of the scene and the layout are here;
    /// the drawing is ChaosApp.Phase9E.cs.</summary>
    public static class PreviewStage
    {
        public const double FrameMs = 100, MissileMs = 420, Gap = 250, Pause = 900;
        public const double TargetAt = 2, KillLead = 600, FadeMs = 350;
        public const int Troll = 15;
        public static readonly double[] FxScales = { 2, 1.5, 1 };
        public static readonly string[] TargetWords = { "explosion", "lightning", "strike", "impact", "hit", "punch", "slash", "bite", "spear", "bolt", "chain", "meteor", "pyre", "fall", "pierce", "arrow", "shot", "inferno" };
        public static readonly StageBox FallbackBox = new StageBox { Left = -8, Top = -8, Right = 24, Bottom = 24 };
        // the missile's start tile when the stage has no caster
        public const double MissileFromX = -2, MissileFromY = -1;
        // the directions the stage turns a creature to
        public const int East = 1, West = 3, South = 2;

        static FxSpec Spec(object o)
        {
            if (!(o is Dictionary<string, object>)) return null;
            int id = Json.Int(o, "id");
            if (id <= 0) return null;
            object m = Json.Get(o, "m");
            return new FxSpec
            {
                Id = id, Dx = Json.Int(o, "dx"), Dy = Json.Int(o, "dy"), Ms = Json.Int(o, "ms"),
                Missile = Json.Truthy(m), Name = Json.Text(o, "n"),
            };
        }

        /// <summary>The steps of a `play` list (cosmetics_core.lua C.playRows): each {a = stock, b = skin}; steps with neither effect are dropped.</summary>
        public static List<FxStep> Steps(object play)
        {
            var o = new List<FxStep>();
            if (!(play is List<object> l)) return o;
            foreach (var s in l)
            {
                var st = new FxStep { A = Spec(Json.Get(s, "a")), B = Spec(Json.Get(s, "b")) };
                if (st.A != null || st.B != null) o.Add(st);
            }
            return o;
        }

        /// <summary>The option of a Cosmetics row that changes effects: a spell skin or kill effect with its steps (P.fromPlayRow); a kill or rare-loot effect plays on a troll that dies.</summary>
        public static PreviewOption FromPlayRow(string kind, object play)
        {
            if (!(play is List<object> l) || l.Count == 0 || Steps(play).Count == 0) return null;
            return new PreviewOption { Kind = "effects", Play = play, KillFx = kind == "killfx" || kind == "rarefx" };
        }

        /// <summary>The effects option inside an option: itself, or a bundle's first part with effects (P.effectsOf); null when none.</summary>
        public static PreviewOption EffectsOf(PreviewOption opt)
        {
            if (opt == null) return null;
            if (opt.Kind == "effects" && opt.Play != null) return opt;
            if (opt.Kind == "bundle" && opt.Parts != null)
                foreach (var p in opt.Parts) { var e = EffectsOf(p); if (e != null) return e; }
            return null;
        }

        public static bool HasStock(List<FxStep> steps) { foreach (var s in steps) if (s.A != null) return true; return false; }

        public static bool HasMissile(List<FxStep> steps)
        {
            foreach (var s in steps) if ((s.A != null && s.A.Missile) || (s.B != null && s.B.Missile)) return true;
            return false;
        }

        public static StageScene SceneOf(PreviewOption opt)
        {
            if (opt != null && opt.KillFx) return new StageScene { Kill = true, Target = new StageTile() };
            return new StageScene { HasCaster = true, Caster = new StageTile(), Target = new StageTile { X = TargetAt } };
        }

        /// <summary>Where a step's effect plays: "missile", "target" or "caster" (P.landsOn): a kill effect is on the target; with a missile in the spell the other effects are its impact; an
        /// effect whose name says it hits something is on the target, the others (war cries, novas, auras) round the caster.</summary>
        public static string LandsOn(FxSpec spec, bool hasMissile, StageScene scene)
        {
            if (spec == null) return "target";
            if (spec.Missile) return "missile";
            if (scene != null && (scene.Kill || !scene.HasCaster)) return "target";
            if (hasMissile) return "target";
            string n = (spec.Name ?? "").ToLowerInvariant();
            foreach (string w in TargetWords) if (n.IndexOf(w, StringComparison.Ordinal) >= 0) return "target";
            return "caster";
        }

        public static double Duration(FxSpec spec, int phases)
        {
            if (spec == null) return 0;
            if (spec.Missile) return MissileMs;
            if (spec.Ms > 0) return spec.Ms;
            return Math.Max(1, phases) * FrameMs;
        }

        /// <summary>The timeline of the steps: side 'b' (the skin), 'a' (the stock effects) or '*' (every stock effect, then every skin effect: the compare switch). phasesOf(spec) gives the frames
        /// of an effect's thing. A kill scene starts its effects after KillLead (the troll standing). Empty steps: no items, total 0.</summary>
        public static FxTimeline Timeline(List<FxStep> steps, char side, Func<FxSpec, int> phasesOf, StageScene scene)
        {
            var tl = new FxTimeline();
            double lead = scene != null && scene.Kill ? KillLead : 0, t = lead;
            bool missile = HasMissile(steps);
            var sides = side == '*' ? new[] { 'a', 'b' } : new[] { side };
            foreach (char sd in sides)
            {
                for (int i = 0; i < steps.Count; i++)
                {
                    var spec = sd == 'a' ? steps[i].A : steps[i].B;
                    if (spec == null || spec.Id <= 0) continue;
                    double dur = Duration(spec, phasesOf != null ? phasesOf(spec) : 1);
                    tl.Items.Add(new FxItem { Spec = spec, Start = t, Dur = dur, Side = sd, Step = i, At = LandsOn(spec, missile, scene) });
                    t += dur + Gap;
                }
            }
            if (tl.Items.Count == 0) return tl;
            tl.Total = t - Gap + Pause;
            tl.Lead = lead;
            return tl;
        }

        /// <summary>What plays at ms into the loop.</summary>
        public static List<FxActive> ActiveAt(FxTimeline tl, double ms)
        {
            var o = new List<FxActive>();
            if (tl == null || tl.Total <= 0) return o;
            double t = ms % tl.Total;
            if (t < 0) t += tl.Total;
            foreach (var it in tl.Items)
                if (t >= it.Start && t < it.Start + it.Dur)
                {
                    double l = t - it.Start;
                    o.Add(new FxActive { Item = it, Ms = l, Frac = it.Dur > 0 ? l / it.Dur : 1 });
                }
            return o;
        }

        /// <summary>The frame of an effect ms into it: one frame per dur / phases, the last held.</summary>
        public static int PhaseAt(double ms, double dur, int phases)
        {
            phases = Math.Max(1, phases);
            if (dur <= 0) return 0;
            return (int)Math.Max(0, Math.Min(phases - 1, Math.Floor(ms * phases / dur)));
        }

        /// <summary>The troll's opacity ms into the loop: 1 standing (always outside a kill scene), fading after the lead, then 0.</summary>
        public static double TargetAlpha(FxTimeline tl, double ms)
        {
            if (tl == null || tl.Total <= 0 || tl.Lead <= 0) return 1;
            double d = ms % tl.Total - tl.Lead;
            if (d < 0) return 1;
            if (d < FadeMs) return 1 - d / FadeMs;
            return 0;
        }

        /// <summary>The direction pattern (x, y in 0..2) of a missile flying (dx, dy) tiles: the 8 sectors of Position::getDirectionFromPositions.</summary>
        public static void MissilePattern(double dx, double dy, out int px, out int py)
        {
            px = py = 1;
            if (dx == 0 && dy == 0) return;
            double deg = Math.Atan2(-dy, dx) * 180 / Math.PI;
            if (deg < 0) deg += 360;
            int sector = (int)Math.Floor((deg + 22.5) / 45) % 8;   // 0 E, 1 NE, 2 N, 3 NW, 4 W, 5 SW, 6 S, 7 SE
            int[][] pat = { new[] { 2, 1 }, new[] { 2, 0 }, new[] { 1, 0 }, new[] { 0, 0 }, new[] { 0, 1 }, new[] { 0, 2 }, new[] { 1, 2 }, new[] { 2, 2 } };
            px = pat[sector][0]; py = pat[sector][1];
        }

        /// <summary>Where a playing item's thing goes, in tiles from the stage's tile (0, 0): ox, oy (fractions for a missile in flight) and the pattern x, y.</summary>
        public static void ItemPlace(FxActive a, StageScene scene, out double ox, out double oy, out int px, out int py)
        {
            var spec = a.Item.Spec;
            var t = scene != null ? scene.Target : new StageTile();
            px = py = 0;
            if (spec.Missile)
            {
                double fx, fy;
                if (scene != null && scene.HasCaster && (scene.Caster.X != t.X || scene.Caster.Y != t.Y)) { fx = scene.Caster.X; fy = scene.Caster.Y; }
                else { fx = t.X + MissileFromX; fy = t.Y + MissileFromY; }
                MissilePattern(t.X - fx, t.Y - fy, out px, out py);
                double f = Math.Min(1, Math.Max(0, a.Frac));
                ox = spec.Dx + fx + (t.X - fx) * f;
                oy = spec.Dy + fy + (t.Y - fy) * f;
                return;
            }
            var at = a.Item.At == "caster" && scene != null && scene.HasCaster ? scene.Caster : t;
            ox = spec.Dx + at.X;
            oy = spec.Dy + at.Y;
        }

        /// <summary>The part of the stage the scene covers, in tiles from the stage's tile (x1, y1 exclusive): each creature by its box, every step's thing from the tile it plays on
        /// (displacement applied; a missile at both ends of its flight). sizeOf gives the thing's w, h, dispX, dispY.</summary>
        public static void Extent(List<FxStep> steps, Func<FxSpec, double[]> sizeOf, StageScene scene, StageBox casterBox, StageBox targetBox,
            out double x0, out double y0, out double x1, out double y1)
        {
            double ax0 = double.NaN, ay0 = 0, ax1 = 0, ay1 = 0;
            void Add(double l, double t, double r, double b)
            {
                if (double.IsNaN(ax0)) { ax0 = l; ay0 = t; ax1 = r; ay1 = b; return; }
                ax0 = Math.Min(ax0, l); ay0 = Math.Min(ay0, t); ax1 = Math.Max(ax1, r); ay1 = Math.Max(ay1, b);
            }
            scene = scene ?? new StageScene();
            if (scene.HasCaster) Add(scene.Caster.X + casterBox.Left / 32, scene.Caster.Y + casterBox.Top / 32, scene.Caster.X + casterBox.Right / 32, scene.Caster.Y + casterBox.Bottom / 32);
            Add(scene.Target.X + targetBox.Left / 32, scene.Target.Y + targetBox.Top / 32, scene.Target.X + targetBox.Right / 32, scene.Target.Y + targetBox.Bottom / 32);
            bool missile = HasMissile(steps);
            foreach (var step in steps)
                foreach (var spec in new[] { step.A, step.B })
                {
                    if (spec == null) continue;
                    double w = 1, h = 1, ddx = 0, ddy = 0;
                    if (sizeOf != null) { var s = sizeOf(spec); w = s[0]; h = s[1]; ddx = s[2]; ddy = s[3]; }
                    w = Math.Max(1, w); h = Math.Max(1, h); ddx /= 32; ddy /= 32;
                    var item = new FxActive { Item = new FxItem { Spec = spec, At = LandsOn(spec, missile, scene) } };
                    foreach (double f in spec.Missile ? new[] { 0.0, 1.0 } : new[] { 0.0 })
                    {
                        item.Frac = f;
                        ItemPlace(item, scene, out double ox, out double oy, out _, out _);
                        Add(ox - (w - 1) - ddx, oy - (h - 1) - ddy, ox + 1 - ddx, oy + 1 - ddy);
                    }
                }
            x0 = ax0; y0 = ay0; x1 = ax1; y1 = ay1;
        }

        /// <summary>The stage layout with effects: the largest of FxScales at which the extent fits the stage (w x h px), the extent centred; every creature keeps its feet on its tile.</summary>
        public static StageLayout Layout(double w, double h, double x0, double y0, double x1, double y1)
        {
            double cols = Math.Max(0.5, x1 - x0), rows = Math.Max(0.5, y1 - y0);
            double s = FxScales[FxScales.Length - 1];
            foreach (double sc in FxScales) if (cols * 32 * sc <= w && rows * 32 * sc <= h) { s = sc; break; }
            double t = Math.Floor(32 * s + 0.5);
            double tileX = Math.Floor((w - cols * t) / 2 - x0 * t + 0.5), tileY = Math.Floor((h - rows * t) / 2 - y0 * t + 0.5);
            return new StageLayout { Scale = s, T = t, TileX = tileX, TileY = tileY, X = tileX - t, Y = tileY - t, Size = 2 * t, FeetY = tileY + t };
        }

        /// <summary>The creature square (x, y, size) of a creature standing on tile pos.</summary>
        public static void CreatureRect(StageLayout l, StageTile pos, out double x, out double y, out double size)
        {
            x = l.TileX + (pos.X - 1) * l.T; y = l.TileY + (pos.Y - 1) * l.T; size = 2 * l.T;
        }

        /// <summary>The pixel place of tile (w, h) of a thing drawn at (ox, oy) tiles from the creature tile, its displacement applied.</summary>
        public static void TilePixel(StageLayout l, double ox, double oy, int w, int h, double dispX, double dispY, out double x, out double y)
        {
            double s = l.T / 32;
            x = Math.Floor(l.TileX + (ox - w) * l.T - dispX * s + 0.5);
            y = Math.Floor(l.TileY + (oy - h) * l.T - dispY * s + 0.5);
        }
    }

    // ============================================================================================================ client_chaos_topbar: the bar before the login
    /// <summary>The entries of the top bar that make sense with no character (chaos_topbar.lua entries marked `offline`): the System drop-down's Options, Sound, Join Discord, Credits and Exit.
    /// The Developer entries stay out (a tool for the owner, not for players), Alt+letter shortcuts do not exist in Unity, and New Window Look is the main client's RmlUi mirror.</summary>
    public static class LoginMenu
    {
        public const string Category = "system";

        public sealed class Entry { public string Id = "", Text = "", Target = ""; }

        /// <summary>The entries, in the order of the shown (English) text: the main client sorts a drop-down by the shown, translated text.</summary>
        public static readonly Entry[] Entries =
        {
            new Entry { Id = "options", Text = "Options", Target = "act:options" },
            new Entry { Id = "sound", Text = "Sound", Target = "act:sound" },
            new Entry { Id = "discord", Text = "Join Discord", Target = "act:discord" },
            new Entry { Id = "credits", Text = "Credits", Target = "act:credits" },
            new Entry { Id = "exit", Text = "Exit", Target = "act:exit" },
        };

        /// <summary>Entries sorted by the shown text of the language (accents folded).</summary>
        public static List<Entry> Shown(Func<string, string> tr)
        {
            var o = new List<Entry>(Entries);
            o.Sort((a, b) =>
            {
                int c = string.CompareOrdinal(TopMenu.SortKey(tr(a.Text)), TopMenu.SortKey(tr(b.Text)));
                return c != 0 ? c : Array.IndexOf(Entries, a).CompareTo(Array.IndexOf(Entries, b));
            });
            return o;
        }

        /// <summary>Entries of the in-game System menu that are also on the login bar: the ids of Entries whose text is a menu entry of that category.</summary>
        public static bool IsOffline(string text)
        {
            foreach (var e in Entries) if (e.Text == text) return true;
            return false;
        }

        /// <summary>The bar shows on the login screen and the character list, not in the game (the in-game bar has every entry).</summary>
        public static bool Visible(bool inGame) => !inGame;

        /// <summary>The options window of the login bar: its pages are the general page (language only: the rest needs a character) and the Sound, Visuals and Layout pages of the options.</summary>
        public static readonly string[] OptionPages = { "General", "Sound", "Visuals", "Layout" };
    }

    // ============================================================================================================ game_chaoslayout: window sizes
    /// <summary>A resize grip in the corner of a window; its size is saved per window with the place in WindowLayout (an extra pair after the open flag). Only a size the player set is saved:
    /// a window the player never resized keeps the size the program gives it.</summary>
    public static class WindowSize
    {
        public const float MinW = 160f, MinH = 100f, Grip = 14f;

        /// <summary>The size kept inside the smallest a window may be and the screen (a window larger than the screen is still allowed to be the screen's size).</summary>
        public static void Clamp(ref float w, ref float h, float screenW, float screenH)
        {
            w = Math.Max(MinW, Math.Min(Math.Max(MinW, screenW), float.IsNaN(w) ? MinW : w));
            h = Math.Max(MinH, Math.Min(Math.Max(MinH, screenH), float.IsNaN(h) ? MinH : h));
        }

        /// <summary>The grip's rect (x, y, w, h) in a window of w x h.</summary>
        public static void GripRect(float w, float h, out float x, out float y, out float size)
        {
            size = Grip; x = w - Grip - 2; y = h - Grip - 2;
        }

        /// <summary>A size to restore: both sides positive and sane.</summary>
        public static bool Valid(float w, float h) => w >= MinW && h >= MinH && w <= 20000 && h <= 20000;
    }
}
