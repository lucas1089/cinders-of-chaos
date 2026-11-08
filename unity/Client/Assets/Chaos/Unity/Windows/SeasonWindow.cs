// Seasons (opcode 246, Core/CollectSeason.cs): the overview with the season's milestones and the join dialog (modes, the Hardcore acknowledgement), and the Journey tab
// (chapters, objectives, rewards). A Hardcore character sends the heartbeat. Reached from the top menu (Adventure) or opened by the server.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class SeasonWindow : ModelWindow
    {
        public override string Title => Loc.T("Seasons");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 300, 60, 600, 520);

        Vector2 trackScroll, chapScroll, objScroll;

        protected override bool ModelVisible(ChaosApp app) => app.Session.Seasons.Visible;
        protected override void ModelShow(ChaosApp app) => app.Session.Seasons.Show();
        protected override void ModelHide(ChaosApp app) => app.Session.Seasons.Hide();

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session?.Seasons;
            if (s == null) return;
            double now = app.Session.Now;
            if (s.State == null) { GUI.Label(new Rect(inner.x + 8, inner.y + 8, 300, 22), Loc.T("Loading..."), app.SmallStyle); return; }
            GUI.Label(new Rect(inner.x + 6, inner.y, inner.width - 200, 22), s.NameLine(), app.TitleStyle);
            GUI.Label(new Rect(inner.xMax - 200, inner.y + 2, 196, 20), s.TimerText(now), new GUIStyle(app.SmallStyle) { alignment = TextAnchor.UpperRight });
            int tab = CU.Tabs(new Rect(inner.x + 4, inner.y + 26, 300, 24), new[] { Loc.T("Overview"), Loc.T("Journey") }, s.Tab == "journey" ? 1 : 0);
            if ((tab == 1 ? "journey" : "season") != s.Tab) s.ShowTab(tab == 1 ? "journey" : "season");
            var body = new Rect(inner.x, inner.y + 56, inner.width, inner.height - 56);
            if (s.Tab == "journey") Journey(app, s, body, now); else Overview(app, s, body);
            if (s.Notice.Length > 0 && s.Tab == "season") { }
            CU.Tooltip(app, new Rect(0, 0, Area.width, Area.height));
            if (s.JoinOpen) JoinDialog(app, s, inner);
        }

        void Overview(ChaosApp app, SeasonState s, Rect body)
        {
            float y = body.y;
            string mod = s.ModifierLine();
            if (mod.Length > 0) { CU.Label(app, new Rect(body.x + 6, y, body.width - 12, 36), mod, "#e8b84a"); y += 36; }
            string mine = s.Notice.Length > 0 ? s.Notice : s.MineText();
            GUI.Label(new Rect(body.x + 6, y, body.width - 140, 54), mine, CU.Wrap(app));
            if (s.CanJoin && GUI.Button(new Rect(body.xMax - 120, y + 4, 110, 28), Loc.T("Join"))) { s.Notice = ""; s.AskJoin(); }
            y += 60;
            if (s.Season == null) { GUI.Label(new Rect(body.x + 6, y, body.width - 12, 40), Loc.T("No season is configured on this server."), CU.Wrap(app)); return; }
            GUI.Label(new Rect(body.x + 6, y, 300, 20), Loc.T("Milestones"), app.TitleStyle);
            var track = s.Track;
            string titles = s.TitlesLine();
            var view = new Rect(body.x + 4, y + 22, body.width - 8, body.yMax - y - 26 - (titles.Length > 0 ? 24 : 0));
            trackScroll = CU.Rows(view, trackScroll, track.Count, 44, (i, r) =>
            {
                var m = track[i];
                string prog = SeasonState.TrackProgress(m, out int pct, out bool un);
                ChaosApp.Fill(r, un ? new Color(0.17f, 0.12f, 0.05f, 1f) : new Color(1f, 1f, 1f, 0.04f));
                CU.Label(app, new Rect(r.x + 4, r.y + 2, r.width * 0.45f, 18), (un ? "* " : "- ") + CF.T(m, "name", "?"), un ? "#f6cf72" : null, false);
                GUI.Label(new Rect(r.x + r.width * 0.5f, r.y + 2, r.width * 0.5f - 4, 18), new GUIContent(CF.T(m, "reward"), un && CF.G(m, "by") != null ? Loc.T("Unlocked by {0}", CF.T(m, "by")) : ""), app.SmallStyle);
                CU.Bar(app, new Rect(r.x + 4, r.y + 24, r.width - 8, 14), pct, prog, un ? new Color(0.54f, 0.42f, 0.11f) : new Color(0.45f, 0.1f, 0.1f));
            });
            if (titles.Length > 0) CU.Label(app, new Rect(body.x + 6, body.yMax - 22, body.width - 12, 20), titles, "#c8b89a", false);
        }

        void Journey(ChaosApp app, SeasonState s, Rect body, double now)
        {
            if (s.Header == null) { GUI.Label(new Rect(body.x + 8, body.y + 4, 300, 22), Loc.T("Waiting for the server..."), app.SmallStyle); return; }
            GUI.Label(new Rect(body.x + 6, body.y, body.width - 12, 22), s.JourneyTitle(), app.TitleStyle);
            GUI.Label(new Rect(body.x + 6, body.y + 22, body.width - 12, 20), s.JourneySummary(), app.SmallStyle);
            float y = body.y + 44;
            if (s.Preview) { CU.Label(app, new Rect(body.x + 6, y, body.width - 12, 20), CF.T(s.Header, "why"), "#b8b0a0", false); y += 20; }
            if (s.Banner.Length > 0 && now - s.BannerAt < 5000) { CU.Label(app, new Rect(body.x + 6, y, body.width - 12, 20), s.Banner, "#7fc86a", false); y += 20; }
            var left = new Rect(body.x + 4, y, 190, body.yMax - y - 4);
            chapScroll = CU.Rows(left, chapScroll, s.Chapters.Count, 40, (i, r) =>
            {
                var c = s.Chapters[i];
                bool sel = s.Selected == i + 1;
                ChaosApp.Fill(r, sel ? new Color(0.3f, 0.22f, 0.1f, 1f) : new Color(1f, 1f, 1f, 0.04f));
                CU.Label(app, new Rect(r.x + 4, r.y + 2, r.width - 8, 18), SeasonState.ChapterLabel(c, i + 1), sel ? "#f6cf72" : CF.T(c, "state") == "locked" ? "#8c8070" : null, false);
                CU.Label(app, new Rect(r.x + 4, r.y + 20, r.width - 8, 16), SeasonState.ChapterStatus(c), StateColor(CF.T(c, "state")), false);
                GUI.Label(r, new GUIContent("", SeasonState.ChapterNote(c)));
                if (Event.current.type == EventType.MouseDown && Event.current.button == 0 && r.Contains(Event.current.mousePosition)) { s.Select(i + 1); Event.current.Use(); }
            });
            var d = new Rect(left.xMax + 8, y, body.xMax - left.xMax - 12, body.yMax - y - 4);
            if (s.Selected < 1 || s.Selected > s.Chapters.Count) return;
            var ch = s.Chapters[s.Selected - 1];
            GUI.Label(new Rect(d.x, d.y, d.width, 20), SeasonState.ChapterLabel(ch, s.Selected), app.TitleStyle);
            GUI.Label(new Rect(d.x, d.y + 22, d.width, 40), SeasonState.ChapterNote(ch), CU.Wrap(app));
            s.Details.TryGetValue(s.Selected, out var det);
            var objs = CF.Rows(CF.G(det, "objectives"));
            var rewards = CF.Rows(CF.G(det, "rewards"));
            var objRect = new Rect(d.x, d.y + 66, d.width, d.height - 66 - 70);
            objScroll = CU.Rows(objRect, objScroll, objs.Count, 40, (i, r) =>
            {
                var o = SeasonState.ObjectiveRow(objs[i], s.Preview);
                ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.04f));
                CU.Label(app, new Rect(r.x + 4, r.y + 2, r.width - 120, 18), (o.Done ? "* " : "- ") + o.Text, o.Done ? "#7fc86a" : CF.T(ch, "state") == "locked" ? "#8c8070" : null, false);
                if (o.Tag != null) CU.Label(app, new Rect(r.xMax - 114, r.y + 2, 110, 18), o.Tag, "#ff7a5a", false);
                CU.Bar(app, new Rect(r.x + 4, r.y + 22, r.width - 8, 14), o.Percent, o.Label, o.Done ? new Color(0.25f, 0.43f, 0.14f) : new Color(0.54f, 0.33f, 0.06f));
            });
            if (objs.Count == 0) GUI.Label(new Rect(objRect.x + 4, objRect.y + 4, objRect.width, 20), Loc.T("Loading..."), app.SmallStyle);
            GUI.Label(new Rect(d.x, d.yMax - 66, d.width, 18), Loc.T("Rewards"), app.TitleStyle);
            float rx = d.x;
            foreach (var r in rewards)
            {
                var cell = new Rect(rx, d.yMax - 46, 120, 42);
                ChaosApp.Fill(cell, new Color(0.11f, 0.09f, 0.12f, 1f));
                var pic = new Rect(cell.x + 2, cell.y + 5, 32, 32);
                if (CF.I(r, "clientId") > 0) app.DrawItem(pic, (ushort)CF.I(r, "clientId"), Mathf.Max(1, CF.I(r, "count")));
                else if (CF.I(r, "look") > 0) app.DrawOutfit(pic, new Outfit(CF.I(r, "look"), 78, 94, 114, 0));
                else GUI.Label(pic, CF.T(r, "kind") == "passxp" ? "XP" : CF.T(r, "kind") == "title" ? "T" : "?", app.SmallStyle);
                var st = new GUIStyle(CU.Wrap(app)) { fontSize = Mathf.Min(10, app.SmallStyle.fontSize) };
                if (CF.B(r, "piece")) st.normal.textColor = new Color(0.69f, 0.44f, 1f);
                GUI.Label(new Rect(cell.x + 36, cell.y + 2, cell.width - 38, 38), new GUIContent(SeasonState.RewardLine(r), CF.B(r, "piece") ? Loc.T("A piece of the {0} set", CF.T(s.Header, "set", "season")) : ""), st);
                rx += 124;
                if (rx + 120 > d.xMax) break;
            }
        }

        static string StateColor(string st) => st == "done" ? "#7fc86a" : st == "open" ? "#f6cf72" : st == "locked" ? "#6b6258" : "#b8b0a0";

        void JoinDialog(ChaosApp app, SeasonState s, Rect inner)
        {
            var box = new Rect(inner.x + 30, inner.y + 50, inner.width - 60, inner.height - 100);
            ChaosApp.Fill(box, new Color(0.07f, 0.05f, 0.09f, 0.98f));
            ChaosApp.Fill(new Rect(box.x, box.y, box.width, 2), new Color(0.6f, 0.4f, 0.15f, 1f));
            GUI.Label(new Rect(box.x + 10, box.y + 8, box.width - 20, 20), Loc.T("Join the season"), app.TitleStyle);
            GUI.Label(new Rect(box.x + 10, box.y + 32, box.width - 20, 110), s.JoinText, CU.Wrap(app));
            float x = box.x + 10, y = box.y + 150;
            foreach (var m in s.JoinChoices)
            {
                float w = Mathf.Max(70, 16 + m.Short.Length * 7);
                if (GUI.Toggle(new Rect(x, y, w, 26), s.JoinChoice != null && s.JoinChoice.Key == m.Key, new GUIContent(m.Short, m.Warning), GUI.skin.button) && (s.JoinChoice == null || s.JoinChoice.Key != m.Key)) s.SelectMode(m.Key);
                x += w + 4;
            }
            CU.Label(app, new Rect(box.x + 10, y + 32, box.width - 20, 70), SeasonJoin.WarningText(s.JoinChoice), s.JoinChoice != null && s.JoinChoice.Hc ? "#ff7a5a" : "#d6c9ae");
            if (SeasonJoin.NeedsAck(s.JoinChoice)) s.JoinAcked = GUI.Toggle(new Rect(box.x + 10, y + 104, box.width - 20, 22), s.JoinAcked, Loc.T("I understand: one life, no second chance."), GUI.skin.toggle);
            if (CU.Button(new Rect(box.x + 10, box.yMax - 36, 160, 28), SeasonJoin.JoinLabel(s.JoinChoice), SeasonJoin.CanJoin(s.JoinChoice, s.JoinAcked))) s.ConfirmJoin();
            if (GUI.Button(new Rect(box.xMax - 110, box.yMax - 36, 100, 28), Loc.T("Cancel"))) s.CloseJoin();
            GUI.Label(box, GUI.tooltip.Length > 0 ? new GUIContent("", GUI.tooltip) : GUIContent.none);
        }
    }
}
