// The community windows (SocialWindow.cs draws them; the models are in Core/Community.cs, CommunityGoal.cs, CommunityExtras.cs). None has a hotkey: the top menu opens them
// (Core/TopMenu.cs) or the server does (the survey at level 20 and 50, the Brazier, the pocket boss NPC, the mentor offer, the patch notes at the login).
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>The admin panel: only in the menu once the server sent a catalog, which it does for staff accounts alone (the same gate as the main client).</summary>
    public sealed class AdminWindow : SocialWindow
    {
        bool available;
        public override string Title => Loc.T("Admin Panel");
        public override bool InMenu => available;
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Admin;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 330), 50, Mathf.Min(660, w - 16), Mathf.Min(600, h - 60));
        public override void Tick(ChaosApp app) { base.Tick(app); available = app.Session?.Community?.Admin.HasCatalog == true; }
    }

    public sealed class BossSpawnsWindow : SocialWindow
    {
        public override string Title => Loc.T("Boss Spawns");
        public override string TravelKey => "pocketboss";
        protected override SocialPanel Panel(GameSession s) => s?.Community?.BossSpawns;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 320), 50, Mathf.Min(640, w - 16), Mathf.Min(600, h - 60));
    }

    /// <summary>The new player survey: opens by itself at level 20 and 50.</summary>
    public sealed class SurveyWindow : SocialWindow
    {
        public override string Title => Loc.T("A few questions");
        public override bool InMenu => false;
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Survey;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 240), 90, Mathf.Min(480, w - 16), Mathf.Min(380, h - 100));
    }

    public sealed class NemesisWindow : SocialWindow
    {
        public override string Title => Loc.T("Nemesis");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Nemesis;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 220), 80, Mathf.Min(440, w - 16), Mathf.Min(420, h - 90));
    }

    public sealed class ReferralWindow : SocialWindow
    {
        public override string Title => Loc.T("Referral");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Referral;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 280), 60, Mathf.Min(560, w - 16), Mathf.Min(560, h - 70));
    }

    public sealed class CommunityGoalWindow : SocialWindow
    {
        public override string Title => Loc.T("Community");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Goal;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 290), 56, Mathf.Min(580, w - 16), Mathf.Min(600, h - 66));
    }

    public sealed class ChronicleWindow : SocialWindow
    {
        public override string Title => Loc.T("Chronicle");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Chronicle;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 300), 50, Mathf.Min(600, w - 16), Mathf.Min(620, h - 60));
    }

    public sealed class MentorWindow : SocialWindow
    {
        public override string Title => Loc.T("Mentors");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Mentor;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 310), 50, Mathf.Min(620, w - 16), Mathf.Min(620, h - 60));
    }

    public sealed class PatchNotesWindow : SocialWindow
    {
        public override string Title => Loc.T("Patch Notes");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.PatchNotes;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 320), 46, Mathf.Min(640, w - 16), Mathf.Min(640, h - 56));
    }

    public sealed class DropFeedWindow : SocialWindow
    {
        public override string Title => Loc.T("Drop Feed");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.DropFeed;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 210), 110, Mathf.Min(420, w - 16), Mathf.Min(170, h - 120));
    }

    public sealed class CreditsWindow : SocialWindow
    {
        public override string Title => Loc.T("Credits");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.Credits;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 300), 50, Mathf.Min(600, w - 16), Mathf.Min(620, h - 60));
    }

    public sealed class StreamerWindow : SocialWindow
    {
        public override string Title => Loc.T("Streamer and cinema mode");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.StreamerWindow;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 270), 80, Mathf.Min(540, w - 16), Mathf.Min(400, h - 90));
    }

    public sealed class PerfWindow : SocialWindow
    {
        public override string Title => Loc.T("Performance");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.PerfWindow;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w - 380), 120, Mathf.Min(360, w - 16), Mathf.Min(360, h - 130));
    }

    public sealed class ShotsWindow : SocialWindow
    {
        public override string Title => Loc.T("Screenshots");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.ShotsWindow;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 250), 90, Mathf.Min(500, w - 16), Mathf.Min(380, h - 100));
    }

    public sealed class OutfitExtrasWindow : SocialWindow
    {
        public override string Title => Loc.T("Customise Character");
        protected override SocialPanel Panel(GameSession s) => s?.Community?.OutfitExtras;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 270), 70, Mathf.Min(540, w - 16), Mathf.Min(460, h - 80));
    }
}
