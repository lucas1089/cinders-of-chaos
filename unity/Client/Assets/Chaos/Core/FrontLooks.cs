// Front-art creatures, the choice of a look (pure C#, tested in Core.Tests/FrontLooksTests.cs): which picture set a live creature is drawn
// with in the front-art look, upright and front-facing (Core/FrontArt.cs, Unity/FrontLiveCreatures.cs).
//   Pack:   a monster by name goes to one of the 14 purchased pack figures (Resources/FrontArt/pk_<folder>/, only in CI after the art
//           is opened) or, for plain skeletons and ghouls, to the committed 8 direction pictures "skeleton" and "ghoul".
//   Hero:   a player by class (docs/CLASSES.md, the 21 vocations as in Hd2dChars) goes to the knight or the mage (or the skeleton for
//           the Lich and the Bone Lord), tinted by the class.
//   Outfit: everything else (townspeople, humans, beasts without a figure, ranged and stealth classes) is its own outfit sprite of the
//           classic art, composed here (FrontOutfit) and drawn upright with the same lighting.
// Missing art never stops a creature: the Unity side tries Folder, then Alt, then the outfit.
// Also here: the outfit composer and the name and health label (FrontLabel), both plain pixel work.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public enum FlKind { Hero, Pack, Outfit }

    /// <summary>How one creature is drawn.</summary>
    public sealed class FrontLook
    {
        public FlKind Kind;
        /// <summary>Resources/FrontArt/NAME: "knight", "mage", "skeleton", "ghoul" (Hero) or "pk_vampire" (Pack); "" for an outfit.</summary>
        public string Folder = "";
        /// <summary>The committed set to use when a Pack folder is not in the build (the pack art comes only with the CHAOS_ART_KEY secret); "" none.</summary>
        public string Alt = "";
        /// <summary>The picture's side in units (a hero 1.5, a pack figure 1.6, the 32-texel armoured skeleton 1.0); 0 for an outfit (its size in cells).</summary>
        public float Units;
        /// <summary>Colour multiplier of the picture (a class's tint).</summary>
        public float R = 1f, G = 1f, B = 1f;
        public string Label = "";
        public bool Monster;

        public override string ToString() => Kind + ":" + (Folder.Length > 0 ? Folder : "outfit") + (Alt.Length > 0 ? "/" + Alt : "") + " " + Label;
    }

    public static class FrontLooks
    {
        /// <summary>The 14 pack folders of Core/FrontArt.cs Build (Resources/FrontArt/pk_NAME).</summary>
        public static readonly string[] PackFolders =
        {
            "fire_demon", "winged_demon", "vampire", "werewolf", "headless", "frost_demon", "rat_king", "goblin_shaman", "lizard_mystic",
            "armored_skeleton", "ghost_king", "ghost_knight", "cultist_red", "cultist_dark",
        };

        /// <summary>The committed 8 direction picture sets, Resources/FrontArt/NAME/DIRECTION.png.</summary>
        public static readonly string[] HeroFolders = { "knight", "mage", "skeleton", "ghoul" };

        public const float HeroUnits = 1.5f, PackUnits = 1.6f, SmallPackUnits = 1.0f;
        public const string PackPrefix = "pk_";

        // ---- words ---------------------------------------------------------------------------------------------------------------
        // Stems as in Hd2dChars: "*x" anywhere in the lower-case name, "=x" a whole word, "x" starts a word.

        static bool Has(string lower, string[] words, string[] stems)
        {
            foreach (var s in stems)
            {
                if (s[0] == '*') { if (lower.IndexOf(s.Substring(1), StringComparison.Ordinal) >= 0) return true; }
                else if (s[0] == '=') { string w = s.Substring(1); for (int i = 0; i < words.Length; i++) if (words[i] == w) return true; }
                else for (int i = 0; i < words.Length; i++) if (words[i].StartsWith(s, StringComparison.Ordinal)) return true;
            }
            return false;
        }

        static readonly string[] Goblin = { "goblin", "hobgoblin", "gnawling", "chitterkin", "cragling", "rootling", "chained runt" };
        static readonly string[] Rat = { "=rat", "=rats", "ratling", "ratkin", "rodent", "vermin", "gnaw", "pitgnawer", "squirrel", "hare", "weasel" };
        static readonly string[] Winged =
        {
            "*wing", "*hawk", "moth", "=bat", "raven", "crow", "hornet", "stork", "parrot", "hawk", "beak", "seraph", "angel", "fledgling", "flock",
            "=owl", "eagle", "wisp", "pixie", "fairy",
        };
        static readonly string[] Headless = { "headless", "=rider", "hangman", "gallows", "gibbet", "headsman", "executioner" };
        static readonly string[] Vampire = { "vampire", "=count", "=countess", "=bride", "leech", "*bloodmoon", "*nightdweller" };
        static readonly string[] CultistWord = { "cultist", "acolyte", "priest", "hierarch", "chaplain", "forgepriest", "herald" };
        static readonly string[] CasterWord =
        {
            "mage", "sorcer", "necro", "warlock", "witch", "hex", "seer", "caller", "crone", "savant", "shaman", "wizard", "lich", "brinecaller",
            "hollowseer", "evoker", "*mancer", "spellsinger", "spellweaver", "magister", "librarian", "shaper", "weaver", "nexweaver", "druid", "illusion", "dryad", "keeper", "lantern", "strayer", "facetis",
            "talath", "mage",
        };
        static readonly string[] Ghostly =
        {
            "wraith", "ghost", "specter", "spectre", "phantom", "shade", "banshee", "geist", "haunt", "lament", "unbidden", "spirit", "reaper",
            "stalker", "lurker", "revenant", "shadow", "fading", "strayer",
        };
        static readonly string[] Crowned = { "king", "regent", "sovereign", "crown", "queen", "=lord", "*archon", "hierarch", "matriarch", "colossus", "tyrant" };
        static readonly string[] NotCrowned = { "*mushroom", "*fung", "*dragon", "*goblin", "*wyrm" };
        static readonly string[] Knightly =
        {
            "knight", "oath", "revenant", "warden", "guard", "bannerman", "zealot", "penitent", "sentry", "champion", "thrall", "warbreaker",
            "taskmaster", "brander", "vanguard", "paladin", "templar",
        };
        static readonly string[] Bony = { "risen", "skelet", "bone", "marrow", "skull", "barrow", "reaver", "lancer", "corpse", "carrion", "golem", "crypt", "grave" };
        static readonly string[] PlainSkeleton = { "skelet" };
        static readonly string[] Ghoul = { "ghoul", "zombie", "rotling", "rotmother", "carrion", "corpse", "rotten", "husk", "limb", "bonepicker" };
        static readonly string[] Wolfish =
        {
            "wolf", "hound", "lycan", "were", "jackal", "fox", "vixen", "hyaena", "hyena", "=cat", "bear", "boar", "badger", "stag", "elk", "=ape",
            "mauler", "lynx", "panther", "hog", "gorebristle", "*tusk", "*fang", "*howl", "*pelt", "skitter", "mange", "orger", "winterstride", "slagback",
        };
        static readonly string[] Lizard =
        {
            "lizard", "scale", "serpent", "snake", "viper", "drake", "wyrm", "snapper", "toad", "frog", "scourgejaw", "basilisk", "naga", "gecko",
            "salamander", "*scale", "*drake", "*worm", "crab", "shellback", "beetle", "spider", "crawler", "hydra", "snapjaw", "swarm", "leechwing",
        };
        static readonly string[] Ice = { "ice", "frost", "rime", "winter", "glacial", "snow", "yeti", "tundra", "skaldra", "shiver", "penguin" };
        static readonly string[] Fire =
        {
            "fire", "ember", "cinder", "ash", "pyre", "blaze", "flame", "inferno", "magma", "slag", "forge", "brimstone", "infernal", "sear",
            "brimhorn", "scorch", "demon", "fiend", "=imp", "asura", "gloomfire", "pyrarch", "*hellhunter",
        };
        static readonly string[] Brute =
        {
            "troll", "ogre", "orc", "giant", "behemoth", "juggernaut", "tyrant", "ravager", "tarrasque", "hulk", "brute", "dragon", "whelp",
            "cleaver", "colossus", "mauler", "hornsworn", "ironhorn", "siege", "cursed", "blazebringer", "vyrm", "ormathulak", "vorathrax",
        };
        static readonly string[] Red = { "fire", "ember", "cinder", "ash", "pyre", "blaze", "flame", "magma", "slag", "forge", "blood", "gore", "crimson", "infernal" };

        static FrontLook Pack(string folder, string alt, string label, bool small = false) => new FrontLook
        {
            Kind = FlKind.Pack, Folder = PackPrefix + folder, Alt = alt, Units = small ? SmallPackUnits : PackUnits, Label = label, Monster = true,
        };

        static FrontLook Hero(string folder, string label, bool monster) => new FrontLook
        {
            Kind = FlKind.Hero, Folder = folder, Units = HeroUnits, Label = label, Monster = monster,
        };

        /// <summary>The look of a monster (or summon) by its name: a pack figure, a plain skeleton or ghoul set, or null (no figure fits: the
        /// creature is drawn as its outfit). The first rule that matches wins: goblins, rats, flyers, headless riders and hangmen, vampires,
        /// cultists and casters (red for fire and blood, dark for the rest), ghosts (a king for a crowned one, a knight otherwise), plain
        /// skeletons and ghouls, crowned undead, armoured undead, then beasts: wolves, lizards and snakes, ice, fire, brutes.</summary>
        public static FrontLook ForMonster(string name)
        {
            string lower = (name ?? "").Trim().ToLowerInvariant();
            if (lower.Length == 0) return null;
            var w = Hd2dChars.Words(lower);
            if (Has(lower, w, Goblin)) return Pack("goblin_shaman", "", "goblin");
            if (Has(lower, w, Rat)) return Pack("rat_king", "", "rat");
            bool ghostly = Has(lower, w, Ghostly), caster = Has(lower, w, CultistWord) || Has(lower, w, CasterWord);
            if (Has(lower, w, Winged) && !ghostly && !caster) return Pack("winged_demon", "", "flyer");
            if (Has(lower, w, Headless)) return Pack("headless", "skeleton", "headless");
            if (Has(lower, w, Vampire)) return Pack("vampire", "skeleton", "vampire");
            if (caster && !(ghostly && Has(lower, w, Crowned)))
            {
                bool red = Has(lower, w, Red);
                return Pack(red ? "cultist_red" : "cultist_dark", "", red ? "red caster" : "dark caster");
            }
            bool crowned = Has(lower, w, Crowned);
            if (ghostly) return crowned ? Pack("ghost_king", "skeleton", "ghost king") : Pack("ghost_knight", "skeleton", "ghost");
            if (Has(lower, w, PlainSkeleton)) return Pack("armored_skeleton", "skeleton", "skeleton", true);
            if (Has(lower, w, Ghoul)) return Hero("ghoul", "ghoul", true);
            if (crowned && !Has(lower, w, NotCrowned) && (Has(lower, w, Bony) || Has(lower, w, new[] { "hollow", "ashen", "nail", "grave", "marrow" })))
                return Pack("ghost_king", "skeleton", "crowned undead");
            if (Has(lower, w, Bony)) return Pack("armored_skeleton", "skeleton", "bone", true);
            if (Has(lower, w, Knightly) && !Has(lower, w, new[] { "man", "barbarian" })) return Pack("ghost_knight", "skeleton", "armoured");
            if (Has(lower, w, Wolfish)) return Pack("werewolf", "", "beast");
            if (Has(lower, w, Lizard)) return Pack("lizard_mystic", "", "reptile");
            if (Has(lower, w, Ice)) return Pack("frost_demon", "", "frost");
            if (Has(lower, w, Fire)) return Pack("fire_demon", "", "fire");
            if (Has(lower, w, Brute)) return Pack("fire_demon", "", "brute");
            return null;
        }

        // ---- classes ---------------------------------------------------------------------------------------------------------------

        /// <summary>The hero set of a class, by the 3D model Hd2dChars gives it: the Knight and the Barbarian are the knight, the Mage is the mage,
        /// the skeletons are the skeleton; the Rogue models (Ranger, Deadeye, Beastmaster, Thief, Ninja) have no front picture yet and are
        /// drawn as their outfit. A class's own tint (Hd2dChars colour, softened: no channel moves more than 0.25 from 1).</summary>
        public static FrontLook ForClass(int vocation)
        {
            var ci = Hd2dChars.ClassOf(vocation);
            if (ci == null) return null;
            string folder = HeroOfModel(ci.Spec.Model);
            var l = new FrontLook { Kind = folder.Length > 0 ? FlKind.Hero : FlKind.Outfit, Folder = folder, Units = folder.Length > 0 ? HeroUnits : 0f, Label = ci.Name };
            Soften(ci.Spec, out l.R, out l.G, out l.B);
            return l;
        }

        public static string HeroOfModel(string model)
        {
            if (model == "Knight" || model == "Barbarian") return "knight";
            if (model == "Mage") return "mage";
            if (model != null && model.StartsWith("Skeleton_", StringComparison.Ordinal)) return "skeleton";
            return "";
        }

        static void Soften(CharSpec s, out float r, out float g, out float b)
        {
            r = Math.Max(0.75f, Math.Min(1.25f, 1f + (s.R - 1f) * 0.6f));
            g = Math.Max(0.75f, Math.Min(1.25f, 1f + (s.G - 1f) * 0.6f));
            b = Math.Max(0.75f, Math.Min(1.25f, 1f + (s.B - 1f) * 0.6f));
        }

        /// <summary>The look of any creature. The local player is its class (`localVocation` from the login; the Warrior when 0); a creature
        /// carrying a vocation is that class; another player, whose class the protocol does not tell, is the knight or the mage by its
        /// outfit's look type (with the tint of the class that look picks), never a skeleton; monsters and summons go by name; NPCs are outfits.</summary>
        public static FrontLook For(Creature c, bool isLocal, int localVocation)
        {
            if (c == null) return new FrontLook { Kind = FlKind.Outfit, Label = "none" };
            if (c.Type == 1 || c.Type == 3 || c.Type == 4)
            {
                var m = ForMonster(c.Name);
                if (m != null) return m;
                return new FrontLook { Kind = FlKind.Outfit, Label = "outfit", Monster = true };
            }
            if (c.Type == 2) return new FrontLook { Kind = FlKind.Outfit, Label = "npc" };
            int voc = isLocal ? (localVocation != 0 ? localVocation : c.Vocation != 0 ? c.Vocation : Hd2dChars.DefaultVocation) : c.Vocation;
            var known = voc != 0 ? ForClass(voc) : null;
            if (known != null) return known;
            if (isLocal) return ForClass(Hd2dChars.DefaultVocation);
            var by = Hd2dChars.ClassByLook(c);
            var l = ForClass(by.Id);
            if (l.Folder == "knight" || l.Folder == "mage") return l;
            int look = c.Outfit != null ? c.Outfit.LookType : 0;
            l.Kind = FlKind.Hero; l.Units = HeroUnits; l.R = l.G = l.B = 1f;
            l.Folder = ((look != 0 ? look : (int)c.Id) & 1) == 0 ? "knight" : "mage";
            return l;
        }

        /// <summary>A key that changes when the look has to be chosen again.</summary>
        public static int KeyOf(Creature c, bool isLocal, int localVocation)
        {
            unchecked
            {
                int h = c.Type * 31 + (isLocal ? 7 : 0) + (isLocal ? localVocation : c.Vocation) * 131 + (c.Outfit != null ? c.Outfit.LookType : 0) * 17;
                foreach (char ch in c.Name ?? "") h = h * 16777619 ^ ch;
                return h;
            }
        }

        /// <summary>The creature direction nearest to a ground heading (x east, z north); south for no heading.</summary>
        public static Dir DirOf(float fx, float fz)
        {
            if (Math.Abs(fx) < 1e-5f && Math.Abs(fz) < 1e-5f) return Dir.South;
            double a = Math.Atan2(fx, fz) * 180.0 / Math.PI;   // 0 north, 90 east
            int k = ((int)Math.Round(((a % 360.0) + 360.0) % 360.0 / 45.0)) % 8;
            Dir[] map = { Dir.North, Dir.NorthEast, Dir.East, Dir.SouthEast, Dir.South, Dir.SouthWest, Dir.West, Dir.NorthWest };
            return map[k];
        }

        /// <summary>The unit heading of a creature's direction on the ground: x east, z north (a tile's y grows south).</summary>
        public static void Face(Dir d, out float fx, out float fz)
        {
            const float k = 0.70710678f;
            switch (d)
            {
                case Dir.North: fx = 0f; fz = 1f; break;
                case Dir.East: fx = 1f; fz = 0f; break;
                case Dir.South: fx = 0f; fz = -1f; break;
                case Dir.West: fx = -1f; fz = 0f; break;
                case Dir.NorthEast: fx = k; fz = k; break;
                case Dir.SouthEast: fx = k; fz = -k; break;
                case Dir.SouthWest: fx = -k; fz = -k; break;
                default: fx = -k; fz = k; break;
            }
        }
    }

    /// <summary>The classic art of an outfit (or of an item shown as a creature), composed into one picture: the base layer coloured by the mask
    /// layer (OutfitColors), the addons the outfit has, every cell of the sprite on a canvas of W x H cells of 32 texels. The picture is drawn
    /// upright and front-facing by the Unity side, its bottom middle on the creature's tile (the oblique lean of the art is not corrected).</summary>
    public static class FrontOutfit
    {
        public const int Cell = 32;

        /// <summary>The look-direction pattern index of a creature direction (the four of the dat; the diagonals take east or west unless
        /// the dat has eight).</summary>
        public static int PatternDir(Dir d, int patternX)
        {
            int dir = (int)d;
            if (patternX >= 8) return dir;
            if (dir > 3) dir = dir == 4 || dir == 5 ? 1 : 3;
            return dir % Math.Max(1, patternX);
        }

        /// <summary>The frame group and phase shown: idle phase 0; walking cycles the phases from 1 by `progress` (0..1 through the step).</summary>
        public static FrameGroup Group(ThingType t, bool walking, float progress, out int phase)
        {
            var g = walking ? t.Moving : t.Idle;
            phase = walking && g.Phases > 1 ? 1 + (int)(Math.Max(0f, Math.Min(0.999f, progress)) * (g.Phases - 1)) % (g.Phases - 1) : 0;
            return g;
        }

        /// <summary>A cache key for the composed picture: type, direction, phase and colours.</summary>
        public static ulong Key(ThingType t, Outfit o, int dir, int phase)
        {
            unchecked
            {
                ulong h = (ulong)(t.Category == ThingCategory.Outfit ? 1 : 2) * 0x9E3779B97F4A7C15UL;
                h = (h ^ (ulong)t.Id) * 0x100000001B3UL;
                h = (h ^ (ulong)(dir * 16 + phase)) * 0x100000001B3UL;
                h = (h ^ (ulong)(o.Head & 127)) * 0x100000001B3UL;
                h = (h ^ (ulong)(o.Body & 127)) * 0x100000001B3UL;
                h = (h ^ (ulong)(o.Legs & 127)) * 0x100000001B3UL;
                h = (h ^ (ulong)(o.Feet & 127)) * 0x100000001B3UL;
                h = (h ^ (ulong)(o.Addons & 255)) * 0x100000001B3UL;
                return h;
            }
        }

        /// <summary>The thing a creature is drawn as: its outfit type, or the item of an item look (LookType 0); null when the dat has none.</summary>
        public static ThingType TypeOf(DatFile dat, Outfit o)
        {
            if (dat == null || o == null) return null;
            return o.LookType != 0 ? dat.Outfit(o.LookType) : o.LookTypeEx != 0 ? dat.Item(o.LookTypeEx) : null;
        }

        /// <summary>Composes the picture: RGBA, W x H cells of 32 texels, rows top first (the sprite order). Null when nothing is drawn.
        /// `raw` gives the 32 x 32 RGBA of a sprite id (null for none).</summary>
        public static byte[] Compose(ThingType t, Outfit o, Dir dir, bool walking, float progress, Func<uint, byte[]> raw, out int w, out int h)
        {
            w = h = 0;
            if (t == null || t.Groups == null || t.Groups.Length == 0) return null;
            bool item = t.Category == ThingCategory.Item;
            int phase = 0;
            FrameGroup g;
            if (item) g = t.Idle;
            else g = Group(t, walking, progress, out phase);
            int pd = item ? 0 : PatternDir(dir, g.PatternX);
            w = Math.Max(1, g.Width); h = Math.Max(1, g.Height);
            int cw = w * Cell, ch = h * Cell;
            var canvas = new byte[cw * ch * 4];
            bool any = false;
            int addons = item ? 1 : Math.Max(1, g.PatternY);
            for (int addon = 0; addon < addons; addon++)
            {
                if (addon > 0 && (o.Addons & (1 << (addon - 1))) == 0) continue;
                for (int hh = 0; hh < g.Height; hh++)
                    for (int ww = 0; ww < g.Width; ww++)
                    {
                        uint baseId = g.Sprite(ww, hh, 0, pd, item ? 0 : addon, 0, phase);
                        if (baseId == 0) continue;
                        var rgba = raw(baseId);
                        if (rgba == null || rgba.Length < Cell * Cell * 4) continue;
                        rgba = (byte[])rgba.Clone();
                        uint maskId = !item && g.Layers > 1 ? g.Sprite(ww, hh, 1, pd, addon, 0, phase) : 0;
                        if (maskId != 0)
                        {
                            var mask = raw(maskId);
                            if (mask != null && mask.Length >= Cell * Cell * 4) OutfitColors.Apply(rgba, mask, o);
                        }
                        // cell (0, 0) is the bottom right one: the art extends west and up
                        int x0 = (w - 1 - ww) * Cell, y0 = (h - 1 - hh) * Cell;
                        for (int y = 0; y < Cell; y++)
                            for (int x = 0; x < Cell; x++)
                            {
                                int s = (y * Cell + x) * 4;
                                int a = rgba[s + 3];
                                if (a == 0) continue;
                                int d = ((y0 + y) * cw + x0 + x) * 4;
                                if (a == 255 || canvas[d + 3] == 0)
                                {
                                    canvas[d] = rgba[s]; canvas[d + 1] = rgba[s + 1]; canvas[d + 2] = rgba[s + 2]; canvas[d + 3] = (byte)a;
                                }
                                else
                                {
                                    int da = canvas[d + 3], oa = a + da * (255 - a) / 255;
                                    for (int k = 0; k < 3; k++) canvas[d + k] = (byte)((rgba[s + k] * a + canvas[d + k] * da * (255 - a) / 255) / Math.Max(1, oa));
                                    canvas[d + 3] = (byte)oa;
                                }
                                any = true;
                            }
                    }
            }
            return any ? canvas : null;
        }

        /// <summary>The picture's size in units for a canvas of w x h cells (1 cell is 1 tile).</summary>
        public static float Units(int w, int h) => Math.Max(w, h);
    }

    /// <summary>The name and health bar over a creature, drawn in the pixel font: an outlined name in the health colour, and under it a bar of
    /// 26 x 3 texels with a dark frame. RGBA, rows bottom first (a Unity texture).</summary>
    public static class FrontLabel
    {
        public const int BarW = 26, BarH = 3, MaxChars = 20;
        public const float Texel = 1f / 30f;   // units a texel covers on the screen

        /// <summary>The colour of a health percentage: green, yellow, orange, red.</summary>
        public static void HealthColor(int hp, out byte r, out byte g, out byte b)
        {
            if (hp >= 60) { r = 70; g = 214; b = 70; }
            else if (hp >= 30) { r = 236; g = 214; b = 60; }
            else if (hp >= 10) { r = 238; g = 140; b = 50; }
            else { r = 226; g = 60; b = 52; }
        }

        public static string Shorten(string name)
        {
            name = (name ?? "").Trim();
            return name.Length <= MaxChars ? name : name.Substring(0, MaxChars - 1) + ".";
        }

        /// <summary>The width and height of the label picture for a name.</summary>
        public static void Size(string name, bool bar, out int w, out int h)
        {
            string n = Shorten(name);
            int tw = PixelText.Width(n, 1);
            w = Math.Max(tw, bar ? BarW + 2 : 0) + 2;
            h = (n.Length > 0 ? PixelText.GlyphH + 2 : 0) + (bar ? (n.Length > 0 ? 1 : 0) + BarH + 2 : 0);
            if (h == 0) { w = 1; h = 1; }
        }

        public static byte[] Pixels(string name, int hp, bool bar, out int w, out int h)
        {
            string n = Shorten(name);
            Size(name, bar, out w, out h);
            var top = new byte[w * h * 4];   // rows top first while drawing
            HealthColor(hp, out byte hr, out byte hg, out byte hb);
            int y = 0;
            if (n.Length > 0)
            {
                var mask = PixelText.Mask(n, 1, out int tw, out int th);
                int ox = (w - tw) / 2;
                // a pale tint of the health colour, readable on a dark night
                byte tr = (byte)((hr * 2 + 255 * 3) / 5), tg = (byte)((hg * 2 + 255 * 3) / 5), tb = (byte)((hb * 2 + 255 * 3) / 5);
                for (int py = 0; py < th; py++)
                    for (int px = 0; px < tw; px++)
                    {
                        if (!mask[py * tw + px]) continue;
                        for (int dy = -1; dy <= 1; dy++)
                            for (int dx = -1; dx <= 1; dx++)
                            {
                                int x = ox + px + dx, yy = 1 + py + dy;
                                if (x < 0 || x >= w || yy < 0 || yy >= h) continue;
                                int i = (yy * w + x) * 4;
                                if (top[i + 3] == 0) { top[i] = 12; top[i + 1] = 10; top[i + 2] = 16; top[i + 3] = 235; }
                            }
                    }
                for (int py = 0; py < th; py++)
                    for (int px = 0; px < tw; px++)
                    {
                        if (!mask[py * tw + px]) continue;
                        int i = ((1 + py) * w + ox + px) * 4;
                        top[i] = tr; top[i + 1] = tg; top[i + 2] = tb; top[i + 3] = 255;
                    }
                y = th + 2 + 1;
            }
            if (bar)
            {
                int bw = BarW + 2, bx = (w - bw) / 2;
                int fill = Math.Max(0, Math.Min(BarW, (int)Math.Round(BarW * Math.Max(0, Math.Min(100, hp)) / 100.0)));
                if (hp > 0 && fill == 0) fill = 1;
                for (int by = 0; by < BarH + 2; by++)
                    for (int bxx = 0; bxx < bw; bxx++)
                    {
                        int i = ((y + by) * w + bx + bxx) * 4;
                        bool frame = by == 0 || by == BarH + 1 || bxx == 0 || bxx == bw - 1;
                        if (frame) { top[i] = 12; top[i + 1] = 10; top[i + 2] = 16; top[i + 3] = 240; }
                        else if (bxx - 1 < fill)
                        {
                            // a lighter top row and a darker bottom row: a little volume
                            int k = by == 1 ? 40 : by == BarH ? -50 : 0;
                            top[i] = (byte)Math.Max(0, Math.Min(255, hr + k)); top[i + 1] = (byte)Math.Max(0, Math.Min(255, hg + k)); top[i + 2] = (byte)Math.Max(0, Math.Min(255, hb + k)); top[i + 3] = 255;
                        }
                        else { top[i] = 44; top[i + 1] = 38; top[i + 2] = 48; top[i + 3] = 235; }
                    }
            }
            var flip = new byte[top.Length];
            for (int row = 0; row < h; row++) Buffer.BlockCopy(top, row * w * 4, flip, (h - 1 - row) * w * 4, w * 4);
            return flip;
        }
    }
}
