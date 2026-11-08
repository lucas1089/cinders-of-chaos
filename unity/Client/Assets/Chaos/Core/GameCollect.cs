// The collection, season and crafting models of one session (O433 phase 4, track N): achievements 250, bestiary 253, charms 198, season pass 227,
// seasons 246, daily reward 207, weekly chest 117, cosmetics and unlocks 225, transmog 212, pets 254, professions 195, crafting bench 232,
// crafting tables 91. Each model owns its opcode (Core/Collect*.cs); this file builds them and runs their timers.
using System;

namespace Chaos.Core
{
    public sealed partial class GameSession
    {
        public AchievementsState Achievements { get; private set; }
        public BestiaryState Bestiary { get; private set; }
        public CharmsState Charms { get; private set; }
        public PassState Pass { get; private set; }
        public SeasonState Seasons { get; private set; }
        public DailyState Daily { get; private set; }
        public WeeklyState Weekly { get; private set; }
        public CosmeticsState Cosmetics { get; private set; }
        public TransmogState Transmog { get; private set; }
        public PetsState Pets { get; private set; }
        public ProfessionsState Professions { get; private set; }
        public CraftingState Crafting { get; private set; }
        public CraftTableState CraftTable { get; private set; }
        bool collectAsked;

        /// <summary>The seven crafting skills of the last 0xA1 packet.</summary>
        public SkillValue[] CraftSkills => parser.CraftSkills;

        /// <summary>Called by the constructor, after Ext exists.</summary>
        void InitCollect()
        {
            Func<double> clock = () => Now;
            Achievements = new AchievementsState(Ext) { Clock = clock };
            Bestiary = new BestiaryState(Ext) { Clock = clock };
            Charms = new CharmsState(Ext) { Clock = clock };
            Pass = new PassState(Ext) { Clock = clock };
            Seasons = new SeasonState(Ext) { Clock = clock };
            Daily = new DailyState(Ext) { Clock = clock };
            Weekly = new WeeklyState(Ext) { Clock = clock };
            Cosmetics = new CosmeticsState(Ext) { Clock = clock };
            Transmog = new TransmogState(Ext) { Clock = clock };
            Pets = new PetsState(Ext) { Clock = clock };
            Professions = new ProfessionsState(Ext) { Clock = clock };
            Crafting = new CraftingState(Ext) { Clock = clock };
            CraftTable = new CraftTableState(Ext)
            {
                Clock = clock,
                PlayerPos = () => world.Player != null ? world.Player.Position : (Pos?)null,
                SkillLevel = i => i >= 0 && i < parser.CraftSkills.Length && parser.CraftSkills[i].Level > 0 ? parser.CraftSkills[i].Level : (int?)null,
            };
        }

        /// <summary>Called by Poll: the first requests after the login (the main client waits 500 ms to 3 s) and the timers.</summary>
        void CollectPoll()
        {
            if (!collectAsked && enteredAt >= 0 && Now - enteredAt > 700)
            {
                collectAsked = true;
                Cosmetics.Hello();          // style, chat name colours, wardrobe
                Cosmetics.AskWardrobe();
                Bestiary.Query();           // the kill task tracker
            }
            if (enteredAt >= 0 && Now - enteredAt > 3000 && !seasonSynced) { seasonSynced = true; Seasons.Sync(); }
            Seasons.Tick(Now);
            Pets.Tick(Now);
            CraftTable.Tick(Now);
        }

        bool seasonSynced;
    }
}
