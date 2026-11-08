// The social and market models of a session (O433 phase 4, track M): market, guild, guild wars, party finder, group queue, inspect, leaderboards, chat links,
// factions, Conquest vendor. Each registers its extended opcode in the constructor (InitSocial, called by the GameSession constructor).
using System;

namespace Chaos.Core
{
    public sealed class SocialState
    {
        public readonly MarketPanel Market;
        public readonly GuildPanel Guild;
        public readonly GuildWarPanel GuildWar;
        public readonly PartyFinderPanel PartyFinder;
        public readonly GroupQueuePanel GroupQueue;
        public readonly InspectPanel Inspect;
        public readonly LeaderboardPanel Leaderboard;
        public readonly ChatLinksState Links;
        public readonly FactionsPanel Factions;
        public readonly ConquestPanel Conquest;

        public SocialState(ExtOpcodes ext, Func<double> clock)
        {
            Market = new MarketPanel(ext) { Clock = clock };
            Guild = new GuildPanel(ext);
            GuildWar = new GuildWarPanel(ext);
            PartyFinder = new PartyFinderPanel(ext) { Clock = clock };
            GroupQueue = new GroupQueuePanel(ext) { Clock = clock };
            Inspect = new InspectPanel(ext);
            Leaderboard = new LeaderboardPanel(ext) { Clock = clock };
            Links = new ChatLinksState(ext) { Clock = clock };
            Factions = new FactionsPanel(ext) { Clock = clock };
            Conquest = new ConquestPanel(ext) { Clock = clock };
            // the guild window's button opens the war window
            Guild.OpenWars = () => GuildWar.OpenTab("wars");
            GroupQueue.FindGroup = () => PartyFinder.Show();
        }
    }

    public sealed partial class GameSession
    {
        /// <summary>The social and market panels.</summary>
        public SocialState Social { get; private set; }

        void InitSocial() { Social = new SocialState(Ext, () => Now); }
    }
}
