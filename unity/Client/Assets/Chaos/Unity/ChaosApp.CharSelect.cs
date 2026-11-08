// Character select: one card per character of the login answer (outfit, name, level, class, world), keyboard navigation
// (arrows, Home, End, PageUp, PageDown, Enter), "Enter game", and "Create character", which opens the website page: the
// login server only lists characters, they are created on the website (as in the main client).
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        CharSelectModel charModel;
        LoginResult charModelFor;
        const float CardH = 62f;

        void CharSelectGui(float w, float h)
        {
            if (charModelFor != login)
            {
                charModelFor = login;
                charModel = CharSelectModel.Build(login.Characters, PlayerPrefs.GetString("chaos.lastchar", ""));
                charScroll = Vector2.zero;
            }
            float bw = Mathf.Min(w - 24, 480f), bh = Mathf.Min(h - 24, 440f);
            Logo(w, h / 2 - bh / 2);
            var box = new Rect(w / 2 - bw / 2, h / 2 - bh / 2, bw, bh);
            GUILayout.BeginArea(box, GUI.skin.box);
            GUILayout.Label(Loc.T("Characters"), titleStyle);
            var e = Event.current;
            var list = GUILayoutUtility.GetRect(bw - 20, bh - 130, GUILayout.ExpandWidth(true));
            var cards = charModel.Cards;
            if (cards.Count == 0)
                GUI.Label(list, Loc.T("No characters on this account. Create one on the website."), small);
            // keys
            if (e.type == EventType.KeyDown && cards.Count > 0)
            {
                string key = e.keyCode == KeyCode.UpArrow ? "Up" : e.keyCode == KeyCode.DownArrow ? "Down" : e.keyCode == KeyCode.Home ? "Home" :
                             e.keyCode == KeyCode.End ? "End" : e.keyCode == KeyCode.PageUp ? "PageUp" : e.keyCode == KeyCode.PageDown ? "PageDown" : null;
                if (key != null)
                {
                    charModel.Navigate(key, Mathf.Max(1, (int)(list.height / CardH)));
                    float top = charModel.Selected * CardH;
                    if (top < charScroll.y) charScroll.y = top;
                    else if (top + CardH > charScroll.y + list.height) charScroll.y = top + CardH - list.height;
                    e.Use();
                }
                else if ((e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter) && charModel.Current != null) { EnterCard(charModel.Current); e.Use(); }
            }
            if (cards.Count > 0)
            {
                charScroll = GUI.BeginScrollView(list, charScroll, new Rect(0, 0, list.width - 18, cards.Count * CardH));
                for (int i = 0; i < cards.Count; i++)
                {
                    var c = cards[i];
                    var row = new Rect(0, i * CardH, list.width - 18, CardH - 4);
                    bool sel = i == charModel.Selected;
                    Fill(row, sel ? new Color(0.6f, 0.45f, 0.12f, 0.4f) : new Color(1f, 1f, 1f, 0.07f));
                    if (sel) Fill(new Rect(row.x, row.y, 3, row.height), new Color(0.96f, 0.81f, 0.45f));
                    var pic = new Rect(row.x + 8, row.y + 6, 46, 46);
                    Fill(pic, new Color(0f, 0f, 0f, 0.5f));
                    DrawOutfit(pic, c.Outfit);
                    GUI.Label(new Rect(row.x + 62, row.y + 4, row.width - 70, 22), streamer.ListName(c.Name, sel), titleStyle);
                    var cs = new GUIStyle(small) { fontSize = 12 };
                    cs.normal.textColor = ColorUtility.TryParseHtmlString(c.Class.Color, out var cc) ? cc : Color.white;
                    string line = c.Level > 0 ? Loc.T("Level {0}", c.Level) + "  " : "";
                    GUI.Label(new Rect(row.x + 62, row.y + 24, row.width - 70, 18), line + c.ClassText, cs);
                    var ws = new GUIStyle(small) { fontSize = 11 };
                    ws.normal.textColor = new Color(0.65f, 0.6f, 0.58f);
                    GUI.Label(new Rect(row.x + 62, row.y + 41, row.width - 70, 16), c.World, ws);
                    if (e.type == EventType.MouseDown && e.button == 0 && row.Contains(e.mousePosition))
                    {
                        // a second click on the highlighted card enters
                        if (sel) EnterCard(c); else charModel.Selected = i;
                        e.Use();
                    }
                }
                GUI.EndScrollView();
            }
            GUILayout.BeginHorizontal();
            GUI.enabled = charModel.Current != null;
            if (GUILayout.Button(Loc.T("Enter game"), GUILayout.Height(30))) EnterCard(charModel.Current);
            GUI.enabled = true;
            string url = CharSelectModel.CreateUrl(host);
            GUI.enabled = url != null;
            if (GUILayout.Button(Loc.T("Create character"), GUILayout.Height(30))) Application.OpenURL(url);
            GUI.enabled = true;
            if (GUILayout.Button(Loc.T("Back"), GUILayout.Height(30))) { screen = Screen.Login; status = ""; }
            GUILayout.EndHorizontal();
            GUILayout.Label(status, small);
            GUILayout.EndArea();
        }

        void EnterCard(CharCard c)
        {
            if (c == null) return;
            PlayerPrefs.SetString("chaos.lastchar", c.Name);
            Enter(c.Entry);
        }
    }
}
