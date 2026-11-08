// The death recap (toolbar, or by itself after a death): who hit the character in its last seconds, with damage, share and element split,
// the killing blow, what was lost, the last hits, a few tips, and the last deaths in a column on the left. The data is Core/DeathRecap.cs
// (opcode 154, the rules of the main client's game_deathrecap). The server sends the recap at the next login (the experience lost is filled
// in then), so the window opens by itself there, unless "Open after a death" is off (PlayerPrefs chaos.deathrecap.auto).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class DeathRecapWindow : GameWindow
    {
        DeathRecap recap;
        GameSession recapFor;
        bool wasOpen, autoOpen = true, autoLoaded;
        Vector2 histScroll, mainScroll;
        GUIStyle small, title, hint;
        readonly List<DeathRow> rows = new List<DeathRow>();
        object rowsFor;

        public override string Title => Loc.T("Recap");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 290f, 60f, 580f, 500f);
        public override void Reset() { recap = null; recapFor = null; wasOpen = false; rowsFor = null; rows.Clear(); }

        public override void Tick(ChaosApp app)
        {
            var s = app.Session;
            if (s == null) return;
            if (!autoLoaded) { autoOpen = PlayerPrefs.GetInt("chaos.deathrecap.auto", 1) == 1; autoLoaded = true; }
            if (recap == null || recapFor != s)
            {
                recapFor = s;
                recap = new DeathRecap(s.Ext);
                recap.AutoOpen += () => { if (autoOpen) { Open = true; wasOpen = true; recap.Open(recap.Selected); } };
            }
            if (Open && !wasOpen) recap.Open(recap.Selected);
            wasOpen = Open;
        }

        void Styles(ChaosApp app)
        {
            if (small != null) return;
            small = new GUIStyle(app.SmallStyle) { fontSize = 12, clipping = TextClipping.Clip };
            title = new GUIStyle(app.TitleStyle) { fontSize = 16 };
            hint = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true };
            hint.normal.textColor = new Color(1f, 1f, 1f, 0.6f);
        }

        static Color Hex(string hex, float a = 1f)
        {
            Color c;
            if (ColorUtility.TryParseHtmlString(hex, out c)) { c.a = a; return c; }
            return new Color(1f, 1f, 1f, a);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            if (recap == null) return;
            Styles(app);
            float histW = 150f;
            var left = new Rect(inner.x + 2, inner.y + 2, histW, inner.height - 30);
            var main = new Rect(inner.x + histW + 8, inner.y + 2, inner.width - histW - 12, inner.height - 30);
            bool auto = GUI.Toggle(new Rect(inner.x + 4, inner.yMax - 24, inner.width - 8, 22), autoOpen, Loc.T("Open after a death"));
            if (auto != autoOpen) { autoOpen = auto; PlayerPrefs.SetInt("chaos.deathrecap.auto", auto ? 1 : 0); }
            DrawHistory(left);
            DrawRecap(main);
        }

        void DrawHistory(Rect r)
        {
            GUI.Label(new Rect(r.x, r.y, r.width, 18), Loc.T("Last deaths"), title);
            var list = DeathRecapRules.HistoryRows(recap.History, recap.Selected);
            var area = new Rect(r.x, r.y + 24, r.width, r.height - 24);
            if (list.Count == 0) { GUI.Label(area, Loc.T("No deaths yet."), hint); return; }
            histScroll = GUI.BeginScrollView(area, histScroll, new Rect(0, 0, r.width - 18, list.Count * 52f));
            for (int i = 0; i < list.Count; i++)
            {
                var row = list[i];
                var rr = new Rect(0, i * 52f, r.width - 18, 50f);
                ChaosApp.Fill(rr, row.Selected ? new Color(0.45f, 0.3f, 0.12f, 0.9f) : new Color(1f, 1f, 1f, 0.06f));
                GUI.Label(new Rect(rr.x + 4, rr.y + 1, rr.width - 8, 16), row.Title, small);
                GUI.Label(new Rect(rr.x + 4, rr.y + 16, rr.width - 8, 16), row.Killer, small);
                GUI.Label(new Rect(rr.x + 4, rr.y + 31, rr.width - 8, 16), row.Sub, hint);
                if (GUI.Button(rr, GUIContent.none, GUIStyle.none)) recap.Select(row.Id);
            }
            GUI.EndScrollView();
        }

        void DrawRecap(Rect r)
        {
            var cur = recap.Current;
            if (cur == null)
            {
                GUI.Label(new Rect(r.x, r.y, r.width, 24), Loc.T("No death to show"), title);
                GUI.Label(new Rect(r.x, r.y + 28, r.width, 40), Loc.T("No death recorded yet."), hint);
                return;
            }
            if (rowsFor != cur) { rowsFor = cur; rows.Clear(); rows.AddRange(DeathRecapRules.Rows(cur)); }
            var h = DeathRecapRules.Header(cur);
            var tips = DeathRecapRules.Tips(cur);
            var line = DeathRecapRules.Timeline(cur);
            float w = r.width - 18;
            float contentH = 150f + rows.Count * 46f + (tips.Count > 0 ? 24f + tips.Count * 36f : 0f) + 24f + line.Count * 16f + 8f;
            mainScroll = GUI.BeginScrollView(r, mainScroll, new Rect(0, 0, w, contentH));
            float y = 0;
            GUI.Label(new Rect(0, y, w, 22), h.Title, title); y += 24;
            GUI.Label(new Rect(0, y, w, 16), h.Sub, hint); y += 18;
            GUI.Label(new Rect(0, y, w, 16), h.Loss, small); y += 18;
            GUI.Label(new Rect(0, y, w, 16), DeathRecapRules.KillingBlow(cur), small); y += 18;
            GUI.Label(new Rect(0, y, w, 16), h.Window, hint); y += 16;
            GUI.Label(new Rect(0, y, w, 16), h.Totals, hint); y += 18;
            // the element bar of the whole recap
            double total = Json.Number(cur, "tot");
            float x = 0;
            ChaosApp.Fill(new Rect(0, y, w, 8), new Color(1f, 1f, 1f, 0.08f));
            foreach (var seg in DeathRecapRules.Segments(DeathRecapRules.ElementList(Json.Get(cur, "el")), total))
            {
                float sw = (float)(w * seg.Frac);
                ChaosApp.Fill(new Rect(x, y, sw, 8), Hex(seg.Color));
                x += sw;
            }
            y += 16;
            foreach (var row in rows)
            {
                var rr = new Rect(0, y, w, 44f);
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                var tint = GUI.color;
                GUI.color = Hex(row.Color);
                GUI.Label(new Rect(rr.x + 4, rr.y + 1, w - 110, 16), row.Name, small);
                GUI.color = tint;
                GUI.Label(new Rect(rr.xMax - 104, rr.y + 1, 100, 16), DeathRecapRules.Short(row.Total) + "  " + row.Pct + "%", new GUIStyle(small) { alignment = TextAnchor.UpperRight });
                // the bar of the row: its elements by colour, the top row full
                float bx = rr.x + 4, bw = (w - 8) * (float)row.Frac;
                ChaosApp.Fill(new Rect(rr.x + 4, rr.y + 18, w - 8, 6), new Color(1f, 1f, 1f, 0.06f));
                foreach (var seg in DeathRecapRules.Segments(row.Elements, row.Total))
                {
                    float sw = bw * (float)seg.Frac;
                    ChaosApp.Fill(new Rect(bx, rr.y + 18, sw, 6), Hex(seg.Color));
                    bx += sw;
                }
                var info = new List<string> { Loc.T(row.Hits == 1 ? "{0}, {1} hit" : "{0}, {1} hits", row.KindName, (int)row.Hits) };
                if (row.Crits > 0) info.Add(Loc.T("{0}% critical", row.CritPct));
                if (row.Mp > 0) info.Add(Loc.T("mana {0}", DeathRecapRules.Short(row.Mp)));
                if (row.ElText != "") info.Add(row.ElText);
                GUI.Label(new Rect(rr.x + 4, rr.y + 26, w - 8, 16), string.Join("  |  ", info), hint);
                y += 46f;
            }
            if (rows.Count == 0) { GUI.Label(new Rect(0, y, w, 20), Loc.T("No hits were recorded before this death."), hint); y += 22; }
            if (tips.Count > 0)
            {
                GUI.Label(new Rect(0, y, w, 18), Loc.T("What to do"), title); y += 22;
                foreach (var t in tips) { GUI.Label(new Rect(0, y, w, 34), t, hint); y += 36; }
            }
            GUI.Label(new Rect(0, y, w, 18), Loc.T("Final hits"), title); y += 22;
            foreach (var e in line)
            {
                var tint = GUI.color;
                if (e.Death) GUI.color = new Color(0.88f, 0.23f, 0.12f);
                GUI.Label(new Rect(0, y, w, 16), e.Text, small);
                GUI.color = tint;
                y += 16;
            }
            GUI.EndScrollView();
        }
    }
}
