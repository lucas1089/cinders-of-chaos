// Achievements (opcode 250, Core/CollectAchievements.cs): categories, the reward track, progress rows, points, the title chooser. Reached from the top menu (Character).
using System.Collections.Generic;
using System.Linq;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class AchievementsWindow : ModelWindow
    {
        public override string Title => Loc.T("Achievements");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 330, 50, 660, 560);

        Vector2 catScroll, rowScroll;
        bool titleOpen;

        protected override bool ModelVisible(ChaosApp app) => app.Session.Achievements.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Achievements.Show();
        protected override void ModelHide(ChaosApp app) => app.Session.Achievements.Hide();

        protected override void Body(ChaosApp app, Rect inner)
        {
            var a = app.Session?.Achievements;
            if (a == null) return;
            if (a.State == null)
            {
                GUI.Label(new Rect(inner.x + 8, inner.y + 8, inner.width - 16, 24), Loc.T("Loading..."), app.SmallStyle);
                return;
            }
            var st = a.State;
            GUI.Label(new Rect(inner.x + 6, inner.y, inner.width - 12, 20), a.SummaryText(), app.SmallStyle);
            CU.Label(app, new Rect(inner.x + 6, inner.y + 20, inner.width - 12, 20), a.RecentText(), "#c8b89a", false);

            // the reward track strip
            float y = inner.y + 44;
            if (a.Track != null)
            {
                var next = AchievementsState.TrackNext(a.Track, out _);
                CU.Bar(app, new Rect(inner.x + 6, y, inner.width - 12, 18), AchievementsState.TrackPercent(a.Track), AchievementsState.TrackText(a.Track), new Color(0.2f, 0.55f, 0.52f, 1f));
                y += 24;
            }

            // titles
            if (a.TitlesOn)
            {
                GUI.Label(new Rect(inner.x + 6, y, 60, 22), Loc.T("Title"), app.SmallStyle);
                string cur = a.ActiveTitle.Length > 0 ? a.ActiveTitle : Loc.T("Newest title");
                if (GUI.Button(new Rect(inner.x + 60, y, 220, 22), cur + "  v")) titleOpen = !titleOpen;
                CU.Label(app, new Rect(inner.x + 290, y, inner.width - 296, 22), Loc.T("Your title shows above your name."), "#8c8070", false);
                y += 26;
            }
            else
            {
                CU.Label(app, new Rect(inner.x + 6, y, inner.width - 12, 20), Loc.T("Titles: {0}.", a.TitleOptions().Count), "#8c8070", false);
                y += 22;
            }

            // categories on the left
            var cats = new List<KeyValuePair<string, string>>
            {
                new KeyValuePair<string, string>(AchievementsState.All, Loc.T("All  {0}/{1}", CF.I(st, "unlocked"), CF.I(st, "total"))),
                new KeyValuePair<string, string>(AchievementsState.Recent, Loc.T("Recently unlocked")),
            };
            if (a.Track != null) cats.Add(new KeyValuePair<string, string>(AchievementsState.TrackKey, Loc.T("Reward track  {0}/{1}", AchievementsState.TrackReached(a.Track), AchievementsState.Steps(a.Track).Count)));
            foreach (var c in CF.Rows(CF.G(st, "categories"))) if (CF.G(c, "key") != null) cats.Add(new KeyValuePair<string, string>(CF.Str(CF.G(c, "key")), AchievementsState.CategoryLabel(c)));
            var left = new Rect(inner.x + 4, y, 170, inner.yMax - y - 4);
            catScroll = CU.Rows(left, catScroll, cats.Count, 26, (i, r) =>
            {
                bool on = cats[i].Key == a.Selected;
                if (GUI.Toggle(new Rect(r.x, r.y, r.width, 24), on, cats[i].Value, GUI.skin.button) && !on) { a.Selected = cats[i].Key; rowScroll = Vector2.zero; }
            });

            // rows on the right
            var right = new Rect(inner.x + 180, y, inner.width - 184, inner.yMax - y - 4);
            if (a.Selected == AchievementsState.TrackKey)
            {
                var rows = AchievementsState.TrackRows(a.Track);
                rowScroll = CU.Rows(right, rowScroll, rows.Count, 62, (i, r) =>
                {
                    var t = rows[i];
                    ChaosApp.Fill(r, t.Done ? new Color(0.17f, 0.12f, 0.05f, 1f) : new Color(1f, 1f, 1f, 0.04f));
                    var name = new GUIStyle(app.SmallStyle) { fontStyle = FontStyle.Bold };
                    name.normal.textColor = CU.Hex(t.Color, t.Done ? new Color(0.96f, 0.81f, 0.45f) : name.normal.textColor);
                    GUI.Label(new Rect(r.x + 4, r.y + 2, r.width - 90, 18), new GUIContent(t.Name, t.Tip), name);
                    GUI.Label(new Rect(r.xMax - 84, r.y + 2, 80, 18), t.Right, app.SmallStyle);
                    GUI.Label(new Rect(r.x + 4, r.y + 18, r.width - 8, 16), t.Desc, app.SmallStyle);
                    CU.Label(app, new Rect(r.x + 4, r.y + 32, r.width - 8, 14), t.Extra, "#8c8070", false);
                    CU.Bar(app, new Rect(r.x + 4, r.y + 47, r.width - 8, 12), t.Percent, t.Progress, t.Done ? new Color(0.54f, 0.42f, 0.11f) : new Color(0.45f, 0.1f, 0.1f));
                });
            }
            else
            {
                var rows = AchievementsState.Filter(a.Rows, a.Selected, a.Selected != AchievementsState.Recent);
                if (rows.Count == 0) GUI.Label(new Rect(right.x + 6, right.y + 6, right.width - 12, 24), Loc.T("Nothing here."), app.SmallStyle);
                rowScroll = CU.Rows(right, rowScroll, rows.Count, 62, (i, r) =>
                {
                    var row = rows[i];
                    ChaosApp.Fill(r, row.IsUnlocked ? new Color(0.17f, 0.12f, 0.05f, 1f) : new Color(1f, 1f, 1f, 0.04f));
                    var name = new GUIStyle(app.SmallStyle) { fontStyle = FontStyle.Bold };
                    name.normal.textColor = row.IsUnlocked ? new Color(0.96f, 0.81f, 0.45f) : name.normal.textColor;
                    GUI.Label(new Rect(r.x + 4, r.y + 2, r.width - 90, 18), row.Name, name);
                    GUI.Label(new Rect(r.xMax - 84, r.y + 2, 80, 18), Loc.T("{0} pts", row.Points), app.SmallStyle);
                    CU.Label(app, new Rect(r.x + 4, r.y + 18, r.width - 8, 16), row.Desc, row.HiddenLocked ? "#6b6258" : null, false);
                    if (!row.HiddenLocked) CU.Label(app, new Rect(r.x + 4, r.y + 32, r.width - 8, 14), AchievementsState.ExtraText(row), "#8c8070", false);
                    string text = row.IsUnlocked ? Loc.T("Unlocked {0}", CF.Date(row.Unlocked)) : AchievementsState.ProgressText(row);
                    CU.Bar(app, new Rect(r.x + 4, r.y + 47, r.width - 8, 12), AchievementsState.PercentOf(row), text, row.IsUnlocked ? new Color(0.54f, 0.42f, 0.11f) : row.HiddenLocked ? new Color(0.23f, 0.2f, 0.22f) : new Color(0.45f, 0.1f, 0.1f));
                });
            }

            // the title list drops over the rows
            if (titleOpen && a.TitlesOn)
            {
                var opts = new List<KeyValuePair<string, string>> { new KeyValuePair<string, string>("auto", Loc.T("Newest title")), new KeyValuePair<string, string>("none", Loc.T("No title")) };
                foreach (var t in a.TitleOptions()) opts.Add(new KeyValuePair<string, string>(t, t));
                var box = new Rect(inner.x + 60, inner.y + 44 + (a.Track != null ? 24 : 0) + 24, 220, Mathf.Min(opts.Count, 8) * 24 + 4);
                ChaosApp.Fill(box, new Color(0.06f, 0.05f, 0.08f, 0.98f));
                for (int i = 0; i < Mathf.Min(opts.Count, 8); i++)
                    if (GUI.Button(new Rect(box.x + 2, box.y + 2 + i * 24, box.width - 4, 22), opts[i].Value)) { a.SetTitle(opts[i].Key); titleOpen = false; }
            }
            CU.Tooltip(app, new Rect(0, 0, Area.width, Area.height));
        }
    }
}
