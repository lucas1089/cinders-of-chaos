// The helper's Support spells section (O433 phase 5, track Q): up to 8 support spells (shields, summons, fight buffs, vigils) the helper casts by itself, in
// priority order, whenever they are off cooldown and the effect is not on. A port of game_helpersupport/supportspells.lua. The main client asks the
// buff bar whether a buff is on; Unity has no buff bar yet, so the rule that file uses when the bar cannot tell applies to every spell: the spell's
// own duration since our last cast, else at least a minute (or its cooldown) since the last cast. A vigil (a switch: a second cast turns it off) is
// never cast blind, so with no bar it stays unused. A capped summon needs the count of own summons (IHelperHostExt.OwnSummons).
// Phase 8 track B: the buff bar (Core/Hud.cs BuffBar.ActiveNames) decides when it has data (SupportContext.BuffActive, IHelperHostBuffs), as in the main client: a vigil
// the bar showed on that goes off by hand stays off (UserOff, TakeUserOff), a haste shows in the player state, and Auto setup plans the Timer rules too (AutoPlanFull).
// Tests: Core.Tests/InfoTests.cs (mirrors supportspells_test.lua for the parts that port).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class SupportSlot { public int Id; public bool Enabled = true; }

    public sealed class HelperSupportConfig
    {
        public bool Enabled = true;
        public int Reserve = HelperSupport.DefaultReserve;
        public readonly List<SupportSlot> Slots = new List<SupportSlot>();
        /// <summary>The Timer rules (the stock helper's timer section): words cast every Cooldown seconds while attacking a monster, outside a protection zone.</summary>
        public readonly List<SupportTimerRule> Timers = new List<SupportTimerRule>();
    }

    /// <summary>One Timer rule Auto setup writes (autosetup.lua timerRule: type words, cooldown in seconds, not in a protection zone, only while attacking a monster).</summary>
    public sealed class SupportTimerRule { public int Id; public string Words = "", Name = ""; public int Cooldown = 30; public bool Enabled = true; }

    /// <summary>What a support spell is: its kind and the numbers of the cycle (supportspells.lua H.KINDS).</summary>
    public sealed class SupportKind
    {
        public string Auto;           // "support" | "timer" | null (offered, never set up)
        public string Kind = "buff";  // buff | shield | summon | switch | party
        public bool Fight, Capped, Haste, KnownEntry = true, ExpectBar;
        public int Dur, Rank;         // seconds, 0 none; 0 = the default of the kind
        public string Minion;
        public string[] Minions;
        public int[][] Keep;          // { level, count } steps
        public string[] Bar;
    }

    public sealed class SupportInfo
    {
        public string Kind = "buff";
        public string Auto;
        public bool Fight, Haste, ExpectBar, Capped, Known;
        /// <summary>The lower-case names the buff bar may show it under: the kind's own, then the spell's name.</summary>
        public string[] Bar = new string[0];
        public int Dur, Rank;
        public string Minion;
        public string[] Minions;
        public int[][] Keep;
    }

    public sealed class SupportState
    {
        public readonly Dictionary<int, double> CastAt = new Dictionary<int, double>(), SettleUntil = new Dictionary<int, double>();
        public readonly Dictionary<int, string> Status = new Dictionary<int, string>();
        public readonly Dictionary<int, int> Misses = new Dictionary<int, int>();
        /// <summary>The buff bar showed this spell's buff once (so "not shown" counts), whether it showed on after the last cast, the last state of a vigil, the ms a vigil was seen switched off.</summary>
        public readonly HashSet<int> Seen = new HashSet<int>(), SawSince = new HashSet<int>();
        public readonly Dictionary<int, bool> BarOn = new Dictionary<int, bool>();
        public readonly Dictionary<int, double> UserOff = new Dictionary<int, double>();
        public double ClearAt = double.NaN, GraceUntil;
        public int Casts;
        public void Reset() { CastAt.Clear(); SettleUntil.Clear(); Status.Clear(); Misses.Clear(); Seen.Clear(); SawSince.Clear(); BarOn.Clear(); UserOff.Clear(); ClearAt = double.NaN; GraceUntil = 0; Casts = 0; }
    }

    /// <summary>What the pick needs from the game; every member may be left null.</summary>
    public sealed class SupportContext
    {
        public double Now;
        public bool Online = true, HelperOn, InPz, Attacking, Channeling;
        public int Mana, MaxMana, Level;
        public Func<int, Spell> SpellOf;
        public Func<Spell, bool> Castable, OnCooldown, Allowed, InParty;
        public Func<Spell, string> Blocked;
        public Func<Spell, int> Refusals;
        /// <summary>The buff bar: is any of the lower-case names on? null when it cannot tell (no data yet).</summary>
        public Func<string[], bool?> BuffActive;
        /// <summary>The player's own haste state; null when unknown.</summary>
        public Func<bool?> Hasted;
        /// <summary>All own summons and those of the names; null when the client cannot tell.</summary>
        public Func<string[], KeyValuePair<int, int>?> SummonCount;
        public Func<int> SummonCap;
    }

    public static class HelperSupport
    {
        public const int SupportMax = 8, TimerMax = 6, DefaultReserve = 20, RefuseLimit = 3, SummonCapDefault = 3;
        public const double SettleMs = 2500, SwitchSettleMs = 6000, SummonGapMs = 10000, RecastMinMs = 60000, RefusedHoldMs = 30000, NoBuffMaxMs = 600000, MaxAutoCooldownMs = 1800000;
        public static readonly int[] Reserves = { 0, 10, 20, 30, 40, 50 };

        /// <summary>The summon cap of a class (Necromancer 3, Lich 1, Bone Lord 6, 7 from level 400).</summary>
        public static int SummonCap(int vocation, int level)
        {
            if (vocation == 20) return 3;
            if (vocation == 21) return 1;
            if (vocation == 22) return level >= 400 ? 7 : 6;
            return SummonCapDefault;
        }

        static readonly HashSet<int> NeverIds = new HashSet<int> { 254, 104, 232 };
        static readonly HashSet<string> NeverNames = new HashSet<string>
        {
            "light", "great light", "ultimate light", "magic rope", "find person", "food", "challenge", "levitate", "invisible", "creature illusion",
            "summon creature", "conjure arrow", "conjure explosive arrow", "conjure piercing bolt", "conjure spear", "cancel invisibility", "find fiend",
            "lantern", "greater lantern", "radiant lantern", "ghost rope", "conjure rations", "wraith step", "shroud of shadows", "call thrall", "unveil",
            "taunt of iron", "duelist's oath", "skinchanger's guise", "hallow spear", "warhorse rush", "town portal",
        };
        static readonly HashSet<string> NeverWords = new HashSet<string>
        {
            "utevo lux", "utevo gran lux", "utevo vis lux", "exani tera", "exiva moe res", "exevo pan", "exana ina", "exeta res", "exeta amp res", "exani hur",
            "utevo res ina", "utevo res", "exana vita", "exevo con", "exevo con flam", "exevo infir con", "exeta con", "utani tempo hur", "utamo tempo san",
            "utana vid", "exevo gran mort", "exana amp res",
        };

        static SupportKind K(string auto, string kind = "buff", bool fight = false, int dur = 0, int rank = 0, bool capped = false, string minion = null,
            string[] minions = null, int[][] keep = null, string[] bar = null, bool haste = false)
            => new SupportKind { Auto = auto, Kind = kind, Fight = fight, Dur = dur, Rank = rank, Capped = capped, Minion = minion, Minions = minions, Keep = keep, Bar = bar, Haste = haste, ExpectBar = bar != null };

        /// <summary>Spell id to kind (the server's ids): the fight buffs, the hastes, the shields, vigils, summons and the ones Auto setup never sets up.</summary>
        public static readonly Dictionary<int, SupportKind> Kinds = new Dictionary<int, SupportKind>
        {
            { 209, K("support", fight: true, dur: 20, rank: 5) }, { 217, K("support", fight: true, dur: 8, rank: 5) }, { 222, K("support", fight: true, dur: 12, rank: 5) },
            { 233, K("support", fight: true, dur: 12, rank: 5) }, { 239, K("support", fight: true, dur: 20, rank: 5) }, { 245, K("support", fight: true, dur: 30, rank: 5) },
            { 72, K("support", fight: true, dur: 12, rank: 5) }, { 223, K("support", fight: true, dur: 8, rank: 5) }, { 226, K("support", fight: true, dur: 10, rank: 5) },
            { 243, K("support", fight: true, dur: 3, rank: 5) }, { 251, K("support", fight: true, dur: 6, rank: 5) }, { 133, K("support", fight: true, dur: 10, rank: 5) },
            { 132, K("support", fight: true, dur: 12, rank: 5) }, { 135, K("support", fight: true, dur: 12, rank: 5) },
            { 143, K("support", fight: true, dur: 20, rank: 5) }, { 150, K("support", fight: true, dur: 20, rank: 5) }, { 153, K("support", fight: true, dur: 20, rank: 5) },
            { 156, K("support", fight: true, dur: 15, rank: 5) }, { 159, K("support", fight: true, dur: 20, rank: 5) }, { 173, K("support", fight: true, dur: 15, rank: 5) },
            { 178, K("support", fight: true, dur: 20, rank: 5) },
            { 6, K(null, "buff", dur: 33, bar: new[] { "haste" }, haste: true) }, { 39, K(null, "buff", dur: 22, bar: new[] { "haste" }, haste: true) },
            { 234, K("support", "shield", dur: 15, rank: 2) }, { 44, K("support", "shield", dur: 200, rank: 2, bar: new[] { "magic shield" }) },
            { 162, K("support", "switch", rank: 1) }, { 161, K(null, "switch", rank: 1) }, { 179, K(null, "switch", rank: 1) }, { 255, K(null, "switch", rank: 1) },
            { 211, K("support", "summon", fight: true, dur: 40, rank: 4) },
            { 180, K("support", "summon", fight: true, rank: 4, capped: true) },
            { 192, K("support", "summon", fight: true, rank: 4, capped: true, minion: "Risen Warrior") },
            { 40, K("support", "summon", fight: true, rank: 4, capped: true, minion: "Risen Archer") },
            { 176, K("support", "summon", fight: true, rank: 4, capped: true, minion: "Risen Mage") },
            { 186, K("support", "summon", fight: true, rank: 4, minions: new[] { "Bone Golem" }, keep: new[] { new[] { 0, 1 } }) },
            { 187, K("support", "buff", fight: true, dur: 20, rank: 5) },
            { 248, K("support", "summon", fight: true, rank: 4, minions: new[] { "War Wolf", "Wolf" }, keep: new[] { new[] { 0, 1 }, new[] { 400, 2 } }) },
            { 194, K("support", "summon", rank: 3) }, { 195, K("support", "summon", rank: 3) }, { 196, K("support", "summon", rank: 3) }, { 197, K("support", "summon", rank: 3) },
            { 282, K("support", "summon", rank: 3) },
            { 247, K(null) }, { 252, K(null, fight: true, dur: 5) }, { 229, K(null, dur: 8) }, { 238, K(null, dur: 4) }, { 235, K(null) }, { 70, K(null) },
            { 126, K(null, "party", dur: 60) }, { 127, K(null, "party", dur: 60) }, { 129, K(null, "party", dur: 60) }, { 278, K(null, "party", dur: 60) },
        };

        static int DefaultRank(string kind) => kind == "shield" ? 2 : kind == "switch" ? 1 : kind == "summon" ? 4 : kind == "party" ? 6 : 5;

        public static string CleanName(string s) => string.Join(" ", (s ?? "").ToLowerInvariant().Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries));

        public static SupportInfo Info(Spell s)
        {
            SupportKind k;
            bool known = Kinds.TryGetValue(s.Id, out k);
            if (!known) k = new SupportKind();
            var bar = new List<string>();
            if (k.Bar != null) foreach (var n in k.Bar) bar.Add(n.ToLowerInvariant());
            bar.Add((s.Name ?? "").ToLowerInvariant());
            return new SupportInfo
            {
                Bar = bar.ToArray(), Kind = k.Kind, Auto = k.Auto, Fight = k.Fight, Dur = k.Dur, Haste = k.Haste, ExpectBar = k.ExpectBar, Capped = k.Capped, Minion = k.Minion,
                Minions = k.Minions, Keep = k.Keep, Rank = k.Rank != 0 ? k.Rank : DefaultRank(k.Kind), Known = known,
            };
        }

        /// <summary>A utility the helper never casts by itself (by id, name or words): light, rope, teleport home, dashes.</summary>
        public static bool IsUtility(Spell s)
        {
            if (s == null) return false;
            if (NeverIds.Contains(s.Id) || NeverNames.Contains(CleanName(s.Name))) return true;
            return s.Words.Length > 0 && NeverWords.Contains(CleanName(s.Words));
        }

        /// <summary>May this spell stand in the section? "ok" or the reason: entry, words, group, target, utility.</summary>
        public static string Eligible(Spell s)
        {
            if (s == null || s.IsRune) return "entry";
            if (s.Words.Length == 0) return "words";
            if (s.Group != 3) return "group";
            if (s.Words.IndexOf('"') >= 0 || HelperLogic.NeedsTarget(s)) return "target";
            if (IsUtility(s)) return "utility";
            return "ok";
        }

        public sealed class Candidate { public Spell Spell; public SupportInfo Info; }

        /// <summary>The eligible spells the character can cast, in the order of the section: kind rank, then the stronger (higher level) first.</summary>
        public static List<Candidate> Candidates(IEnumerable<Spell> spells, Func<int, bool> canCast)
        {
            var o = new List<Candidate>();
            foreach (var s in spells) if (Eligible(s) == "ok" && (canCast == null || canCast(s.Id))) o.Add(new Candidate { Spell = s, Info = Info(s) });
            o.Sort((a, b) =>
            {
                if (a.Info.Rank != b.Info.Rank) return a.Info.Rank.CompareTo(b.Info.Rank);
                if (a.Spell.Level != b.Spell.Level) return b.Spell.Level.CompareTo(a.Spell.Level);
                return a.Spell.Id.CompareTo(b.Spell.Id);
            });
            return o;
        }

        static string AutoSlot(Candidate c)
        {
            if (IsUtility(c.Spell)) return null;
            if (c.Info.Known) return c.Info.Auto;
            if (c.Spell.Name.Trim().Length == 0) return null;
            return c.Spell.Cooldown > MaxAutoCooldownMs ? null : "support";
        }

        /// <summary>What Auto setup puts in the section: the shields, vigils and summons first, the fight buffs after them, at most 8.</summary>
        public static List<int> AutoPlan(IEnumerable<Spell> spells, Func<int, bool> canCast)
        {
            var support = new List<int>();
            var buffs = new List<int>();
            foreach (var c in Candidates(spells, canCast))
            {
                string slot = AutoSlot(c);
                if (slot != "support" && slot != "timer") continue;
                bool fightBuff = c.Info.Fight && c.Info.Kind == "buff";
                if (fightBuff) buffs.Add(c.Spell.Id); else if (support.Count < SupportMax) support.Add(c.Spell.Id);
            }
            foreach (int id in buffs) if (support.Count < SupportMax) support.Add(id);
            return support;
        }

        /// <summary>What Auto setup puts where (autoPlan): the Support ids and the Timer rules. A fight buff that finds no free Support row (a Bone Lord's army fills the section) stays a Timer rule,
        /// so no buff is lost; the rule's cooldown is the longer of the spell's cooldown and its effect, plus one second. At most TimerMax rules.</summary>
        public static List<int> AutoPlanFull(IEnumerable<Spell> spells, Func<int, bool> canCast, out List<SupportTimerRule> timers)
        {
            var support = new List<int>();
            var buffs = new List<Candidate>();
            var rules = new List<SupportTimerRule>();
            Action<Candidate> addTimer = c =>
            {
                if (rules.Count >= TimerMax) return;
                int cd = Math.Max((int)Math.Ceiling(c.Spell.Cooldown / 1000.0), c.Info.Dur) + 1;
                rules.Add(new SupportTimerRule { Id = c.Spell.Id, Words = c.Spell.Words, Name = c.Spell.Name, Cooldown = cd });
            };
            foreach (var c in Candidates(spells, canCast))
            {
                string slot = AutoSlot(c);
                if (slot == "timer") addTimer(c);
                else if (slot == "support" && c.Info.Fight && c.Info.Kind == "buff") buffs.Add(c);
                else if (slot == "support" && support.Count < SupportMax) support.Add(c.Spell.Id);
            }
            foreach (var c in buffs) { if (support.Count < SupportMax) support.Add(c.Spell.Id); else addTimer(c); }
            timers = rules;
            return support;
        }

        /// <summary>The Timer rules after the plan: replace drops the player's; else the player's stay and the planned ones whose words are not there yet are added.</summary>
        public static List<SupportTimerRule> MergeTimers(IList<SupportTimerRule> current, IList<SupportTimerRule> planned, bool replace)
        {
            var o = new List<SupportTimerRule>();
            var words = new HashSet<string>();
            if (!replace) foreach (var r in current) { o.Add(r); words.Add(r.Words.ToLowerInvariant()); }
            foreach (var r in planned) if (o.Count < TimerMax && words.Add(r.Words.ToLowerInvariant())) o.Add(r);
            return o;
        }

        /// <summary>Is this Timer rule due? Enabled, attacking a monster, outside a protection zone, its cooldown over since the last cast, and the first casts of the rules a stagger apart
        /// (the support spells share the support group's 2 s cooldown on the server).</summary>
        public static bool TimerDue(SupportTimerRule r, double lastCastMs, double now, bool attacking, bool pz, double lastAnyMs)
        {
            if (!r.Enabled || !attacking || pz || r.Words.Length == 0) return false;
            if (!double.IsNaN(lastCastMs) && now - lastCastMs < r.Cooldown * 1000.0) return false;
            if (double.IsNaN(lastCastMs) && !double.IsNaN(lastAnyMs) && now - lastAnyMs < TimerStaggerMs) return false;
            return true;
        }
        public const double TimerStaggerMs = 2500;

        /// <summary>The list after Auto setup. replace: the plan's ids; else the player's rows stay and new ids go below (up to 8).</summary>
        public static List<SupportSlot> MergeSlots(IList<SupportSlot> current, IList<int> planned, bool replace)
        {
            var o = new List<SupportSlot>();
            var have = new HashSet<int>();
            if (!replace)
                foreach (var s in current) if (o.Count < SupportMax && have.Add(s.Id)) o.Add(new SupportSlot { Id = s.Id, Enabled = s.Enabled });
            foreach (int id in planned) { if (o.Count >= SupportMax) break; if (have.Add(id)) o.Add(new SupportSlot { Id = id }); }
            return o;
        }

        /// <summary>Why a saved row can never work again (a utility, a spell that is not a support spell any more), or null.</summary>
        public static string DeadReason(Spell s)
        {
            if (s == null) return null;
            string why = Eligible(s);
            if (why == "utility") return "utility";
            if (s.Group != 0 && s.Group != 3 && !s.IsRune) return "group";
            return null;
        }

        public static int KeepCount(SupportInfo info, int level)
        {
            int n = 0;
            if (info.Keep != null) foreach (var step in info.Keep) if (level >= step[0]) n = step[1];
            return n;
        }

        static string ManaOk(SupportContext ctx, Spell s, int reserve)
        {
            if (s.Mana <= 0) return null;
            if (ctx.Mana < s.Mana) return "mana";
            if (ctx.MaxMana > 0 && (ctx.Mana - s.Mana) * 100.0 / ctx.MaxMana < reserve) return "reserve";
            return null;
        }

        /// <summary>Is the effect on us? true / false, or null when nothing tells (never cast, or a vigil: never cast blind). No buff bar: the spell's
        /// own duration, else at least a minute (or its cooldown) since our last cast.</summary>
        static bool? Active(SupportState st, SupportInfo info, Spell s, SupportContext ctx, double now)
        {
            bool? fromBar = ctx.BuffActive != null ? ctx.BuffActive(info.Bar) : null;
            if (info.Kind == "switch")
            {
                // a vigil the bar showed on goes off without a cast of ours settling: the player switched it off. The helper leaves it off (TakeUserOff unticks the row)
                // and not within the grace of a death, a login or a teleport (NoteClear): the buffs go and come back then.
                bool was;
                bool hadState = st.BarOn.TryGetValue(s.Id, out was);
                if (fromBar != null) st.BarOn[s.Id] = fromBar.Value;
                double settle;
                st.SettleUntil.TryGetValue(s.Id, out settle);
                if (fromBar == false && hadState && was && settle <= now && st.GraceUntil <= now) st.UserOff[s.Id] = now;
                else if (fromBar == true) st.UserOff.Remove(s.Id);
            }
            if (info.Haste && ctx.Hasted != null && ctx.Hasted() == true) fromBar = true;   // a haste shows in the player's own state even where the bar has no entry
            if (fromBar == true)
            {
                st.Seen.Add(s.Id); st.SawSince.Add(s.Id); st.Misses[s.Id] = 0;
                return true;
            }
            if (info.Kind == "switch" && fromBar == null) return null;   // a vigil is never cast blind
            double at;
            bool cast = st.CastAt.TryGetValue(s.Id, out at);
            if (fromBar == false && (st.Seen.Contains(s.Id) || !cast)) return false;
            if (!cast) return null;
            if (info.Dur > 0) return now < at + info.Dur * 1000.0;
            return now < at + Math.Max(RecastMinMs, s.Cooldown);
        }

        /// <summary>How many casts of this spell in a row were not followed by its buff (the last one counts once the wait is over).</summary>
        public static int Unanswered(SupportState st, int id)
        {
            int n; st.Misses.TryGetValue(id, out n);
            if (st.CastAt.ContainsKey(id) && !st.SawSince.Contains(id)) n++;
            return n;
        }

        public const double UserOffConfirmMs = 2000, SessionGraceMs = 10000;

        /// <summary>The vigils the player switched off by hand: their rows are unticked, so the helper does not switch them on again until the player ticks the row. Returns the ids.
        /// A drop of two or more vigils in one tick (a death, a cleanse) or one close to a death, login or teleport (NoteClear) is not the player's. now NaN: every mark.</summary>
        public static List<int> TakeUserOff(SupportState st, HelperSupportConfig cfg, double now)
        {
            var o = new List<int>();
            if (st == null || cfg == null || st.UserOff.Count == 0) return o;
            var same = new Dictionary<double, int>();
            foreach (var at in st.UserOff.Values) { same.TryGetValue(at, out int n); same[at] = n + 1; }
            foreach (var id in new List<int>(st.UserOff.Keys))
            {
                double at = st.UserOff[id];
                bool near = !double.IsNaN(st.ClearAt) && at >= st.ClearAt - UserOffConfirmMs && at <= Math.Max(st.ClearAt + UserOffConfirmMs, st.GraceUntil);
                if (same[at] > 1 || near) st.UserOff.Remove(id);
            }
            foreach (var slot in cfg.Slots)
            {
                if (!st.UserOff.TryGetValue(slot.Id, out double at)) continue;
                bool due = double.IsNaN(now) || now - at >= UserOffConfirmMs;
                if (due && slot.Enabled) { slot.Enabled = false; o.Add(slot.Id); }
            }
            return o;
        }

        /// <summary>A death, a login or a teleport now: a vigil drop close to it is not the player's. graceMs: how long a bar drop is not read as the player's.</summary>
        public static void NoteClear(SupportState st, double now, double graceMs = UserOffConfirmMs) { st.ClearAt = now; st.GraceUntil = now + graceMs; }

        /// <summary>Why this spell may not be cast now (null: it may). Consumes nothing.</summary>
        public static string Why(SupportState st, HelperSupportConfig cfg, SupportSlot slot, SupportContext ctx)
        {
            double now = ctx.Now;
            var spell = ctx.SpellOf(slot.Id);
            if (spell == null) return "unknown";
            string eligible = Eligible(spell);
            if (eligible == "utility") return "utility";
            var info = Info(spell);
            if (!slot.Enabled) return "off";
            if (info.Fight && !ctx.Attacking) return "nofight";
            if (info.Kind == "party" && !(ctx.InParty != null && ctx.InParty(spell))) return "noparty";
            if (ctx.Castable != null && !ctx.Castable(spell)) return "level";
            string mana = ManaOk(ctx, spell, cfg.Reserve);
            if (mana != null) return mana;
            if (ctx.OnCooldown != null && ctx.OnCooldown(spell)) return "cooldown";
            double settle, last;
            if (st.SettleUntil.TryGetValue(spell.Id, out settle) && settle > now) return "wait";
            bool cast = st.CastAt.TryGetValue(spell.Id, out last);
            if (info.Kind == "summon" && cast && now - last < SummonGapMs) return "wait";
            if (info.Capped)
            {
                var count = ctx.SummonCount != null ? ctx.SummonCount(info.Minion != null ? new[] { info.Minion } : new string[0]) : null;
                if (count == null) return "nocount";
                int cap = ctx.SummonCap != null ? ctx.SummonCap() : SummonCapDefault;
                if (count.Value.Key >= cap) return "full";
                if (info.Minion != null && count.Value.Value > 0) return "have";
            }
            bool counted = info.Capped;
            if (!info.Capped && info.Minions != null && ctx.SummonCount != null)
            {
                var own = ctx.SummonCount(info.Minions);
                if (own != null)
                {
                    counted = true;
                    if (own.Value.Value >= KeepCount(info, ctx.Level)) return "have";
                }
            }
            if (!counted)
            {
                bool? active = Active(st, info, spell, ctx, now);
                if (active == true) return "active";
                if (info.Kind == "switch" && st.UserOff.ContainsKey(spell.Id)) return "useroff";
                if (info.Kind == "switch" && active == null) return "nobar";
            }
            if (info.ExpectBar && cast)
            {
                int n = Unanswered(st, spell.Id);
                if (n >= 1 && now - last < Math.Min(RecastMinMs * Math.Pow(2, n - 1), NoBuffMaxMs)) return "backoff";
            }
            int refused = ctx.Refusals != null ? ctx.Refusals(spell) : 0;
            if (refused >= RefuseLimit && cast && now - last < RefusedHoldMs) return "backoff";
            if (ctx.Blocked != null) { string b = ctx.Blocked(spell); if (b != null) return b; }
            return null;
        }

        /// <summary>The next spell to cast: the first row that may go out. Every row's reason lands in st.Status (the rows show it).</summary>
        public static Spell Pick(SupportState st, HelperSupportConfig cfg, SupportContext ctx, out string overall)
        {
            st.Status.Clear();
            overall = "idle";
            if (!cfg.Enabled) { overall = "disabled"; return null; }
            if (!ctx.Online) { overall = "offline"; return null; }
            if (!ctx.HelperOn) { overall = "helperoff"; return null; }
            if (ctx.InPz) { overall = "pz"; return null; }
            Spell winner = null;
            foreach (var slot in cfg.Slots)
            {
                string why = Why(st, cfg, slot, ctx);
                if (why == null)
                {
                    if (winner != null) why = "queued";
                    else if (ctx.Channeling) why = "casting";
                    else
                    {
                        var spell = ctx.SpellOf(slot.Id);
                        if (ctx.Allowed != null && !ctx.Allowed(spell)) why = "rate";
                        else { winner = spell; why = "cast"; }
                    }
                }
                st.Status[slot.Id] = why;
            }
            if (winner != null) overall = "cast";
            return winner;
        }

        /// <summary>The cast went out.</summary>
        public static void NoteCast(SupportState st, Spell s, double now)
        {
            var info = Info(s);
            if (info.ExpectBar) { st.Misses[s.Id] = st.CastAt.ContainsKey(s.Id) ? Unanswered(st, s.Id) : 0; st.SawSince.Remove(s.Id); }
            st.CastAt[s.Id] = now;
            st.SettleUntil[s.Id] = now + (info.Kind == "switch" ? SwitchSettleMs : SettleMs);
            st.Casts++;
        }

        /// <summary>The words the Support rows show for a reason.</summary>
        public static string ReasonText(string why)
        {
            switch (why)
            {
                case "cast": return Loc.T("Casting");
                case "active": return Loc.T("Active");
                case "cooldown": return Loc.T("Cooldown");
                case "wait": return Loc.T("Waiting");
                case "nofight": return Loc.T("Waits for a fight");
                case "mana": return Loc.T("No mana");
                case "reserve": return Loc.T("Mana reserve");
                case "level": return Loc.T("Not castable");
                case "off": return Loc.T("Off");
                case "queued": return Loc.T("Next");
                case "rate": return Loc.T("Rate limit");
                case "casting": return Loc.T("Casting another spell");
                case "backoff": return Loc.T("Resting");
                case "have": return Loc.T("Summon is out");
                case "full": return Loc.T("Summon limit");
                case "nocount": return Loc.T("Cannot count summons");
                case "nobar": return Loc.T("Needs the buff bar");
                case "useroff": return Loc.T("Switched off by you");
                case "noparty": return Loc.T("Needs a party");
                case "utility": return Loc.T("Utility, never cast");
                case "unknown": return Loc.T("Unknown spell");
                default: return why ?? "";
            }
        }
    }
}
