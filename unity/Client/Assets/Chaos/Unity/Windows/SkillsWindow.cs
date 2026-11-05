using System.Globalization;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>Level with its experience bar, magic level, the seven skills with percent bars, stamina, speed and capacity.</summary>
    public sealed class SkillsWindow : GameWindow
    {
        public override string Title => "Skills";
        public override KeyCode Hotkey => KeyCode.K;

        static readonly string[] Names =
            { "Fist Fighting", "Club Fighting", "Sword Fighting", "Axe Fighting", "Distance Fighting", "Shielding", "Fishing" };
        const float Row = 34;
        GUIStyle right;

        protected override Rect Place(float w, float h) => new Rect(w - 178 - 232, 48, 228, 410);

        static void Bar(Rect r, int percent, Color fill)
        {
            ChaosApp.Fill(r, new Color(0f, 0f, 0f, 0.8f));
            ChaosApp.Fill(new Rect(r.x + 1, r.y + 1, (r.width - 2) * Mathf.Clamp(percent, 0, 100) / 100f, r.height - 2), fill);
        }

        void Line(ChaosApp app, float x, float y, float w, string name, string value, int percent, Color fill)
        {
            if (right == null) right = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.UpperRight };
            GUI.Label(new Rect(x, y, w * 0.62f, 20), name, app.SmallStyle);
            GUI.Label(new Rect(x + w * 0.5f, y, w * 0.5f, 20), value, right);
            Bar(new Rect(x, y + 20, w, 8), percent, fill);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            if (s == null) return;
            var p = s.Parser;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            Line(app, x, y, w, "Level", p.Level.ToString(CultureInfo.InvariantCulture), p.LevelPercent, new Color(0.85f, 0.65f, 0.2f, 1f));
            y += Row;
            GUI.Label(new Rect(x, y - 4, w, 20), "Experience: " + p.Experience.ToString("N0", CultureInfo.InvariantCulture), app.SmallStyle);
            y += 22;
            Line(app, x, y, w, "Magic level", Value(p.MagicLevel, p.BaseMagicLevel), p.MagicPercent, new Color(0.3f, 0.45f, 0.95f, 1f));
            y += Row;
            for (int i = 0; i < p.Skills.Length; i++)
            {
                var k = p.Skills[i];
                Line(app, x, y, w, Names[i], Value(k.Level, k.Base), k.Percent, new Color(0.35f, 0.7f, 0.3f, 1f));
                y += Row;
            }
            int m = p.Stamina;
            string stamina = (m / 60).ToString(CultureInfo.InvariantCulture) + ":" + (m % 60).ToString("00", CultureInfo.InvariantCulture);
            GUI.Label(new Rect(x, y, w, 20), "Stamina: " + stamina + "    Speed: " + p.Speed, app.SmallStyle);
            GUI.Label(new Rect(x, y + 20, w, 20), "Cap: " + (p.FreeCap / 100u), app.SmallStyle);
        }

        static string Value(int level, int baseLevel) =>
            level == baseLevel ? level.ToString(CultureInfo.InvariantCulture) : level + " (" + baseLevel + ")";
    }
}
