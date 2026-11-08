// Daily reward (opcode 207, Core/CollectDaily.cs): seven reward cells, the claim button on today's, the timer on the next one, the streak and its cosmetics. The server opens it
// at the login; closing it tells the server (it may open the next window of its queue). The Weekly Chest (opcode 117) is the second window of this file.
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class DailyWindow : ModelWindow
    {
        public override string Title => Loc.T("Daily Reward");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 300, 70, 600, 360);

        protected override bool ModelVisible(ChaosApp app) => app.Session.Daily.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Daily.Show();
        protected override void ModelHide(ChaosApp app) => app.Session.Daily.Hide();

        protected override void Body(ChaosApp app, Rect inner)
        {
            var d = app.Session?.Daily;
            if (d == null) return;
            if (d.Data == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            double now = app.Session.Now;
            var rewards = d.Rewards;
            float cw = (inner.width - 8) / 7f;
            for (int i = 1; i <= rewards.Count && i <= 7; i++)
            {
                var r = new Rect(inner.x + 4 + (i - 1) * cw, inner.y + 8, cw - 4, 130);
                string st = d.CellState(i);
                ChaosApp.Fill(r, st == "claimable" ? new Color(0.25f, 0.2f, 0.07f, 1f) : new Color(1f, 1f, 1f, 0.05f));
                GUI.Label(new Rect(r.x, r.y + 2, r.width, 18), Loc.T("Day {0}", i), new GUIStyle(app.SmallStyle) { alignment = TextAnchor.UpperCenter });
                var pic = new Rect(r.center.x - 20, r.y + 24, 40, 40);
                ChaosApp.Fill(pic, new Color(0.11f, 0.09f, 0.12f, 1f));
                app.DrawItem(pic, (ushort)CF.I(rewards[i - 1], "ClientID"), Mathf.Max(1, CF.I(rewards[i - 1], "Count")));
                var center = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleCenter };
                var br = new Rect(r.x + 4, r.y + 72, r.width - 8, 24);
                if (st == "claimable") { if (GUI.Button(new Rect(r.x + 4, r.y + 76, r.width - 8, 28), Loc.T("Claim"))) d.Claim(); }
                else if (st == "claimed") GUI.Label(br, Loc.T("Taken"), center);
                else if (st == "next") { string t = d.NextTimer(now, out int pct); CU.Bar(app, new Rect(r.x + 4, r.y + 80, r.width - 8, 16), pct, t, new Color(0.35f, 0.45f, 0.2f)); }
                else GUI.Label(br, "-", center);
            }
            float y = inner.y + 146;
            if (d.HasStreak)
            {
                GUI.Label(new Rect(inner.x + 6, y, 260, 20), d.StreakLine(), app.TitleStyle);
                GUI.Label(new Rect(inner.x + 280, y + 2, 120, 20), d.BestLine(), app.SmallStyle);
                GUI.Label(new Rect(inner.x + 400, y + 2, inner.width - 406, 20), new GUIContent(d.GraceLine(), d.GraceTip()), app.SmallStyle);
                y += 26;
                GUI.Label(new Rect(inner.x + 6, y, inner.width - 12, 20), d.MilestoneLine(), app.SmallStyle); y += 22;
                string t = d.TitleLine();
                if (t.Length > 0) { GUI.Label(new Rect(inner.x + 6, y, inner.width - 12, 20), t, app.SmallStyle); y += 22; }
                string c = d.CosmeticsLine();
                if (c.Length > 0) GUI.Label(new Rect(inner.x + 6, y, inner.width - 12, 40), new GUIContent(c, Loc.T("Granted once to the account when its streak first gets there. Choose them in the Wardrobe.")), CU.Wrap(app));
            }
            CU.Tooltip(app, new Rect(0, 0, Area.width, Area.height));
        }
    }

    public sealed class WeeklyChestWindow : ModelWindow
    {
        public override string Title => Loc.T("Weekly Chest");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 230, 80, 460, 420);

        protected override bool ModelVisible(ChaosApp app) => app.Session.Weekly.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Weekly.Show();
        protected override void ModelHide(ChaosApp app) => app.Session.Weekly.Hide();

        protected override void Body(ChaosApp app, Rect inner)
        {
            var w = app.Session?.Weekly;
            if (w == null) return;
            if (w.State == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            GUI.Label(new Rect(inner.x + 6, inner.y, inner.width - 12, 22), w.Head(), app.TitleStyle);
            GUI.Label(new Rect(inner.x + 6, inner.y + 22, inner.width - 12, 20), w.Ends(), app.SmallStyle);
            float y = inner.y + 48;
            foreach (var r in w.Rows())
            {
                ChaosApp.Fill(new Rect(inner.x + 4, y, inner.width - 8, 34), new Color(1f, 1f, 1f, 0.04f));
                GUI.Label(new Rect(inner.x + 10, y + 2, 200, 18), r.Name, app.SmallStyle);
                CU.Label(app, new Rect(inner.xMax - 160, y + 2, 150, 18), r.Status, r.Color, false, TextAnchor.UpperRight);
                CU.Label(app, new Rect(inner.x + 10, y + 18, inner.width - 20, 16), r.What, "#8c8070", false);
                y += 38;
            }
            y += 6;
            CU.Label(app, new Rect(inner.x + 6, y, inner.width - 12, 20), w.ChestLine(out string cc), cc, false);
            GUI.Label(new Rect(inner.x + 6, y + 20, inner.width - 12, 20), w.RewardLine(), app.SmallStyle);
            CU.Label(app, new Rect(inner.x + 6, y + 44, inner.width - 12, 36), w.BonusLine(out string bc), bc);
            GUI.Label(new Rect(inner.x + 6, inner.yMax - 22, inner.width - 12, 20), w.ChestsLine(), app.SmallStyle);
        }
    }
}
