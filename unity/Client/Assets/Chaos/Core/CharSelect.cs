// Character select: the cards of the login answer (name, class, level, world, outfit), keyboard navigation and the website
// link for creating a character. A port of the pure part of client_chaos_charselect (charselect_core.lua).
// Characters are created on the website (createcharacter.php, or the account API at Services.account that the main client's
// own create window calls); the login server only lists them. So the "Create character" button opens the website page.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class CharClass
    {
        public int Id, Base;
        public string Name = "", Line = "", Color = "#9a9088";
        public bool Ascended;
        /// <summary>"Juggernaut (Warrior)" for an ascended class, "Warrior" for a base class.</summary>
        public string Text => Ascended ? Name + " (" + Line + ")" : Name;
    }

    /// <summary>The 7 class lines (docs/CLASSES.md): the base class and its two ascensions, with the colour of the line.</summary>
    public static class ClassTable
    {
        // base, name, colour (game_partyframes PartyMath.LINES), then the two ascended (id, name) pairs
        static readonly object[][] Lines =
        {
            new object[] { 4, "Warrior", "#d9743a", 8, "Juggernaut", 14, "Berserker" },
            new object[] { 3, "Ranger", "#6fbf5a", 7, "Deadeye", 15, "Beastmaster" },
            new object[] { 1, "Mystic", "#5a9be0", 5, "Elementalist", 10, "Illusionist" },
            new object[] { 11, "Thief", "#a77be0", 12, "Ninja", 13, "Samurai" },
            new object[] { 17, "Monk", "#e0b84a", 18, "Shadowfist", 19, "Iron Sage" },
            new object[] { 20, "Necromancer", "#4fc2b0", 21, "Lich", 22, "Bone Lord" },
            new object[] { 23, "Templar", "#f0e0a0", 24, "Inquisitor", 25, "Sentinel" },
        };

        /// <summary>The class of a vocation id. Ids retired by the class rework (2, 6, 9) show as the class they moved to; an unknown id has an empty Line.</summary>
        public static CharClass Of(int vocation)
        {
            int id = vocation == 2 || vocation == 9 ? 1 : vocation == 6 ? 10 : vocation;
            foreach (var l in Lines)
            {
                int b = (int)l[0];
                string name = (string)l[1], color = (string)l[2];
                if (id == b) return new CharClass { Id = id, Base = b, Name = name, Line = name, Color = color };
                if (id == (int)l[3]) return new CharClass { Id = id, Base = b, Name = (string)l[4], Line = name, Color = color, Ascended = true };
                if (id == (int)l[5]) return new CharClass { Id = id, Base = b, Name = (string)l[6], Line = name, Color = color, Ascended = true };
            }
            return new CharClass { Id = id, Name = id == 0 ? "No class" : "Unknown class" };
        }
    }

    public sealed class CharCard
    {
        public int Index;   // 0-based position in the login list
        public string Name = "", ClassText = "", World = "", Host = "";
        public int Level, Port, Vocation;
        public CharClass Class;
        public Outfit Outfit;
        public CharacterEntry Entry;
    }

    public sealed class CharSelectModel
    {
        public readonly List<CharCard> Cards = new List<CharCard>();
        /// <summary>The highlighted card, -1 when the list is empty.</summary>
        public int Selected = -1;

        public static CharSelectModel Build(IList<CharacterEntry> list, string lastName = null, string fallbackWorld = "Cinders of Chaos")
        {
            var m = new CharSelectModel();
            if (list != null)
                for (int i = 0; i < list.Count; i++)
                {
                    var e = list[i];
                    var cls = ClassTable.Of(e.Vocation);
                    m.Cards.Add(new CharCard
                    {
                        Index = i, Name = e.Name ?? "", Level = e.Level, Vocation = e.Vocation, Class = cls, ClassText = cls.Text,
                        World = string.IsNullOrEmpty(e.World) ? fallbackWorld : e.World, Host = e.Host, Port = e.Port, Outfit = e.Outfit, Entry = e,
                    });
                }
            m.Selected = InitialIndex(m.Cards, lastName);
            return m;
        }

        /// <summary>The card of the character played last, else the first (-1 for none).</summary>
        public static int InitialIndex(IList<CharCard> cards, string lastName)
        {
            if (cards == null || cards.Count == 0) return -1;
            if (!string.IsNullOrEmpty(lastName))
                for (int i = 0; i < cards.Count; i++)
                    if (cards[i].Name == lastName) return i;
            return 0;
        }

        /// <summary>The index after a key (Up, Down, Left, Right, Home, End, PageUp, PageDown), kept inside the list.</summary>
        public static int Move(int index, int count, string key, int page = 5)
        {
            if (count <= 0) return -1;
            index = Math.Max(0, Math.Min(count - 1, index));
            page = Math.Max(1, page);
            switch (key)
            {
                case "Up": case "Left": index--; break;
                case "Down": case "Right": index++; break;
                case "Home": index = 0; break;
                case "End": index = count - 1; break;
                case "PageUp": index -= page; break;
                case "PageDown": index += page; break;
            }
            return Math.Max(0, Math.Min(count - 1, index));
        }

        public void Navigate(string key, int page = 5) { Selected = Move(Selected, Cards.Count, key, page); }
        public CharCard Current => Selected >= 0 && Selected < Cards.Count ? Cards[Selected] : null;

        /// <summary>The website page that creates a character: the login host without a leading "play." (or "login."), over https. Null for an empty or local host.</summary>
        public static string CreateUrl(string host)
        {
            host = (host ?? "").Trim().ToLowerInvariant();
            if (host.Length == 0 || host == "localhost" || host.StartsWith("127.", StringComparison.Ordinal)) return null;
            foreach (string p in new[] { "play.", "login.", "game." })
                if (host.StartsWith(p, StringComparison.Ordinal)) { host = host.Substring(p.Length); break; }
            foreach (char c in host)
                if (!(char.IsLetterOrDigit(c) || c == '.' || c == '-')) return null;
            return "https://" + host + "/createcharacter.php";
        }
    }
}
