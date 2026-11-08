// Rift run HUD, the main client's game_rift on opcode 228: the clock, monsters slain and left, the guardian, the modifiers, the rewards
// and the live notes of the rift the character is in. It opens by itself on the server's start, shows the result for a few seconds
// after the end and closes. The x hides it for this run. Core: Core/Progression.cs (RiftHud).
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class RiftWindow : GameWindow
    {
        bool wasActive, dismissed, lastOpen;
        GUIStyle tiny, wrap;

        public override string Title => Loc.T("Rift");
        public override bool InMenu => false;
        protected override Rect Place(float w, float h) => new Rect(8, 108, 262, 300);
        public override void Reset() { wasActive = false; dismissed = false; lastOpen = false; }

        public override void Tick(ChaosApp app)
        {
            var rift = app.Session?.Progress?.Rift;
            if (rift == null) return;
            if (rift.Active && !wasActive) { Open = true; dismissed = false; }
            if (rift.HideAt >= 0 && app.Session.Now >= rift.HideAt) rift.Hide();
            if (!rift.Active) Open = false;
            else
            {
                if (!Open && lastOpen && wasActive) dismissed = true;   // the player closed it with the x
                if (dismissed) Open = false;
            }
            lastOpen = Open;
            wasActive = rift.Active;
        }

        static Color Hex(string hex) => ColorUtility.TryParseHtmlString(hex, out var c) ? c : Color.white;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var session = app.Session;
            var r = session?.Progress?.Rift;
            if (r == null || !r.Active) return;
            if (tiny == null) { tiny = new GUIStyle(app.SmallStyle) { fontSize = 11 }; wrap = new GUIStyle(tiny) { wordWrap = true }; }
            float x = inner.x + 6, w = inner.width - 12, y = inner.y + 2;
            var head = new GUIStyle(app.SmallStyle) { fontSize = 14, fontStyle = FontStyle.Bold };
            GUI.Label(new Rect(x, y, w, 20), r.Title.Length > 0 ? r.Title : Loc.T("Rift - Tier {0}", r.Tier), head);
            y += 20;
            string lives = r.LivesLine();
            if (lives.Length > 0)
            {
                var ls = new GUIStyle(tiny);
                ls.normal.textColor = r.Lives <= 1 ? Hex("#ff4030") : r.LivesMax > 0 && r.Lives * 2 < r.LivesMax ? Hex("#ff9a30") : Hex("#9fd89f");
                GUI.Label(new Rect(x, y, w, 16), lives, ls);
                y += 16;
            }
            if (r.Theme.Length > 0) { GUI.Label(new Rect(x, y, w, 16), r.Theme, tiny); y += 16; }
            // the clock
            double now = session.Now;
            double left = r.LeftNow(now);
            var cs = new GUIStyle(app.SmallStyle) { fontSize = 24, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
            string clock;
            if (r.State == "running") { clock = Fmt.Clock(left); cs.normal.textColor = Hex(RiftHud.ClockColor(left)); }
            else if (r.State == "success") { clock = Loc.T("Sealed"); cs.normal.textColor = Hex("#7fd07f"); }
            else if (r.State == "left") { clock = Loc.T("Left"); cs.normal.textColor = Hex("#8c8070"); }
            else { clock = Loc.T("Collapsed"); cs.normal.textColor = Hex("#ff4030"); }
            GUI.Label(new Rect(x, y, w, 32), clock, cs);
            y += 32;
            bool met = false;
            string swift = r.State == "running" ? r.SwiftLine(left, out met) : "";
            if (swift.Length > 0)
            {
                var ss = new GUIStyle(wrap);
                ss.normal.textColor = Hex(met ? "#7fb8e8" : "#8c8070");
                GUI.Label(new Rect(x, y, w, 30), swift, ss);
                y += 30;
            }
            // progress to the guardian
            var bar = new Rect(x, y, w, 18);
            ChaosApp.Fill(bar, new Color(0f, 0f, 0f, 0.8f));
            ChaosApp.Fill(new Rect(bar.x + 1, bar.y + 1, (bar.width - 2) * r.BossPercent() / 100f, bar.height - 2), r.Boss == "waiting" ? Hex("#6a2ab0") : Hex("#8a1010"));
            var bs = new GUIStyle(tiny) { alignment = TextAnchor.MiddleCenter };
            bs.normal.textColor = Color.white;
            string barText = r.Omen.Length > 0 ? Loc.T("Omen: {0}", r.Omen) : Loc.T("{0} / {1} slain, {2} left", Fmt.Short(r.Killed), Fmt.Short(r.Total), Fmt.Short(System.Math.Max(0, r.Total - r.Killed)));
            GUI.Label(bar, barText, bs);
            y += 22;
            GUI.Label(new Rect(x, y, w, 18), r.BossLine(), tiny);
            y += 20;
            if (r.Mods.Count > 0 || r.Omen.Length == 0)
            {
                var hs = new GUIStyle(tiny) { fontStyle = FontStyle.Bold };
                GUI.Label(new Rect(x, y, w, 16), r.Mods.Count > 0 ? Loc.T("Modifiers") : Loc.T("No modifiers"), hs);
                y += 16;
            }
            foreach (var m in r.Mods)
            {
                var st = new GUIStyle(wrap);
                if (m.Boon) st.normal.textColor = Hex("#e8c060");
                else if (m.Side == "suffix") st.normal.textColor = Hex("#c9a6ff");
                string text = "- " + RiftHud.ModLine(m);
                float h = wrap.CalcHeight(new GUIContent(text), w);
                GUI.Label(new Rect(x, y, w, h), text, st);
                y += h;
            }
            foreach (string n in r.Notes)
            {
                float h = wrap.CalcHeight(new GUIContent(n), w);
                GUI.Label(new Rect(x, y, w, h), n, wrap);
                y += h;
            }
            string bonus = r.BonusLine();
            if (bonus.Length > 0) { GUI.Label(new Rect(x, y + 2, w, 18), Loc.T("Rewards: {0}", bonus), tiny); y += 20; }
            if (r.ResultText.Length > 0)
            {
                var rs = new GUIStyle(wrap) { fontSize = 12, fontStyle = FontStyle.Bold };
                rs.normal.textColor = r.Result == "success" ? Hex("#7fd07f") : Hex("#ff6040");
                float h = rs.CalcHeight(new GUIContent(r.ResultText), w);
                GUI.Label(new Rect(x, y + 2, w, h), r.ResultText, rs);
            }
        }
    }
}
