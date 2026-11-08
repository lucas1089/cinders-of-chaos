// The helper loop's extras (track Q): healing runes, attack runes on the target, party and friend heals, food, the Support section.
// Same pacing and guards as the main client's helper: every rune goes through HelperTimers (one second per kind), every cast through
// HelperTimers and HelperCasts, an ally heal has a gap per target and a budget (HelperAlly), nothing runs in a protection zone.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed partial class HelperEngine
    {
        public const double EveryAlly = 250, EveryRoutine = 1000, EverySupport = 250, EveryRunes = 250;

        /// <summary>The Everfull flasks the character carries (opcode 116); null runs without it.</summary>
        public EverfullHeld Held;
        public readonly HelperAllyState AllyState = new HelperAllyState();
        public readonly SupportState SupportRun = new SupportState();
        /// <summary>What the Support rows show: the reason of each row at the last pass, and the overall one.</summary>
        public string SupportWhy = "idle";
        public int RunesUsed, AllyHeals, Meals;
        double lastMeal = -1;

        IHelperHostExt HostExt => Host as IHelperHostExt;

        void ResetExtras()
        {
            AllyState.Last.Clear(); AllyState.Sent.Clear();
            SupportRun.Reset();
            lastMeal = -1;
        }

        // ------------------------------------------------------------------------------------ runes
        bool RuneReady(int id, string channel) => Timers.UseReady(channel, Host.Now) && Host.ItemCount(id) > 0;

        bool RuneClassOk(HelperRuneInfo rune)
        {
            var ext = HostExt;
            return rune.Vocations == null || ext == null || ext.Vocation <= 0 || Array.IndexOf(rune.Vocations, ext.Vocation) >= 0;
        }

        /// <summary>Uses the rune on a creature (0: yourself); true when the use went out.</summary>
        bool UseRune(int id, uint creature, string channel)
        {
            if (!RuneReady(id, channel)) return false;
            bool sent;
            var ext = HostExt;
            if (creature == 0) { Host.UseOnSelf(id); sent = true; }
            else sent = ext != null && ext.UseOnCreature(id, creature);
            if (!sent) return false;
            Timers.Used(channel, Host.Now);
            RunesUsed++;
            return true;
        }

        void RuneHealTick(double hp)
        {
            int id = HelperRunes.PickHeal(Config.RuneHeal, hp, rid => RuneReady(rid, HelperTimers.HealRune));
            if (id > 0) UseRune(id, 0, HelperTimers.HealRune);
        }

        /// <summary>An attack rune on the target (while the spell rotation is on): the rune whose area hits enough monsters, in priority order.</summary>
        void RunesTick()
        {
            if (!Config.MagicShooter) return;
            uint target = Host.AttackTarget;
            if (target == 0) return;
            var pos = Host.Position;
            var list = Gather(pos);
            HelperCreature tc;
            if (!InList(list, target, out tc)) return;
            var row = HelperRunes.PickAttack(Config.RuneAttack, true, tc.Position, tc.Health, pos, list,
                p => p.Z == pos.Z && HelperLogic.InReach(pos, p),
                id => { var info = HelperRunes.Info(id); return info != null && RuneClassOk(info) && RuneReady(id, HelperTimers.AttackRune); });
            if (row != null) UseRune(row.Id, target, HelperTimers.AttackRune);
        }

        // ------------------------------------------------------------------------------------ party and friend heals
        bool CastWords(Spell s, string words, string channel)
        {
            double t = Host.Now;
            if (!Timers.CastAllowed(channel, words, t)) return false;
            Host.Say(words);
            Casts.Cast(s.Id, GroupsOf(s), t);
            Casted++;
            return true;
        }

        Spell AllySpell(int id)
        {
            var ext = HostExt;
            var entry = (HelperAlly.SingleOf(id) ?? HelperAlly.GroupOf(id));
            if (entry == null) return null;
            if (entry.Vocations != null && ext != null && ext.Vocation > 0 && Array.IndexOf(entry.Vocations, ext.Vocation) < 0) return null;
            return Book.ById(id);
        }

        void AllyTick(bool pz)
        {
            var ext = HostExt;
            var cfg = Config.Allies;
            if (ext == null || pz || !cfg.Active) return;
            double hp = Pct(Host.Health, Host.MaxHealth);
            if (HelperAlly.SelfFirst(Config, hp)) return;
            var pos = Host.Position;
            var cands = HelperAlly.Candidates(cfg, ext.Players(), pos);
            if (cands.Count == 0) return;
            var pick = HelperAlly.Pick(cfg, pos, cands, false, Pct(Host.Mana, Host.MaxMana), AllySpell, s => Ready(s, false),
                id => { var info = HelperRunes.Info(id); return info != null && RuneClassOk(info) && RuneReady(id, HelperTimers.HealRune); });
            if (pick == null) return;
            double t = Host.Now;
            string key = pick.Target != null ? pick.Target.Id.ToString() : "group" + (pick.Spell != null ? pick.Spell.Id : 0);
            if (!HelperAlly.Allowed(AllyState, key, t)) return;
            bool went = pick.Kind == "rune" ? UseRune(pick.RuneId, pick.Target.Id, HelperTimers.HealRune) : CastWords(pick.Spell, pick.Words, HelperTimers.Heal);
            if (went) { HelperAlly.Noted(AllyState, key, t); AllyHeals++; }
        }

        // ------------------------------------------------------------------------------------ food
        void FoodTick()
        {
            var ext = HostExt;
            if (!Config.AutoEat || ext == null || !Timers.UseReady(HelperTimers.Food, Host.Now)) return;
            int id = HelperFood.Pick(ext.Hungry, Host.Now, lastMeal, Host.ItemCount);
            if (id <= 0 || !ext.UseItem(id)) return;
            Timers.Used(HelperTimers.Food, Host.Now);
            lastMeal = Host.Now;
            Meals++;
        }

        // ------------------------------------------------------------------------------------ the Support section
        SupportContext SupportCtx(bool pz)
        {
            var ext = HostExt;
            return new SupportContext
            {
                Now = Host.Now, Online = true, HelperOn = Config.Enabled, InPz = pz, Attacking = Host.AttackTarget != 0, Channeling = Casts.Channeling(Host.Now),
                Mana = Host.Mana, MaxMana = Host.MaxMana, Level = Host.Level,
                SpellOf = Book.ById,
                Castable = s => HelperLogic.Castable(s, Host.Level, Host.Mana, Host.MaxMana) && (!Book.Loaded || Book.Status(s) == SpellStatus.Ready),
                OnCooldown = s => Book.CooldownLeft(s) > 0,
                Blocked = s => Casts.Blocked(s.Id, GroupsOf(s), Host.Now, true),
                Refusals = s => Casts.Fails(s.Id),
                InParty = s => { if (ext == null) return false; foreach (var p in ext.Players()) if (p.IsSelf && HelperAlly.IsPartyShield(p.Shield)) return true; return false; },
                SummonCount = names =>
                {
                    if (ext == null) return null;
                    var all = ext.OwnSummons();
                    int own = 0;
                    foreach (var n in all) if (names != null && Array.IndexOf(names, n) >= 0) own++;
                    return new KeyValuePair<int, int>(all.Count, own);
                },
                SummonCap = () => HelperSupport.SummonCap(ext != null ? ext.Vocation : 0, Host.Level),
                Allowed = s => Timers.CastAllowed(HelperTimers.Support, s.Words, Host.Now),
            };
        }

        void SupportTick(bool pz)
        {
            if (!Book.Loaded && Config.Support.Slots.Count == 0) return;
            string overall;
            var spell = HelperSupport.Pick(SupportRun, Config.Support, SupportCtx(pz), out overall);
            SupportWhy = overall;
            if (spell == null) return;
            Host.Say(spell.Words);
            Casts.Cast(spell.Id, GroupsOf(spell), Host.Now);
            Casted++;
            HelperSupport.NoteCast(SupportRun, spell, Host.Now);
        }

        /// <summary>The Support part of Auto setup: fills the section from the class's support spells when it is empty (a list the player made stays).
        /// Returns how many rows it wrote.</summary>
        public int AutoSupport(bool replace = false)
        {
            if (!Book.Loaded) return 0;
            if (!replace && Config.Support.Slots.Count > 0) return 0;
            var plan = HelperSupport.AutoPlan(Book.Spells, CanCast);
            var merged = HelperSupport.MergeSlots(Config.Support.Slots, plan, replace);
            Config.Support.Slots.Clear();
            Config.Support.Slots.AddRange(merged);
            return merged.Count;
        }
    }
}
