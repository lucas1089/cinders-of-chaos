using System.Globalization;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>Level with its experience bar, magic level, the skills with percent bars (the simple list of the main client's
    /// game_simpleskills: one Melee row, Ranged, Shielding, Fishing, Fist Fighting for the Monk line), the combat stat rows of
    /// opcode 119 (game_skillstats), stamina, speed and capacity.</summary>
    public sealed class SkillsWindow : GameWindow
    {
        public override string Title => Loc.T("Skills");
        public override KeyCode Hotkey => KeyCode.K;

        const float Row = 34;
        GUIStyle right;

        protected override Rect Place(float w, float h) => new Rect(w - 178 - 232, 48, 228, 560);

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

        void Skill(ChaosApp app, float x, float y, float w, string name, SkillValue k)
        {
            Line(app, x, y, w, name, Value(k.Level, k.Base), k.Percent, new Color(0.35f, 0.7f, 0.3f, 1f));
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            if (s == null) return;
            var p = s.Parser;
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            Line(app, x, y, w, Loc.T("Level"), p.Level.ToString(CultureInfo.InvariantCulture), p.LevelPercent, new Color(0.85f, 0.65f, 0.2f, 1f));
            y += Row;
            GUI.Label(new Rect(x, y - 4, w, 20), Loc.T("Experience: {0}", p.Experience.ToString("N0", CultureInfo.InvariantCulture)), app.SmallStyle);
            y += 22;
            Line(app, x, y, w, Loc.T("Magic / Wand"), Value(p.MagicLevel, p.BaseMagicLevel), p.MagicPercent, new Color(0.3f, 0.45f, 0.95f, 1f));
            y += Row;
            var melee = SkillStats.Melee(p.Skills);
            Skill(app, x, y, w, Loc.T("Melee"), melee);
            y += Row;
            if (SkillStats.ShowFist(app.World?.PlayerVocation ?? 0))
            {
                Skill(app, x, y, w, Loc.T("Fist Fighting"), p.Skills[SkillStats.Fist]);
                y += Row;
            }
            Skill(app, x, y, w, Loc.T("Ranged"), p.Skills[SkillStats.Distance]);
            y += Row;
            Skill(app, x, y, w, Loc.T("Shielding"), p.Skills[SkillStats.Shielding]);
            y += Row;
            Skill(app, x, y, w, Loc.T("Fishing"), p.Skills[SkillStats.Fishing]);
            y += Row;
            // the combat stat rows: "-" until the server's numbers arrive, damage and attack hidden for a wand or bare hands
            var rows = SkillStats.Build(s.Progress?.Stats.Last);
            string[] names = { Loc.T("Damage/Healing"), Loc.T("Attack Value"), Loc.T("Defense Value"), Loc.T("Armor Value"), Loc.T("Mitigation") };
            for (int i = 0; i < SkillStats.Rows.Length; i++)
            {
                var r = rows[SkillStats.Rows[i]];
                if (!r.Visible) continue;
                GUI.Label(new Rect(x, y, w * 0.62f, 20), names[i], app.SmallStyle);
                var vs = new GUIStyle(right);
                vs.normal.textColor = r.Green ? new Color(0.27f, 0.68f, 0.15f) : new Color(0.73f, 0.73f, 0.73f);
                GUI.Label(new Rect(x + w * 0.5f, y, w * 0.5f, 20), r.Text, vs);
                y += 20;
            }
            y += 4;
            int m = p.Stamina;
            string stamina = (m / 60).ToString(CultureInfo.InvariantCulture) + ":" + (m % 60).ToString("00", CultureInfo.InvariantCulture);
            GUI.Label(new Rect(x, y, w, 20), Loc.T("Stamina: {0}    Speed: {1}", stamina, p.Speed), app.SmallStyle);
            GUI.Label(new Rect(x, y + 20, w, 20), Loc.T("Cap: {0}", p.FreeCap / 100u), app.SmallStyle);
        }

        static string Value(int level, int baseLevel) =>
            level == baseLevel ? level.ToString(CultureInfo.InvariantCulture) : level + " (" + baseLevel + ")";
    }
}
