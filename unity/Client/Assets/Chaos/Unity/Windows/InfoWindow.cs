// Info and Services, the main client's game_chaosinfo on opcode 237: the player commands of the server in one window instead of the
// chat. A list of pages on the left (character info, services, house, rift keys, events, the Ancestral Store, server info), the page on
// the right with its buttons, the server's answer in a text area. The server's catalog says which commands exist; a page with none is
// left out. The Services buttons follow the Services state (tokens, free switch, frames) and say why one is off. Core: Core/Progression.cs
// (ChaosInfo).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class InfoWindow : GameWindow
    {
        Vector2 scrollOut, scrollRows;
        readonly Dictionary<string, string> fields = new Dictionary<string, string>();
        readonly Dictionary<string, int> choices = new Dictionary<string, int>();
        bool asked;
        GUIStyle tiny, wrap, out_;

        public override string Title => Loc.T("Info & Services");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 330), 60, Mathf.Min(660, w - 16), Mathf.Min(500, h - 70));
        public override void Reset() { fields.Clear(); choices.Clear(); asked = false; scrollOut = scrollRows = Vector2.zero; }

        /// <summary>Opens the window on a page.</summary>
        public void Show(ChaosApp app, string page)
        {
            var info = app.Session?.Progress?.Info;
            if (info == null) return;
            Open = true;
            info.Show(page);
            scrollOut = Vector2.zero;
        }

        public override void Tick(ChaosApp app)
        {
            var info = app.Session?.Progress?.Info;
            if (info == null) return;
            if (info.OpenPage.Length > 0) { string p = info.OpenPage; info.OpenPage = ""; Show(app, p); }
        }

        string Field(string id) => fields.TryGetValue(id, out string v) ? v : "";

        protected override void Body(ChaosApp app, Rect inner)
        {
            var info = app.Session?.Progress?.Info;
            if (info == null) return;
            if (tiny == null)
            {
                tiny = new GUIStyle(app.SmallStyle) { fontSize = 11 };
                wrap = new GUIStyle(tiny) { wordWrap = true };
                out_ = new GUIStyle(wrap) { fontSize = 12, alignment = TextAnchor.UpperLeft };
            }
            if (!asked) { asked = true; if (!info.HasCatalog) info.RequestCatalog(); if (info.Current.Length == 0) info.Show("character"); }
            float listW = 138f;
            // the page list
            float y = inner.y;
            foreach (var p in ChaosInfo.Pages)
            {
                if (!info.PageShown(p)) continue;
                bool on = info.Current == p.Id;
                if (GUI.Toggle(new Rect(inner.x + 2, y, listW - 6, 26), on, Loc.T(p.Title), GUI.skin.button) && !on) info.Show(p.Id);
                y += 30;
            }
            var page = ChaosInfo.Page(info.Current);
            if (page == null) return;
            float x = inner.x + listW + 4, w = inner.width - listW - 8;
            y = inner.y;
            var head = new GUIStyle(app.SmallStyle) { fontSize = 15, fontStyle = FontStyle.Bold };
            GUI.Label(new Rect(x, y, w, 22), Loc.T(page.Title), head);
            y += 22;
            string text = Loc.T(page.Text);
            float th = wrap.CalcHeight(new GUIContent(text), w);
            GUI.Label(new Rect(x, y, w, th), text, wrap);
            y += th + 4;
            GUI.tooltip = "";
            y = DrawRows(app, info, page, x, y, w);
            var area = new Rect(x, y, w, inner.yMax - y - 20);
            if (page.Store) DrawStore(app, info, area);
            else DrawOutput(info, area);
            if (GUI.tooltip.Length > 0)
                GUI.Label(new Rect(x, inner.yMax - 18, w, 18), GUI.tooltip, tiny);
        }

        float DrawRows(ChaosApp app, ChaosInfo info, InfoPage page, float x, float y, float w)
        {
            foreach (var row in page.Rows)
            {
                var buttons = new List<InfoButton>();
                foreach (var b in row.Buttons) if (info.ButtonShown(b)) buttons.Add(b);
                if (buttons.Count == 0) continue;
                float bx = x;
                if (row.Label.Length > 0)
                {
                    GUI.Label(new Rect(bx, y + 3, 90, 20), Loc.T(row.Label), tiny);
                    bx += 94;
                }
                string fieldId = row.Edit.Length > 0 ? row.Edit : row.Combo;
                if (row.Edit.Length > 0)
                {
                    string name = "info_" + row.Edit;
                    GUI.SetNextControlName(name);
                    fields[row.Edit] = GUI.TextField(new Rect(bx, y, 150, 24), Field(row.Edit), 60);
                    if (GUI.GetNameOfFocusedControl() == name) app.MarkTextEditing();
                    bx += 156;
                }
                else if (row.Combo.Length > 0)
                {
                    var options = row.Combo == "vocations" ? info.VocationOptions() : info.FrameOptions();
                    int idx = choices.TryGetValue(row.Combo, out int ci) ? ci : 0;
                    if (options.Count > 0) idx = Mathf.Clamp(idx, 0, options.Count - 1);
                    if (GUI.Button(new Rect(bx, y, 22, 24), "<") && options.Count > 0) idx = (idx + options.Count - 1) % options.Count;
                    GUI.Label(new Rect(bx + 24, y + 3, 102, 20), options.Count > 0 ? options[idx].Key : Loc.T("No frames yet"), tiny);
                    if (GUI.Button(new Rect(bx + 128, y, 22, 24), ">") && options.Count > 0) idx = (idx + 1) % options.Count;
                    choices[row.Combo] = idx;
                    fields[row.Combo] = options.Count > 0 ? options[idx].Value : "";
                    bx += 156;
                }
                float rowX = bx;
                foreach (var b in buttons)
                {
                    float bw = Mathf.Max(70f, tiny.CalcSize(new GUIContent(Loc.T(b.Text))).x + 22);
                    if (rowX + bw > x + w && rowX > x + 4) { y += 28; rowX = x + (row.Label.Length > 0 ? 94 : 0); }
                    bool met = info.NeedMet(b.Need);
                    string hint = met ? (b.Hint.Length > 0 ? Loc.T(b.Hint) : "") : Loc.T(b.Why.Length > 0 ? b.Why : b.Hint);
                    var r = new Rect(rowX, y, bw, 24);
                    GUI.enabled = met;
                    if (GUI.Button(new Rect(r.x, r.y, r.width, r.height), new GUIContent(Loc.T(b.Text), hint))) info.Press(page, row, b, Field(fieldId));
                    GUI.enabled = true;
                    // a disabled button still shows why on hover
                    if (!met && r.Contains(Event.current.mousePosition)) GUI.tooltip = hint;
                    else if (met && r.Contains(Event.current.mousePosition)) GUI.tooltip = hint;
                    rowX += bw + 6;
                }
                y += 30;
            }
            return y + 2;
        }

        void DrawOutput(ChaosInfo info, Rect r)
        {
            ChaosApp.Fill(r, new Color(0f, 0f, 0f, 0.35f));
            string text = info.Current == "services" ? info.ServicesText() : info.Output;
            if (info.Current == "services" && info.Output.Length > 0 && info.LastResult.Length == 0) text = info.Output + "\n\n" + text;
            float h = Mathf.Max(r.height, out_.CalcHeight(new GUIContent(text), r.width - 24) + 8);
            scrollOut = GUI.BeginScrollView(r, scrollOut, new Rect(0, 0, r.width - 18, h));
            GUI.Label(new Rect(4, 2, r.width - 24, h), text, out_);
            GUI.EndScrollView();
        }

        void DrawStore(ChaosApp app, ChaosInfo info, Rect r)
        {
            var rows = info.StoreRows(out long points);
            string msg = info.StoreData != null ? Json.Text(info.StoreData, "message") : "";
            GUI.Label(new Rect(r.x, r.y, r.width, 18), info.StoreData == null ? Loc.T("Loading...") : Loc.T("Your Ancestral Points: {0}", points), tiny);
            if (msg.Length > 0) GUI.Label(new Rect(r.x, r.y + 16, r.width, 18), msg, tiny);
            var list = new Rect(r.x, r.y + 36, r.width, r.height - 36);
            ChaosApp.Fill(list, new Color(0f, 0f, 0f, 0.35f));
            const float rowH = 32f;
            scrollRows = GUI.BeginScrollView(list, scrollRows, new Rect(0, 0, list.width - 18, Mathf.Max(list.height, rows.Count * rowH)));
            float w = list.width - 22;
            if (info.StoreData != null && rows.Count == 0) GUI.Label(new Rect(4, 4, w, 20), Loc.T("The store has nothing for sale."), tiny);
            for (int i = 0; i < rows.Count; i++)
            {
                var s = rows[i];
                float y = i * rowH;
                var old = GUI.color;
                if (!s.Afford) GUI.color = new Color(1f, 1f, 1f, 0.5f);
                if (s.Item > 0) app.DrawItem(new Rect(2, y + 2, 28, 28), (ushort)s.Item, 1);
                GUI.Label(new Rect(34, y + 2, w - 190, 16), s.Name, tiny);
                GUI.Label(new Rect(34, y + 15, w - 190, 16), Loc.T(s.Kind), tiny);
                GUI.Label(new Rect(w - 150, y + 8, 80, 18), Loc.T("{0} points", s.Price), tiny);
                GUI.enabled = s.Afford;
                if (GUI.Button(new Rect(w - 68, y + 4, 64, 24), new GUIContent(Loc.T("Buy"), s.Afford ? Loc.T("Buy {0} for {1} Ancestral Points.", s.Name, s.Price) : Loc.T("You need {0} more Ancestral Points.", s.Missing)))) info.Buy(s.Id);
                GUI.enabled = true;
                GUI.color = old;
            }
            GUI.EndScrollView();
        }
    }
}
