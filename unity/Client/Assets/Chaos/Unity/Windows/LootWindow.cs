// The loot window (Ctrl+L): the loot channel (what each kill dropped, a click takes an item, Shift takes one of a stack), the loot filter
// settings (what glows and what dims, presets) and the ground label settings. It also owns the two models of the server's loot systems and
// scans the ground for labels once per frame (the labels are drawn by ChaosApp.Loot.cs over the map).
// Core: LootFilter.cs (opcode 238), GroundLabels.cs (opcode 230). The label settings are kept per character in PlayerPrefs (chaos.groundlabels.<name>).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class LootWindow : GameWindow
    {
        LootFilterModel filter;
        GroundLabelsModel ground;
        GameSession modelsFor;
        string loadedFor;
        int lastFrame = -1;
        double lastScan = -1e9;
        Pos lastPos;
        bool synced, wasOpen;
        int tab;
        Vector2 scroll;
        GUIStyle small, hint;

        public override string Title => Loc.T("Loot");
        public override KeyCode Hotkey => KeyCode.D;
        protected override Rect Place(float w, float h) => new Rect(w - 392f, 130f, 372f, 440f);

        public LootFilterModel Filter => filter;
        public GroundLabelsModel Ground => ground;

        public override void Reset() { filter = null; ground = null; modelsFor = null; loadedFor = null; synced = false; wasOpen = false; }

        public override void Tick(ChaosApp app)
        {
            var s = app.Session;
            if (s == null) return;
            string name = app.World?.Player?.Name;
            if (filter == null || modelsFor != s)
            {
                modelsFor = s;
                filter = new LootFilterModel(s.Ext) { Clock = () => s.Now / 1000.0 };
                ground = new GroundLabelsModel(s.Ext) { Clock = () => s.Now / 1000.0 };
                filter.ShowRequested += () => { Open = true; if (tab == 0) tab = 1; };
                synced = false; loadedFor = null;
            }
            if (name != null && name != loadedFor)
            {
                loadedFor = name;
                ground.Settings = GroundLabelSettings.From(Json.TryParse(PlayerPrefs.GetString("chaos.groundlabels." + name.ToLowerInvariant(), "")));
            }
            if (Time.frameCount == lastFrame) return;   // OnGUI runs several times a frame
            lastFrame = Time.frameCount;
            if (!synced && s.Now > 1000) { synced = true; filter.Sync(); }
            var me = app.World?.Player;
            if (me == null) return;
            double now = s.Now;
            bool moved = me.Position != lastPos;
            if (now - lastScan >= (moved ? GroundLabelRules.MoveScanMs : GroundLabelRules.ScanMs))
            {
                lastScan = now;
                lastPos = me.Position;
                ground.Scan(app.World, app.World.Center);
            }
            if (Open && !wasOpen && tab != 0) filter.Open();
            wasOpen = Open;
        }

        void Styles(ChaosApp app)
        {
            if (small != null) return;
            small = new GUIStyle(app.SmallStyle) { fontSize = 12, clipping = TextClipping.Clip };
            hint = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true };
            hint.normal.textColor = new Color(1f, 1f, 1f, 0.6f);
        }

        static Color Hex(string hex)
        {
            Color c;
            return ColorUtility.TryParseHtmlString(hex ?? "", out c) ? c : new Color(0.85f, 0.81f, 0.75f);
        }

        void SaveLabels()
        {
            if (loadedFor == null) return;
            PlayerPrefs.SetString("chaos.groundlabels." + loadedFor.ToLowerInvariant(), Json.Serialize(ground.Settings.ToDict()));
            PlayerPrefs.Save();
            ground.Dirty = true;
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            if (filter == null) return;
            Styles(app);
            float x = inner.x + 4, w = inner.width - 8, y = inner.y + 2;
            int t = GUI.Toolbar(new Rect(x, y, w, 24), tab, new[] { Loc.T("Loot"), Loc.T("Filter"), Loc.T("Labels") });
            if (t != tab) { tab = t; scroll = Vector2.zero; if (t != 0) filter.Open(); }
            y += 30;
            var area = new Rect(x, y, w, inner.yMax - y);
            if (tab == 0) DrawLoot(app, area);
            else if (tab == 1) DrawFilter(area);
            else DrawLabels(area);
        }

        // ---- the loot channel ----
        void DrawLoot(ChaosApp app, Rect r)
        {
            if (filter.Message.Length > 0 && app.Session != null && app.Session.Now / 1000.0 - filter.MessageAt < 6)
                GUI.Label(new Rect(r.x, r.y, r.width, 18), filter.Message, new GUIStyle(hint) { normal = { textColor = new Color(1f, 0.48f, 0.35f) } });
            var area = new Rect(r.x, r.y + 20, r.width, r.height - 20);
            if (filter.Kills.Count == 0) { GUI.Label(area, Loc.T("Nothing looted yet. Kills drop their items here."), hint); return; }
            float rowH = 22f;
            float total = 0;
            foreach (var k in filter.Kills) total += 20f + Mathf.Max(1, k.Items.Count) * rowH + 4f;
            scroll = GUI.BeginScrollView(area, scroll, new Rect(0, 0, r.width - 18, total));
            float y = 0;
            var e = Event.current;
            foreach (var k in filter.Kills)
            {
                GUI.Label(new Rect(0, y, r.width - 18, 18), k.Monster == "" ? Loc.T("Unknown") : k.Monster, small);
                y += 20;
                if (k.Items.Count == 0) { GUI.Label(new Rect(8, y, r.width - 26, rowH), Loc.T("Nothing to loot"), hint); y += rowH; }
                foreach (var it in k.Items)
                {
                    var rr = new Rect(8, y, r.width - 26, rowH - 2);
                    bool gone;
                    int count = LootFilterRules.IconCount(it, out gone);
                    bool dim = gone || k.Decayed;
                    ChaosApp.Fill(rr, new Color(1f, 1f, 1f, dim ? 0.02f : 0.07f));
                    var tint = GUI.color;
                    var col = Hex(LootFilterRules.Color(it));
                    if (dim) col.a = 0.4f;
                    GUI.color = col;
                    GUI.Label(new Rect(rr.x + 4, rr.y + 2, rr.width - 40, 18), (count > 1 ? count + "x " : "") + LootFilterRules.Label(it), small);
                    GUI.color = tint;
                    if (!dim && rr.Contains(e.mousePosition))
                    {
                        GUI.tooltip = LootFilterRules.Tooltip(it);
                        if (e.type == EventType.MouseDown && e.button == 0) { filter.Take(k, it, e.shift); e.Use(); }
                    }
                    y += rowH;
                }
                y += 4;
            }
            GUI.EndScrollView();
            if (!string.IsNullOrEmpty(GUI.tooltip)) GUI.Label(new Rect(r.x, r.yMax - 52, r.width, 52), GUI.tooltip, hint);
        }

        // ---- the filter ----
        int RarityIndex(int id) { int i = System.Array.IndexOf(LootFilterRules.RarityIds, id); return i + 1; }

        int RarityStepper(Rect r, int id)
        {
            int idx = RarityIndex(id);   // 0 = off
            if (GUI.Button(new Rect(r.x, r.y, 24, r.height), "-")) idx = Mathf.Max(0, idx - 1);
            GUI.Label(new Rect(r.x + 24, r.y + 2, r.width - 48, r.height), LootFilterRules.ThresholdText(idx == 0 ? 0 : LootFilterRules.RarityIds[idx - 1]), new GUIStyle(small) { alignment = TextAnchor.UpperCenter });
            if (GUI.Button(new Rect(r.xMax - 24, r.y, 24, r.height), "+")) idx = Mathf.Min(LootFilterRules.RarityIds.Length, idx + 1);
            return idx == 0 ? 0 : LootFilterRules.RarityIds[idx - 1];
        }

        void DrawFilter(Rect r)
        {
            if (!filter.Loaded) { GUI.Label(r, Loc.T("Loading..."), hint); return; }
            var s = filter.Settings.Copy();
            float x = r.x, w = r.width, y = r.y;
            if (filter.Presets.Count > 0)
            {
                GUI.Label(new Rect(x, y, w, 18), Loc.T("Presets"), small);
                y += 20;
                float bw = (w - 4 * (filter.Presets.Count - 1)) / filter.Presets.Count;
                for (int i = 0; i < filter.Presets.Count; i++)
                    if (GUI.Button(new Rect(x + i * (bw + 4), y, bw, 24), filter.Presets[i].Value)) filter.Preset(filter.Presets[i].Key);
                y += 30;
            }
            GUI.Label(new Rect(x, y + 2, w - 130, 20), Loc.T("Glow on gear from"), small);
            s.Highlight = RarityStepper(new Rect(x + w - 126, y, 126, 22), s.Highlight); y += 26;
            GUI.Label(new Rect(x, y + 2, w - 130, 20), Loc.T("Dim gear below"), small);
            s.Dim = RarityStepper(new Rect(x + w - 126, y, 126, 22), s.Dim); y += 26;
            GUI.Label(new Rect(x, y + 2, w - 130, 20), Loc.T("Glow on a modifier of"), small);
            if (GUI.Button(new Rect(x + w - 126, y, 24, 22), "-")) s.Tier = Mathf.Max(0, s.Tier - 1);
            GUI.Label(new Rect(x + w - 102, y + 2, 78, 20), s.Tier == 0 ? Loc.T("Off") : "T" + s.Tier + "+", new GUIStyle(small) { alignment = TextAnchor.UpperCenter });
            if (GUI.Button(new Rect(x + w - 24, y, 24, 22), "+")) s.Tier = Mathf.Min(LootFilterRules.MaxTier, s.Tier + 1);
            y += 30;
            foreach (var c in LootFilterRules.Categories)
            {
                bool on = GUI.Toggle(new Rect(x, y, w, 22), s.Show[c], Loc.T("Show") + " " + LootFilterRules.CategoryName(c).ToLowerInvariant());
                s.Show[c] = on;
                y += 24;
            }
            GUI.Label(new Rect(x, y, w, 30), Loc.T("Unchecked categories are dimmed (still lootable). Uniques and orbs always glow."), hint);
            y += 34;
            s.Notify = GUI.Toggle(new Rect(x, y, w, 22), s.Notify, Loc.T("Rare-drop message"));
            if (!SameSettings(s, filter.Settings)) filter.Set(s);
        }

        static bool SameSettings(LootFilterSettings a, LootFilterSettings b)
        {
            if (a.Highlight != b.Highlight || a.Dim != b.Dim || a.LootMin != b.LootMin || a.LootFrom != b.LootFrom || a.Tier != b.Tier || a.Icons != b.Icons || a.Notify != b.Notify) return false;
            foreach (var c in LootFilterRules.Categories) if (a.Show[c] != b.Show[c]) return false;
            return true;
        }

        // ---- ground labels ----
        void DrawLabels(Rect r)
        {
            var s = ground.Settings;
            float x = r.x, w = r.width, y = r.y;
            GUI.Label(new Rect(x, y, w, 30), Loc.T("Names over the items on the ground, by these rules"), hint);
            y += 34;
            bool changed = false;
            bool v = GUI.Toggle(new Rect(x, y, w, 22), s.Enabled, Loc.T("Ground labels")); changed |= v != s.Enabled; s.Enabled = v; y += 24;
            v = GUI.Toggle(new Rect(x, y, w, 22), s.RarePlus, Loc.T("Magic and better always get a label")); changed |= v != s.RarePlus; s.RarePlus = v; y += 24;
            v = GUI.Toggle(new Rect(x, y, w, 22), s.AltAll, Loc.T("Hold Alt to show every item")); changed |= v != s.AltAll; s.AltAll = v; y += 24;
            v = GUI.Toggle(new Rect(x, y, w, 22), s.Corpses, Loc.T("Corpse labels")); changed |= v != s.Corpses; s.Corpses = v; y += 24;
            v = GUI.Toggle(new Rect(x, y, w, 22), s.Timers, Loc.T("Decay timers")); changed |= v != s.Timers; s.Timers = v; y += 28;
            GUI.Label(new Rect(x, y + 2, 60, 20), Loc.T("Size"), small);
            string[] sizes = { Loc.T("Small"), Loc.T("Normal"), Loc.T("Large") };
            int cur = System.Array.IndexOf(GroundLabelRules.SizeOrder, s.Size);
            int next = GUI.Toolbar(new Rect(x + 60, y, w - 60, 22), cur < 0 ? 1 : cur, sizes);
            if (next != cur) { s.Size = GroundLabelRules.SizeOrder[next]; changed = true; }
            y += 30;
            GUI.Label(new Rect(x, y, w, 30), Loc.T("Click a corpse label to open the corpse."), hint);
            if (changed) SaveLabels();
        }
    }
}
