// Fight modes: offensive / balanced / defensive, chase / stand, secure mode on or off. The choice is saved in PlayerPrefs
// (chaos.fight), sent when the character enters the game (GameSession.Poll) and at every change (opcode 0xA0).
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class FightWindow : GameWindow
    {
        public override string Title => Loc.T("Fight");
        protected override Rect Place(float w, float h)
        {
            // wide enough for the three mode labels in the current language
            float ww = 208;
            var bs = GUI.skin.button;
            float sum = 0;
            foreach (var n in new[] { "Offensive", "Balanced", "Defensive" }) sum += bs.CalcSize(new GUIContent(Loc.T(n))).x + 12;
            ww = Mathf.Max(ww, sum + 8 + 16);
            // above the bottom band: the hotkey bar (with its Q and E sockets) and the globes take the bottom centre
            return new Rect(w - ww - 8, 462, ww, 118);
        }
        public FightWindow() { Open = true; }
        public override void Reset() { Open = true; }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            if (s == null) return;
            var m = s.Modes;
            byte fight = m.Fight;
            bool chase = m.Chase, secure = m.Secure;
            string[] names = { Loc.T("Offensive"), Loc.T("Balanced"), Loc.T("Defensive") };
            var bs = GUI.skin.button;
            var nw = new float[3];
            float total = 0;
            for (int i = 0; i < 3; i++) { nw[i] = bs.CalcSize(new GUIContent(names[i])).x + 12; total += nw[i]; }
            float spare = Mathf.Max(0, inner.width - 8 - total) / 3f;   // the spare width is shared so the row fills the window
            float bx = inner.x;
            for (int i = 0; i < 3; i++)
            {
                float bw = nw[i] + spare;
                if (GUI.Toggle(new Rect(bx, inner.y, bw, 28), fight == i + 1, names[i], GUI.skin.button) && fight != i + 1) fight = (byte)(i + 1);
                bx += bw + 4;
            }
            float hw = (inner.width - 4) / 2f;
            if (GUI.Toggle(new Rect(inner.x, inner.y + 34, hw, 28), !chase, Loc.T("Stand"), GUI.skin.button) && chase) chase = false;
            if (GUI.Toggle(new Rect(inner.x + hw + 4, inner.y + 34, hw, 28), chase, Loc.T("Chase"), GUI.skin.button) && !chase) chase = true;
            secure = GUI.Toggle(new Rect(inner.x, inner.y + 68, inner.width, 22), secure, Loc.T("Secure mode"));
            if (fight != m.Fight || chase != m.Chase || secure != m.Secure)
            {
                var n = new FightModes { Fight = fight, Chase = chase, Secure = secure };
                bool secureChanged = secure != m.Secure;
                if (secureChanged) EndgameBridge.Guard.UserChose(secure);
                // a match holds secure mode off: the window shows that, the saved choice stays the player's own
                var save = EndgameBridge.Guard.ToSave(n, secureChanged);
                s.SetFightModes(n);
                PlayerPrefs.SetString("chaos.fight", save.Encode());
            }
        }
    }
}
