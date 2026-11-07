// Party frames (Ctrl+G): a frame for every member of the party, from the server's party frames (extended opcode 235,
// Core/Party.cs): outfit, name in the class colour, level, leader mark, health and mana bars, the state (dead, in a fight,
// connection lost) and the distance. Left click selects the member (and follows, as the main client's "clicking follows"),
// right click opens the menu (follow, pass leadership and remove for the leader, leave, invite, copy name). The window opens
// by itself when the character joins a party.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class PartyFramesWindow : GameWindow
    {
        const float RowH = 46f;
        Vector2 scroll;
        uint selected;
        bool wasInParty;
        string inviteName = "";
        GUIStyle tiny;

        public override string Title => Loc.T("Party");
        public override KeyCode Hotkey => KeyCode.G;
        protected override Rect Place(float w, float h) => new Rect(8, 108, 236, 250);
        public override void Reset() { scroll = Vector2.zero; selected = 0; wasInParty = false; inviteName = ""; }

        public override void Tick(ChaosApp app)
        {
            var party = app.Session?.Party;
            if (party == null) return;
            // joining a party opens the window; leaving does not close it (the player may keep it for the invite box)
            if (party.InParty && !wasInParty) Open = true;
            wasInParty = party.InParty;
        }

        static Color Hex(string hex)
        {
            return ColorUtility.TryParseHtmlString(hex, out var c) ? c : new Color(0.6f, 0.55f, 0.5f);
        }

        static Color HpColor(int pct) => pct > 50 ? new Color(0.2f, 0.8f, 0.2f) : pct > 20 ? new Color(0.95f, 0.8f, 0.1f) : new Color(0.9f, 0.15f, 0.1f);

        protected override void Body(ChaosApp app, Rect inner)
        {
            var party = app.Session?.Party;
            if (party == null) return;
            if (tiny == null) tiny = new GUIStyle(app.SmallStyle) { fontSize = 11 };
            var e = Event.current;
            double now = app.Session.Now;
            bool stale = party.Stale(now);

            // header: count, shared experience bonus, invite box
            string head = party.InParty ? Loc.T("Party ({0})", party.Members.Count) : Loc.T("Not in a party");
            GUI.Label(new Rect(inner.x + 2, inner.y, inner.width - 70, 20), head, app.SmallStyle);
            string xp = party.XpText();
            if (xp.Length > 0)
            {
                var st = new GUIStyle(tiny) { alignment = TextAnchor.MiddleRight };
                st.normal.textColor = party.XpOn == 1 ? new Color(0.45f, 0.8f, 0.35f) : new Color(0.7f, 0.65f, 0.6f);
                GUI.Label(new Rect(inner.xMax - 90, inner.y, 88, 20), xp == "XP off" ? Loc.T("XP off") : xp, st);
            }
            var nameRect = new Rect(inner.x + 2, inner.y + 22, inner.width - 74, 22);
            GUI.SetNextControlName("partyInvite");
            string typed = GUI.TextField(nameRect, inviteName, 30);
            if (GUI.GetNameOfFocusedControl() == "partyInvite") app.MarkTextEditing();
            inviteName = typed;
            bool enter = e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter) && GUI.GetNameOfFocusedControl() == "partyInvite";
            if (inviteName.Length == 0 && e.type == EventType.Repaint && GUI.GetNameOfFocusedControl() != "partyInvite")
                GUI.Label(nameRect, "  " + Loc.T("Invite a player..."), tiny);
            if (GUI.Button(new Rect(inner.xMax - 70, inner.y + 22, 68, 22), Loc.T("Invite")) || enter)
            {
                if (party.Invite(inviteName)) { app.PostLine(Loc.T("Invitation sent to {0}.", inviteName.Trim())); inviteName = ""; }
                if (enter) e.Use();
            }

            var list = new Rect(inner.x, inner.y + 48, inner.width, inner.height - 48);
            if (!party.InParty)
            {
                GUI.Label(new Rect(list.x + 4, list.y + 4, list.width - 8, 60), Loc.T("You are not in a party. Invite a player here, or right-click a player on the map."), tiny);
                return;
            }
            float contentW = list.width - 18;
            scroll = GUI.BeginScrollView(list, scroll, new Rect(0, 0, contentW, Mathf.Max(list.height, party.Members.Count * RowH)));
            for (int i = 0; i < party.Members.Count; i++)
            {
                var m = party.Members[i];
                var row = new Rect(0, i * RowH, contentW, RowH - 2);
                bool sel = m.Id == selected;
                ChaosApp.Fill(row, m.Fight ? new Color(0.35f, 0.07f, 0.05f, 0.85f) : sel ? new Color(0.6f, 0.45f, 0.12f, 0.35f) : new Color(1f, 1f, 1f, 0.06f));
                float alpha = stale || m.Offline || m.Far ? 0.65f : 1f;
                var prev = GUI.color;
                GUI.color = new Color(1f, 1f, 1f, alpha);
                var pic = new Rect(row.x + 3, row.y + 5, 36, 36);
                ChaosApp.Fill(pic, new Color(0f, 0f, 0f, 0.5f));
                app.DrawOutfit(pic, m.Outfit);
                GUI.color = prev;

                var cls = ClassTable.Of(m.Vocation);
                var nameCol = m.Dead ? new Color(0.5f, 0.45f, 0.47f) : Hex(cls.Color);
                float nx = row.x + 44;
                if (m.Leader) ChaosApp.Fill(new Rect(nx, row.y + 6, 8, 8), new Color(0.96f, 0.81f, 0.45f));
                var ns = new GUIStyle(tiny) { fontSize = 12, fontStyle = FontStyle.Bold };
                ns.normal.textColor = nameCol;
                GUI.Label(new Rect(nx + (m.Leader ? 11 : 0), row.y + 1, row.width - 44 - 52 - (m.Leader ? 11 : 0), 18), m.Name, ns);
                var ls = new GUIStyle(tiny) { alignment = TextAnchor.MiddleRight };
                GUI.Label(new Rect(row.xMax - 54, row.y + 1, 50, 18), Loc.T("Lv {0}", m.Level), ls);

                var hp = new Rect(nx, row.y + 20, row.width - 48, 12);
                ChaosApp.Fill(hp, new Color(0f, 0f, 0f, 0.9f));
                ChaosApp.Fill(new Rect(hp.x + 1, hp.y + 1, (hp.width - 2) * Mathf.Clamp01(m.Percent / 100f), hp.height - 2), HpColor(m.Percent));
                var hs = new GUIStyle(tiny) { alignment = TextAnchor.MiddleCenter, fontSize = 10 };
                hs.normal.textColor = Color.white;
                GUI.Label(hp, StateText(m, stale), hs);
                if (!m.Far)
                {
                    var mp = new Rect(nx, row.y + 34, row.width - 48, 7);
                    ChaosApp.Fill(mp, new Color(0f, 0f, 0f, 0.9f));
                    ChaosApp.Fill(new Rect(mp.x + 1, mp.y + 1, (mp.width - 2) * Mathf.Clamp01(m.ManaPercent / 100f), mp.height - 2), new Color(0.15f, 0.35f, 0.85f));
                }

                if (e.type == EventType.MouseDown && row.Contains(e.mousePosition))
                {
                    if (e.button == 0)
                    {
                        selected = m.Id;
                        if (!m.Self) app.FollowMember(m.Id);
                    }
                    else if (e.button == 1) app.ShowMemberMenu(m, Area.position + e.mousePosition - scroll + new Vector2(list.x, list.y));
                    e.Use();
                }
            }
            GUI.EndScrollView();
        }

        string StateText(PartyMember m, bool stale)
        {
            if (stale || m.Offline) return Loc.T("Connection lost");
            if (m.Dead) return Loc.T("Dead");
            if (m.Far)
            {
                string far = Loc.T("far");
                if (m.Floors < 0) far += ", " + Loc.T("{0} up", -m.Floors);
                else if (m.Floors > 0) far += ", " + Loc.T("{0} down", m.Floors);
                return far;
            }
            string t = Plate.Short(m.Hp) + " / " + Plate.Short(m.HpMax);
            string d = m.DistanceText();
            return d.Length > 0 ? t + "   " + d : t;
        }
    }
}
