// The social and market windows (SocialWindow.cs draws them; the models are in Core/Market.cs, Guild.cs, PartyFinder.cs, Inspect.cs, Leaderboard.cs, Factions.cs).
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class MarketWindow : SocialWindow
    {
        public override string Title => Loc.T("Market");
        protected override SocialPanel Panel(GameSession s) => s?.Social?.Market;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 300), 56, Mathf.Min(600, w - 16), Mathf.Min(580, h - 70));
    }

    public sealed class GuildWindow : SocialWindow
    {
        public override string Title => Loc.T("Guild");
        protected override SocialPanel Panel(GameSession s) => s?.Social?.Guild;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 270), 60, Mathf.Min(540, w - 16), Mathf.Min(560, h - 70));
    }

    public sealed class GuildWarWindow : SocialWindow
    {
        public override string Title => Loc.T("Guild Wars");
        protected override SocialPanel Panel(GameSession s) => s?.Social?.GuildWar;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 280), 64, Mathf.Min(560, w - 16), Mathf.Min(560, h - 70));
    }

    public sealed class PartyFinderWindow : SocialWindow
    {
        public override string Title => Loc.T("Party Finder");
        protected override SocialPanel Panel(GameSession s) => s?.Social?.PartyFinder;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 290), 56, Mathf.Min(580, w - 16), Mathf.Min(580, h - 70));
    }

    public sealed class GroupQueueWindow : SocialWindow
    {
        public override string Title => Loc.T("Group Queue");
        protected override SocialPanel Panel(GameSession s) => s?.Social?.GroupQueue;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 240), 80, Mathf.Min(480, w - 16), Mathf.Min(500, h - 90));
    }

    public sealed class InspectWindow : SocialWindow
    {
        public override string Title => Loc.T("Inspect Player");
        protected override SocialPanel Panel(GameSession s) => s?.Social?.Inspect;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 250), 70, Mathf.Min(500, w - 16), Mathf.Min(560, h - 80));

        protected override void DrawExtra(ChaosApp app, SocialPanel p, Rect header)
        {
            var ip = p as InspectPanel;
            var o = ip?.Data != null ? InspectMath.OutfitOf(ip.Data) : null;
            if (o != null) app.DrawOutfit(new Rect(header.xMax - 68, header.y - 2, 64, 64), o);
        }
    }

    public sealed class LeaderboardWindow : SocialWindow
    {
        public override string Title => Loc.T("Leaderboards");
        protected override SocialPanel Panel(GameSession s) => s?.Social?.Leaderboard;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 280), 56, Mathf.Min(560, w - 16), Mathf.Min(580, h - 70));
    }

    public sealed class FactionsWindow : SocialWindow
    {
        public override string Title => Loc.T("Factions");
        protected override SocialPanel Panel(GameSession s) => s?.Social?.Factions;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 290), 56, Mathf.Min(580, w - 16), Mathf.Min(600, h - 70));
    }

    public sealed class ConquestWindow : SocialWindow
    {
        public override string Title => Loc.T("Conquest Vendor");
        protected override SocialPanel Panel(GameSession s) => s?.Social?.Conquest;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 290), 60, Mathf.Min(580, w - 16), Mathf.Min(560, h - 70));
    }

    /// <summary>The ready check box of the group queue: opens by itself when a queue pops, shows the bar and Accept / Decline, closes when the time is up.</summary>
    public sealed class ReadyCheckWindow : GameWindow
    {
        public override string Title => Loc.T("Ready check");
        public override bool InMenu => false;
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 180, 150, 360, 150);
        public override void Reset() { Open = false; }

        public override void Tick(ChaosApp app)
        {
            var gq = app.Session?.Social?.GroupQueue;
            if (gq == null) return;
            bool want = gq.CheckOpen;
            if (want && !Open) Open = true;
            else if (!want && Open) Open = false;
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var gq = app.Session?.Social?.GroupQueue;
            var c = gq?.Check;
            if (c == null) return;
            GUI.Label(new Rect(inner.x + 6, inner.y + 4, inner.width - 12, 22), c.Title, app.TitleStyle);
            GUI.Label(new Rect(inner.x + 6, inner.y + 28, inner.width - 12, 20), c.Sub, app.SmallStyle);
            var bar = new Rect(inner.x + 6, inner.y + 54, inner.width - 12, 18);
            ChaosApp.Fill(bar, new Color(0.12f, 0.1f, 0.12f, 1f));
            ChaosApp.Fill(new Rect(bar.x, bar.y, bar.width * c.Percent / 100f, bar.height), new Color(0.54f, 0.33f, 0.06f, 1f));
            GUI.Label(new Rect(bar.x + 4, bar.y, bar.width - 8, bar.height), c.Timer, app.SmallStyle);
            GUI.enabled = !c.Answered;
            if (GUI.Button(new Rect(inner.x + 6, inner.y + 82, inner.width / 2 - 9, 28), Loc.T("Accept"))) gq.Answer(true);
            if (GUI.Button(new Rect(inner.x + inner.width / 2 + 3, inner.y + 82, inner.width / 2 - 9, 28), Loc.T("Decline"))) gq.Answer(false);
            GUI.enabled = true;
        }
    }
}
