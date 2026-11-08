// Phase 7, track Z: windows and HUD pieces of the gameplay system rows (docs/UNITY_PARITY.md). Models: Core/Phase7Z*.cs.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>game_bestiary: the task tracker HUD (the active kill tasks and bounty contracts with a thin bar each). Opens by itself while a task is active, a click on the title
    /// folds it, the x or the Hunt menu entry Task Tracker turns it off (saved per install). Not a menu window: the entry is act:tracker.</summary>
    public sealed class TaskTrackerWindow : GameWindow
    {
        public override string Title => Loc.T("Tasks");
        public override bool InMenu => false;
        protected override Rect Place(float w, float h) => new Rect(w - 178 - 232 - 214, h - 300, 214, 80);

        bool wasOpen, loaded;

        static TaskTrackerState Tracker(ChaosApp app) => app.Session?.Bestiary?.Tracker;

        public override void Reset() { wasOpen = false; loaded = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var t = Tracker(app);
            if (t == null) return;
            if (!loaded)
            {
                loaded = true;
                try { t.Enabled = PlayerPrefs.GetInt(TaskTrackerState.PrefsEnabled, 1) == 1; t.Folded = PlayerPrefs.GetInt(TaskTrackerState.PrefsFolded, 0) == 1; } catch { }
            }
            int rows = TaskTrackerState.Rows(app.Session.Bestiary.TrackerRows).Count;
            bool want = t.Visible(rows);
            if (wasOpen && !Open && want)
            {
                // the player closed it with the x: it stays off
                t.Enabled = false; t.Opened = false; want = false;
                Save(t);
            }
            if (Open != want) Open = want;
            wasOpen = Open;
            if (Open) Area.height = t.Folded ? 30 : 32 + Mathf.Max(1, rows) * 28;
        }

        static void Save(TaskTrackerState t)
        {
            try { PlayerPrefs.SetInt(TaskTrackerState.PrefsEnabled, t.Enabled ? 1 : 0); PlayerPrefs.SetInt(TaskTrackerState.PrefsFolded, t.Folded ? 1 : 0); PlayerPrefs.Save(); } catch { }
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var t = Tracker(app);
            if (t == null) return;
            var rows = TaskTrackerState.Rows(app.Session.Bestiary.TrackerRows);
            var title = new Rect(inner.x + 2, inner.y - 2, inner.width - 4, 18);
            if (GUI.Button(title, new GUIContent(t.Folded ? Loc.T("Tasks ({0}) +", rows.Count) : Loc.T("Fold"), Loc.T("Click to fold or unfold the list.")), GUIStyle.none))
            {
                t.Fold();
                Save(t);
            }
            if (t.Folded) return;
            float y = inner.y + 18;
            if (rows.Count == 0)
            {
                CU.Label(app, new Rect(inner.x + 4, y, inner.width - 8, 40), Loc.T(TaskTrackerState.EmptyHint), "#8c8070");
                return;
            }
            foreach (var r in rows)
            {
                string text = BestiaryState.TrackerLine(r, out int pct, out bool done);
                CU.Label(app, new Rect(inner.x + 2, y, 14, 16), TaskTrackerState.Kind(r), TaskTrackerState.KindColor(r), false);
                CU.Label(app, new Rect(inner.x + 16, y, inner.width - 20, 16), text, done ? "#7fd07f" : "#e8dcc2", false);
                var bar = new Rect(inner.x + 16, y + 17, inner.width - 20, 5);
                ChaosApp.Fill(bar, new Color(0f, 0f, 0f, 0.7f));
                ChaosApp.Fill(new Rect(bar.x, bar.y, bar.width * Mathf.Clamp(pct, 0, 100) / 100f, bar.height), CU.Hex(TaskTrackerState.BarColor(r), new Color(0.64f, 0.52f, 0.29f)));
                y += 28;
            }
        }
    }

    /// <summary>game_playerinspect: the passive tree of the inspected character, read-only. Drag to move, the wheel zooms, a node shows its text; the points they took are lit.</summary>
    public sealed class InspectTreeWindow : GameWindow
    {
        InspectTreeView view;
        Vector2 center;
        float zoom = 0.2f;
        bool fitted, dragging;
        Vector2 dragLast;
        string hoverTip = "";

        public override string Title => view != null ? view.Summary() : Loc.T("Inspected passive tree");
        public override bool InMenu => false;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, (w - 760) / 2), 60, Mathf.Min(760, w - 16), Mathf.Min(540, h - 70));
        public override void Reset() { view = null; fitted = false; Open = false; }

        public override void Tick(ChaosApp app)
        {
            var p = app.Session?.Social?.Inspect;
            if (p == null || !p.TreeViewRequested) return;
            p.TreeViewRequested = false;
            view = InspectTreeView.From(p.TreeData);
            fitted = false;
            if (view != null) Open = true;
        }

        Vector2 ToScreen(float x, float y, Rect vp) => new Vector2(vp.x + vp.width / 2 + (x - center.x) * zoom, vp.y + vp.height / 2 + (y - center.y) * zoom);

        protected override void Body(ChaosApp app, Rect inner)
        {
            var data = PassiveTreeWindow.LoadData();
            if (view == null || data == null)
            {
                GUI.Label(inner, data == null ? Loc.T("The passive tree data is missing from this build.") : Loc.T("Nothing to show."), app.SmallStyle);
                return;
            }
            var vp = new Rect(inner.x, inner.y, inner.width, inner.height);
            if (!fitted) { InspectTreeView.Fit(data, vp.width, vp.height, out zoom, out center.x, out center.y); fitted = true; }
            var e = Event.current;
            bool over = vp.Contains(e.mousePosition);
            if (over && e.type == EventType.ScrollWheel) { zoom = Mathf.Clamp(zoom * (e.delta.y < 0 ? 1.15f : 1f / 1.15f), 0.04f, 1.5f); e.Use(); }
            if (over && e.type == EventType.MouseDown && e.button == 0) { dragging = true; dragLast = e.mousePosition; e.Use(); }
            else if (dragging && e.type == EventType.MouseDrag) { center -= (e.mousePosition - dragLast) / zoom; dragLast = e.mousePosition; e.Use(); }
            else if (e.type == EventType.MouseUp) dragging = false;
            GUI.BeginClip(vp);
            var local = new Rect(0, 0, vp.width, vp.height);
            ChaosApp.Fill(local, new Color(0.05f, 0.04f, 0.06f, 1f));
            hoverTip = "";
            if (e.type == EventType.Repaint)
            {
                var mouse = e.mousePosition;   // inside the clip the pointer is already local
                var col = new Color(0.5f, 0.4f, 0.2f, 0.7f);
                var oldMatrix = GUI.matrix;
                foreach (var n in data.Ordered)
                {
                    if (!view.Shown(n) || !view.Owned.Contains(n.Id)) continue;
                    var a = ToScreen(n.X, n.Y, local);
                    foreach (int o in n.Links)
                    {
                        if (o < n.Id || !view.Owned.Contains(o) || !data.Nodes.TryGetValue(o, out var b) || !view.Shown(b)) continue;
                        var bp = ToScreen(b.X, b.Y, local);
                        float len = Vector2.Distance(a, bp);
                        if (len < 1f) continue;
                        GUIUtility.RotateAroundPivot(Mathf.Atan2(bp.y - a.y, bp.x - a.x) * Mathf.Rad2Deg, a);
                        ChaosApp.Fill(new Rect(a.x, a.y - 1, len, 2), col);
                        GUI.matrix = oldMatrix;
                    }
                }
                foreach (var n in data.Ordered)
                {
                    if (!view.Shown(n)) continue;
                    var s = ToScreen(n.X, n.Y, local);
                    if (s.x < -20 || s.y < -20 || s.x > local.width + 20 || s.y > local.height + 20) continue;
                    bool own = view.Owned.Contains(n.Id);
                    float r = Mathf.Max(2f, PassiveRadius(n) * zoom * (own ? 1f : 0.6f));
                    var rc = new Rect(s.x - r, s.y - r, r * 2, r * 2);
                    var c = PassiveColor(n);
                    if (!own) c = new Color(c.r * 0.35f, c.g * 0.35f, c.b * 0.35f, 0.8f);
                    ChaosApp.Fill(rc, c);
                    if (rc.Contains(mouse)) hoverTip = view.Tip(n);
                }
            }
            GUI.EndClip();
            if (hoverTip.Length > 0) app.SetTip(hoverTip);
            GUI.Label(new Rect(inner.x + 6, inner.yMax - 18, inner.width - 12, 16), Loc.T("Drag to move, the wheel zooms. Lit nodes are the ones this character took."), app.SmallStyle);
        }

        static float PassiveRadius(TreeNode n)
        {
            switch (n.Type) { case 's': return 36; case 'M': return 24; case 'd': return 28; case 'm': return 17; case 'v': return 20; case 'r': return 16; case 'u': return 13; default: return 10; }
        }

        static Color PassiveColor(TreeNode n)
        {
            switch (n.Type)
            {
                case 's': return new Color(0.85f, 0.7f, 0.3f);
                case 'M': return new Color(0.3f, 0.75f, 0.75f);
                case 'd': return new Color(0.95f, 0.6f, 0.3f);
                case 'm': return new Color(0.7f, 0.5f, 0.9f);
                case 'v': return new Color(0.9f, 0.55f, 0.85f);
                case 'r': return new Color(0.4f, 0.6f, 0.95f);
                case 'u': return new Color(0.45f, 0.8f, 0.5f);
                default: return new Color(0.62f, 0.6f, 0.58f);
            }
        }
    }

    public sealed partial class ChaosApp
    {
        void AddPhase7ZWindows()
        {
            windows.Add(new InspectTreeWindow());
            windows.Add(new TaskTrackerWindow());
        }
    }
}
