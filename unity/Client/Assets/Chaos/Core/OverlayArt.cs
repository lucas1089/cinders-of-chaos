// Pictures of the main client's modules that the Unity HUD and windows draw (O433 phase 6, track U): which file and which part of it.
// Pure rules, no engine calls: spell icon cells (Core/SpellIconData.cs is generated from game_chaosspells/spelldata.lua), buff icons
// (game_buffbar buffmath.lua ownName), toast icons (game_chaosnotify notifications.lua), the liquid orb globes (game_shaderfx
// shaderfxlogic.lua plain globe) and the monster bar frame (game_monsterbar monsterbarstyle.lua). Files are named relative to the folder
// "modules" of OverlayFiles; the pictures that live in client/overlay/data are reached as "../data/...". Nothing is copied into Unity
// but the files themselves (StreamingAssets, unity-prototype.yml); a missing file is no error: the caller draws its older stand-in.
using System;
using System.Collections.Generic;
using System.Text;

namespace Chaos.Core
{
    public static class ArtPaths
    {
        /// <summary>A file of client/overlay/data, as a path under the "modules" folder of OverlayFiles.</summary>
        public static string Data(string rel) => "../data/" + rel;
    }

    /// <summary>The spell icon sheets: 20 columns of cells, cell n (1-based) at column (n - 1) % 20, row (n - 1) / 20 (tools/ci/check_spell_icons.py).</summary>
    public static partial class SpellIcons
    {
        public const int Columns = 20;
        public const string Dir = "images/game/spells/";
        /// <summary>The sheet the spellbook and the hotbar draw (32 x 32 cells); the other two are for smaller places.</summary>
        public const string Sheet32 = "spell-icons-32x32.png", Sheet22 = "spell-icons-22x24.png", Sheet20 = "spell-icons-20x20.png";
        public static readonly string[] Sheets = { Sheet32, Sheet22, Sheet20 };

        static Dictionary<string, int> byWords;
        static Dictionary<int, int> byId;

        static void Build()
        {
            if (byWords != null) return;
            var w = new Dictionary<string, int>();
            var i = new Dictionary<int, int>();
            for (int k = 0; k + 2 < Data.Length; k += 3)
            {
                int id = (int)Data[k], cell = (int)Data[k + 2];
                string words = (string)Data[k + 1];
                w[words] = cell;
                i[id] = cell;
            }
            byId = i;
            byWords = w;
        }

        public static int Count { get { Build(); return byWords.Count; } }

        /// <summary>The path of a sheet under the modules folder.</summary>
        public static string Path(string sheet) => ArtPaths.Data(Dir + sheet);

        /// <summary>The cell of a Chaos spell by its words (case-insensitive), 0 when it has none (a stock spell).</summary>
        public static int CellByWords(string words)
        {
            Build();
            return !string.IsNullOrEmpty(words) && byWords.TryGetValue(words.Trim().ToLowerInvariant(), out int c) ? c : 0;
        }

        public static int CellById(int spellId)
        {
            Build();
            return byId.TryGetValue(spellId, out int c) ? c : 0;
        }

        /// <summary>The cell of a spell: its words first, then its server id (0 for a rune entry or a spell without a cell).</summary>
        public static int Cell(string words, int spellId)
        {
            int c = CellByWords(words);
            return c != 0 ? c : (spellId > 0 ? CellById(spellId) : 0);
        }

        /// <summary>The part of a sheet (sheetW x sheetH pixels, cells cw x ch) that holds a cell, as texture coordinates with the origin at the bottom left (u, v, width,
        /// height); false when the cell is 0 or lies outside the sheet.</summary>
        public static bool CellUv(int cell, int cw, int ch, int sheetW, int sheetH, out float u, out float v, out float w, out float h)
        {
            u = v = w = h = 0f;
            if (cell < 1 || cw <= 0 || ch <= 0 || sheetW <= 0 || sheetH <= 0) return false;
            int col = (cell - 1) % Columns, row = (cell - 1) / Columns;
            int x = col * cw, y = row * ch;
            if (x + cw > sheetW || y + ch > sheetH) return false;
            u = (float)x / sheetW; w = (float)cw / sheetW;
            h = (float)ch / sheetH; v = 1f - (float)(y + ch) / sheetH;
            return true;
        }
    }

    /// <summary>Buff bar icons (game_buffbar buffmath.lua): our own 26 px pixel art, one file per name in images/game/buffs.</summary>
    public static class BuffIcons
    {
        public const int Size = 26;
        public const string Dir = "images/game/buffs/", Fallback = "spellbuff";

        /// <summary>"buff:regen" -> kind "buff", arg "regen"; "spell:utani hur"; "cond:05". False for anything else.</summary>
        public static bool ParseIcon(string spec, out string kind, out string arg)
        {
            kind = arg = "";
            if (string.IsNullOrEmpty(spec)) return false;
            int colon = spec.IndexOf(':');
            if (colon <= 0 || colon == spec.Length - 1) return false;
            string k = spec.Substring(0, colon);
            if (k != "buff" && k != "spell" && k != "cond") return false;
            kind = k; arg = spec.Substring(colon + 1);
            return true;
        }

        /// <summary>A file name made of letters, digits and underscores only (no path tricks).</summary>
        public static bool ValidName(string name)
        {
            if (string.IsNullOrEmpty(name)) return false;
            foreach (char c in name) if (!(c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) return false;
            return true;
        }

        /// <summary>The icon a buff draws: "buff:name" is that name; any other spec draws the key's own icon, and "spellbuff" when neither is a valid name.</summary>
        public static string OwnName(string spec, string key)
        {
            if (ParseIcon(spec, out string kind, out string arg) && kind == "buff" && ValidName(arg)) return arg;
            if (ValidName(key)) return key;
            return Fallback;
        }

        public static string Path(string name) => ArtPaths.Data(Dir + name + ".png");
    }

    /// <summary>Toast icons (game_chaosnotify notifications.lua): a 48 px picture per toast type in images/toast, one from the top bar for an achievement.</summary>
    public static class ToastIcons
    {
        public const int Size = 48, Box = 60;
        public const string Fallback = "images/toast/announce.png";

        /// <summary>Module-relative file of a toast type's icon (game_chaosnotify/...); null for the achievement, whose picture is a data file.</summary>
        public static readonly Dictionary<string, string> Files = new Dictionary<string, string>
        {
            { "GM_BROADCAST", "images/toast/announce.png" }, { "TASK_COMPLETE", "images/toast/task.png" }, { "BATTLE_PASS", "images/toast/season_pass.png" },
            { "PARTY_INVITE", "images/toast/party_invite.png" }, { "BOUNTY", "images/toast/bounty.png" }, { "NEW_PLAYER", "images/toast/new_player.png" },
            { "BESTIARY", "images/toast/bestiary.png" }, { "ACHIEVEMENT", null }, { "ASCENSION", "images/toast/ascension.png" },
            { "MARKET", "images/toast/market.png" }, { "SALE", "images/toast/market.png" }, { "INVASION", "images/toast/invasion.png" },
            { "CURSED_CHEST", "images/toast/invasion.png" }, { "WEEKLY_CHEST", "images/toast/task.png" }, { "MILESTONE", "images/toast/ascension.png" },
            { "SEASON_PASS", "images/toast/season_pass.png" }, { "PACT", "images/toast/pact.png" }, { "JOURNEY", "images/toast/journey.png" },
            { "BOSS_POINT", "images/toast/boss_point.png" }, { "SCREENSHOT", "images/toast/announce.png" }, { "CATACOMB_FREE", "images/toast/catacomb_invite.png" },
        };

        /// <summary>The path under the modules folder of the icon of a toast type (an unknown type gets the announcement icon).</summary>
        public static string Path(string type)
        {
            if (type == "ACHIEVEMENT") return ArtPaths.Data("images/chaos/topbutton_ranking.png");
            return "game_chaosnotify/" + (type != null && Files.TryGetValue(type, out string f) && f != null ? f : Fallback);
        }
    }

    /// <summary>The liquid orbs as plain globes (game_shaderfx shaderfxlogic.lua): a round white mask cut to the fill from the bottom, tinted, under a painted ring.</summary>
    public static class OrbArt
    {
        public static readonly int[] Sizes = { 76, 150, 190 };
        public const string HealthColor = "#d8262c", ManaColor = "#2f6ef0";
        public const string Dir = "game_shaderfx/images/";
        /// <summary>The hotbar's globe at 100 percent (hotbar_logic.lua ORB_BASE).</summary>
        public const int Base = 110;

        /// <summary>The opening of a ring of this size: the liquid keeps the ring's proportion, 50 of 76.</summary>
        public static int Liquid(int size) => (int)Math.Floor(size * 50.0 / 76.0 + 0.5);

        /// <summary>The art size (one of Sizes) nearest to a drawn diameter.</summary>
        public static int NearestSize(int diameter)
        {
            int best = Sizes[0];
            int gap = int.MaxValue;
            foreach (int s in Sizes) { int g = Math.Abs(s - diameter); if (g < gap) { best = s; gap = g; } }
            return best;
        }

        public static string RingFile(int artSize) => Dir + "orb_ring_" + artSize + ".png";
        public static string MaskFile(int artSize) => Dir + "orb_mask_" + Liquid(artSize) + ".png";

        /// <summary>0 to 1 fill (0 without a maximum).</summary>
        public static double Fill(double value, double max)
        {
            if (max <= 0 || value <= 0) return 0;
            return value >= max ? 1 : value / max;
        }

        /// <summary>The plain globe: the mask drawn as far up as the fill, cut from the bottom. clipHeight is in texels of a mask `texels` wide (the art is 2x); drawnHeight is
        /// in pixels of a liquid `liquid` high (shaderfxlogic.lua plainClip).</summary>
        public static void PlainClip(double fill, int texels, int liquid, out int clipHeight, out int drawnHeight)
        {
            double f = Math.Max(0, Math.Min(1, fill));
            clipHeight = (int)Math.Floor(texels * f + 0.5);
            drawnHeight = (int)Math.Floor(liquid * f + 0.5);
        }

        /// <summary>The number in the globe: 1234 -> 1.2k, 1500000 -> 1.5m (below 1000 as it is).</summary>
        public static string Short(int v)
        {
            if (v < 1000) return Math.Max(0, v).ToString();
            if (v < 1000000) return (v / 100 / 10.0).ToString("0.#", System.Globalization.CultureInfo.InvariantCulture) + "k";
            return (v / 100000 / 10.0).ToString("0.#", System.Globalization.CultureInfo.InvariantCulture) + "m";
        }
    }

    /// <summary>The monster bar's art (game_monsterbar): a 420 x 58 frame with a 344 x 16 socket, a name plate and modifier chips, in images/chaos/monsterbar.</summary>
    public static class MonsterBarArt
    {
        public const int PanelW = 420, PanelH = 90, FrameY = 8, FrameH = 58, SocketX = 38, SocketY = 38, SocketW = 344, SocketH = 16;
        public const int PlateTop = 2, PlateH = 22, PlateBorderX = 10, PlateBorderY = 6, PlatePad = 28, NameMax = 300, NameMin = 120, LevelMin = 44, LevelMax = 80, LevelGap = 2;
        public const int ModsTop = 63, ChipSize = 26, ChipSpacing = 3;
        public const string Dir = "images/chaos/monsterbar/";

        static string Style(string key) => key != null && MonsterBar.Styles.ContainsKey(key) ? key : "normal";
        public static string Frame(string key) => ArtPaths.Data(Dir + "frame_" + Style(key) + ".png");
        public static string Fill(string key) => ArtPaths.Data(Dir + "fill_" + Style(key) + ".png");
        public static string Plaque(string key) => ArtPaths.Data(Dir + "plaque_" + Style(key) + ".png");
        public static string Trail => ArtPaths.Data(Dir + "trail.png");

        /// <summary>The key of a modifier name (letters only, lower case), "unknown" when the name is not a known modifier.</summary>
        public static string ModKey(string name)
        {
            var sb = new StringBuilder();
            foreach (char c in name ?? "") if (char.IsLetter(c)) sb.Append(char.ToLowerInvariant(c));
            return MonsterBar.Mods.ContainsKey(sb.ToString()) ? sb.ToString() : "unknown";
        }

        public static string Chip(string name) => ArtPaths.Data(Dir + "mods/" + ModKey(name) + ".png");

        /// <summary>A plate as wide as its text plus the nine-slice borders, held between min and max.</summary>
        public static int PlateWidth(float textWidth, int min, int max) => Math.Max(min, Math.Min(max, (int)Math.Ceiling(textWidth) + PlatePad));

        /// <summary>Width of the row of chips (the row is centred under the bar).</summary>
        public static int ChipsWidth(int n) => n <= 0 ? 0 : n * ChipSize + (n - 1) * ChipSpacing;
    }
}
