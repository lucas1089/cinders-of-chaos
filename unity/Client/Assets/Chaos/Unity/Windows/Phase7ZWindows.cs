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


    public sealed partial class ChaosApp
    {
        void AddPhase7ZWindows()
        {
            windows.Add(new TaskTrackerWindow());
        }
    }
}
