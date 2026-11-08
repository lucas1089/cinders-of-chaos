// The helper's extras (O433 phase 5, track Q): runes (healing on yourself, attack runes on the target), party and friend heals, food, the Everfull
// "held" message (opcode 116), shooter profiles and the helper HUD rows. Ports of game_helper/helper_runes.lua, helper_ally.lua, the food and
// profile parts of helper.lua / helper_config.lua, game_helperrotation/everfullheld.lua and game_helperhud/helperhud_logic.lua.
// Pure rules here; the engine (HelperEngine.cs) calls them through IHelperHostExt, so Core.Tests drives them with a fake game.
// Not ported: Follow (needs a follow state the Unity session lacks), Auto sell (needs the pouches window of the main client), exercise weapons,
// the potion gate for closed backpacks (a rune or potion is used only when it is in the equipment or an open bag).
using System;
using System.Collections.Generic;
using System.Text;

namespace Chaos.Core
{
    // ---------------------------------------------------------------------------------------- runes
    public sealed class HelperRuneInfo
    {
        public int Id, Server, Radius;
        public string Name = "", Kind = "attack";
        public int[] Vocations;
        public HelperRuneInfo(int id, int server, string name, string kind, int radius, int[] vocations = null) { Id = id; Server = server; Name = name; Kind = kind; Radius = radius; Vocations = vocations; }
    }

    /// <summary>One attack rune row: the rune, how many monsters it must hit, the health range of the monsters (0 and 0: no limit) and its priority.</summary>
    public sealed class HelperRuneRow { public int Id, Creatures = 1, HpMin, HpMax, Priority = 1; }

    public sealed class HelperRuneHealRow { public int Id, Percent; }

    public static class HelperRunes
    {
        public const int ServerOffset = 887, AreaReach = 6, MinGapMs = 1000;
        public const string HealChannel = "healRune", AttackChannel = "attackRune";

        // client item ids (what the use packet takes); the server's ids are the client ids minus 887 for the stock runes
        public static readonly List<HelperRuneInfo> List = new List<HelperRuneInfo>
        {
            new HelperRuneInfo(3152, 2265, "Mending Rune", "heal", 0), new HelperRuneInfo(3160, 2273, "Grand Mending Rune", "heal", 0),
            new HelperRuneInfo(21352, 23723, "Faint Dart Rune", "attack", 0), new HelperRuneInfo(3174, 2287, "Hexdart Rune", "attack", 0),
            new HelperRuneInfo(3198, 2311, "Greater Hexdart Rune", "attack", 0), new HelperRuneInfo(3182, 2295, "Dawnshard Rune", "attack", 0, new[] { 3, 7 }),
            new HelperRuneInfo(3155, 2268, "Reaper's Rune", "attack", 0), new HelperRuneInfo(3195, 2308, "Soulpyre Rune", "attack", 0),
            new HelperRuneInfo(3158, 2271, "Rimespike Rune", "attack", 0), new HelperRuneInfo(3179, 2292, "Stonefang Rune", "attack", 0),
            new HelperRuneInfo(3189, 2302, "Cinder Orb Rune", "attack", 1), new HelperRuneInfo(3200, 2313, "Concussion Rune", "attack", 1),
            new HelperRuneInfo(3191, 2304, "Searing Orb Rune", "attack", 3), new HelperRuneInfo(3161, 2274, "Frostfall Rune", "attack", 3),
            new HelperRuneInfo(3175, 2288, "Rockfall Rune", "attack", 3), new HelperRuneInfo(3202, 2315, "Stormcall Rune", "attack", 3),
            new HelperRuneInfo(21351, 23722, "Pebblestorm Rune", "attack", 3),
        };

        public static HelperRuneInfo Info(int id) { foreach (var r in List) if (r.Id == id) return r; return null; }
        public static bool IsHeal(int id) { var r = Info(id); return r != null && r.Kind == "heal"; }
        public static bool IsAttack(int id) { var r = Info(id); return r != null && r.Kind == "attack"; }

        /// <summary>The runes of a kind the class may use (a rune with a class list needs the class; unknown class: all).</summary>
        public static List<HelperRuneInfo> Offered(string kind, int vocation)
        {
            var o = new List<HelperRuneInfo>();
            foreach (var r in List)
                if (r.Kind == kind && (r.Vocations == null || vocation <= 0 || Array.IndexOf(r.Vocations, vocation) >= 0)) o.Add(r);
            return o;
        }

        /// <summary>The healing rune to use now (0: none): the lowest threshold first.</summary>
        public static int PickHeal(IList<HelperRuneHealRow> rows, double healthPct, Func<int, bool> available = null)
        {
            int best = 0, bestPct = int.MaxValue, bestIndex = int.MaxValue;
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                if (!IsHeal(r.Id) || healthPct > r.Percent || (available != null && !available(r.Id))) continue;
                if (r.Percent < bestPct || (r.Percent == bestPct && i < bestIndex)) { best = r.Id; bestPct = r.Percent; bestIndex = i; }
            }
            return best;
        }

        public static bool HealDue(IList<HelperRuneHealRow> rows, double healthPct) => PickHeal(rows, healthPct) != 0;

        /// <summary>The monsters a rune on the target would hit: the target and every monster within the rune's radius of it; a rune without an
        /// area counts the monsters near the player. hpOk drops a monster whose health does not fit the row.</summary>
        public static int Hits(HelperRuneInfo rune, IList<HelperCreature> entries, Pos from, Pos targetPos, Func<HelperCreature, bool> hpOk = null)
        {
            int n = 0, radius = rune != null ? rune.Radius : 0;
            foreach (var e in entries)
            {
                var p = e.Position;
                if (p.Z != from.Z || (hpOk != null && !hpOk(e))) continue;
                if (radius > 0) { if (Math.Max(Math.Abs(p.X - targetPos.X), Math.Abs(p.Y - targetPos.Y)) <= radius) n++; }
                else if (Math.Max(Math.Abs(p.X - from.X), Math.Abs(p.Y - from.Y)) <= AreaReach) n++;
            }
            return n;
        }

        /// <summary>A health range of 0 / 0 means no limit.</summary>
        public static bool HealthFits(HelperRuneRow row, double healthPct)
        {
            if (healthPct < row.HpMin) return false;
            return !(row.HpMax > 0 && healthPct > row.HpMax);
        }

        /// <summary>The attack rows in the order they are tried: priority, then position.</summary>
        public static List<HelperRuneRow> Order(IList<HelperRuneRow> rows)
        {
            var list = new List<KeyValuePair<int, HelperRuneRow>>();
            for (int i = 0; i < rows.Count; i++) if (IsAttack(rows[i].Id)) list.Add(new KeyValuePair<int, HelperRuneRow>(i, rows[i]));
            list.Sort((a, b) => a.Value.Priority != b.Value.Priority ? a.Value.Priority.CompareTo(b.Value.Priority) : a.Key.CompareTo(b.Key));
            var o = new List<HelperRuneRow>();
            foreach (var e in list) o.Add(e.Value);
            return o;
        }

        /// <summary>The attack rune row to use now (null: none). The target must be in range; the rune must be at hand (available).</summary>
        public static HelperRuneRow PickAttack(IList<HelperRuneRow> rows, bool hasTarget, Pos targetPos, double targetHealth, Pos from, IList<HelperCreature> entries,
            Func<Pos, bool> inRange, Func<int, bool> available)
        {
            if (!hasTarget || (inRange != null && !inRange(targetPos))) return null;
            foreach (var row in Order(rows))
            {
                var rune = Info(row.Id);
                if (rune == null || !HealthFits(row, targetHealth) || (available != null && !available(rune.Id))) continue;
                int hits = Hits(rune, entries, from, targetPos, e => HealthFits(row, e.Health));
                if (hits >= Math.Max(1, row.Creatures)) return row;
            }
            return null;
        }
    }

    // ---------------------------------------------------------------------------------------- party and friend heals
    public sealed class HelperPlayer
    {
        public uint Id;
        public string Name = "";
        public int Health = 100;
        public Pos Position;
        public int Shield;
        public bool IsSelf;
    }

    public sealed class HelperAllyTarget
    {
        public uint Id;
        public string Name = "";
        public int Health, Distance;
        public Pos Position;
        public bool Party, Friend;
    }

    public sealed class HelperAllyEntry { public int Id, Range; public bool NameMode, PartyOnly; public int[] Vocations; public int Radius; }

    /// <summary>The Allies settings: heal the party and a list of friends with a heal-others spell, a group spell and optionally a healing rune.</summary>
    public sealed class HelperAllies
    {
        public const int Names = 5, GroupCountMax = 8;
        public bool PartyEnabled, FriendsEnabled;
        public int PartyPercent = 70, FriendsPercent = 70, Spell, GroupId, GroupCount = 2, RuneId;
        public readonly string[] FriendNames = { "", "", "", "", "" };
        public bool Active => PartyEnabled || FriendsEnabled;
    }

    public sealed class HelperAllyPick { public string Kind = ""; public Spell Spell; public string Words = ""; public HelperAllyTarget Target; public int RuneId; }

    public sealed class HelperAllyState
    {
        public readonly Dictionary<string, double> Last = new Dictionary<string, double>();
        public readonly List<double> Sent = new List<double>();
    }

    public static class HelperAlly
    {
        public const int NameMin = 2, NameMax = 29, MinManaPercent = 10, BudgetMax = 8;
        public const double TargetGapMs = 1200, BudgetMs = 10000;

        // single-target spells: the name goes after the words ('name') or the server picks the most hurt party member
        public static readonly HelperAllyEntry[] Single =
        {
            new HelperAllyEntry { Id = 84, NameMode = true },
            new HelperAllyEntry { Id = 101, NameMode = true },
            new HelperAllyEntry { Id = 96, NameMode = true, PartyOnly = true, Range = 7 },
            new HelperAllyEntry { Id = 253, NameMode = true, PartyOnly = true, Range = 5 },
            new HelperAllyEntry { Id = 66, NameMode = false, PartyOnly = true, Range = 5, Vocations = new[] { 19 } },
        };

        // group spells: on the caster's words, no name; radius 0 means the helper's window
        public static readonly HelperAllyEntry[] Group =
        {
            new HelperAllyEntry { Id = 82, Radius = 3 },
            new HelperAllyEntry { Id = 128, PartyOnly = true },
            new HelperAllyEntry { Id = 97, PartyOnly = true },
        };

        public static HelperAllyEntry SingleOf(int id) { foreach (var e in Single) if (e.Id == id) return e; return null; }
        public static HelperAllyEntry GroupOf(int id) { foreach (var e in Group) if (e.Id == id) return e; return null; }

        /// <summary>A player name the helper may put into a chat line, or null: trimmed, single spaces, letters, space, ' and - only, 2 to 29 characters.</summary>
        public static string CleanName(string s)
        {
            if (s == null) return null;
            var parts = s.Trim().Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            s = string.Join(" ", parts);
            if (s.Length < NameMin || s.Length > NameMax) return null;
            if (!((s[0] >= 'A' && s[0] <= 'Z') || (s[0] >= 'a' && s[0] <= 'z'))) return null;
            foreach (char c in s)
                if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '\'' || c == ' ' || c == '-')) return null;
            return s;
        }

        /// <summary>"Ann, Bob Smith" -> the clean names, at most max, bad names and repeats dropped.</summary>
        public static List<string> ParseNames(string text, int max)
        {
            var o = new List<string>();
            var seen = new HashSet<string>();
            foreach (var part in (text ?? "").Split(',', ';', '\n'))
            {
                var n = CleanName(part);
                if (n != null && seen.Add(n.ToLowerInvariant())) { o.Add(n); if (o.Count >= max) break; }
            }
            return o;
        }

        public static bool IsPartyShield(int shield) => shield >= 3 && shield <= 10;
        public static bool IsLeaderShield(int shield) => shield == 4 || shield == 6 || shield == 8 || shield == 10;

        /// <summary>The players to heal, the most hurt first (then the nearer, then the lower id).</summary>
        public static List<HelperAllyTarget> Candidates(HelperAllies cfg, IList<HelperPlayer> players, Pos from, Func<Pos, Pos, bool> sight = null)
        {
            var o = new List<HelperAllyTarget>();
            var set = new HashSet<string>();
            foreach (var n in cfg.FriendNames) { var c = CleanName(n); if (c != null) set.Add(c.ToLowerInvariant()); }
            foreach (var p in players)
            {
                if (p.IsSelf || p.Health <= 0 || p.Health >= 100 || !HelperLogic.InReach(from, p.Position)) continue;
                string name = CleanName(p.Name);
                bool party = IsPartyShield(p.Shield);
                bool friend = name != null && set.Contains(name.ToLowerInvariant());
                bool isParty = cfg.PartyEnabled && party && p.Health <= cfg.PartyPercent;
                bool isFriend = cfg.FriendsEnabled && friend && p.Health <= cfg.FriendsPercent;
                if (!(isParty || isFriend) || (sight != null && !sight(from, p.Position))) continue;
                o.Add(new HelperAllyTarget { Id = p.Id, Name = name ?? "", Health = p.Health, Position = p.Position, Party = party, Friend = friend, Distance = HelperLogic.Distance(from, p.Position) });
            }
            o.Sort((a, b) => a.Health != b.Health ? a.Health.CompareTo(b.Health) : a.Distance != b.Distance ? a.Distance.CompareTo(b.Distance) : a.Id.CompareTo(b.Id));
            return o;
        }

        /// <summary>Does the character need a heal of its own first (its spell, potion or rune rows are due by the numbers)?</summary>
        public static bool SelfFirst(HelperConfig cfg, double healthPct)
        {
            foreach (var r in cfg.Heals) if (r.Id > 0 && healthPct <= r.Percent) return true;
            if (HelperPotions.HealthDue(cfg.Potions, healthPct)) return true;
            return HelperRunes.HealDue(cfg.RuneHeal, healthPct);
        }

        public static string Words(Spell spell, HelperAllyEntry entry, HelperAllyTarget target)
        {
            if (entry != null && entry.NameMode)
            {
                var name = target != null ? CleanName(target.Name) : null;
                return name == null ? null : spell.Words + " \"" + name + "\"";
            }
            return spell.Words;
        }

        static bool Reaches(HelperAllyEntry e, Pos from, HelperAllyTarget t)
        {
            if (e.PartyOnly && !t.Party) return false;
            return !(e.Range > 0 && HelperLogic.Distance(from, t.Position) > e.Range);
        }

        public static int GroupHits(HelperAllyEntry e, Pos from, IList<HelperAllyTarget> cands)
        {
            int n = 0;
            foreach (var c in cands)
                if ((!e.PartyOnly || c.Party) && (e.Radius <= 0 || HelperLogic.Distance(from, c.Position) <= e.Radius)) n++;
            return n;
        }

        /// <summary>The heal to send now, or null. spellOf gives the spell when the class may cast it; ready says it can go out now.</summary>
        public static HelperAllyPick Pick(HelperAllies cfg, Pos from, IList<HelperAllyTarget> cands, bool selfFirst, double manaPct,
            Func<int, Spell> spellOf, Func<Spell, bool> ready, Func<int, bool> runeAvailable)
        {
            if (selfFirst || cands.Count == 0 || manaPct < MinManaPercent) return null;
            var g = GroupOf(cfg.GroupId);
            if (g != null)
            {
                var spell = spellOf(g.Id);
                if (spell != null && GroupHits(g, from, cands) >= Math.Max(1, cfg.GroupCount) && ready(spell))
                    return new HelperAllyPick { Kind = "group", Spell = spell, Words = spell.Words };
            }
            var s = SingleOf(cfg.Spell);
            var sp = s != null ? spellOf(s.Id) : null;
            if (s != null && sp != null && ready(sp))
            {
                foreach (var c in cands)
                {
                    if (!Reaches(s, from, c)) continue;
                    string words = Words(sp, s, c);
                    if (words != null) return new HelperAllyPick { Kind = "spell", Spell = sp, Words = words, Target = c };
                }
            }
            if (HelperRunes.IsHeal(cfg.RuneId) && runeAvailable != null && runeAvailable(cfg.RuneId))
                foreach (var c in cands)
                    if (HelperLogic.Distance(from, c.Position) <= HelperLogic.ReachX) return new HelperAllyPick { Kind = "rune", RuneId = cfg.RuneId, Target = c };
            return null;
        }

        /// <summary>The guard: a gap per target and a budget for the whole job.</summary>
        public static bool Allowed(HelperAllyState st, string key, double now)
        {
            double last;
            if (st.Last.TryGetValue(key, out last) && now - last < TargetGapMs) return false;
            int recent = 0;
            foreach (var t in st.Sent) if (now - t < BudgetMs) recent++;
            return recent < BudgetMax;
        }

        public static void Noted(HelperAllyState st, string key, double now)
        {
            st.Last[key] = now;
            st.Sent.RemoveAll(t => now - t >= BudgetMs);
            st.Sent.Add(now);
        }

        /// <summary>The heal-others spells the class may use: the entries whose spell the character can cast, in catalogue order.</summary>
        public static List<KeyValuePair<Spell, HelperAllyEntry>> Offered(HelperAllyEntry[] list, Func<int, Spell> spellOf, Func<Spell, bool> castable, int vocation)
        {
            var o = new List<KeyValuePair<Spell, HelperAllyEntry>>();
            foreach (var e in list)
            {
                var s = spellOf(e.Id);
                bool classOk = e.Vocations == null || vocation <= 0 || Array.IndexOf(e.Vocations, vocation) >= 0;
                if (s != null && classOk && castable(s)) o.Add(new KeyValuePair<Spell, HelperAllyEntry>(s, e));
            }
            return o;
        }
    }

    // ---------------------------------------------------------------------------------------- food
    public static class HelperFood
    {
        public const double GapMs = 120000;
        public static readonly int[] Ids = { 3577, 3578, 3579, 3581, 3582, 3583, 3585, 3586, 3587, 3588, 3589, 3592, 3595, 3597, 3600, 3601, 3602,
            3606, 3607, 3723, 3724, 3725, 3728, 3731, 3732, 8011, 8014, 8016, 8017, 12310, 14085, 17457, 17820, 17821, 21143, 21144, 21146, 23535, 23545 };

        /// <summary>The food to eat now (0: none): the first carried one, when hungry or the gap since the last meal has passed (the 10.98 state word has no
        /// hungry bit, so the gap rules).</summary>
        public static int Pick(bool hungry, double now, double lastMeal, Func<int, int> count)
        {
            if (!hungry && lastMeal >= 0 && now - lastMeal < GapMs) return 0;
            foreach (int id in Ids) if (count(id) > 0) return id;
            return 0;
        }
    }

    // ---------------------------------------------------------------------------------------- Everfull held (opcode 116)
    public sealed class EverfullSlot { public int Look, Tier, Level; public string Line = ""; public bool Ready; }

    /// <summary>Which Everfull flask each slot carries (extended opcode 116, `held`): a health or mana potion row follows an upgraded flask. A message
    /// that does not fit is dropped; before the first message nothing is held and the helper behaves as before.</summary>
    public sealed class EverfullHeld
    {
        public const byte Opcode = 116;
        public EverfullSlot Health, Mana;
        public bool Received;
        readonly ExtOpcodes ext;

        public EverfullHeld(ExtOpcodes e)
        {
            ext = e;
            if (e != null) e.On(Opcode, m => { if (m.Action == "held") Apply(m.Data); });
        }

        public void Ask() { if (ext != null) ext.Send(Opcode, "sync", new Dictionary<string, object>()); }

        static int Whole(object o, string key, int lo, int hi)
        {
            var v = Json.Get(o, key);
            if (!(v is double d) || d != Math.Floor(d) || d < lo || d > hi) return -1;
            return (int)d;
        }

        /// <summary>One slot of a message, or null when it does not fit.</summary>
        public static EverfullSlot Clean(string slot, object x)
        {
            if (!(x is Dictionary<string, object>)) return null;
            int look = Whole(x, "look", 1, 65535), tier = Whole(x, "tier", 1, 9), level = Whole(x, "level", 0, 99999);
            string line = Json.Text(x, "line");
            if (look < 0 || tier < 0 || level < 0 || (line != "health" && line != "mana" && line != "spirit")) return null;
            if ((slot == "mana") != (line == "mana")) return null;
            return new EverfullSlot { Look = look, Tier = tier, Level = level, Line = line, Ready = Json.Bool(x, "ready") };
        }

        public bool Apply(object data)
        {
            if (!(data is Dictionary<string, object>)) return false;
            Health = Clean("health", Json.Get(data, "health"));
            Mana = Clean("mana", Json.Get(data, "mana"));
            Received = true;
            return true;
        }

        public void Reset() { Health = null; Mana = null; Received = false; }

        /// <summary>What a row on potion id really drinks: the stock Health / Mana Potion looks follow the carried Everfull of the slot when it is a plain health
        /// or mana flask, ready and allowed at the level.</summary>
        public int Resolve(int id, int level)
        {
            EverfullSlot h = id == 266 ? Health : id == 268 ? Mana : null;
            string slot = id == 266 ? "health" : "mana";
            if (h == null || !h.Ready || h.Line != slot || h.Look == id) return id;
            if (level < h.Level) return id;
            var p = HelperPotions.Info(h.Look);
            return p == null || p.Kind != slot ? id : p.Id;
        }
    }

    // ---------------------------------------------------------------------------------------- shooter profiles
    /// <summary>A named shooter preset: the five slots, the attack rune rows and the Auto Target mode. The live values of the config are the
    /// selected profile's; SelectProfile stores them back before it loads another.</summary>
    public sealed class HelperProfile
    {
        public readonly List<HelperSlot> Slots = new List<HelperSlot>();
        public readonly List<HelperRuneRow> Runes = new List<HelperRuneRow>();
        public int AutoTargetMode = HelperLogic.ModeDefault;

        public HelperProfile()
        {
            for (int i = 0; i < HelperConfig.Slots; i++) Slots.Add(new HelperSlot { Priority = i + 1 });
            for (int i = 0; i < HelperConfig.RuneRows; i++) Runes.Add(new HelperRuneRow { Priority = i + 1 });
        }
    }

    public static class HelperProfiles
    {
        public const int NameMax = 12, Max = 20;

        /// <summary>Why a new name is not allowed (an English text), or null.</summary>
        public static string NameProblem(string name, Func<string, bool> exists)
        {
            if (string.IsNullOrEmpty(name)) return "The name cannot be empty.";
            if (name.Length > NameMax) return "The name cannot be longer than 12 characters.";
            foreach (char c in name)
                if (!(char.IsLetterOrDigit(c) && c < 128) && c != ' ' && c != '-' && c != '_') return "The name can only have letters, digits, spaces, - and _.";
            if (exists != null && exists(name)) return "There is already a preset with this name.";
            return null;
        }

        public static List<string> Names(HelperConfig cfg)
        {
            var o = new List<string>(cfg.Profiles.Keys);
            o.Sort(string.CompareOrdinal);
            return o;
        }

        /// <summary>The preset after current in alphabetical order (the hotkey that cycles them).</summary>
        public static string Next(HelperConfig cfg, string current)
        {
            var names = Names(cfg);
            if (names.Count == 0) return null;
            for (int i = 0; i < names.Count; i++) if (names[i] == current) return names[(i + 1) % names.Count];
            return names[0];
        }
    }

    // ---------------------------------------------------------------------------------------- the bot HUD rows (game_helperhud)
    public sealed class HelperHudSettings
    {
        public bool Enabled, ShowTargeting = true, ShowHaste = true, ShowPlayer = true, ShowHealing = true;
        public string Size = "Normal";
    }

    public sealed class HelperHudRow { public string Icon = "", Name = "", Value = ""; public bool Active; }

    public sealed class HelperHudShape { public int Width, RowsPerColumn, CardWidth, ValueWidth, CardHeight; public bool TwoColumns; }

    public static class HelperHud
    {
        public const int MaxRows = 8, RowHeight = 15, RowSpacing = 1, CardInset = 14, RowLabelInset = 13 + 6 + 58 + 4;
        public static readonly string[] Sizes = { "Compact", "Normal", "Wide" };

        static string Shorten(string text, int limit) { text = text ?? ""; return text.Length <= limit ? text : text.Substring(0, limit) + ".."; }
        static int Percent(int v, int max) => max <= 0 ? 0 : (int)Math.Floor(v * 100.0 / max);

        /// <summary>The rows of the ticked sections. targetName: the creature attacked ("" none); spellName gives a spell's name.</summary>
        public static List<HelperHudRow> Entries(HelperConfig cfg, string targetName, Func<int, string> spellName, int health, int maxHealth, int mana, int maxMana, int level)
        {
            var hud = cfg.Hud;
            var rows = new List<HelperHudRow>();
            string off = Loc.T("Off");
            Action<bool, bool, string, string, string> add = (show, active, icon, name, value) => { if (show) rows.Add(new HelperHudRow { Icon = icon, Name = name, Value = value, Active = active }); };

            bool combat = cfg.AutoTarget || cfg.MagicShooter;
            var parts = new List<string>();
            if (cfg.AutoTarget) parts.Add(Loc.T("Auto"));
            if (cfg.MagicShooter) parts.Add(Loc.T("Shooter"));
            if (!string.IsNullOrEmpty(targetName)) parts.Add(Shorten(targetName, 14));
            add(hud.ShowTargeting, combat, "shooter", Loc.T("Combat"), combat ? string.Join("  ", parts) : off);

            int heals = 0, potions = 0;
            foreach (var r in cfg.Heals) if (r.Id > 0) heals++;
            foreach (var r in cfg.Potions) if (r.Id > 0) potions++;
            var healing = new List<string>();
            if (heals > 0) healing.Add(Loc.T("{0} spells", heals));
            if (potions > 0) healing.Add(Loc.T("{0} potions", potions));
            add(hud.ShowHealing, healing.Count > 0, "healing", Loc.T("Healing"), healing.Count > 0 ? string.Join("  ", healing) : off);

            var support = new List<string>();
            if (cfg.Haste.Enabled)
            {
                string n = spellName != null ? spellName(cfg.Haste.Id) : null;
                support.Add(Loc.T("Haste {0}", n != null ? Shorten(n, 12) : Loc.T("none")));
            }
            if (cfg.Training.Enabled) support.Add(Loc.T("Train {0}%", cfg.Training.Percent));
            add(hud.ShowHaste, cfg.Haste.Enabled || cfg.Training.Enabled, "healing", Loc.T("Support"), support.Count > 0 ? string.Join("  ", support) : off);

            if (maxHealth > 0 || maxMana > 0)
                add(hud.ShowPlayer, true, "healing", Loc.T("Player"), Loc.T("HP {0}%  MP {1}%  Lv {2}", Percent(health, maxHealth), Percent(mana, maxMana), level));

            if (rows.Count == 0) rows.Add(new HelperHudRow { Icon = "tools", Name = Loc.T("Bot HUD"), Value = Loc.T("Pick sections in the Helper window"), Active = false });
            return rows;
        }

        public static int ActiveCount(IList<HelperHudRow> rows) { int n = 0; foreach (var r in rows) if (r.Active) n++; return n; }

        /// <summary>The shape for count rows at a size: one column up to four rows (and always for Compact), else two.</summary>
        public static HelperHudShape Layout(string size, int count)
        {
            int width = size == "Compact" ? 300 : size == "Wide" ? 680 : 520;
            bool columns = size != "Compact";
            count = Math.Max(1, count);
            bool two = columns && count > 4;
            int perColumn = Math.Min(MaxRows, two ? (count + 1) / 2 : count);
            int cardWidth = two ? (width - 6) / 2 : width;
            return new HelperHudShape
            {
                Width = width, TwoColumns = two, RowsPerColumn = perColumn, CardWidth = cardWidth, ValueWidth = cardWidth - CardInset - RowLabelInset,
                CardHeight = 8 + perColumn * RowHeight + Math.Max(0, perColumn - 1) * RowSpacing,
            };
        }
    }

    // ---------------------------------------------------------------------------------------- what the engine needs on top of IHelperHost
    /// <summary>The optional part of the helper's host: other players in view, the class, use an item, the hunger state. A host without it runs the
    /// original helper (a fake game in a test may implement only the base interface).</summary>
    /// <summary>Phase 8 B: what the Support section asks the buff bar (the lower-case names of the buffs on the character, null while the server has not sent its list).</summary>
    public interface IHelperHostBuffs
    {
        HashSet<string> ActiveBuffs();
    }

    public interface IHelperHostExt
    {
        int Vocation { get; }
        bool Hungry { get; }
        /// <summary>The other players (and yourself, flagged) in view with their party shield.</summary>
        IList<HelperPlayer> Players();
        /// <summary>Uses the item (a client id) on a creature (0x84); false when it is not at hand.</summary>
        bool UseOnCreature(int clientId, uint creature);
        /// <summary>Uses an item by itself (food): 0x82 from the equipment or an open bag.</summary>
        bool UseItem(int clientId);
        /// <summary>The creatures that are your own summons, by creature name (the Support tab counts them).</summary>
        IList<string> OwnSummons();
    }
}
