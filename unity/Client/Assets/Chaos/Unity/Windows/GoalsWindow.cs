// Next Goals (Ctrl+J), the main client's game_goals on opcode 178: the goals of the character's level band with a bar and a button that
// goes where the goal is, the gear path, the hunts of the band and the next unlocks. The server pushes the list while the window is
// open ("open" / "close"). Core: Core/Progression.cs (Goals).
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class GoalsWindow : GameWindow
    {
        Vector2 scrollGoals, scrollSide;
        bool wasOpen;
        GUIStyle tiny, wrap, title;

        public override string Title => Loc.T("Next Goals");
        public override KeyCode Hotkey => KeyCode.Y;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 330), 50, Mathf.Min(660, w - 16), Mathf.Min(520, h - 60));
        public override void Reset() { wasOpen = false; scrollGoals = scrollSide = Vector2.zero; }

        public override void Tick(ChaosApp app)
        {
            var goals = app.Session?.Progress?.Goals;
            if (goals == null) return;
            if (Open && !wasOpen) goals.Open();
            if (!Open && wasOpen) goals.Close();
            wasOpen = Open;
        }

        static Color Hex(string hex) => ColorUtility.TryParseHtmlString(hex, out var c) ? c : Color.white;

        static Color StateColor(string state) => state == "done" ? Hex("#7fc86a") : state == "locked" ? Hex("#6b6258") : Hex("#f6cf72");

        protected override void Body(ChaosApp app, Rect inner)
        {
            var g = app.Session?.Progress?.Goals;
            if (g == null) return;
            if (tiny == null)
            {
                tiny = new GUIStyle(app.SmallStyle) { fontSize = 11 };
                wrap = new GUIStyle(tiny) { wordWrap = true };
                title = new GUIStyle(app.SmallStyle) { fontSize = 14, fontStyle = FontStyle.Bold };
            }
            float x = inner.x + 4, w = inner.width - 8, y = inner.y;
            GUI.Label(new Rect(x, y, w, 22), g.HeaderLine(), title);
            y += 22;
            string band = g.HasHeader ? g.BandText : "";
            float bh = wrap.CalcHeight(new GUIContent(band), w);
            if (band.Length > 0) { GUI.Label(new Rect(x, y, w, bh), band, wrap); y += bh + 2; }
            Bar(new Rect(x, y, w, 14), g.BandPercent, Hex("#8a5410"), g.HasHeader ? Loc.T("Band {0} of {1}", g.BandIndex, g.BandCount) : "", tiny);
            y += 18;
            GUI.Label(new Rect(x, y, w - 150, 20), g.SummaryLine(), tiny);
            if (!g.HasHeader) GUI.Label(new Rect(x, y, w, 20), Loc.T("Waiting for the server..."), tiny);
            y += 22;

            float sideW = Mathf.Max(170, w * 0.36f);
            var goalsRect = new Rect(x, y, w - sideW - 6, inner.yMax - y);
            var sideRect = new Rect(goalsRect.xMax + 6, y, sideW, inner.yMax - y);
            DrawGoals(app, g, goalsRect);
            DrawSide(app, g, sideRect);
        }

        void Bar(Rect r, int percent, Color fill, string text, GUIStyle st)
        {
            ChaosApp.Fill(r, new Color(0f, 0f, 0f, 0.8f));
            ChaosApp.Fill(new Rect(r.x + 1, r.y + 1, (r.width - 2) * Mathf.Clamp(percent, 0, 100) / 100f, r.height - 2), fill);
            if (text.Length > 0)
            {
                var c = new GUIStyle(st) { alignment = TextAnchor.MiddleCenter };
                c.normal.textColor = Color.white;
                GUI.Label(r, text, c);
            }
        }

        void DrawGoals(ChaosApp app, Goals g, Rect r)
        {
            const float rowH = 96f;
            int extra = g.More > 0 ? 1 : 0;
            scrollGoals = GUI.BeginScrollView(r, scrollGoals, new Rect(0, 0, r.width - 18, Mathf.Max(r.height, g.GoalList.Count * rowH + extra * 24)));
            float y = 0, w = r.width - 22;
            foreach (var goal in g.GoalList)
            {
                var row = new Rect(0, y, w, rowH - 4);
                ChaosApp.Fill(row, new Color(1f, 1f, 1f, 0.05f));
                var ts = new GUIStyle(app.SmallStyle) { fontSize = 13, fontStyle = FontStyle.Bold };
                ts.normal.textColor = StateColor(goal.State);
                GUI.Label(new Rect(row.x + 6, y + 2, w - 110, 20), goal.Title, ts);
                float ty = y + 20;
                if (goal.Why.Length > 0) { float h = wrap.CalcHeight(new GUIContent(goal.Why), w - 12); GUI.Label(new Rect(row.x + 6, ty, w - 12, Mathf.Min(h, 30)), goal.Why, wrap); ty += Mathf.Min(h, 30); }
                string meta = (goal.Effort.Length > 0 ? Loc.T("Effort: {0}", goal.Effort) : "") + (goal.Reward.Length > 0 && goal.State != "done" ? "   " + Loc.T("Reward: {0}", goal.Reward) : "");
                if (meta.Length > 0) GUI.Label(new Rect(row.x + 6, ty, w - 12, 16), meta, tiny);
                Bar(new Rect(row.x + 6, y + rowH - 24, w - 12 - (goal.State == "open" && goal.Where?.Button() != null ? 96 : 0), 16), goal.Percent,
                    goal.State == "done" ? Hex("#3f6e24") : Hex("#8a5410"), Goals.BarLabel(goal), tiny);
                string button = goal.State == "open" ? goal.Where?.Button() : null;
                if (button != null && GUI.Button(new Rect(row.xMax - 92, y + rowH - 26, 88, 20), Loc.T(button))) app.RunWhere(goal.Where);
                y += rowH;
            }
            if (g.More > 0) GUI.Label(new Rect(4, y, w, 20), Loc.T("and {0} more from earlier levels", g.More), tiny);
            if (g.HasHeader && g.GoalList.Count == 0) GUI.Label(new Rect(4, 4, w, 20), Loc.T("No goals right now."), tiny);
            GUI.EndScrollView();
        }

        void Section(string text, ref float y, float w)
        {
            var st = new GUIStyle(tiny) { fontStyle = FontStyle.Bold, fontSize = 12 };
            st.normal.textColor = Hex("#e8d9a8");
            GUI.Label(new Rect(2, y, w, 18), text, st);
            y += 20;
        }

        void SideLine(ChaosApp app, string text, GoalWhere where, ref float y, float w, Color color)
        {
            float h = Mathf.Max(18, wrap.CalcHeight(new GUIContent(text), w - 4));
            var r = new Rect(2, y, w - 2, h);
            bool clickable = where != null && where.Button() != null;
            var st = new GUIStyle(wrap);
            st.normal.textColor = clickable ? Hex("#9ab8ff") : color;
            GUI.Label(r, text, st);
            if (clickable && Event.current.type == EventType.MouseDown && Event.current.button == 0 && r.Contains(Event.current.mousePosition))
            {
                app.RunWhere(where);
                Event.current.Use();
            }
            y += h + 2;
        }

        void DrawSide(ChaosApp app, Goals g, Rect r)
        {
            ChaosApp.Fill(r, new Color(0f, 0f, 0f, 0.25f));
            float content = 40 + (g.Gear.Count + Mathf.Max(1, g.Hunts.Count) + g.Upcoming.Count) * 34 + 80;
            scrollSide = GUI.BeginScrollView(r, scrollSide, new Rect(0, 0, r.width - 18, Mathf.Max(r.height, content)));
            float y = 2, w = r.width - 20;
            var dim = Hex("#d6c9ae");
            Section(Loc.T("Gear path"), ref y, w);
            foreach (var gear in g.Gear) SideLine(app, "- " + gear.Key, gear.Value, ref y, w, dim);
            Section(Loc.T("Where to hunt"), ref y, w);
            if (g.Hunts.Count > 0)
                foreach (var h in g.Hunts) SideLine(app, "- " + Loc.T("{0} (levels {1}-{2})", h.Name.Length > 0 ? h.Name : h.Id, h.Lo, h.Hi), h.Where, ref y, w, dim);
            else SideLine(app, Loc.T("- The hunting grounds near your temple (Bestiary: where each creature lives)."), g.Here, ref y, w, dim);
            if (g.Upcoming.Count > 0)
            {
                Section(Loc.T("Next unlocks"), ref y, w);
                foreach (var u in g.Upcoming) SideLine(app, "- " + Loc.T("Level {0}: {1}", u.Level, u.Title), null, ref y, w, Hex("#8c8070"));
            }
            GUI.EndScrollView();
        }
    }
}
