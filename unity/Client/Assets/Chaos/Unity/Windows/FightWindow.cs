// Fight modes: offensive / balanced / defensive, chase / stand, secure mode on or off. The choice is saved in PlayerPrefs
// (chaos.fight), sent when the character enters the game (GameSession.Poll) and at every change (opcode 0xA0).
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class FightWindow : GameWindow
    {
        public override string Title => Loc.T("Fight");
        protected override Rect Place(float w, float h) => new Rect(w - 216, 582, 208, 118);
        public FightWindow() { Open = true; }
        public override void Reset() { Open = true; }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            if (s == null) return;
            var m = s.Modes;
            byte fight = m.Fight;
            bool chase = m.Chase, secure = m.Secure;
            float bw = (inner.width - 8) / 3f;
            string[] names = { Loc.T("Offensive"), Loc.T("Balanced"), Loc.T("Defensive") };
            for (int i = 0; i < 3; i++)
                if (GUI.Toggle(new Rect(inner.x + i * (bw + 4), inner.y, bw, 28), fight == i + 1, names[i], GUI.skin.button) && fight != i + 1) fight = (byte)(i + 1);
            float hw = (inner.width - 4) / 2f;
            if (GUI.Toggle(new Rect(inner.x, inner.y + 34, hw, 28), !chase, Loc.T("Stand"), GUI.skin.button) && chase) chase = false;
            if (GUI.Toggle(new Rect(inner.x + hw + 4, inner.y + 34, hw, 28), chase, Loc.T("Chase"), GUI.skin.button) && !chase) chase = true;
            secure = GUI.Toggle(new Rect(inner.x, inner.y + 68, inner.width, 22), secure, Loc.T("Secure mode"));
            if (fight != m.Fight || chase != m.Chase || secure != m.Secure)
            {
                var n = new FightModes { Fight = fight, Chase = chase, Secure = secure };
                s.SetFightModes(n);
                PlayerPrefs.SetString("chaos.fight", n.Encode());
            }
        }
    }
}
