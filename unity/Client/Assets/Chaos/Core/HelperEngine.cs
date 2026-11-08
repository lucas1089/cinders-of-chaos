// The helper's loop: heals by health thresholds (spells and potions), mana training, Auto Haste, Auto Target and the five-slot spell
// rotation (the magic shooter). A port of the tick of game_helper/helper.lua (healTick, trainingTick, hasteTick, targetTick, shooterTick).
// It decides and talks to the game only through IHelperHost, so Core.Tests drives it with a fake game and a fake clock.
//
// Pacing, as the main client's: the loop runs every 50 ms and each part has its own period (heal 250, mana 100, haste 500, target 250,
// shooter 100 ms); every cast goes through HelperTimers (per channel at most 4 casts a second, the same words not within 500 ms; a potion at
// most every 600 ms) and HelperCasts (a cast waits for the server's cooldown packet, a refused one backs off). One shooter cast per tick.
// A hit taken heals at once (OnHealthChanged), at most every 100 ms. When the server sent nothing for 2.5 s nothing is sent until it is back.
// Track Q added runes, party and friend heals, food, the Everfull held flask, the Support section and shooter profiles (HelperEngineExtras.cs).
// Phase 7 track X added Follow, Auto sell, the exercise weapon, the potion gate for closed backpacks, the line-of-sight check of the area counts, ally heals
// and attack runes, and the level-up notice (Phase7XHelper.cs).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public interface IHelperHost
    {
        /// <summary>The ms clock (GameSession.Now).</summary>
        double Now { get; }
        int Health { get; }
        int MaxHealth { get; }
        int Mana { get; }
        int MaxMana { get; }
        int Level { get; }
        Pos Position { get; }
        Dir Facing { get; }
        bool InProtectionZone { get; }
        bool Hasted { get; }
        /// <summary>The creature being attacked (0: none).</summary>
        uint AttackTarget { get; }
        /// <summary>Following a creature: the fight systems pause.</summary>
        bool Following { get; }
        /// <summary>Milliseconds since the server last sent anything.</summary>
        double MsSinceLastRead { get; }
        /// <summary>The monsters in view: not players, not summons, alive. The engine keeps the ones in reach.</summary>
        IList<HelperCreature> Monsters();
        void Say(string words);
        void Attack(uint id);
        void CancelAttack();
        void Turn(Dir d);
        /// <summary>How many of the item (a client id) are at hand in the equipment and the open bags.</summary>
        int ItemCount(int clientId);
        /// <summary>Uses the item on yourself (0x84 with your own creature id).</summary>
        void UseOnSelf(int clientId);
    }

    public sealed partial class HelperEngine
    {
        public const double TickMs = 50, FreezeMs = 2500, FreezeResumeMs = 1500, SummonsRadius = 6;
        public const double EveryHeal = 250, EveryMana = 100, EveryHaste = 500, EveryTarget = 250, EveryShooter = 100, QuickHealGapMs = 100;

        public HelperConfig Config = new HelperConfig();
        public readonly SpellBook Book;
        public readonly IHelperHost Host;
        public readonly HelperTimers Timers = new HelperTimers();
        public readonly HelperCasts Casts = new HelperCasts();
        public readonly HelperLogic.HasteState Haste = new HelperLogic.HasteState();
        /// <summary>Why the fight systems are paused now: "helperoff", "pz", "follow", "freeze" or null (they run). A pause never touches a setting.</summary>
        public string Why;
        /// <summary>The creature Auto Target keeps attacking.</summary>
        public uint LockedTarget;
        /// <summary>Auto Target class by creature id: 1 loot goblin, 2 boss, 3 special, 4 normal (AutoTargetCore.ClassOf, from the name and the monster bar). Null: no class rule.
        /// With it a goblin, boss or special monster in reach comes before every normal one, and a lock on a worse class is dropped when a better one is in reach.</summary>
        public Func<uint, int> RankOf;
        /// <summary>The re-sends of the locked target: dropped after 3 in 3 s (TargetGuard, game_targetguard).</summary>
        public readonly TargetLock LockGuard = new TargetLock();
        public int Casted, Potions;

        double lastTick = -1, frozenUntil;
        bool pzWas;
        readonly Dictionary<string, double> lastRun = new Dictionary<string, double>();

        public HelperEngine(SpellBook book, IHelperHost host) { Book = book; Host = host; }

        // ------------------------------------------------------------------------------------ cooldown packets
        public void OnSpellCooldown(int id) { Casts.ConfirmSpell(id, Host.Now); }
        public void OnGroupCooldown(int group) { Casts.ConfirmGroup(group, Host.Now); }

        // ------------------------------------------------------------------------------------ spells
        static IEnumerable<int> GroupsOf(Spell s) { if (s.Group != 0) yield return s.Group; }

        /// <summary>Can this spell go out now: the character can cast it, the mana is there, it is off cooldown, the answer to its last cast is in.</summary>
        bool Ready(Spell s, bool holdGroups = true)
        {
            if (s == null || s.IsRune || s.Words.Length == 0) return false;
            if (Book.Loaded && Book.Status(s) != SpellStatus.Ready) return false;
            if (!HelperLogic.Castable(s, Host.Level, Host.Mana, Host.MaxMana)) return false;
            if (Book.CooldownLeft(s) > 0) return false;
            return Casts.Blocked(s.Id, GroupsOf(s), Host.Now, holdGroups) == null;
        }

        bool Cast(Spell s, string channel = null)
        {
            double t = Host.Now;
            if (!Timers.CastAllowed(channel ?? HelperLogic.Channel(s), s.Words, t)) return false;
            Host.Say(s.Words);
            Casts.Cast(s.Id, GroupsOf(s), t);
            Casted++;
            return true;
        }

        static double Pct(int v, int max) => max <= 0 ? 100 : v * 100.0 / max;

        // ------------------------------------------------------------------------------------ the parts
        public void HealTick()
        {
            double hp = Pct(Host.Health, Host.MaxHealth), mp = Pct(Host.Mana, Host.MaxMana);
            int id = HelperLogic.PickHeal(Config.Heals, hp, sid => Ready(Book.ById(sid), false));
            if (id > 0) { var s = Book.ById(id); if (s != null) Cast(s, HelperTimers.Heal); }
            string kind;
            int potion = HelperPotions.Pick(Config.Potions, hp, mp, pid => PotionAvailable(pid), out kind, Held != null ? (Func<int, int>)(pid => Held.Resolve(pid, Host.Level)) : null);
            if (potion > 0) UsePotion(potion);
            RuneHealTick(hp);
        }

        bool PotionAvailable(int id)
        {
            if (!HelperPotions.CanDrink(id, Host.Level)) return false;
            if (!Timers.UseReady(HelperTimers.Potion, Host.Now)) return false;
            return Probeable(id, Host.ItemCount(id));   // a potion in a closed backpack is probed by id (the potion gate)
        }

        bool UsePotion(int id)
        {
            double t = Host.Now;
            int have = Host.ItemCount(id);
            if (!Timers.UseReady(HelperTimers.Potion, t) || !Probeable(id, have)) return false;
            if (have > 0) Host.UseOnSelf(id);
            else
            {
                var p7 = HostP7;
                if (p7 == null || !p7.UseByIdOnCreature(id, 0)) return false;
                Gate.Used(id, t, have);
                GateProbes++;
            }
            if (have > 0) Gate.Used(id, t, have);
            Timers.Used(HelperTimers.Potion, t);
            Potions++;
            return true;
        }

        void TrainingTick()
        {
            if (!HelperLogic.TrainingDue(Config.Training, Pct(Host.Mana, Host.MaxMana))) return;
            if (Casts.Channeling(Host.Now)) return;
            var s = Book.ById(Config.Training.Id);
            if (s != null && Ready(s)) Cast(s);
        }

        void HasteTick(bool pz)
        {
            var row = Config.Haste;
            if (!row.Enabled || row.Id <= 0) return;
            Haste.Observe(Host.Hasted);
            if (!HelperLogic.HasteDue(row, Host.Hasted, Host.Now, Haste.Last, Haste.Misses, pz)) return;
            if (Casts.Channeling(Host.Now)) return;
            var s = Book.ById(row.Id);
            if (s != null && Ready(s) && Cast(s, HelperTimers.Support)) Haste.Cast(Host.Now);
        }

        List<HelperCreature> Gather(Pos pos)
        {
            var o = new List<HelperCreature>();
            foreach (var c in Host.Monsters()) if (c.Health > 0 && HelperLogic.InReach(pos, c.Position)) o.Add(c);
            return o;
        }

        static bool InList(IList<HelperCreature> list, uint id, out HelperCreature found)
        {
            foreach (var c in list) if (c.Id == id) { found = c; return true; }
            found = default(HelperCreature);
            return false;
        }

        /// <summary>Auto Target: keeps the locked creature while it lives and is in reach, else picks by the mode (A..H) and attacks.</summary>
        void TargetTick()
        {
            if (!Config.AutoTarget) return;
            var pos = Host.Position;
            var list = Gather(pos);
            HelperCreature locked;
            if (LockedTarget != 0 && InList(list, LockedTarget, out locked))
            {
                var act = LockGuard.Action(LockedTarget, Host.AttackTarget, Host.Now);
                if (act == LockAction.Attack) Host.Attack(LockedTarget);
                bool dropLock = act == LockAction.Drop;
                if (!dropLock && RankOf != null && !AutoTargetCore.KeepLock(Cand(locked, pos), Cands(list, pos), null, true)) dropLock = true;   // a better class came into reach
                if (!dropLock) return;
            }
            LockedTarget = 0;
            var cands = new List<HelperCreature>();
            foreach (var c in list)
            {
                int hits = 0;
                if (Config.AutoTargetMode == HelperLogic.ModeHits)
                    hits = HelperLogic.CountHits(c.Position, Dir.East, Circle3, list, true);
                cands.Add(new HelperCreature(c.Id, c.Position, c.Health, hits));
            }
            HelperCreature pick;
            if (!HelperLogic.PickByMode(cands, pos, Config.AutoTargetMode, out pick)) return;
            if (RankOf != null)
            {
                var first = AutoTargetCore.PickPriority(Cands(list, pos), null);   // a goblin, boss or special monster in reach comes first
                if (first != null && InList(list, first.Id, out var better)) pick = better;
            }
            if (Host.AttackTarget != pick.Id) Host.Attack(pick.Id);
            LockedTarget = pick.Id;
        }

        AutoCand Cand(HelperCreature c, Pos from) => new AutoCand { Id = c.Id, Dist = HelperLogic.Distance(from, c.Position), Health = c.Health, Rank = RankOf != null ? RankOf(c.Id) : AutoTargetCore.RankNormal };

        List<AutoCand> Cands(IList<HelperCreature> list, Pos from)
        {
            var o = new List<AutoCand>();
            foreach (var c in list) o.Add(Cand(c, from));
            return o;
        }

        // the area the "most hits" mode counts around a creature (3 x 3 around the middle)
        static readonly int[][] Circle3 = { new[] { 1, 1, 1 }, new[] { 1, 3, 1 }, new[] { 1, 1, 1 } };

        /// <summary>How many monsters the slot's spell would hit now, and the facing to cast it at (hasDir false: keep the facing).</summary>
        int HitsOf(HelperSlot slot, Spell spell, Pos pos, IList<HelperCreature> list, uint target, bool hasTarget, Pos targetPos, out bool hasDir, out Dir dir)
        {
            hasDir = false; dir = Dir.North;
            int range = spell.Range;
            var area = HelperLogic.ToMatrix(spell.Area);
            bool needTarget = HelperLogic.NeedsTarget(spell);
            bool targetable = range > 0 && (area == null || needTarget) && !slot.SelfCast;
            if (targetable)
            {
                if (!hasTarget || targetPos.Z != pos.Z || HelperLogic.Distance(pos, targetPos) > range) return 0;
                if (area != null) return HelperLogic.CountHits(targetPos, Dir.East, area, list, true);
                return HelperLogic.CountNear(list, pos, (int)SummonsRadius);
            }
            if (area != null)
            {
                Dir d;
                if (slot.ForceCast && hasTarget && HelperLogic.FacingToward(pos, targetPos, out d))
                {
                    hasDir = true; dir = d;
                    return HelperLogic.CountHits(pos, d, area, list, false, Sight);
                }
                int n;
                var best = HelperLogic.BestDirection(pos, area, list, out n, Sight);
                if (n > 0) { hasDir = true; dir = best; }
                return n;
            }
            if (HelperLogic.IsSelfArea(spell)) return HelperLogic.CountNear(list, pos, HelperCasts.SelfAreaRadius);
            return list.Count > 0 ? 1 : 0;
        }

        void ShooterTick()
        {
            if (!Config.MagicShooter) return;
            if (Casts.Channeling(Host.Now)) return;
            var pos = Host.Position;
            double mp = Pct(Host.Mana, Host.MaxMana);
            var list = Gather(pos);
            uint target = Host.AttackTarget;
            Pos tp = default(Pos);
            bool hasTarget = false;
            if (target != 0 && InList(list, target, out HelperCreature tc)) { tp = tc.Position; hasTarget = true; }
            foreach (var slot in HelperLogic.SlotOrder(Config.Shooter))
            {
                var spell = Book.ById(slot.Id);
                if (spell == null || mp < slot.Percent || !Ready(spell)) continue;
                bool hasDir; Dir dir;
                int hits = HitsOf(slot, spell, pos, list, target, hasTarget, tp, out hasDir, out dir);
                if (!HelperLogic.SlotDue(slot, mp, hits)) continue;
                Dir turn;
                bool turns = HelperLogic.TurnDirection(HelperLogic.IsDirectional(spell), Config.AutoTurn, Host.Facing, pos, hasTarget, tp, hasDir, dir, out turn);
                if (Cast(spell, HelperTimers.Attack))
                {
                    if (turns) Host.Turn(turn);
                    return;   // one cast per tick: the next one waits for the server's answer
                }
            }
        }

        // ------------------------------------------------------------------------------------ the tick
        bool Due(string key, double every)
        {
            double now = Host.Now, last;
            if (lastRun.TryGetValue(key, out last) && now - last < every) return false;
            lastRun[key] = now;
            return true;
        }

        /// <summary>Call every frame; it runs a pass every 50 ms. Needs the character's level and the spell list (Book.Loaded) to do anything useful.</summary>
        public void Tick()
        {
            double t = Host.Now;
            if (lastTick >= 0 && t - lastTick < TickMs) return;
            lastTick = t;
            int vocationNow = HostExt != null ? HostExt.Vocation : 0;
            LevelWatch(vocationNow);      // phase 7 track X: a level-up asks about new spells (Phase7XHelper.cs)
            VocationWatch(vocationNow);   // and a class change takes the old class's spells out
            // the server sent nothing for a while (a save): do not pile packets up for when it is back
            if (Host.MsSinceLastRead > FreezeMs) frozenUntil = t + FreezeResumeMs;
            if (t < frozenUntil) { Why = "freeze"; return; }
            bool pz = Host.InProtectionZone;
            Why = !Config.Enabled ? "helperoff" : pz ? "pz" : Host.Following ? "follow" : null;
            if (pz && !pzWas) { LockedTarget = 0; if (Host.AttackTarget != 0) Host.CancelAttack(); }   // entering a protection zone drops the attack, not the settings
            pzWas = pz;
            P7Tick(pz);   // Follow, Auto sell and the exercise weapon (Phase7XHelper.cs)
            if (Why == "helperoff") { LockedTarget = 0; return; }
            if (Host.MaxHealth <= 0) return;
            if (Due("heal", EveryHeal)) HealTick();
            if (Due("mana", EveryMana)) TrainingTick();
            if (Due("haste", EveryHaste)) HasteTick(pz);
            if (Due("ally", EveryAlly)) AllyTick(pz);
            if (Due("routine", EveryRoutine)) FoodTick();
            if (Due("support", EverySupport)) SupportTick(pz);
            if (Why == null)
            {
                if (Due("target", EveryTarget)) TargetTick();
                if (Due("shooter", EveryShooter)) ShooterTick();
                if (Due("runes", EveryRunes)) RunesTick();
            }
        }

        /// <summary>A hit taken: heal now, not at the next pass (at most every 100 ms).</summary>
        public void OnHealthChanged(int oldHealth, int health)
        {
            if (!Config.Enabled || health >= oldHealth || Host.MaxHealth <= 0 || Host.MsSinceLastRead > FreezeMs) return;
            double now = Host.Now, last;
            if (lastRun.TryGetValue("heal", out last) && now - last < QuickHealGapMs) return;
            lastRun["heal"] = now;
            HealTick();
        }

        /// <summary>The spell ids the character can cast now, for Auto setup (knows it, its class and level).</summary>
        public bool CanCast(int id)
        {
            var s = Book.ById(id);
            return s != null && Book.Status(s) == SpellStatus.Ready;
        }

        /// <summary>The Auto setup button: fills the five slots and the healing rows from the class presets. Returns the message, or null when
        /// the class has no preset for the level or the spell list has not arrived.</summary>
        public string AutoSetup(int vocation)
        {
            if (!Book.Loaded) return null;
            var sel = HelperRotation.Select(vocation, Host.Level, CanCast);
            if (sel == null) return null;
            var slots = HelperRotation.Slots(sel);
            for (int i = 0; i < HelperConfig.Slots; i++)
            {
                Config.Shooter[i] = i < slots.Count ? slots[i] : new HelperSlot { Priority = i + 1 };
            }
            Config.AutoMarker.Clear();
            Config.AutoMarker.AddRange(sel.Ids);
            if (HealingEmpty())
            {
                var heals = HelperRotation.Heals(vocation, Host.Level, CanCast);
                for (int i = 0; i < HelperConfig.HealRows; i++) Config.Heals[i] = i < heals.Count ? heals[i] : new HelperHealRow();
            }
            return HelperRotation.Message(sel, id => { var s = Book.ById(id); return s != null ? s.Name : id.ToString(); });
        }

        public bool HealingEmpty()
        {
            foreach (var h in Config.Heals) if (h.Id != 0) return false;
            return true;
        }

        public void Reset()
        {
            Timers.Reset();
            LockedTarget = 0;
            lastTick = -1; frozenUntil = 0; pzWas = false;
            lastRun.Clear();
            ResetExtras();
            ResetP7();
        }
    }

    /// <summary>Which spells the helper's pickers offer (helper_spells.lua): the server has it with words to say, the character's class lists it and the
    /// level is reached, it is no utility the helper never casts by itself (the vigils, Town Portal, dashes), it needs no typed name or target,
    /// and its kind fits the picker: a healing spell (group 2) for the healing and training rows, an attack spell (attack or special group) for
    /// the shooter, Haste for Auto Haste.</summary>
    public static class HelperPickers
    {
        public static readonly int[] HasteIds = { 6 };
        static readonly HashSet<int> Never = new HashSet<int> { 179, 255, 161, 162, 254, 232 };

        static bool Offered(SpellBook book, Spell s)
        {
            if (s.IsRune || s.Words.Length == 0 || Never.Contains(s.Id)) return false;
            if (s.Words.IndexOf('"') >= 0) return false;   // a spell with a typed name
            return !book.Loaded || book.Status(s) == SpellStatus.Ready;
        }

        public static List<Spell> Healing(SpellBook book)
        {
            var o = new List<Spell>();
            foreach (var s in book.Spells) if (Offered(book, s) && s.Group == 2 && !HelperLogic.NeedsTarget(s)) o.Add(s);
            return o;
        }

        public static List<Spell> Attack(SpellBook book)
        {
            var o = new List<Spell>();
            foreach (var s in book.Spells) if (Offered(book, s) && (s.Group == 1 || s.Group == 4) && s.Kind == "attack") o.Add(s);
            return o;
        }

        public static List<Spell> Haste(SpellBook book)
        {
            var o = new List<Spell>();
            foreach (var s in book.Spells) if (Offered(book, s) && System.Array.IndexOf(HasteIds, s.Id) >= 0) o.Add(s);
            return o;
        }
    }
}
