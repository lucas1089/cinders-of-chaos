// The info and help windows (O433 phase 5, track Q): the DPS meter (opcode 204), the Codex, the help search, the How it works card and the weapon list of the
// proficiency window. Rules and data: Core/DpsMeter.cs, Core/Codex.cs, Core/HelpSearch.cs, Core/HowItWorks.cs, Core/ProficiencyCatalog.cs. None has a hotkey: the top menu
// opens them (Hunt > DPS Meter, Economy > Codex, System > Help Search) and the title bar of a feature window has a ? button for its How it works card.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    // ============================================================================================================================ DPS meter
    public sealed class DpsMeterWindow : GameWindow
    {
        GameSession forSession;
        bool wasOpen, details, confirmReset;
        Vector2 scroll;
        GUIStyle small, hint, right;
        string loadedKey, hover = "";

        public override string Title => Loc.T("DPS Meter");
        Rect? saved;   // the position and size of the last session (settings x, y, w, h), used when the window is first placed
        bool resizing;
        Vector2 dragged;   // the corner drag so far, in UI units (a mouse delta is already scaled)
        int startW, startH;
        protected override Rect Place(float w, float h) => saved ?? new Rect(8f, 176f, 440f, 380f);
        public override void Reset() { forSession = null; wasOpen = false; loadedKey = null; confirmReset = false; saved = null; resizing = false; }

        void Save(DpsMeter m) { if (loadedKey != null) { PlayerPrefs.SetString(loadedKey, m.Settings.ToJson()); PlayerPrefs.Save(); } }

        public override void Tick(ChaosApp app)
        {
            var s = app.Session;
            string name = app.World?.Player?.Name;
            if (s == null || s.Info == null || name == null) return;
            var m = s.Info.Dps;
            if (forSession != s)
            {
                forSession = s;
                loadedKey = DpsMath.PrefsKey(name);
                m.Forget();
                m.Settings = DpsMath.Sanitize(Json.TryParse(PlayerPrefs.GetString(loadedKey, "")));
                m.SegSel = m.Settings.Seg;
                // the panel keeps its own position and size (settings x, y, w, h)
                var st = m.Settings;
                bool sized = st.W != DpsMath.DefaultW || st.H != DpsMath.DefaultH;
                if (st.X.HasValue && st.Y.HasValue || sized)
                {
                    float rw = sized ? st.W : 440f, rh = sized ? st.H : 380f;
                    float rx = st.X ?? 8, ry = st.Y ?? 176;
                    DpsPanel.ClampPosition(ref rx, ref ry, rw, rh, Screen.width, Screen.height);
                    saved = new Rect(rx, ry, rw, rh);
                    if (Area.width > 0) Area = saved.Value;
                }
                wasOpen = false;
                Open = m.Settings.Shown;
            }
            if (Open && !wasOpen) { m.Settings.Shown = true; Save(m); m.Start(); }
            else if (!Open && wasOpen) { m.Settings.Shown = false; Save(m); m.Stop(); }
            wasOpen = Open;
        }

        void Styles(ChaosApp app)
        {
            if (small != null) return;
            small = new GUIStyle(app.SmallStyle) { fontSize = 12, clipping = TextClipping.Clip };
            hint = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true };
            hint.normal.textColor = new Color(1f, 1f, 1f, 0.6f);
            right = new GUIStyle(small) { alignment = TextAnchor.UpperRight };
        }

        static Color Hex(string hex) => Ui.Hex(hex);

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            if (s == null || s.Info == null) return;
            Styles(app);
            var m = s.Info.Dps;
            var set = m.Settings;
            hover = "";
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;
            var tabNames = new string[DpsMath.Tabs.Length];
            int cur = 0;
            for (int i = 0; i < tabNames.Length; i++) { tabNames[i] = Loc.T(DpsMath.Tabs[i].Short); if (DpsMath.Tabs[i].Key == (details ? set.DetailTab : set.Tab)) cur = i; }
            int t = GUI.Toolbar(new Rect(x, y, w, 24), cur, tabNames);
            if (t != cur) { if (details) set.DetailTab = DpsMath.Tabs[t].Key; else set.Tab = DpsMath.Tabs[t].Key; Save(m); }
            var tab = DpsMath.Tab(details ? set.DetailTab : set.Tab);
            y += 28;

            // the fight: previous, name, next
            var opts = DpsMath.SegmentOptions(m.Segs);
            int si = opts.FindIndex(o => o.Id == m.SegSel);
            if (si < 0) si = 0;
            if (GUI.Button(new Rect(x, y, 24, 22), "<")) { m.Choose(opts[(si + 1) % opts.Count].Id); }
            GUI.Label(new Rect(x + 28, y + 2, w - 56 - 190, 20), opts[si].Text, small);
            if (GUI.Button(new Rect(x + w - 190 - 24, y, 24, 22), ">")) { m.Choose(opts[(si - 1 + opts.Count) % opts.Count].Id); }
            bool party = GUI.Toggle(new Rect(x + w - 186, y, 90, 22), set.Party, Loc.T("Party"));
            if (party != set.Party) { m.SetParty(party); Save(m); }
            bool det = GUI.Toggle(new Rect(x + w - 94, y, 94, 22), details, Loc.T("Combat log"));
            if (det != details) { details = det; scroll = Vector2.zero; }
            y += 26;

            var view = m.View;
            double total;
            var rows = DpsMath.Rows(view, tab.Idx, out total);
            if (view is Dictionary<string, object>)
            {
                string line = DpsMath.Title(view) + "   " + DpsMath.Short(total) + " (" + DpsMath.Short(DpsMath.PerSecond(total, Json.Number(view, "dur"))) + " " + tab.Rate + ")";
                GUI.Label(new Rect(x, y, w, 18), line, small);
            }
            else GUI.Label(new Rect(x, y, w, 18), m.State == null ? Loc.T("Waiting for the server...") : DpsMath.Title(null), small);
            y += 20;

            var area = new Rect(x, y, w, inner.yMax - y - 30);
            if (set.Party && m.Party != null && !details) DrawParty(area, m, tab);
            else if (details) DrawDetails(area, view, tab, rows);
            else DrawBars(app, area, rows, tab);
            PanelFrame(m);

            // footer
            float fy = inner.yMax - 26;
            if (GUI.Button(new Rect(x, fy, 70, 24), Loc.T("Copy"))) { GUIUtility.systemCopyBuffer = DpsMath.Summary(view, tab.Idx); app.PostLine(Loc.T("Fight summary copied to the clipboard.")); }
            if (GUI.Button(new Rect(x + 74, fy, 70, 24), Loc.T("To chat"))) { app.PutInChat(DpsMath.ChatLine(view, tab.Idx, 240)); }
            bool share = GUI.Toggle(new Rect(x + 150, fy, w - 150 - 110, 24), set.Share, Loc.T("Share with party"));
            if (share != set.Share) { m.SetShare(share); Save(m); }
            if (GUI.Button(new Rect(x + w - 104, fy, 104, 24), confirmReset ? Loc.T("Sure?") : Loc.T("Reset...")))
            {
                if (confirmReset) { m.Reset(); confirmReset = false; } else confirmReset = true;
            }
        }

        // the source icon of a bar (dpsmath.lua iconSpec): the spell's cell, the rune's sprite, else a coloured glyph for the pictures only the main client has
        void DrawIcon(ChaosApp app, Rect r, DpsRow row, DpsTab tab)
        {
            var spec = DpsIcons.Spec(row.Kind, row.Icon);
            if (spec.Kind == "spell")
            {
                var sp = app.Session?.Spells?.ByWords(spec.Words);
                if (app.DrawSpellIcon(r, spec.Words, sp != null ? sp.Id : 0)) return;
            }
            else if (spec.Kind == "item" && app.Dat?.Item((ushort)spec.ItemId) != null) { app.DrawItem(r, (ushort)spec.ItemId, 1); return; }
            var col = Hex(DpsMath.BarColor(row.Kind, tab.Idx)); col.a = 0.9f;
            ChaosApp.Fill(r, col);
            var g = new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontSize = 10 };
            GUI.Label(r, spec.Glyph, g);
        }

        void DrawBars(ChaosApp app, Rect area, List<DpsRow> rows, DpsTab tab)
        {
            if (rows.Count == 0) { GUI.Label(area, Loc.T("Nothing in this tab yet."), hint); return; }
            const float Row = 22f;
            scroll = GUI.BeginScrollView(area, scroll, new Rect(0, 0, area.width - 18, rows.Count * Row));
            float bw = area.width - 18;
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                var rr = new Rect(0, i * Row, bw, Row - 2);
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                var col = Hex(DpsMath.BarColor(r.Kind, tab.Idx)); col.a = 0.75f;
                ChaosApp.Fill(new Rect(rr.x, rr.y, Mathf.Max(1f, rr.width * (float)r.Frac), rr.height), col);
                DrawIcon(app, new Rect(rr.x + 3, rr.y + 3, 16, 16), r, tab);
                GUI.Label(new Rect(rr.x + 24, rr.y + 2, rr.width - 214, 18), r.Name, small);
                GUI.Label(new Rect(rr.xMax - 188, rr.y + 2, 184, 18), DpsMath.Short(r.Total) + "  " + DpsMath.Short(r.Rate) + "/s  " + r.Pct.ToString("0.#") + "%", right);
                if (rr.Contains(Event.current.mousePosition))
                    hover = r.Name + "\n" + DpsMath.Exact(r.Total) + " / " + DpsMath.Exact(r.Rate) + "/s, " + r.Pct.ToString("0.#") + "%\n"
                        + (long)r.Hits + " " + Loc.T("hits") + ", " + (long)r.CritPct + "% " + Loc.T("critical") + ", " + Loc.T("avg") + " " + DpsMath.Exact(r.Avg) + ", " + Loc.T("max") + " " + DpsMath.Exact(r.Max)
                        + (r.Over > 0 ? "\n" + Loc.T("overhealing") + " " + DpsMath.Exact(r.Over) : "") + (DpsMath.IsNote(r.Kind) ? "\n" + Loc.T("A keystone note: how much it changed. Already counted in the other rows.") : "");
            }
            GUI.EndScrollView();
            if (hover.Length > 0)
            {
                var mp = Event.current.mousePosition;
                var tr = new Rect(Mathf.Min(mp.x + 12, Area.width - 270f), Mathf.Min(mp.y + 16, Area.height - 90f), 260f, 84f);
                ChaosApp.Fill(tr, new Color(0f, 0f, 0f, 0.92f));
                GUI.Label(tr, hover, hint);
            }
        }

        // the position and size of the panel are kept in the settings: the corner handle resizes, a moved panel is saved when the button is up
        void PanelFrame(DpsMeter m)
        {
            var set = m.Settings;
            var ev = Event.current;
            var handle = new Rect(Area.width - 16, Area.height - 16, 14, 14);
            ChaosApp.Fill(new Rect(handle.x + 8, handle.y + 3, 2, 10), new Color(1f, 1f, 1f, 0.35f));
            ChaosApp.Fill(new Rect(handle.x + 3, handle.y + 8, 10, 2), new Color(1f, 1f, 1f, 0.35f));
            if (ev.type == EventType.MouseDown && ev.button == 0 && handle.Contains(ev.mousePosition))
            {
                resizing = true; dragged = Vector2.zero; startW = (int)Area.width; startH = (int)Area.height; ev.Use();
            }
            else if (resizing && ev.type == EventType.MouseDrag)
            {
                dragged += ev.delta;
                DpsPanel.Resize(startW, startH, dragged.x, dragged.y, out int nw, out int nh);
                Area.width = nw; Area.height = nh;
                ev.Use();
            }
            else if (resizing && (ev.type == EventType.MouseUp || ev.rawType == EventType.MouseUp))
            {
                resizing = false;
                set.W = (int)Area.width; set.H = (int)Area.height;
                set.X = (int)Area.x; set.Y = (int)Area.y;
                Save(m);
            }
            else if (!resizing && ev.type == EventType.Repaint && !Input.GetMouseButton(0) && (set.X != (int)Area.x || set.Y != (int)Area.y))
            {
                set.X = (int)Area.x; set.Y = (int)Area.y;
                Save(m);
            }
        }

        void DrawParty(Rect area, DpsMeter m, DpsTab tab)
        {
            var rows = DpsMath.PartyRows(m.Party, tab.Idx, m.SegSel == "s");
            if (rows.Count == 0) { GUI.Label(area, Loc.T("No party numbers yet."), hint); return; }
            const float Row = 22f;
            scroll = GUI.BeginScrollView(area, scroll, new Rect(0, 0, area.width - 18, rows.Count * Row));
            float bw = area.width - 18;
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                var rr = new Rect(0, i * Row, bw, Row - 2);
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                ChaosApp.Fill(new Rect(rr.x, rr.y, Mathf.Max(1f, rr.width * (float)r.Frac), rr.height), r.Self ? new Color(0.66f, 0.52f, 0.23f, 0.8f) : new Color(0.35f, 0.29f, 0.42f, 0.8f));
                var old = GUI.contentColor;
                GUI.contentColor = r.Self ? Hex("#f6cf72") : Hex("#f2e8d0");
                GUI.Label(new Rect(rr.x + 4, rr.y + 2, rr.width - 190, 18), r.Name, small);
                GUI.contentColor = old;
                GUI.Label(new Rect(rr.xMax - 188, rr.y + 2, 184, 18), DpsMath.Short(r.Rate) + " " + tab.Rate + "  (" + DpsMath.Short(r.Value) + ")", right);
            }
            GUI.EndScrollView();
        }

        static readonly string[] Columns = { "Total", "%", "Per s", "Hits", "Crit", "Avg", "Max", "Over" };
        static readonly float[] ColW = { 52, 38, 48, 38, 38, 48, 48, 50 };

        void DrawDetails(Rect area, object view, DpsTab tab, List<DpsRow> rows)
        {
            bool heal = tab.Idx == 2 || tab.Idx == 4;
            float nameW = area.width - 18 - 360 - 4;
            float hx = nameW;
            for (int c = 0; c < Columns.Length; c++)
            {
                GUI.Label(new Rect(area.x + hx, area.y, ColW[c], 16), Loc.T(Columns[c]), right);
                hx += ColW[c];
            }
            GUI.Label(new Rect(area.x + 4, area.y, nameW, 16), Loc.T("Source"), small);
            var body = new Rect(area.x, area.y + 18, area.width, area.height - 36);
            if (rows.Count == 0) { GUI.Label(body, Loc.T("Nothing in this tab yet."), hint); }
            else
            {
                const float Row = 20f;
                scroll = GUI.BeginScrollView(body, scroll, new Rect(0, 0, area.width - 18, rows.Count * Row));
                for (int i = 0; i < rows.Count; i++)
                {
                    var r = rows[i];
                    float ry = i * Row;
                    if (i % 2 == 1) ChaosApp.Fill(new Rect(0, ry, area.width - 18, Row), new Color(1f, 1f, 1f, 0.04f));
                    GUI.Label(new Rect(4, ry + 2, nameW - 4, 18), r.Name, small);
                    string[] cells = { DpsMath.Short(r.Total), r.Pct.ToString("0.#") + "%", DpsMath.Short(r.Rate), ((long)r.Hits).ToString(), (long)r.CritPct + "%", DpsMath.Short(r.Avg), DpsMath.Short(r.Max), heal ? DpsMath.Short(r.Over) : "" };
                    float cx = nameW;
                    for (int c = 0; c < cells.Length; c++) { GUI.Label(new Rect(cx, ry + 2, ColW[c], 18), cells[c], right); cx += ColW[c]; }
                }
                GUI.EndScrollView();
            }
            var parts = new List<string>();
            foreach (var e in DpsMath.Elements(view, tab.Idx)) parts.Add(Loc.T(e.Name) + " " + e.Pct.ToString("0.#") + "%");
            if (parts.Count > 0) GUI.Label(new Rect(area.x, area.yMax - 16, area.width, 16), Loc.T("Elements: ") + string.Join(", ", parts), hint);
        }
    }

    // ============================================================================================================================ Codex
    public sealed class CodexWindow : GameWindow
    {
        int tabIndex;
        readonly Dictionary<string, Dictionary<string, string>> values = new Dictionary<string, Dictionary<string, string>>();
        readonly Dictionary<string, string> queries = new Dictionary<string, string>(), selected = new Dictionary<string, string>();
        readonly List<string> history = new List<string>();
        Vector2 listScroll, pageScroll;
        GUIStyle small, hint, head, para, title;
        List<CodexEntry> shown = new List<CodexEntry>();
        string shownKey;
        float pageH = 100f;
        string pageKey;

        public override string Title => Loc.T("Codex");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8f, w / 2 - 380f), 50f, Mathf.Min(760f, w - 16f), Mathf.Min(560f, h - 60f));
        public override void Reset() { shownKey = null; history.Clear(); }

        CodexTab Tab { get { var d = InfoStore.Codex; return d.Ready ? d.Tabs[Mathf.Clamp(tabIndex, 0, d.Tabs.Count - 1)] : null; } }

        Dictionary<string, string> Values(CodexTab t)
        {
            Dictionary<string, string> v;
            if (!values.TryGetValue(t.Id, out v)) values[t.Id] = v = new Dictionary<string, string>();
            return v;
        }

        string Query(CodexTab t) { string q; return queries.TryGetValue(t.Id, out q) ? q : ""; }

        /// <summary>Opens the Codex on an entry; false when it has none of that id.</summary>
        public bool OpenEntry(string id)
        {
            int ti;
            var e = CodexView.Find(InfoStore.Codex, id, out ti);
            if (e == null) return false;
            Open = true;
            tabIndex = ti;
            var tab = InfoStore.Codex.Tabs[ti];
            queries[tab.Id] = "";
            Values(tab).Clear();
            selected[tab.Id] = id;
            shownKey = null;
            pageScroll = Vector2.zero;
            return true;
        }

        /// <summary>A tab, filter or option text: the Codex table first (pt-BR), then the client's own texts.</summary>
        static string Cx(string text) { string s = CodexText.T(text); return s != text ? s : Loc.T(text); }

        void Styles(ChaosApp app)
        {
            if (small != null) return;
            small = new GUIStyle(app.SmallStyle) { fontSize = 12, clipping = TextClipping.Clip };
            hint = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true };
            hint.normal.textColor = new Color(1f, 1f, 1f, 0.6f);
            head = new GUIStyle(app.TitleStyle) { fontSize = 15, wordWrap = true };
            para = new GUIStyle(app.SmallStyle) { fontSize = 12, wordWrap = true };
            title = new GUIStyle(app.TitleStyle) { fontSize = 18, wordWrap = true };
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var data = InfoStore.Codex;
            Styles(app);
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;
            if (!data.Ready) { GUI.Label(new Rect(x, y, w, 40), Loc.T("The Codex data is missing from this build."), hint); return; }
            var names = new string[data.Tabs.Count];
            for (int i = 0; i < names.Length; i++) names[i] = Cx(data.Tabs[i].Name);
            int t = GUI.SelectionGrid(new Rect(x, y, w, 50), tabIndex, names, 6);
            if (t != tabIndex) { tabIndex = t; shownKey = null; listScroll = pageScroll = Vector2.zero; history.Clear(); }
            y += 54;
            var tab = Tab;
            var vals = Values(tab);
            // filters: a button each, a click goes to the next option
            float fx = x;
            int n = tab.Filters.Count;
            float fw = n > 0 ? Mathf.Min(150f, (w - 220f - 6f * n) / n) : 0f;
            foreach (var f in tab.Filters)
            {
                string cur;
                vals.TryGetValue(f.Key, out cur);
                int oi = Mathf.Max(0, f.Options.FindIndex(o => o.Value == (cur ?? "")));
                if (GUI.Button(new Rect(fx, y, fw, 22), new GUIContent(Cx(f.Options[oi].Text), Cx(f.Label))))
                {
                    oi = (oi + (Event.current.button == 1 ? f.Options.Count - 1 : 1)) % f.Options.Count;
                    vals[f.Key] = f.Options[oi].Value;
                    shownKey = null;
                }
                fx += fw + 6f;
            }
            string q = Query(tab);
            GUI.SetNextControlName("codexSearch");
            string nq = GUI.TextField(new Rect(x + w - 210, y, 210, 22), q, 60);
            if (GUI.GetNameOfFocusedControl() == "codexSearch") app.MarkTextEditing();
            if (nq != q) { queries[tab.Id] = nq; shownKey = null; }
            if (nq.Length == 0 && GUI.GetNameOfFocusedControl() != "codexSearch") GUI.Label(new Rect(x + w - 204, y + 2, 200, 18), Loc.T("Search..."), hint);
            y += 28;

            string key = tab.Id + "|" + Query(tab);
            foreach (var kv in vals) key += "|" + kv.Key + "=" + kv.Value;
            if (key != shownKey)
            {
                shownKey = key;
                shown = CodexView.List(tab, Query(tab), vals, data);
                string sel;
                if (!selected.TryGetValue(tab.Id, out sel) || !shown.Exists(e => e.Id == sel)) selected[tab.Id] = shown.Count > 0 ? shown[0].Id : "";
                pageKey = null;
            }
            int? level = CodexView.LevelOf(vals, tab.Filters);

            float listW = Mathf.Min(250f, w * 0.34f);
            var listRect = new Rect(x, y, listW, inner.yMax - y - 20);
            DrawList(listRect, tab, level, data);
            GUI.Label(new Rect(x, inner.yMax - 18, listW, 16), Loc.T("{0} of {1}", shown.Count, tab.Entries.Count), hint);
            var pageRect = new Rect(x + listW + 8f, y, w - listW - 8f, inner.yMax - y);
            string selId = selected[tab.Id];
            var entry = shown.Find(e => e.Id == selId);
            DrawPage(app, pageRect, entry, level, data);
        }

        void DrawList(Rect r, CodexTab tab, int? level, CodexData data)
        {
            const float Row = 38f;
            ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.04f));
            if (shown.Count == 0) { GUI.Label(new Rect(r.x + 4, r.y + 4, r.width - 8, 40), Loc.T("Nothing found."), hint); return; }
            listScroll = GUI.BeginScrollView(r, listScroll, new Rect(0, 0, r.width - 18, shown.Count * Row));
            for (int i = 0; i < shown.Count; i++)
            {
                var e = shown[i];
                var rr = new Rect(0, i * Row, r.width - 18, Row - 2);
                bool on = selected[tab.Id] == e.Id;
                ChaosApp.Fill(rr, on ? new Color(0.45f, 0.3f, 0.12f, 0.9f) : new Color(1f, 1f, 1f, 0.05f));
                var old = GUI.contentColor;
                if (e.Color.Length > 0) GUI.contentColor = Ui.Hex(e.Color);
                GUI.Label(new Rect(rr.x + 4, rr.y + 1, rr.width - 8, 16), e.Name, small);
                GUI.contentColor = old;
                GUI.Label(new Rect(rr.x + 4, rr.y + 18, rr.width - 8, 16), CodexView.Subline(e, level, data), hint);
                if (GUI.Button(rr, GUIContent.none, GUIStyle.none)) { selected[tab.Id] = e.Id; history.Clear(); pageScroll = Vector2.zero; pageKey = null; }
            }
            GUI.EndScrollView();
        }

        // the page of an entry: one pass measures, the same pass draws
        float Page(ChaosApp app, float w, CodexEntry e, int? level, CodexData data, bool draw)
        {
            float y = 0;
            var tint = GUI.contentColor;
            if (draw && e.Color.Length > 0) GUI.contentColor = Ui.Hex(e.Color);
            y = Ui.Para(e.Name, title, 0, y, w);
            GUI.contentColor = tint;
            y = Ui.Para(CodexView.Subline(e, level, data), hint, 0, y, w);
            if (e.Items.Count > 0)
            {
                for (int i = 0; i < e.Items.Count; i++)
                {
                    var br = new Rect(0, y, w, 22);
                    string label = e.Items.Count > 1 ? Loc.T("Where to find: tier {0}", i + 1) : Loc.T("Where to find: drops, shops, recipes and rewards");
                    if (draw && GUI.Button(br, label)) { var f = app.Session?.Utils?.Finder; if (f != null) f.ShowItem(e.Items[i], 0); }
                    y += 26;
                }
            }
            foreach (var raw in e.Sections)
            {
                var s = CodexView.Section(raw, data);
                if (s == null) continue;
                if (s.H.Length > 0) y = Ui.Para(CodexText.T(s.H), head, 0, y + 4, w, "#f6cf72");
                foreach (var p in s.Paragraphs) y = Ui.Para(CodexText.T(p), para, 0, y, w);
                if (s.Rows != null)
                {
                    y = Table(app, s, w, y, level, data, draw);
                    if (s.Tiers && level.HasValue)
                    {
                        var ch = CodexView.TierChances(level.Value, data);
                        var parts = new List<string>();
                        foreach (var r in CodexView.TierRows(level.Value, data)) parts.Add("T" + r.Key + " " + ch[r.Key].ToString("0.#") + "%");
                        y = Ui.Para(Loc.T("Marked: the tiers that roll at item level {0} ({1}).", level.Value, string.Join(", ", parts)), hint, 0, y, w);
                    }
                }
                else if (s.Links != null)
                {
                    foreach (var id in s.Links)
                    {
                        if (draw && GUI.Button(new Rect(0, y, w, 22), Loc.T("See: {0}", LinkName(id)))) { history.Add(selected[Tab.Id]); GoTo(id); }
                        y += 26;
                    }
                }
            }
            return y + 8;
        }

        static string LinkName(string id)
        {
            int ti;
            var e = CodexView.Find(InfoStore.Codex, id, out ti);
            return e != null ? e.Name : id;
        }

        void GoTo(string id)
        {
            int ti;
            if (CodexView.Find(InfoStore.Codex, id, out ti) == null) return;
            var tab = InfoStore.Codex.Tabs[ti];
            tabIndex = ti;
            queries[tab.Id] = ""; Values(tab).Clear();
            selected[tab.Id] = id;
            shownKey = null; pageKey = null; pageScroll = Vector2.zero;
        }

        float Table(ChaosApp app, CodexSection s, float w, float y, int? level, CodexData data, bool draw)
        {
            var widths = CodexView.Columns(s.W, w - 8, 8);
            var marks = CodexView.Highlight(s, level, data);
            var rows = new List<List<string>>();
            if (s.Cols.Count > 0 && string.Join("", s.Cols).Length > 0) rows.Add(s.Cols);
            int headRows = rows.Count;
            foreach (var r in s.Rows) rows.Add(r);
            for (int ri = 0; ri < rows.Count; ri++)
            {
                var cells = rows[ri];
                bool head = ri < headRows;
                int dataIndex = ri - headRows;
                string link = !head && s.Links != null && dataIndex < s.Links.Count ? s.Links[dataIndex] : "";
                float rh = 18f;
                for (int c = 0; c < cells.Count && c < widths.Length; c++) rh = Mathf.Max(rh, Ui.Height(CodexText.T(cells[c]), para, widths[c]) + 2f);
                var rr = new Rect(0, y, w, rh);
                if (draw)
                {
                    bool mark = !head && marks.Contains(dataIndex + 1);
                    ChaosApp.Fill(rr, head ? new Color(0.9f, 0.72f, 0.29f, 0.10f) : mark ? new Color(0.96f, 0.81f, 0.45f, 0.19f) : (ri % 2 == 0 ? new Color(1f, 1f, 1f, 0.04f) : new Color(0, 0, 0, 0)));
                    float cx = 4;
                    for (int c = 0; c < cells.Count && c < widths.Length; c++)
                    {
                        string hex = head ? "#c8a85a" : (c == 0 && link.Length > 0) ? "#7fa8ff" : mark ? "#f6cf72" : null;
                        Ui.Text(new Rect(cx, y + 1, widths[c], rh), CodexText.T(cells[c]), para, hex);
                        cx += widths[c] + 8;
                    }
                    if (link.Length > 0 && GUI.Button(rr, GUIContent.none, GUIStyle.none)) { history.Add(selected[Tab.Id]); GoTo(link); }
                }
                y += rh;
            }
            return y + 4;
        }

        void DrawPage(ChaosApp app, Rect r, CodexEntry e, int? level, CodexData data)
        {
            if (e == null) { GUI.Label(new Rect(r.x, r.y, r.width, 24), Loc.T("Nothing to show"), head); return; }
            float cw = r.width - 18f;
            string key = e.Id + "|" + (level.HasValue ? level.Value : -1) + "|" + (int)cw;
            if (key != pageKey) { pageKey = key; pageH = Page(app, cw, e, level, data, false); }
            if (history.Count > 0 && GUI.Button(new Rect(r.xMax - 70, r.y, 70, 20), Loc.T("Back")))
            {
                string back = history[history.Count - 1];
                history.RemoveAt(history.Count - 1);
                GoTo(back);
                return;
            }
            pageScroll = GUI.BeginScrollView(r, pageScroll, new Rect(0, 0, cw, pageH));
            Page(app, cw, e, level, data, true);
            GUI.EndScrollView();
        }
    }

    // ============================================================================================================================ Help search
    public sealed class HelpSearchWindow : GameWindow
    {
        string query = "", lastQuery = null;
        Vector2 scroll;
        GUIStyle small, hint, head, para;
        List<HelpResult> results = new List<HelpResult>();
        List<string> words = new List<string>();

        public override string Title => Loc.T("Help");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8f, w / 2 - 270f), 70f, Mathf.Min(540f, w - 16f), Mathf.Min(520f, h - 80f));
        public override void Reset() { query = ""; lastQuery = null; results.Clear(); }

        void Styles(ChaosApp app)
        {
            if (small != null) return;
            small = new GUIStyle(app.SmallStyle) { fontSize = 12, clipping = TextClipping.Clip };
            hint = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true };
            hint.normal.textColor = new Color(1f, 1f, 1f, 0.6f);
            head = new GUIStyle(app.TitleStyle) { fontSize = 14, wordWrap = true };
            para = new GUIStyle(app.SmallStyle) { fontSize = 12, wordWrap = true };
        }

        /// <summary>Fills the box and the list.</summary>
        public void Search(string text) { query = text ?? ""; lastQuery = null; }

        void Activate(ChaosApp app, HelpDoc d)
        {
            if (d.Kind == "codex") app.OpenCodex(d.Key);
            else if (d.Kind == "card") app.ShowHow(d.Key);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            Styles(app);
            string lang = Loc.Language;
            var index = InfoStore.Help;
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;
            GUI.SetNextControlName("helpQuery");
            query = GUI.TextField(new Rect(x, y, w, 26), query, 120);
            if (GUI.GetNameOfFocusedControl() == "helpQuery") app.MarkTextEditing();
            if (query.Length == 0 && GUI.GetNameOfFocusedControl() != "helpQuery") GUI.Label(new Rect(x + 6, y + 4, w - 12, 18), Loc.T("Ask a question: how do I get orbs?"), hint);
            y += 32;
            if (query != lastQuery) { lastQuery = query; results = HelpSearch.Search(index, query, out words); scroll = Vector2.zero; }
            var area = new Rect(x, y, w, inner.yMax - y);
            if (query.Trim().Length == 0)
            {
                var steps = index.Steps;
                float contentH = 40f + steps.Count * 52f;
                scroll = GUI.BeginScrollView(area, scroll, new Rect(0, 0, w - 18, contentH));
                float cy = Ui.Para(HelpSearch.Pick(index.Intro, lang), para, 0, 0, w - 18);
                cy += 6;
                foreach (var s in steps)
                {
                    var rr = new Rect(0, cy, w - 18, 48);
                    ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                    GUI.Label(new Rect(rr.x + 4, rr.y + 2, rr.width - 8, 16), HowItWorks.IsPt(lang) && s.Doc.Title.Pt.Length > 0 ? s.Doc.Title.Pt : s.Doc.Title.En, head);
                    GUI.Label(new Rect(rr.x + 4, rr.y + 20, rr.width - 8, 28), HelpSearch.Pick(s.Tip, lang), hint);
                    if (GUI.Button(rr, GUIContent.none, GUIStyle.none)) Activate(app, s.Doc);
                    cy += 52;
                }
                GUI.EndScrollView();
                return;
            }
            if (results.Count == 0) { GUI.Label(area, Loc.T("Nothing found. Try other words."), hint); return; }
            const float Row = 64f;
            scroll = GUI.BeginScrollView(area, scroll, new Rect(0, 0, w - 18, results.Count * Row));
            for (int i = 0; i < results.Count; i++)
            {
                var d = results[i].Doc;
                var rr = new Rect(0, i * Row, w - 18, Row - 4);
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                string title = HowItWorks.IsPt(lang) && d.Title.Pt.Length > 0 ? d.Title.Pt : d.Title.En;
                string where = d.Kind == "codex" ? Loc.T("Codex: {0}", d.Tab) : d.Menu.Length > 0 ? d.Menu : "";
                if (d.Level.HasValue && d.Level.Value > 0) where += (where.Length > 0 ? "  |  " : "") + Loc.T("Level {0}", d.Level.Value);
                GUI.Label(new Rect(rr.x + 4, rr.y + 2, rr.width - 8, 18), title, head);
                GUI.Label(new Rect(rr.x + 4, rr.y + 20, rr.width - 8, 14), where, hint);
                GUI.Label(new Rect(rr.x + 4, rr.y + 34, rr.width - 8, 28), HelpSearch.SnippetOf(d, words, lang), hint);
                if (GUI.Button(rr, GUIContent.none, GUIStyle.none)) Activate(app, d);
            }
            GUI.EndScrollView();
        }
    }

    // ============================================================================================================================ How it works
    public sealed class HowItWorksWindow : GameWindow
    {
        HowCard card;
        Vector2 scroll;
        GUIStyle head, para;
        bool autoOpen = true, autoLoaded;
        readonly Dictionary<string, HashSet<string>> seen = new Dictionary<string, HashSet<string>>();
        string seenFor;

        public override string Title => Loc.T("How it works");
        public override bool InMenu => false;
        public override string HowKey => null;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8f, w / 2 - 230f), 90f, Mathf.Min(460f, w - 16f), Mathf.Min(430f, h - 100f));
        public override void Reset() { card = null; seenFor = null; seen.Clear(); }

        public override void Tick(ChaosApp app) { if (app.Session != null) app.HowCheck(this); }

        /// <summary>Opens the card of a feature; false when there is none.</summary>
        public bool Show(string key)
        {
            var c = InfoStore.How.Find(key);
            if (c == null) return false;
            card = c; Open = true; scroll = Vector2.zero;
            return true;
        }

        /// <summary>A feature window just opened: its card opens by itself, once per character and card, unless the box below the card turned that off.</summary>
        public void FirstOpen(ChaosApp app, string key)
        {
            if (!autoLoaded) { autoOpen = PlayerPrefs.GetInt("chaos.howitworks.auto", 1) == 1; autoLoaded = true; }
            string name = app.World?.Player?.Name;
            if (name == null || !autoOpen) return;
            string ck = HowItWorks.CharKey(name), prefs = "chaos.howitworks.seen." + ck;
            if (seenFor != ck)
            {
                seenFor = ck;
                var set = new HashSet<string>();
                foreach (var k in PlayerPrefs.GetString(prefs, "").Split(',')) if (k.Length > 0) set.Add(k);
                seen[ck] = set;
            }
            if (!HowItWorks.FirstOpen(seen, ck, key)) return;
            PlayerPrefs.SetString(prefs, string.Join(",", seen[ck]));
            PlayerPrefs.Save();
            Show(key);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            if (card == null) return;
            if (head == null)
            {
                head = new GUIStyle(app.TitleStyle) { fontSize = 14, wordWrap = true };
                para = new GUIStyle(app.SmallStyle) { fontSize = 13, wordWrap = true };
            }
            string lang = Loc.Language;
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;
            GUI.Label(new Rect(x, y, w, 24), HowItWorks.Title(card, lang), head);
            y += 28;
            var rows = HowItWorks.RowsOf(card, lang);
            float h = 0;
            foreach (var r in rows) h += 24f + Ui.Height(r.Value, para, w - 18) + 6f;
            var area = new Rect(x, y, w, inner.yMax - y - 26);
            scroll = GUI.BeginScrollView(area, scroll, new Rect(0, 0, w - 18, h));
            float cy = 0;
            foreach (var r in rows)
            {
                GUI.Label(new Rect(0, cy, w - 18, 20), Loc.T(HowItWorks.Heading(r.Key)), head);
                cy += 22;
                cy = Ui.Para(r.Value, para, 0, cy, w - 18) + 4;
            }
            GUI.EndScrollView();
            bool auto = GUI.Toggle(new Rect(x, inner.yMax - 24, w, 22), autoOpen, Loc.T("Open the card the first time I open a window"));
            if (auto != autoOpen) { autoOpen = auto; PlayerPrefs.SetInt("chaos.howitworks.auto", auto ? 1 : 0); }
        }
    }

    // ============================================================================================================================ weapon list
    public sealed class ProficiencyWindow : GameWindow
    {
        List<ProficiencyWeapon> weapons;
        DatFile weaponsFor;
        int seen, category = -1;
        string query = "";
        Vector2 scroll;
        GUIStyle small, hint;

        public override string Title => Loc.T("Weapon Proficiency");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8f, w / 2 - 230f), 80f, Mathf.Min(460f, w - 16f), Mathf.Min(480f, h - 90f));

        protected override void Body(ChaosApp app, Rect inner)
        {
            if (app.Dat == null) return;
            if (small == null)
            {
                small = new GUIStyle(app.SmallStyle) { fontSize = 12, clipping = TextClipping.Clip };
                hint = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true };
                hint.normal.textColor = new Color(1f, 1f, 1f, 0.6f);
            }
            if (weapons == null || weaponsFor != app.Dat) { weaponsFor = app.Dat; weapons = ProficiencyCatalog.FromDat(app.Dat, out seen); }
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;
            var names = new List<string> { Loc.T("All") };
            foreach (int c in ProficiencyCatalog.Categories) names.Add(Loc.T(ProficiencyCatalog.CategoryName(c)));
            int sel = category < 0 ? 0 : System.Array.IndexOf(ProficiencyCatalog.Categories, category) + 1;
            int t = GUI.SelectionGrid(new Rect(x, y, w, 50), sel, names.ToArray(), 4);
            if (t != sel) { category = t == 0 ? -1 : ProficiencyCatalog.Categories[t - 1]; scroll = Vector2.zero; }
            y += 54;
            GUI.SetNextControlName("profQuery");
            query = GUI.TextField(new Rect(x, y, w, 22), query, 40);
            if (GUI.GetNameOfFocusedControl() == "profQuery") app.MarkTextEditing();
            y += 28;
            var list = ProficiencyCatalog.Filter(weapons, category, query);
            const float Row = 22f;
            var area = new Rect(x, y, w, inner.yMax - y - 34);
            scroll = GUI.BeginScrollView(area, scroll, new Rect(0, 0, w - 18, list.Count * Row));
            for (int i = 0; i < list.Count; i++)
            {
                var wp = list[i];
                var rr = new Rect(0, i * Row, w - 18, Row - 2);
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                app.DrawItem(new Rect(rr.x + 2, rr.y, 20, 20), (ushort)wp.Id, 1);
                GUI.Label(new Rect(rr.x + 28, rr.y + 2, rr.width - 150, 18), wp.Name, small);
                GUI.Label(new Rect(rr.xMax - 118, rr.y + 2, 116, 18), Loc.T(ProficiencyCatalog.CategoryName(wp.Category)), hint);
            }
            GUI.EndScrollView();
            GUI.Label(new Rect(x, inner.yMax - 32, w, 30), Loc.T("{0} weapons. The perk trees and weapon experience are not in this client yet.", weapons.Count), hint);
        }
    }
}
