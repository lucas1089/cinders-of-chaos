// 3D characters in the HD-2D view: which model, tint and weapons a creature gets (a class per vocation id, a monster per name),
// where it stands, which way it faces, how big it is, the dark fantasy tint and which animation clip is the idle one.
// Pure C#, no Unity types (Unity/Hd2dChars3d.cs applies it; Core.Tests/CharsTests.cs checks every rule).
// Models: Resources/KayKit/NAME.fbx (the CC0 KayKit Adventurers and Skeletons packs by Kay Lousberg, fetched by
// unity/tools/fetch_3d_assets.py, not committed) and, when those are absent, Resources/Chars3d/NAME.fbx (the CC0 RPG Character
// Pack by Quaternius, committed). Both are in docs/CREDITS.md. unity/README.md "3D characters" has the class table and the rules.
// Axes as in Hd2dRuins: x east, z north (screen up: z = -(tile y - origin y)), y up; the camera is on the south side.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>What a creature is drawn as: a model, the items it holds, a colour multiplier and a size.</summary>
    public sealed class CharSpec
    {
        /// <summary>The KayKit model (Resources/KayKit/NAME): Knight, Barbarian, Mage, Rogue, RogueHooded, Skeleton_Warrior, Skeleton_Mage,
        /// Skeleton_Rogue or Skeleton_Minion.</summary>
        public string Model;
        /// <summary>The Chars3d model used when the KayKit files are not in the build: Warrior, Cleric or Wizard.</summary>
        public string Fallback;
        /// <summary>What it holds. An adventurer's item is the name of a node of its FBX (shown, every other weapon node hidden); a skeleton's
        /// item is a weapon FBX of Resources/KayKit (Skeleton_Blade, ...) attached to a hand bone.</summary>
        public string[] Items = new string[0];
        /// <summary>Colour multiplier of the model's own colour, before the dim.</summary>
        public float R = 1f, G = 1f, B = 1f;
        /// <summary>Brightness of the dark restyle (Hd2dChars.Dim unless the model should read lighter or darker).</summary>
        public float Dim = Hd2dChars.Dim;
        /// <summary>Size factor of this model next to the others (1 = Hd2dChars.Height tiles).</summary>
        public float Scale = 1f;
        /// <summary>Why it got this model: the class name or the monster rule (for logs, labels and tests).</summary>
        public string Label = "";

        /// <summary>The idle clip to prefer: two-handed grips and bare hands have their own idle; "" takes plain Idle.</summary>
        public string Idle
        {
            get
            {
                if (Items.Length == 0) return Model != null && Model.StartsWith("Skeleton_", StringComparison.Ordinal) ? "" : "Unarmed_Idle";
                foreach (var i in Items) if (i == "2H_Sword" || i == "2H_Axe" || i == "2H_Staff" || i == "Skeleton_Staff") return "2H_Melee_Idle";
                return "";
            }
        }
    }

    /// <summary>One class: the vocation id of server/data/XML/chaos_vocations*.xml (docs/CLASSES.md), its group and what it looks like.</summary>
    public sealed class ClassInfo
    {
        public int Id;
        public string Name, Group;
        public CharSpec Spec;
    }

    public static class Hd2dChars
    {
        /// <summary>The model files of the fallback pack, Resources/Chars3d/NAME. The legacy player model is the first.</summary>
        public static readonly string[] Models = { "Warrior", "Cleric", "Wizard" };
        public const string PlayerModel = "Warrior";
        /// <summary>The model the build needs at least: Resources/KayKit/Knight (the Warrior class).</summary>
        public const string KayKitFolder = "KayKit/", FallbackFolder = "Chars3d/", KayKitProbe = "Knight";
        /// <summary>A character is this many tiles tall (1 tile = 1 unit).</summary>
        public const float Height = 1.7f;
        /// <summary>Added to every yaw: the pack's models face +z in Unity (Blender export), so 0.</summary>
        public const float ModelYaw = 0f;
        /// <summary>Dark fantasy restyle of the bright textures: colour multiplier and the share pulled to grey.</summary>
        public const float Dim = 0.75f, Desaturate = 0.2f;
        /// <summary>Bounds of a creature's size (tiles tall = Height x this): a rat is not smaller than 0.85, a boss not bigger than 1.6.</summary>
        public const float MinSize = 0.85f, MaxSize = 1.6f;
        /// <summary>The glowing eyes of a skeleton (the "Glow" material): bright yellow, never dimmed, emissive when the shader allows it.</summary>
        public const float GlowR = 1f, GlowG = 0.85f, GlowB = 0.25f, GlowEmission = 1.6f;
        public const string GlowMaterial = "Glow";

        static int Hash(uint a, int b)
        {
            unchecked
            {
                int h = (int)a * 73856093 ^ b * 19349663 ^ 0x5bd1e995;
                h ^= h >> 13; h *= 0x5bd1e995; h ^= h >> 15;
                return h & 0x7fffffff;
            }
        }

        /// <summary>Replaced by a model: a creature drawn as an outfit (look type), not as an item.</summary>
        public static bool Replaces(Creature c) => c != null && c.Outfit != null && c.Outfit.LookType != 0;

        // ---- classes ---------------------------------------------------------------------------------------------------------

        static CharSpec Spec(string model, string fallback, string label, string[] items, float r = 1f, float g = 1f, float b = 1f, float dim = Dim, float scale = 1f)
            => new CharSpec { Model = model, Fallback = fallback, Label = label, Items = items, R = r, G = g, B = b, Dim = dim, Scale = scale };

        static ClassInfo Class(int id, string name, string group, CharSpec spec) => new ClassInfo { Id = id, Name = name, Group = group, Spec = spec };

        static string[] I(params string[] items) => items;

        /// <summary>The 21 classes in the order of docs/CLASSES.md: base class, then its two ascended classes. The vocation ids are the ones of
        /// server/data/XML/chaos_vocations*.xml. Melee heavy: Knight and Barbarian; casters: Mage; ranged and stealth: Rogue and RogueHooded;
        /// holy: Knight in a light tint (dim 0.95); the Lich and the Bone Lord are skeletons; every class a tint of its own.</summary>
        public static readonly ClassInfo[] Classes =
        {
            Class(4, "Warrior", "Warrior", Spec("Knight", "Warrior", "Warrior", I("1H_Sword", "Round_Shield"))),
            Class(8, "Juggernaut", "Warrior", Spec("Knight", "Warrior", "Juggernaut", I("1H_Sword", "Spike_Shield"), 0.85f, 0.95f, 1.1f)),
            Class(14, "Berserker", "Warrior", Spec("Barbarian", "Warrior", "Berserker", I("2H_Axe"), 1.15f, 0.8f, 0.75f)),
            Class(3, "Ranger", "Ranger", Spec("RogueHooded", "Warrior", "Ranger", I("2H_Crossbow"), 0.85f, 1.1f, 0.85f)),
            Class(7, "Deadeye", "Ranger", Spec("Rogue", "Warrior", "Deadeye", I("2H_Crossbow"), 0.8f, 0.85f, 1f)),
            Class(15, "Beastmaster", "Ranger", Spec("Rogue", "Warrior", "Beastmaster", I("1H_Crossbow"), 1.1f, 0.95f, 0.75f)),
            Class(1, "Mystic", "Mystic", Spec("Mage", "Wizard", "Mystic", I("2H_Staff"))),
            Class(5, "Elementalist", "Mystic", Spec("Mage", "Wizard", "Elementalist", I("2H_Staff"), 1.2f, 0.85f, 0.7f)),
            Class(10, "Illusionist", "Mystic", Spec("Mage", "Wizard", "Illusionist", I("1H_Wand", "Spellbook"), 1f, 0.85f, 1.2f)),
            Class(11, "Thief", "Thief", Spec("Rogue", "Warrior", "Thief", I("Knife", "Knife_Offhand"))),
            Class(12, "Ninja", "Thief", Spec("RogueHooded", "Warrior", "Ninja", I("Knife", "Knife_Offhand"), 0.7f, 0.7f, 0.85f)),
            Class(13, "Samurai", "Thief", Spec("Knight", "Warrior", "Samurai", I("1H_Sword"), 1.15f, 0.8f, 0.8f)),
            Class(20, "Necromancer", "Necromancer", Spec("Mage", "Wizard", "Necromancer", I("1H_Wand", "Spellbook"), 0.75f, 1f, 0.8f)),
            Class(21, "Lich", "Necromancer", Spec("Skeleton_Mage", "Wizard", "Lich", I("Skeleton_Staff"), 0.9f, 0.9f, 1.15f, 0.8f)),
            Class(22, "Bone Lord", "Necromancer", Spec("Skeleton_Warrior", "Warrior", "Bone Lord", I("Skeleton_Axe", "Skeleton_Shield_Large_A"), 1f, 1f, 1f, 0.8f)),
            Class(17, "Monk", "Monk", Spec("Barbarian", "Cleric", "Monk", I(), 1.1f, 0.95f, 0.75f)),
            Class(18, "Shadowfist", "Monk", Spec("Barbarian", "Cleric", "Shadowfist", I(), 0.85f, 0.8f, 1.05f)),
            Class(19, "Iron Sage", "Monk", Spec("Mage", "Cleric", "Iron Sage", I("2H_Staff"), 1.15f, 1.05f, 0.75f)),
            Class(23, "Templar", "Templar", Spec("Knight", "Cleric", "Templar", I("1H_Sword", "Badge_Shield"), 1.05f, 1f, 0.8f, 0.95f)),
            Class(24, "Inquisitor", "Templar", Spec("Knight", "Cleric", "Inquisitor", I("2H_Sword"), 1f, 1f, 1.05f, 0.95f)),
            Class(25, "Sentinel", "Templar", Spec("Knight", "Cleric", "Sentinel", I("1H_Sword", "Rectangle_Shield"), 0.9f, 1f, 1.15f, 0.95f)),
        };

        static Dictionary<int, ClassInfo> classById;

        /// <summary>The class of a vocation id, or null when the id is none of the 21.</summary>
        public static ClassInfo ClassOf(int vocation)
        {
            if (classById == null)
            {
                var d = new Dictionary<int, ClassInfo>();
                foreach (var c in Classes) d[c.Id] = c;
                classById = d;
            }
            classById.TryGetValue(vocation, out var ci);
            return ci;
        }

        /// <summary>The Warrior: the player's class when the vocation is not known.</summary>
        public const int DefaultVocation = 4;

        /// <summary>The class of a player whose vocation the protocol does not tell: the look type picks one of the 21 (stable).</summary>
        public static ClassInfo ClassByLook(Creature c)
        {
            int look = c.Outfit != null ? c.Outfit.LookType : 0;
            int k = Hash(look != 0 ? (uint)look : c.Id, look != 0 ? 1 : 2) % Classes.Length;
            return Classes[k];
        }

        // ---- monsters --------------------------------------------------------------------------------------------------------
        // Stems: "*x" is found anywhere in the lower-case name, "=x" is a whole word, "x" starts a word.

        static readonly string[] Undead =
        {
            "*skelet", "*bone", "*skull", "*lich", "*undead", "*zombie", "*ghoul", "*ghost", "*wraith", "*necro", "*mummy", "*death", "*grave",
            "*crypt", "*vampire", "*risen", "*revenant", "*specter", "*spectre", "*phantom", "*banshee", "*marrow", "*sepulchre", "*barrow",
            "*haunt", "*geist", "*shade", "*corpse", "*carrion", "*reaper", "*gallows", "*gibbet", "*thrall", "*lament", "*unbidden", "*fading",
            "=count", "=countess",
        };
        static readonly string[] UndeadCaster =
        {
            "*lich", "*necro", "*mage", "*mancer", "*caller", "*priest", "*seer", "*witch", "*cultist", "*acolyte", "*shaman", "*hierarch",
            "*warlock", "*sorcer", "*wizard", "*savant", "*voodoo", "*chaplain", "*magist", "*spell", "*lantern",
        };
        static readonly string[] UndeadEthereal =
        {
            "*wraith", "*ghost", "*specter", "*spectre", "*phantom", "*shade", "*banshee", "=count", "=countess", "*geist", "*haunt", "*reaper",
            "*stalker", "*archer", "*ranger", "*assassin", "*rogue", "*lurker", "*raven", "*crow", "*gibbet", "*bride", "*lament", "*fledgling",
            "*vampire", "*unbidden",
        };
        static readonly string[] UndeadWarrior =
        {
            "*warrior", "*knight", "*colossus", "*golem", "*reaver", "*lancer", "*oath", "*juggernaut", "*lord", "*king", "*regent", "*warden",
            "*sovereign", "*rider", "*crown", "*ravager", "*warlord", "*executioner", "*bannerman", "*guard", "*revenant", "*champion",
            "*behemoth", "*breaker",
        };
        static readonly string[] UndeadAxe = { "*colossus", "*golem", "*reaver", "*juggernaut", "*oath", "*lord", "*king", "*ravager", "*warlord", "*executioner", "*behemoth" };
        static readonly string[] UndeadShieldBig = { "*knight", "*guard", "*warden", "*bannerman", "*champion" };
        static readonly string[] UndeadBow = { "*archer", "*ranger", "*stalker", "*lurker", "*assassin" };
        static readonly string[] UndeadFloats = { "*wraith", "*ghost", "*specter", "*spectre", "*phantom", "*shade", "*banshee", "*geist", "*haunt", "*unbidden" };

        static readonly string[] Goblins = { "goblin", "hobgoblin", "gnawling", "chitterkin", "cragling", "rootling" };
        static readonly string[] HumanMage =
        {
            "mage", "sorcer", "wizard", "witch", "warlock", "cultist", "acolyte", "priest", "seer", "illusion", "magist", "savant", "alchemist",
            "chaplain", "professor", "doctor", "apprentice", "hermit", "spellsinger", "spellweaver", "evoker", "druid", "=sage", "shaman",
            "hexmage", "crone", "caller", "forgepriest", "hollowseer", "hierophant",
        };
        static readonly string[] HumanCaster = { "cultist", "acolyte", "priest", "chaplain", "alchemist", "forgepriest" };
        static readonly string[] HumanRogue =
        {
            "bandit", "thief", "assassin", "archer", "ranger", "sneak", "scout", "smuggler", "pirate", "corsair", "bloodbeard", "convict", "rogue",
            "dancer", "skirmisher", "sniper", "venomsniper", "raider", "looter", "plunderer", "trapper", "hunter", "burglar", "crake", "mantassin",
            "fleshhunter", "brigand", "slasher", "bomber", "charlatan", "saltbone", "masque",
        };
        static readonly string[] HumanHooded = { "assassin", "shadow", "veil", "hood", "sneak", "mantassin", "dancer", "masque", "charlatan" };
        static readonly string[] HumanBow = { "archer", "ranger", "sniper", "venomsniper", "hunter", "crake" };
        static readonly string[] HumanBarbarian =
        {
            "barbarian", "brute", "brawler", "bruiser", "warlord", "gladiator", "butcher", "executioner", "headsman", "berserk", "ripper",
            "reckless", "ironhorn", "hornsworn", "mauler", "smasher", "rocksmash", "skullbang", "chieftain", "taskmaster", "warbreaker",
            "anvilbreaker", "gorrak",
        };
        static readonly string[] HumanTwoHanded = { "warlord", "butcher", "executioner", "headsman", "chieftain", "gladiator", "berserk" };
        static readonly string[] HumanKnight =
        {
            "knight", "paladin", "guard", "soldier", "captain", "general", "commander", "templar", "bannerman", "vanguard", "sentry", "warden",
            "zealot", "footman", "royal", "legendary", "mercenary", "=man", "duke", "earl", "baron", "=sir", "prince", "king", "=lord", "regent",
            "warrior", "warbound", "sovereign", "oathbreaker", "preceptor", "usurper", "marshal", "penitent", "foreman",
        };
        static readonly string[] HumanKnightBig = { "royal", "captain", "general", "commander", "king", "prince", "regent", "sovereign", "legendary", "duke", "baron", "usurper" };
        static readonly string[] HumanKnightGuard = { "guard", "sentry", "vanguard", "bannerman", "footman", "soldier" };

        // beasts and the rest, by build: magical and odd shapes, fast hunters, heavy brutes (each a skeleton with no weapon, in its family's colour)
        static readonly string[] BeastMagic =
        {
            "elemental", "wisp", "spark", "fairy", "pixie", "spirit", "shard", "eye", "seraph", "angel", "wyrd", "construct", "emitter", "source",
            "matter", "anemone", "fung", "mushroom", "myconid", "cluster", "bloom", "blob", "slime", "visco", "ooze", "energizer", "effigy", "urn",
            "glider", "essence", "facet", "icon", "plant", "snapjaw", "flytrap", "mycelium", "shroom", "glowcap", "inkcap", "puffball", "morel", "bracket",
        };
        static readonly string[] BeastFast =
        {
            "wolf", "hound", "cat", "fox", "vixen", "hyaena", "panther", "lynx", "spider", "snake", "serpent", "viper", "crawler", "hare", "=bat", "hawk",
            "wing", "moth", "hornet", "scorpion", "lizard", "drake", "mantis", "jackal", "=rat", "weasel", "skitter", "gnaw", "raptor", "parrot",
            "stork", "beak", "swarm", "squirrel", "frog", "toad", "snapper", "penguin", "whelp", "lycan", "badger", "hyena", "butterfly", "bug",
        };
        static readonly string[] BeastHeavy =
        {
            "bear", "boar", "troll", "ogre", "orc", "=ape", "gorehide", "behemoth", "tusk", "horn", "giant", "beetle", "crab", "turtle", "stag", "elk", "yeti",
            "dragon", "wyrm", "hydra", "treant", "colossus", "ironbound", "owlbear", "mammoth", "bovine", "orger", "demon", "fiend", "tarrasque", "asura",
            "bull", "hog", "gorilla", "orclops", "hulk", "craghulk", "stompgut", "quakemaw", "tyrant", "mauler", "gutworm", "kin",
        };

        static readonly string[] BigWords =
        {
            "lord", "king", "queen", "colossus", "dragon", "behemoth", "wyrm", "mother", "regent", "sovereign", "titan", "giant", "tyrant",
            "matriarch", "hierarch", "warlord", "chieftain", "hydra", "treant", "tarrasque", "ancient", "elder", "great", "grand", "mammoth",
            "juggernaut", "overlord", "archon", "colossal",
        };
        static readonly string[] SmallWords =
        {
            "little", "sapling", "whelp", "spiderling", "imp", "pixie", "fledgling", "moth", "grub", "swarm", "pet", "squirrel", "frog", "hare",
            "cat", "penguin", "parrot", "wisp", "goblin", "mini", "baby", "runt", "lady", "bug", "butterfly", "cricket", "rat",
        };

        // colour families by word: the first match wins
        static readonly string[][] FamilyWords =
        {
            new[] { "fire", "ember", "cinder", "ash", "pyre", "blaze", "flame", "inferno", "magma", "slag", "forge", "brimstone", "infernal", "sear", "brimhorn", "pyrarch", "scorch" },
            new[] { "ice", "frost", "rime", "winter", "glacial", "snow", "yeti", "penguin", "tundra", "skaldra", "shiver" },
            new[] { "poison", "blight", "plague", "toxic", "rot", "moss", "fungus", "spore", "swamp", "bog", "mire", "venom", "acid", "myco", "shroom", "fen", "verdant", "sludge", "ooze", "goblin", "inkcap", "morel", "puffball", "glowcap", "bracket" },
            new[] { "blood", "gore", "crimson", "bloody", "gorge", "carn" },
            new[] { "void", "shadow", "night", "dusk", "abyss", "hex", "umbra", "gloom", "dread", "dream", "hollow", "=wan", "veil" },
            new[] { "gold", "gild", "sun", "dawn", "seraph", "celestial", "holy", "purity", "radiant" },
            new[] { "storm", "energy", "arcspark", "arcane", "spark", "thunder", "lightning", "azure", "tide", "brine", "coral" },
            new[] { "stone", "rock", "crag", "geode", "boulder", "iron", "steel", "rust", "slate" },
        };
        static readonly float[][] FamilyTints =
        {
            new[] { 1.25f, 0.8f, 0.6f },
            new[] { 0.75f, 0.95f, 1.3f },
            new[] { 0.8f, 1.2f, 0.75f },
            new[] { 1.3f, 0.7f, 0.7f },
            new[] { 0.85f, 0.75f, 1.2f },
            new[] { 1.3f, 1.15f, 0.7f },
            new[] { 0.75f, 1f, 1.3f },
            new[] { 0.95f, 0.95f, 1f },
        };

        /// <summary>The words of a name: lower-case letter runs ("Ul'thazmor" is "ul" and "thazmor").</summary>
        public static string[] Words(string name)
        {
            var list = new List<string>();
            var sb = new System.Text.StringBuilder();
            foreach (char ch in name ?? "")
            {
                char c = char.ToLowerInvariant(ch);
                if (c >= 'a' && c <= 'z') sb.Append(c);
                else if (sb.Length > 0) { list.Add(sb.ToString()); sb.Length = 0; }
            }
            if (sb.Length > 0) list.Add(sb.ToString());
            return list.ToArray();
        }

        static bool Has(string lower, string[] words, string[] stems)
        {
            foreach (var s in stems)
            {
                if (s[0] == '*') { if (lower.IndexOf(s.Substring(1), StringComparison.Ordinal) >= 0) return true; }
                else if (s[0] == '=') { for (int i = 0; i < words.Length; i++) if (words[i] == s.Substring(1)) return true; }
                else for (int i = 0; i < words.Length; i++) if (words[i].StartsWith(s, StringComparison.Ordinal)) return true;
            }
            return false;
        }

        static void Family(string lower, string[] words, out float r, out float g, out float b)
        {
            for (int f = 0; f < FamilyWords.Length; f++)
                if (Has(lower, words, FamilyWords[f]))
                {
                    r = FamilyTints[f][0]; g = FamilyTints[f][1]; b = FamilyTints[f][2];
                    return;
                }
            r = g = b = 1f;
        }

        /// <summary>The model, items and colours of a monster (or summon) by its name; the look type only picks a skeleton for an unnamed one.
        /// Every name gets a model: undead keywords first (skeleton, bone, lich, undead, zombie, ghoul, ghost, wraith, necro, mummy, death,
        /// grave, crypt, vampire and more) give one of the four KayKit skeletons by role (casters and liches: Skeleton_Mage; ethereal, archers
        /// and stalkers: Skeleton_Rogue; armoured and big: Skeleton_Warrior; the rest: Skeleton_Minion); then humans and bandits give an
        /// adventurer (Mage, Rogue, RogueHooded, Barbarian, Knight) in a darker tint; everything else is the Skeleton_Minion, the default dark
        /// monster. A colour family by word (fire, ice, poison, blood, void, gold, storm, stone) tints the body, never the glowing eyes.</summary>
        public static CharSpec MonsterSpec(string name, int lookType)
        {
            string lower = (name ?? "").Trim().ToLowerInvariant();
            if (lower.Length == 0)
            {
                string[] pick = { "Skeleton_Warrior", "Skeleton_Mage", "Skeleton_Rogue", "Skeleton_Minion" };
                string m = pick[Hash((uint)lookType, 5) % pick.Length];
                return Spec(m, m == "Skeleton_Mage" ? "Wizard" : "Warrior", "unnamed", m == "Skeleton_Minion" ? I() : m == "Skeleton_Mage" ? I("Skeleton_Staff") : I("Skeleton_Blade"), 1f, 1f, 1f, 0.8f, m == "Skeleton_Minion" ? 0.9f : 1f);
            }
            var words = Words(lower);
            Family(lower, words, out float fr, out float fg, out float fb);
            if (Has(lower, words, Undead))
            {
                if (Has(lower, words, UndeadCaster))
                    return Spec("Skeleton_Mage", "Wizard", "undead caster", I("Skeleton_Staff"), fr, fg, fb, 0.8f);
                if (Has(lower, words, UndeadEthereal))
                {
                    string[] it = Has(lower, words, UndeadFloats) ? I() : Has(lower, words, UndeadBow) ? I("Skeleton_Crossbow") : I("Skeleton_Blade");
                    return Spec("Skeleton_Rogue", "Warrior", "undead ethereal", it, fr, fg, fb, 0.8f);
                }
                if (Has(lower, words, UndeadWarrior))
                {
                    string[] it = Has(lower, words, UndeadAxe) ? I("Skeleton_Axe")
                        : Has(lower, words, UndeadShieldBig) ? I("Skeleton_Blade", "Skeleton_Shield_Large_A") : I("Skeleton_Blade", "Skeleton_Shield_Small_A");
                    return Spec("Skeleton_Warrior", "Warrior", "undead warrior", it, fr, fg, fb, 0.8f);
                }
                return Spec("Skeleton_Minion", "Warrior", "undead minion", lower.IndexOf("skelet", StringComparison.Ordinal) >= 0 ? I("Skeleton_Blade") : I(), fr, fg, fb, 0.8f, 0.9f);
            }
            if (Has(lower, words, Goblins))
                return Spec("Skeleton_Minion", "Warrior", "goblin", I(), fr, fg, fb, Dim, 0.9f);
            // humans and bandits: an adventurer, darker, tinted by its family
            const float dr = 0.85f, dg = 0.85f, db = 0.9f, hd = 0.65f;
            if (Has(lower, words, HumanMage))
                return Spec("Mage", "Wizard", "human caster", Has(lower, words, HumanCaster) ? I("1H_Wand", "Spellbook") : I("2H_Staff"), fr * dr, fg * dg, fb * db, hd);
            if (Has(lower, words, HumanRogue))
                return Spec(Has(lower, words, HumanHooded) ? "RogueHooded" : "Rogue", "Warrior", "human rogue",
                    Has(lower, words, HumanBow) ? I("2H_Crossbow") : I("Knife", "Knife_Offhand"), fr * dr, fg * dg, fb * db, hd);
            if (Has(lower, words, HumanBarbarian))
                return Spec("Barbarian", "Warrior", "human brute", Has(lower, words, HumanTwoHanded) ? I("2H_Axe") : I("1H_Axe", "Barbarian_Round_Shield"), fr * dr, fg * dg, fb * db, hd);
            if (Has(lower, words, HumanKnight))
                return Spec("Knight", "Warrior", "human knight",
                    Has(lower, words, HumanKnightBig) ? I("2H_Sword") : Has(lower, words, HumanKnightGuard) ? I("1H_Sword", "Rectangle_Shield") : I("1H_Sword", "Round_Shield"),
                    fr * dr, fg * dg, fb * db, hd);
            if (Has(lower, words, BeastMagic)) return Spec("Skeleton_Mage", "Wizard", "beast magic", I(), fr, fg, fb, Dim);
            if (Has(lower, words, BeastFast)) return Spec("Skeleton_Rogue", "Warrior", "beast fast", I(), fr, fg, fb, Dim);
            if (Has(lower, words, BeastHeavy)) return Spec("Skeleton_Warrior", "Warrior", "beast heavy", I(), fr, fg, fb, Dim);
            return Spec("Skeleton_Minion", "Warrior", "default", I(), fr, fg, fb, Dim, 0.9f);
        }

        /// <summary>The model of a townsperson (an NPC): an adventurer in plain colours, no weapon, picked by the look type.</summary>
        public static CharSpec NpcSpec(Creature c)
        {
            string[] m = { "Knight", "Barbarian", "Mage", "Rogue" };
            int look = c.Outfit != null ? c.Outfit.LookType : 0;
            string model = m[Hash(look != 0 ? (uint)look : c.Id, look != 0 ? 1 : 2) % m.Length];
            return Spec(model, model == "Mage" ? "Wizard" : "Warrior", "npc", I());
        }

        /// <summary>What a creature is drawn as. The local player is its class (`playerVocation`, from the login; the Warrior when 0); another
        /// creature carrying a vocation (Creature.Vocation, the offline demo) is that class; other players, whose class the protocol does
        /// not tell, pick one of the 21 by their look type; monsters and summons go by name; NPCs are townspeople.</summary>
        public static CharSpec SpecFor(Creature c, bool isPlayer, int playerVocation)
        {
            if (c == null) return Classes[0].Spec;
            int voc = isPlayer ? (playerVocation != 0 ? playerVocation : c.Vocation != 0 ? c.Vocation : DefaultVocation) : c.Vocation;
            if (c.Type == 1 || c.Type == 3 || c.Type == 4) return MonsterSpec(c.Name, c.Outfit != null ? c.Outfit.LookType : 0);
            var ci = voc != 0 ? ClassOf(voc) : null;
            if (ci != null) return ci.Spec;
            if (isPlayer) return ClassOf(DefaultVocation).Spec;
            if (c.Type == 2) return NpcSpec(c);
            return ClassByLook(c).Spec;
        }

        /// <summary>How big a creature is drawn next to a standard one (1): its sprite's size in tiles (2 x 2 and more are the big ones) and
        /// size words in its name; players and NPCs are 1. Between MinSize and MaxSize.</summary>
        public static float SizeFor(Creature c, int spriteW, int spriteH)
        {
            if (c == null || c.Type == 0 || c.Type == 2) return 1f;
            int m = Math.Max(spriteW, spriteH);
            float s = m <= 1 ? 1f : m == 2 ? 1.3f : m == 3 ? 1.5f : MaxSize;
            string lower = (c.Name ?? "").ToLowerInvariant();
            var words = Words(lower);
            if (Has(lower, words, BigWords)) s *= 1.15f;
            else if (Has(lower, words, SmallWords)) s *= 0.85f;
            return Math.Min(MaxSize, Math.Max(MinSize, s));
        }

        // ---- items and bones -------------------------------------------------------------------------------------------------

        /// <summary>The weapon and shield nodes the adventurer FBX files carry (all of them are in the file): the ones not in a spec's items are hidden.</summary>
        public static readonly string[] WeaponNodes =
        {
            "1H_Sword", "1H_Sword_Offhand", "2H_Sword", "Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield",
            "1H_Axe", "1H_Axe_Offhand", "2H_Axe", "Barbarian_Round_Shield", "Mug",
            "1H_Wand", "2H_Staff", "Spellbook", "Spellbook_open",
            "1H_Crossbow", "2H_Crossbow", "Knife", "Knife_Offhand", "Throwable",
        };

        public static bool IsWeaponNode(string name) => Array.IndexOf(WeaponNodes, (name ?? "").Replace(" (Instance)", "")) >= 0;

        /// <summary>An item held in the left hand (shields, offhand blades, the spellbook); the rest go to the right hand.</summary>
        public static bool LeftHand(string item)
        {
            string s = (item ?? "").ToLowerInvariant();
            return s.IndexOf("shield", StringComparison.Ordinal) >= 0 || s.IndexOf("offhand", StringComparison.Ordinal) >= 0 || s.IndexOf("spellbook", StringComparison.Ordinal) >= 0;
        }

        /// <summary>The hand bone among the bone names of a model: "handslot.r" first (where KayKit weapons attach), then a plain hand bone
        /// ("hand.r", "Hand_R", "RightHand"); never an IK helper ("handIK.r"). -1 when there is none.</summary>
        public static int HandBone(string[] names, bool right)
        {
            int best = -1, rank = 9;
            for (int i = 0; i < names.Length; i++)
            {
                string n = (names[i] ?? "").ToLowerInvariant();
                if (n.IndexOf("hand", StringComparison.Ordinal) < 0 || n.IndexOf("ik", StringComparison.Ordinal) >= 0) continue;
                bool isRight = n.EndsWith(".r", StringComparison.Ordinal) || n.EndsWith("_r", StringComparison.Ordinal) || n.IndexOf("right", StringComparison.Ordinal) >= 0;
                bool isLeft = n.EndsWith(".l", StringComparison.Ordinal) || n.EndsWith("_l", StringComparison.Ordinal) || n.IndexOf("left", StringComparison.Ordinal) >= 0;
                if (right ? !isRight || isLeft : !isLeft || isRight) continue;
                int r = n.IndexOf("slot", StringComparison.Ordinal) >= 0 ? 0 : n.StartsWith("hand", StringComparison.Ordinal) ? 1 : 2;
                if (r < rank) { rank = r; best = i; }
            }
            return best;
        }

        /// <summary>The texture of a KayKit model or weapon (Resources/KayKit/NAME): one per model family.</summary>
        public static string KayKitTexture(string model)
        {
            string m = model ?? "";
            if (m.StartsWith("Skeleton", StringComparison.Ordinal)) return "skeleton_texture";
            if (m.StartsWith("Knight", StringComparison.Ordinal)) return "knight_texture";
            if (m.StartsWith("Barbarian", StringComparison.Ordinal)) return "barbarian_texture";
            if (m.StartsWith("Mage", StringComparison.Ordinal)) return "mage_texture";
            return "rogue_texture";
        }

        // ---- place, facing, size, colour, pose -------------------------------------------------------------------------------

        /// <summary>Yaw in degrees round y, 0 = +z (north, away from the camera), 90 = east, 180 = south, 270 = west.</summary>
        public static float Yaw(Dir d)
        {
            switch (d)
            {
                case Dir.North: return 0f;
                case Dir.NorthEast: return 45f;
                case Dir.East: return 90f;
                case Dir.SouthEast: return 135f;
                case Dir.South: return 180f;
                case Dir.SouthWest: return 225f;
                case Dir.West: return 270f;
                case Dir.NorthWest: return 315f;
            }
            return 180f;
        }

        /// <summary>The centre of the tile cell at drawn tile (x, y) (may be fractional while walking).</summary>
        public static float X(Pos origin, float x) => x - origin.X + 0.5f;
        public static float Z(Pos origin, float y) => -(y - origin.Y) - 0.5f;

        /// <summary>Scale that makes a model of `modelHeight` units stand Height tall; 1 when the height is unknown.</summary>
        public static float ScaleFor(float modelHeight) => modelHeight > 1e-4f && !float.IsNaN(modelHeight) ? Height / modelHeight : 1f;

        /// <summary>The material colour that multiplies the texture: Dim, with Desaturate of the base colour pulled to its grey.</summary>
        public static void Tint(float r, float g, float b, out float tr, out float tg, out float tb) => Tint(r, g, b, Dim, out tr, out tg, out tb);

        /// <summary>The same with a brightness of its own (a spec's Dim); no channel goes over 1.5.</summary>
        public static void Tint(float r, float g, float b, float dim, out float tr, out float tg, out float tb)
        {
            float grey = 0.299f * r + 0.587f * g + 0.114f * b;
            tr = Math.Min(1.5f, (r + (grey - r) * Desaturate) * dim);
            tg = Math.Min(1.5f, (g + (grey - g) * Desaturate) * dim);
            tb = Math.Min(1.5f, (b + (grey - b) * Desaturate) * dim);
        }

        /// <summary>The material colour of a spec's body.</summary>
        public static void Tint(CharSpec s, out float tr, out float tg, out float tb) => Tint(s.R, s.G, s.B, s.Dim, out tr, out tg, out tb);

        /// <summary>The idle clip among the clip names of a model ("CharacterArmature|Idle", "...|Idle_Weapon", ...): plain
        /// Idle first, then any Idle that is not an attack, then any name with Idle; -1 when there is none.</summary>
        public static int IdleClip(string[] names)
        {
            int best = -1, rank = 9;
            for (int i = 0; i < names.Length; i++)
            {
                string n = names[i] ?? "";
                if (n.StartsWith("__preview__", StringComparison.Ordinal)) continue;
                int bar = n.LastIndexOf('|');
                string s = (bar >= 0 ? n.Substring(bar + 1) : n).ToLowerInvariant();
                int r = s == "idle" ? 0 : s.StartsWith("idle", StringComparison.Ordinal) && s.IndexOf("attack", StringComparison.Ordinal) < 0 ? 1 : s.IndexOf("idle", StringComparison.Ordinal) >= 0 ? 2 : 9;
                if (r < rank) { rank = r; best = i; }
            }
            return best;
        }

        /// <summary>The same, taking the clip called `prefer` when the model has it ("2H_Melee_Idle", "Unarmed_Idle").</summary>
        public static int IdleClip(string[] names, string prefer)
        {
            if (!string.IsNullOrEmpty(prefer))
                for (int i = 0; i < names.Length; i++)
                {
                    string n = names[i] ?? "";
                    if (n.StartsWith("__preview__", StringComparison.Ordinal)) continue;
                    int bar = n.LastIndexOf('|');
                    if (string.Equals(bar >= 0 ? n.Substring(bar + 1) : n, prefer, StringComparison.OrdinalIgnoreCase)) return i;
                }
            return IdleClip(names);
        }

        /// <summary>Where in the idle clip a creature is sampled (seconds): its own phase, so a group does not breathe in step.</summary>
        public static float IdleTime(uint id, float length) => length <= 0f ? 0f : length * (Hash(id, 3) % 1000) / 1000f;

        /// <summary>The texture name for a Chars3d material: its own name when it is a texture name of the pack, else the model's body
        /// texture; a weapon sub-mesh ("Warrior_Sword_Texture") is told apart by its material name.</summary>
        public static string TextureFor(string model, string materialName)
        {
            string m = (materialName ?? "").Replace(" (Instance)", "").Trim();
            if (m.StartsWith(model + "_", StringComparison.Ordinal) && m.EndsWith("_Texture", StringComparison.Ordinal)) return m;
            if (m.StartsWith(model + "_", StringComparison.Ordinal)) return m + "_Texture";
            return model + "_Texture";
        }
    }
}
