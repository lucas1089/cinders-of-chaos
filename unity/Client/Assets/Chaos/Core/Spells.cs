// The spell list of the server and the spell cooldowns: the model behind the spellbook and the hotbar. A port of the logic of
// the main client's game_spellbook (spellbook.lua, spellbook_core.lua; server/data/scripts/chaos/spellbook.lua, extended
// opcode 219) and of the cooldown packets 0xA4 / 0xA5.
//
//   server -> client  open {vocation, level, magicLevel, total, chunks, sig, unchanged, learned, vocationNames}
//                     spells {index, spells = [...]}  (several messages; none when unchanged)
//                     done {total, sig}
//                     show {}  (a spellbook item was used: open the window)
//   client -> server  open {have = sig of the cached list, prefetch}
// Casting an instant spell is saying its words (GameSession.Say), as the main client's hotbar does (g_game.talk). A rune
// entry is an item to use, not words: Cast refuses it.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class Spell
    {
        public string Name = "", Words = "", Type = "", Element = "", Target = "", Center = "", Description = "", Scaling = "";
        public int Id, Level, MagicLevel, Mana, ManaPercent, Soul, Cooldown, GroupCooldown, Range, Quest;
        /// <summary>The spell group: 1 attack, 2 healing, 3 support, 4 special (0 unknown). The cooldown packet 0xA5 names it.</summary>
        public int Group;
        public bool NeedLearn, Premium;
        /// <summary>Server item id of a rune entry, 0 for a spell.</summary>
        public int Rune, RuneClientId;
        public List<int> Vocations = new List<int>();
        /// <summary>The area matrix (1 hit, 2 centre, 3 centre and hit), rows of cells; empty when the server sent none.</summary>
        public List<List<int>> Area = new List<List<int>>();

        public bool IsRune => Rune != 0;

        public static Spell From(object o)
        {
            var s = new Spell
            {
                Name = Json.Text(o, "name"), Words = Json.Text(o, "words"), Type = Json.Text(o, "type").ToLowerInvariant(),
                Element = Json.Text(o, "element"), Target = Json.Text(o, "target").ToLowerInvariant(), Center = Json.Text(o, "center"),
                Description = Json.Text(o, "description"), Scaling = Json.Text(o, "scaling"),
                Id = Json.Int(o, "id"), Level = Json.Int(o, "level"), MagicLevel = Json.Int(o, "maglevel", Json.Int(o, "mlevel")),
                Mana = Json.Int(o, "mana"), ManaPercent = Json.Int(o, "manaPercent"), Soul = Json.Int(o, "soul"),
                Cooldown = Json.Int(o, "cooldown"), GroupCooldown = Json.Int(o, "groupCooldown"), Range = Json.Int(o, "range"),
                Quest = Json.Int(o, "quest"), NeedLearn = Json.Bool(o, "needLearn"), Premium = Json.Bool(o, "premium"),
                Rune = Json.Get(o, "rune") is double r ? (int)r : 0, RuneClientId = Json.Int(o, "runeClientId"),
            };
            object g = Json.Get(o, "group");
            if (g is double gd) s.Group = (int)gd;
            else if (g is string gs) s.Group = GroupOf(gs);
            foreach (object v in Json.List(o, "vocations")) if (v is double d) s.Vocations.Add((int)d);
            foreach (object row in Json.List(o, "area"))
            {
                var cells = new List<int>();
                if (row is List<object> rl) foreach (object c in rl) cells.Add(c is double cd ? (int)cd : 0);
                s.Area.Add(cells);
            }
            return s;
        }

        public static int GroupOf(string name)
        {
            switch ((name ?? "").ToLowerInvariant())
            {
                case "attack": return 1;
                case "healing": return 2;
                case "support": return 3;
                case "special": return 4;
                default: return 0;
            }
        }

        /// <summary>"attack" or "support" (spellbook_core kindOf): damage is an attack; heal, buff, summon, conjure, utility support;
        /// without a type the group decides.</summary>
        public string Kind
        {
            get
            {
                if (Type == "damage") return "attack";
                if (Type == "heal" || Type == "buff" || Type == "summon" || Type == "conjure" || Type == "utility") return "support";
                return Group == 1 ? "attack" : "support";
            }
        }
    }

    /// <summary>The character as the spell filter sees it.</summary>
    public struct SpellContext
    {
        public int Vocation, Level, MagicLevel;
    }

    public enum SpellStatus { Ready, Level, Learn, Quest, Vocation }

    public sealed class SpellBook
    {
        public const byte Opcode = 219;
        public const string FilterLearned = "learned", FilterSoon = "soon", FilterVocation = "vocation", FilterAll = "all", FilterRunes = "runes";
        public const int SoonLevels = 10;

        readonly ExtOpcodes ext;
        /// <summary>The ms clock the cooldowns run on (GameSession.Now).</summary>
        public Func<double> Clock = () => 0;
        /// <summary>Says a line (GameSession.Say): how a spell is cast.</summary>
        public Action<string> Say = delegate { };
        /// <summary>The live level and magic level, when the session has them (the open header's are older).</summary>
        public Func<int> LevelNow, MagicLevelNow;
        /// <summary>The list, its learned names or a cooldown changed.</summary>
        public event Action Changed = delegate { };
        /// <summary>The server asked to show the window (a spellbook item was used).</summary>
        public event Action ShowRequested = delegate { };

        public readonly List<Spell> Spells = new List<Spell>();
        public string Sig;
        public int Vocation, Level, MagicLevel;
        public readonly HashSet<string> Learned = new HashSet<string>();
        public readonly Dictionary<int, string> VocationNames = new Dictionary<int, string>();
        /// <summary>True once a full list has arrived (or the server said the cached one is current).</summary>
        public bool Loaded { get; private set; }
        public int Total;

        List<Spell> pending;
        readonly Dictionary<int, double> spellEnds = new Dictionary<int, double>();
        readonly Dictionary<int, double> groupEnds = new Dictionary<int, double>();

        public SpellBook(ExtOpcodes e)
        {
            ext = e;
            ext.On(Opcode, OnMessage);
        }

        /// <summary>Asks for the list (the main client sends it a few seconds after login with prefetch, and at each window open).</summary>
        public void Open(bool prefetch = false)
        {
            var data = new Dictionary<string, object>();
            if (Sig != null) data["have"] = Sig;
            if (prefetch) data["prefetch"] = true;
            ext.Send(Opcode, "open", data.Count > 0 ? data : null);
        }

        void OnMessage(ExtMessage m)
        {
            switch (m.Action)
            {
                case "show": ShowRequested(); return;
                case "open":
                {
                    Vocation = Json.Int(m.Data, "vocation");
                    Level = Json.Int(m.Data, "level");
                    MagicLevel = Json.Int(m.Data, "magicLevel");
                    Total = Json.Int(m.Data, "total");
                    Learned.Clear();
                    foreach (object n in Json.List(m.Data, "learned")) if (n is string s) Learned.Add(s.ToLowerInvariant());
                    var names = Json.List(m.Data, "vocationNames");
                    if (names.Count > 0)
                    {
                        VocationNames.Clear();
                        foreach (object v in names) VocationNames[Json.Int(v, "id")] = Json.Text(v, "name");
                    }
                    if (Json.Bool(m.Data, "unchanged") && Spells.Count > 0)
                    {
                        pending = null;
                        string sig = Json.Text(m.Data, "sig", null);
                        if (sig != null) Sig = sig;
                        Loaded = true;
                        Changed();
                    }
                    else pending = new List<Spell>();
                    return;
                }
                case "spells":
                {
                    if (pending == null) pending = new List<Spell>();
                    foreach (object o in Json.List(m.Data, "spells")) pending.Add(Spell.From(o));
                    return;
                }
                case "done":
                {
                    if (pending != null)
                    {
                        Sort(pending);
                        Spells.Clear();
                        Spells.AddRange(pending);
                        pending = null;
                    }
                    Sig = Json.Text(m.Data, "sig", Sig);
                    Loaded = true;
                    Changed();
                    return;
                }
            }
        }

        // ------------------------------------------------------------------------------------ rules (spellbook_core.lua)
        public static int Compare(Spell a, Spell b)
        {
            if (a.Level != b.Level) return a.Level.CompareTo(b.Level);
            int n = string.CompareOrdinal(a.Name.ToLowerInvariant(), b.Name.ToLowerInvariant());
            return n != 0 ? n : string.CompareOrdinal(a.Words.ToLowerInvariant(), b.Words.ToLowerInvariant());
        }

        /// <summary>Level, then name, then words; stable.</summary>
        public static void Sort(List<Spell> list)
        {
            var keyed = new List<KeyValuePair<int, Spell>>();
            for (int i = 0; i < list.Count; i++) keyed.Add(new KeyValuePair<int, Spell>(i, list[i]));
            keyed.Sort((x, y) => { int c = Compare(x.Value, y.Value); return c != 0 ? c : x.Key.CompareTo(y.Key); });
            for (int i = 0; i < keyed.Count; i++) list[i] = keyed[i].Value;
        }

        /// <summary>The character: the server's vocation id and the live level and magic level.</summary>
        public SpellContext Context => new SpellContext
        {
            Vocation = Vocation,
            Level = LevelNow != null && LevelNow() > 0 ? LevelNow() : Level,
            MagicLevel = MagicLevelNow != null ? MagicLevelNow() : MagicLevel,
        };

        public SpellStatus Status(Spell s) => Status(s, Context);

        /// <summary>Castable now ("Ready"), or why not: another vocation, a spell to learn (or a quest spell), a level too low.</summary>
        public SpellStatus Status(Spell s, SpellContext ctx)
        {
            if (s.Vocations.Count > 0 && !s.Vocations.Contains(ctx.Vocation)) return SpellStatus.Vocation;
            if (s.NeedLearn && !Learned.Contains(s.Name.ToLowerInvariant())) return s.Quest > 0 ? SpellStatus.Quest : SpellStatus.Learn;
            if (ctx.Level > 0 && s.Level > ctx.Level) return SpellStatus.Level;
            if (ctx.MagicLevel >= 0 && s.MagicLevel > ctx.MagicLevel) return SpellStatus.Level;
            return SpellStatus.Ready;
        }

        public static bool TextMatches(Spell s, string text)
        {
            text = (text ?? "").Trim().ToLowerInvariant();
            if (text.Length == 0) return true;
            return s.Name.ToLowerInvariant().Contains(text) || s.Words.ToLowerInvariant().Contains(text);
        }

        public bool FilterMatches(Spell s, string filter)
        {
            if (filter == FilterRunes) return s.IsRune;
            if (s.IsRune) return false;
            if (filter == FilterAll) return true;
            var ctx = Context;
            var st = Status(s, ctx);
            if (filter == FilterVocation) return st != SpellStatus.Vocation;
            if (filter == FilterSoon)
            {
                if (st == SpellStatus.Ready || st == SpellStatus.Vocation) return false;
                if (st == SpellStatus.Quest) return true;
                return s.Level <= ctx.Level + SoonLevels;
            }
            return st == SpellStatus.Ready;   // learned, and the default for an unknown filter
        }

        /// <summary>The spells that pass the filter ("learned", "soon", "vocation", "all", "runes"), the kind ("all", "attack",
        /// "support") and the search text, in list order.</summary>
        public List<Spell> Visible(string filter, string kind, string text)
        {
            var list = new List<Spell>();
            foreach (var s in Spells)
                if (FilterMatches(s, filter) && (kind == "attack" || kind == "support" ? s.Kind == kind : true) && TextMatches(s, text)) list.Add(s);
            return list;
        }

        public Spell ByWords(string words)
        {
            words = (words ?? "").Trim();
            foreach (var s in Spells) if (!s.IsRune && string.Equals(s.Words, words, StringComparison.OrdinalIgnoreCase)) return s;
            return null;
        }

        public Spell ById(int id)
        {
            foreach (var s in Spells) if (!s.IsRune && s.Id == id) return s;
            return null;
        }

        // ------------------------------------------------------------------------------------ cooldowns
        /// <summary>0xA4: the spell with this id is on cooldown for ms.</summary>
        public void OnSpellCooldown(int id, uint ms)
        {
            spellEnds[id] = Clock() + ms;
            Changed();
        }

        /// <summary>0xA5: the group is on cooldown for ms.</summary>
        public void OnGroupCooldown(int group, uint ms)
        {
            groupEnds[group] = Clock() + ms;
            Changed();
        }

        /// <summary>Milliseconds left before the spell can be cast again (its own cooldown or its group's), 0 when ready.</summary>
        public double CooldownLeft(Spell s)
        {
            double now = Clock(), left = 0;
            if (spellEnds.TryGetValue(s.Id, out var e)) left = Math.Max(left, e - now);
            if (s.Group != 0 && groupEnds.TryGetValue(s.Group, out var g)) left = Math.Max(left, g - now);
            return left;
        }

        /// <summary>Seconds shown on a slot ("3", rounded up), 0 when none.</summary>
        public int CooldownSeconds(Spell s) => (int)Math.Ceiling(CooldownLeft(s) / 1000.0);

        /// <summary>Casts by saying the words. False for a rune entry, an unknown spell or a spell the character cannot cast.</summary>
        public bool Cast(Spell s)
        {
            if (s == null || s.IsRune || s.Words.Length == 0) return false;
            if (Loaded && Status(s) != SpellStatus.Ready) return false;
            Say(s.Words);
            return true;
        }

        /// <summary>A hotkey: says its line as it is (it may be any text; a spell the character cannot cast yet gets the server's own
        /// answer). A rune entry has no words to say.</summary>
        public void CastOrSay(string words)
        {
            if (string.IsNullOrWhiteSpace(words)) return;
            Say(words.Trim());
        }

        /// <summary>Forget everything of the last character (logout).</summary>
        public void Reset()
        {
            Spells.Clear();
            Learned.Clear();
            spellEnds.Clear();
            groupEnds.Clear();
            Sig = null;
            Loaded = false;
            pending = null;
        }
    }
}
