// The community models of a session (O433 phase 5, track S): admin panel, boss spawns, survey, nemesis, referral, community goal, chronicle, mentor, patch notes, card borders,
// drop feed, credits, streamer and cinema mode, performance overlay, automatic screenshots, Customise Character extras. Each registers its extended opcode in its constructor
// (InitCommunity, called by the GameSession constructor).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class CommunityState
    {
        public readonly AdminPanel Admin;
        public readonly BossSpawnsPanel BossSpawns;
        public readonly SurveyPanel Survey;
        public readonly NemesisPanel Nemesis;
        public readonly ReferralPanel Referral;
        public readonly CommunityGoalPanel Goal;
        public readonly ChroniclePanel Chronicle;
        public readonly MentorPanel Mentor;
        public readonly PatchNotesPanel PatchNotes;
        public readonly CardBorderState CardBorder;
        public readonly DropFeedPanel DropFeed;
        public readonly CreditsPanel Credits = new CreditsPanel();
        public readonly StreamerState Streamer;
        public readonly StreamerPanel StreamerWindow;
        public readonly PerfState Perf = new PerfState();
        public readonly PerfPanel PerfWindow;
        public readonly ShotsState Shots;
        public readonly ShotsPanel ShotsWindow;
        public readonly OutfitExtrasPanel OutfitExtras;

        public CommunityState(ExtOpcodes ext, Func<double> clock, GameSession s, StreamerState streamer)
        {
            Streamer = streamer ?? new StreamerState();
            Admin = new AdminPanel(ext) { Clock = clock };
            BossSpawns = new BossSpawnsPanel(ext) { Clock = clock };
            Survey = new SurveyPanel(ext) { Clock = clock };
            Nemesis = new NemesisPanel(ext) { Clock = clock };
            Referral = new ReferralPanel(ext) { Clock = clock };
            Goal = new CommunityGoalPanel(ext) { Clock = clock };
            Chronicle = new ChroniclePanel(ext) { Clock = clock };
            Mentor = new MentorPanel(ext) { Clock = clock };
            PatchNotes = new PatchNotesPanel(ext) { Clock = clock };
            CardBorder = new CardBorderState(ext);
            DropFeed = new DropFeedPanel(ext);
            StreamerWindow = new StreamerPanel(Streamer);
            PerfWindow = new PerfPanel(Perf);
            Shots = new ShotsState(ext);
            ShotsWindow = new ShotsPanel(Shots);
            OutfitExtras = new OutfitExtrasPanel(() => s.Cosmetics, () => s.Pets, () => s.Progress?.Info);
        }
    }

    public sealed partial class GameSession
    {
        /// <summary>The community panels and small systems.</summary>
        public CommunityState Community { get; private set; }

        bool communityHello;

        void InitCommunity()
        {
            Community = new CommunityState(Ext, () => Now, this, opt.Streamer);
            parser.Talks.Streamer = Community.Streamer;
            parser.Talks.ServerText = Community.Shots.OnServerText;
            Community.Shots.LevelNow = () => parser.Level;
            Community.Shots.CharName = () => opt.Character ?? "";
            Community.Shots.TargetNow = () => AttackTarget;
            Community.Shots.BossesNow = BossesInView;
        }

        /// <summary>The boss-tier monsters in view with their health percent (Boss Defeated of the screenshot options).</summary>
        IEnumerable<KeyValuePair<uint, int>> BossesInView()
        {
            foreach (var c in world.Creatures.Values)
                if (c.Type == 1 && Hud.Monster.Tier(c.Id) == "boss") yield return new KeyValuePair<uint, int>(c.Id, c.HealthPercent);
        }

        /// <summary>Called by Poll: the first requests after the login (the admin catalog, the card border set, the drop feed option) and the timers.</summary>
        void CommunityPoll()
        {
            var c = Community;
            bool inGame = enteredAt >= 0;
            c.Admin.Poll(Now, inGame, enteredAt);
            if (inGame && !communityHello && Now - enteredAt > 900) { communityHello = true; c.CardBorder.Sync(); }
            c.DropFeed.Poll(inGame && Now - enteredAt > 1200);
            c.BossSpawns.Poll(Now);
            c.Goal.Poll(Now);
            c.PatchNotes.Poll(Now, inGame);
            c.Shots.Streamer = c.Streamer.Streamer;
            c.Shots.Poll(Now, inGame);
        }
    }
}
