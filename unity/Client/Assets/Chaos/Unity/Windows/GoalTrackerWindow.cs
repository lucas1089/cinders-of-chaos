// Goal tracker: the compact list the main client keeps on the map. Sections in order: the welcome path of a new character (with a Skip
// button that asks twice), Next Goals, the ascension quest and the line's spell quest, each row a line of text and a thin bar. It opens
// by itself when the server sends rows (opcode 178 "tracker", "welcome", "ascension", "spellquest"); close it with the x, open it again
// from the Adventure menu. Core: Core/Progression.cs (Goals).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class GoalTrackerWindow : GameWindow
    {
        bool autoOpened;
        double skipArmedAt = -1;
        GUIStyle line;

        public override string Title => Loc.T("Goal Tracker");
        protected override Rect Place(float w, float h) => new Rect(8, 150, 236, 260);
        public override void Reset() { autoOpened = false; skipArmedAt = -1; }

        public override void Tick(ChaosApp app)
        {
            var g = app.Session?.Progress?.Goals;
            if (g == null) return;
            if (!autoOpened && g.TrackerHasRows) { autoOpened = true; Open = true; }
        }

        static Color Hex(string hex) => ColorUtility.TryParseHtmlString(hex, out var c) ? c : Color.white;

        float Row(ChaosApp app, float x, float y, float w, string text, int percent, Color color)
        {
            if (line == null) line = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true };
            float h = line.CalcHeight(new GUIContent(text), w);
            var st = new GUIStyle(line);
            st.normal.textColor = color;
            GUI.Label(new Rect(x, y, w, h), text, st);
            var bar = new Rect(x, y + h + 1, w, 4);
            ChaosApp.Fill(bar, new Color(0f, 0f, 0f, 0.7f));
            ChaosApp.Fill(new Rect(bar.x, bar.y, bar.width * Mathf.Clamp(percent, 0, 100) / 100f, bar.height), percent >= 100 ? Hex("#3f6e24") : Hex("#a3844b"));
            return h + 10;
        }

        float Header(ChaosApp app, float x, float y, float w, string text)
        {
            var st = new GUIStyle(app.SmallStyle) { fontSize = 12, fontStyle = FontStyle.Bold };
            st.normal.textColor = Hex("#e8d9a8");
            GUI.Label(new Rect(x, y, w, 18), text, st);
            return 20;
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var g = app.Session?.Progress?.Goals;
            if (g == null) return;
            float x = inner.x + 4, w = inner.width - 8, y = inner.y;
            if (!g.TrackerHasRows) { GUI.Label(new Rect(x, y, w, 40), Loc.T("Nothing to track right now."), app.SmallStyle); return; }
            if (g.Welcome.Count > 0)
            {
                y += Header(app, x, y, w, Loc.T("Welcome Path {0}/{1}", g.WelcomeStep, g.WelcomeCount));
                foreach (var r in g.Welcome)
                {
                    y += Row(app, x, y, w, r.TrackerText(true) + (r.Hint.Length > 0 && !r.Done ? "\n" + r.Hint : ""), r.Percent, Hex(r.Done ? "#7fc86a" : "#f6cf72"));
                }
                bool armed = skipArmedAt >= 0 && app.Session.Now - skipArmedAt < 4000;
                if (GUI.Button(new Rect(x, y, w, 22), armed ? Loc.T("Click again to skip") : Loc.T("Skip welcome path")))
                {
                    if (armed) { g.SkipWelcome(); skipArmedAt = -1; }
                    else skipArmedAt = app.Session.Now;
                }
                y += 28;
            }
            Section(app, g.Tracker, Loc.T("Next Goals"), false, x, ref y, w);
            Section(app, g.Ascension, Loc.T("Ascension"), true, x, ref y, w);
            Section(app, g.SpellQuest, Loc.T("Spell Quest"), true, x, ref y, w);
        }

        void Section(ChaosApp app, List<GoalRow> rows, string title, bool ascension, float x, ref float y, float w)
        {
            if (rows.Count == 0) return;
            y += Header(app, x, y, w, title);
            foreach (var r in rows)
            {
                bool done = ascension && (r.State == "done" || r.Progress >= r.Target);
                y += Row(app, x, y, w, r.TrackerText(ascension), r.Percent, Hex(done ? "#7fc86a" : "#f6cf72"));
            }
        }
    }
}
