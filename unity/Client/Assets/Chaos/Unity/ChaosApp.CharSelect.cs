// Character select: one card per character of the login answer (outfit, name, level, class, world), keyboard navigation
// (arrows, Home, End, PageUp, PageDown, Enter), "Enter game", and "Create character", which opens the website page: the
// login server only lists characters, they are created on the website (as in the main client).
using System;
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
                creating = false;
                AccountStart();   // ChaosApp.Phase6V.cs: the website's looks, last login and slots
            }
            if (creating) { CharCreateGui(w, h); return; }   // ChaosApp.Phase7X.cs: the in-client create window
            float bw = Mathf.Min(w - 24, 480f), bh = Mathf.Min(h - 24, 440f);
            Logo(w, h / 2 - bh / 2);
            var box = new Rect(w / 2 - bw / 2, h / 2 - bh / 2, bw, bh);
            GUILayout.BeginArea(box, GUI.skin.box);
            GUILayout.Label(Loc.T("Characters"), titleStyle);
            // the slots line (the website's account API): "3 characters, 3 of 5 slots used"
            if (acct != null && acct.SlotsLimit >= 0)
            {
                int used = Mathf.Max(charModel.Cards.Count, acct.SlotsUsed);
                GUILayout.Label(CharCardText.SlotsFull(used, acct.SlotsLimit)
                    ? Loc.T("{0} characters, no free slot", charModel.Cards.Count)
                    : Loc.T("{0} characters, {1} of {2} slots used", charModel.Cards.Count, used, acct.SlotsLimit), small);
            }
            var e = Event.current;
            var list = GUILayoutUtility.GetRect(bw - 20, bh - 150, GUILayout.ExpandWidth(true));
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
                    var look = LookOf(c.Name);
                    DrawOutfitFx(pic, CharCardText.Merge(c.Outfit, look));   // wings, aura and shader too (Phase7X)
                    GUI.Label(new Rect(row.x + 62, row.y + 4, row.width - 130, 22), streamer.ListName(c.Name, sel), titleStyle);
                    CardBadge(row, c, look);
                    var cs = new GUIStyle(small) { fontSize = 12 };
                    cs.normal.textColor = ColorUtility.TryParseHtmlString(c.Class.Color, out var cc) ? cc : Color.white;
                    string line = c.Level > 0 ? Loc.T("Level {0}", c.Level) + "  " : "";
                    GUI.Label(new Rect(row.x + 62, row.y + 24, row.width - 70, 18), line + c.ClassText, cs);
                    var ws = new GUIStyle(small) { fontSize = 11 };
                    ws.normal.textColor = new Color(0.65f, 0.6f, 0.58f);
                    GUI.Label(new Rect(row.x + 62, row.y + 41, row.width - 70, 16), c.World + CardExtras(look), ws);
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
            bool inClient = CreateInfo != null && CreateInfo.Classes.Count > 0;   // the website's API answered: the window; else its page
            GUI.enabled = url != null || inClient;
            if (GUILayout.Button(Loc.T("Create character"), GUILayout.Height(30))) { if (inClient) BeginCreate(); else Application.OpenURL(url); }
            GUI.enabled = true;
            if (GUILayout.Button(Loc.T("Back"), GUILayout.Height(30))) { AccountEnd(); screen = Screen.Login; status = ""; }
            GUILayout.EndHorizontal();
            if (SiteUrls.Account(host) != null)
            {
                bool on = GUILayout.Toggle(AccountApiOn, Loc.T("Load wings, aura, last login and slots from the website"));
                if (on != AccountApiOn) { PlayerPrefs.SetInt("chaos.account.api", on ? 1 : 0); if (on) AccountStart(); else AccountEnd(); }
                if (acctError.Length > 0) GUILayout.Label(acctError, small);
            }
            GUILayout.Label(status, small);
            GUILayout.EndArea();
        }

        /// <summary>The class badge at the right of a card (a coloured square with the class initial, its ascension marked) and the season tag under it.</summary>
        void CardBadge(Rect row, CharCard c, AccountLook look)
        {
            var badge = new Rect(row.xMax - 36, row.y + 6, 28, 28);
            Color col = ColorUtility.TryParseHtmlString(c.Class.Color, out var cc) ? cc : new Color(0.6f, 0.55f, 0.5f);
            Fill(badge, new Color(0f, 0f, 0f, 0.6f));
            Fill(new Rect(badge.x + 2, badge.y + 2, badge.width - 4, badge.height - 4), new Color(col.r * 0.45f, col.g * 0.45f, col.b * 0.45f, 1f));
            var st = new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontStyle = FontStyle.Bold, fontSize = 15 };
            st.normal.textColor = col;
            string initial = c.Class.Name.Length > 0 ? c.Class.Name.Substring(0, 1) : "?";
            GUI.Label(badge, c.Class.Ascended ? initial + "+" : initial, st);
            if (look != null && look.Season.Length > 0)
            {
                var ss = new GUIStyle(small) { fontSize = 10, alignment = TextAnchor.MiddleCenter };
                ss.normal.textColor = new Color(0.96f, 0.81f, 0.45f);
                GUI.Label(new Rect(row.xMax - 66, row.y + 36, 60, 14), look.Season, ss);
            }
        }

        /// <summary>The line after the world: the last login in short words and the wings, aura and shader the website knows ("- 2 hours ago - Wings, Aura").</summary>
        string CardExtras(AccountLook look)
        {
            if (look == null) return "";
            string key = CharCardText.LastLoginKey(look.LastLogin, DateTimeOffset.UtcNow.ToUnixTimeSeconds(), out int n, true);
            string when = n < 0 ? Loc.T(key, CharCardText.DateOf(look.LastLogin)) : Loc.T(key, n);
            var fx = new System.Collections.Generic.List<string>();
            if (look.Outfit != null)
            {
                if (look.Outfit.Wings > 0) fx.Add(Loc.T("Wings"));
                if (look.Outfit.Aura > 0) fx.Add(Loc.T("Aura"));
                if (!string.IsNullOrEmpty(look.Outfit.Shader)) fx.Add(look.Outfit.Shader);
            }
            return "  -  " + when + (fx.Count > 0 ? "  -  " + string.Join(", ", fx) : "");
        }

        void EnterCard(CharCard c)
        {
            if (c == null) return;
            PlayerPrefs.SetString("chaos.lastchar", c.Name);
            AccountEnd();
            Enter(c.Entry);
        }
    }
}
