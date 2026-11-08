// Party frames (Ctrl+G): a frame for every member of the party, from the server's party frames (extended opcode 235,
// Core/Party.cs): outfit, name in the class colour, level, leader mark, health and mana bars, the state (dead, in a fight,
// connection lost), the distance and the member's first buffs and debuffs. Left click selects the member (and follows, as the
// main client's "clicking follows" option), right click opens the menu (follow, pass leadership and remove for the leader, leave,
// invite, copy name). The gear button opens the settings of the main client's gear window (Core/PanelSettings.cs PartySettings):
// scale, lock, show the panel, show myself, buffs, numbers, clicking follows. The window opens by itself when the character joins a party.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class PartyFramesWindow : GameWindow
    {
        Vector2 scroll;
        uint selected;
        bool wasInParty;
        string inviteName = "";
        GUIStyle tiny;
        PartySettings settings;
        bool showSettings;
        bool lastBuffs = true;

        public override string Title => Loc.T("Party");
        public override KeyCode Hotkey => KeyCode.G;
        protected override Rect Place(float w, float h) => new Rect(8, 108, 236, 250);
        public override void Reset() { scroll = Vector2.zero; selected = 0; wasInParty = false; inviteName = ""; showSettings = false; }
        public override bool DragLocked => settings != null && settings.Locked;

        PartySettings Settings
        {
            get
            {
                if (settings == null) settings = PartySettings.Load(PlayerPrefs.GetString(PartySettings.Pref, ""));
                return settings;
            }
        }

        void Save() { PlayerPrefs.SetString(PartySettings.Pref, Settings.ToJson()); PlayerPrefs.Save(); }

        public override void Tick(ChaosApp app)
        {
            var party = app.Session?.Party;
            if (party == null) return;
            // joining a party opens the window (unless the settings hide it); leaving does not close it (the player may keep it for the invite box)
            if (party.InParty && !wasInParty && Settings.Shown) Open = true;
            wasInParty = party.InParty;
            Fit(party);
            // the buffs row asks the server for the buffs only when it is on
            if (Settings.ShowBuffs != lastBuffs) { lastBuffs = Settings.ShowBuffs; if (party.Watching) party.Open(lastBuffs); }
        }

        /// <summary>The width follows the scale, the height the frames (up to 460): set here, as the window's own rect is only taken from outside its draw.</summary>
        void Fit(PartyFrames party)
        {
            if (!Open) return;
            var cfg = Settings;
            Area.width = Mathf.Max(236f, cfg.Scaled(PartySettings.FrameW) + 36f);
            float content = 0;
            foreach (var m in cfg.Visible(party.Members)) content += cfg.FrameHeight(m) + PartySettings.Gap;
            float top = 28 + 22 + (showSettings ? 144 : 0);
            Area.height = party.InParty ? Mathf.Clamp(top + 30 + content, 120f, 460f) : Mathf.Max(Area.height, 150f);
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
            var cfg = Settings;
            // header: count, shared experience bonus, gear, invite box
            string head = party.InParty ? Loc.T("Party ({0})", party.Members.Count) : Loc.T("Not in a party");
            GUI.Label(new Rect(inner.x + 2, inner.y, inner.width - 124, 20), head, app.SmallStyle);
            string xp = party.XpText();
            if (xp.Length > 0)
            {
                var st = new GUIStyle(tiny) { alignment = TextAnchor.MiddleRight };
                st.normal.textColor = party.XpOn == 1 ? new Color(0.45f, 0.8f, 0.35f) : new Color(0.7f, 0.65f, 0.6f);
                GUI.Label(new Rect(inner.xMax - 116, inner.y, 88, 20), xp == "XP off" ? Loc.T("XP off") : xp, st);
            }
            if (GUI.Button(new Rect(inner.xMax - 26, inner.y, 24, 20), showSettings ? "<" : "...")) showSettings = !showSettings;
            float top = inner.y + 22;
            if (showSettings) top = SettingsPanel(app, inner, top, party);
            var nameRect = new Rect(inner.x + 2, top, inner.width - 74, 22);
            GUI.SetNextControlName("partyInvite");
            string typed = GUI.TextField(nameRect, inviteName, 30);
            if (GUI.GetNameOfFocusedControl() == "partyInvite") app.MarkTextEditing();
            inviteName = typed;
            bool enter = e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter) && GUI.GetNameOfFocusedControl() == "partyInvite";
            if (inviteName.Length == 0 && e.type == EventType.Repaint && GUI.GetNameOfFocusedControl() != "partyInvite")
                GUI.Label(nameRect, "  " + Loc.T("Invite a player..."), tiny);
            if (GUI.Button(new Rect(inner.xMax - 70, top, 68, 22), Loc.T("Invite")) || enter)
            {
                if (party.Invite(inviteName)) { app.PostLine(Loc.T("Invitation sent to {0}.", inviteName.Trim())); inviteName = ""; }
                if (enter) e.Use();
            }

            var list = new Rect(inner.x, top + 26, inner.width, inner.yMax - top - 26);
            if (!party.InParty)
            {
                GUI.Label(new Rect(list.x + 4, list.y + 4, list.width - 8, 60), Loc.T("You are not in a party. Invite a player here, or right-click a player on the map."), tiny);
                return;
            }
            var members = cfg.Visible(party.Members);
            float k = cfg.Scale / 100f, gap = PartySettings.Gap;
            float contentW = list.width - 18, contentH = 0;
            foreach (var m in members) contentH += cfg.FrameHeight(m) + gap;
            scroll = GUI.BeginScrollView(list, scroll, new Rect(0, 0, contentW, Mathf.Max(list.height, contentH)));
            var ns = new GUIStyle(tiny) { fontSize = Mathf.RoundToInt(12 * k), fontStyle = FontStyle.Bold };
            var ls = new GUIStyle(tiny) { alignment = TextAnchor.MiddleRight, fontSize = Mathf.RoundToInt(11 * k) };
            var hs = new GUIStyle(tiny) { alignment = TextAnchor.MiddleCenter, fontSize = Mathf.Max(8, Mathf.RoundToInt(10 * k)) };
            hs.normal.textColor = Color.white;
            float y = 0;
            foreach (var m in members)
            {
                float fh = cfg.FrameHeight(m);
                var row = new Rect(0, y, contentW, fh - 2);
                y += fh + gap;
                bool sel = m.Id == selected;
                ChaosApp.Fill(row, m.Fight ? new Color(0.35f, 0.07f, 0.05f, 0.85f) : sel ? new Color(0.6f, 0.45f, 0.12f, 0.35f) : new Color(1f, 1f, 1f, 0.06f));
                float alpha = stale || m.Offline || m.Far ? 0.65f : 1f;
                var prev = GUI.color;
                GUI.color = new Color(1f, 1f, 1f, alpha);
                float ps = 36 * k;
                var pic = new Rect(row.x + 3, row.y + 5 * k, ps, ps);
                ChaosApp.Fill(pic, new Color(0f, 0f, 0f, 0.5f));
                app.DrawOutfit(pic, m.Outfit);
                GUI.color = prev;

                var cls = ClassTable.Of(m.Vocation);
                ns.normal.textColor = m.Dead ? new Color(0.5f, 0.45f, 0.47f) : Hex(cls.Color);
                float nx = row.x + 8 + ps;
                float rightW = 52 * k;
                if (m.Leader) ChaosApp.Fill(new Rect(nx, row.y + 6 * k, 8, 8), new Color(0.96f, 0.81f, 0.45f));
                GUI.Label(new Rect(nx + (m.Leader ? 11 : 0), row.y + 1, row.width - (nx - row.x) - rightW - (m.Leader ? 11 : 0), 18 * k), m.Name, ns);
                GUI.Label(new Rect(row.xMax - rightW - 2, row.y + 1, rightW, 18 * k), Loc.T("Lv {0}", m.Level), ls);

                var hp = new Rect(nx, row.y + 20 * k, row.xMax - nx - 4, 12 * k);
                ChaosApp.Fill(hp, new Color(0f, 0f, 0f, 0.9f));
                ChaosApp.Fill(new Rect(hp.x + 1, hp.y + 1, (hp.width - 2) * Mathf.Clamp01(m.Percent / 100f), hp.height - 2), HpColor(m.Percent));
                string stateText = StateText(m, stale, cfg.ShowNumbers);
                GUI.Label(hp, stateText, hs);
                if (!m.Far)
                {
                    var mp = new Rect(nx, row.y + 34 * k, row.xMax - nx - 4, 7 * k);
                    ChaosApp.Fill(mp, new Color(0f, 0f, 0f, 0.9f));
                    ChaosApp.Fill(new Rect(mp.x + 1, mp.y + 1, (mp.width - 2) * Mathf.Clamp01(m.ManaPercent / 100f), mp.height - 2), new Color(0.15f, 0.35f, 0.85f));
                }
                if (cfg.BuffsShown(m)) BuffRow(row, m, k, now);

                if (e.type == EventType.MouseDown && row.Contains(e.mousePosition))
                {
                    if (e.button == 0)
                    {
                        selected = m.Id;
                        if (cfg.Follow && !m.Self) app.FollowMember(m.Id);
                    }
                    else if (e.button == 1) app.ShowMemberMenu(m, Area.position + e.mousePosition - scroll + new Vector2(list.x, list.y));
                    e.Use();
                }
            }
            GUI.EndScrollView();
        }

        /// <summary>The member's first buffs under the frame: a small square per buff, gold for a buff, red for a debuff, with the name's initials; the name and the time left show on a hover.</summary>
        void BuffRow(Rect row, PartyMember m, float k, double now)
        {
            float size = 14 * k, x = row.x + 4, y = row.yMax - size - 1;
            var e = Event.current;
            var small = new GUIStyle(tiny) { fontSize = Mathf.Max(7, Mathf.RoundToInt(8 * k)), alignment = TextAnchor.MiddleCenter };
            small.normal.textColor = Color.white;
            foreach (var b in m.Buffs)
            {
                if (x + size > row.xMax - 2) break;
                var r = new Rect(x, y, size, size);
                var border = b.Debuff ? new Color(0.79f, 0.19f, 0.12f) : new Color(0.72f, 0.57f, 0.23f);
                ChaosApp.Fill(r, border);
                ChaosApp.Fill(new Rect(r.x + 1, r.y + 1, r.width - 2, r.height - 2), b.Debuff ? new Color(0.35f, 0.08f, 0.06f) : new Color(0.2f, 0.15f, 0.06f));
                GUI.Label(r, PartySettings.BuffLabel(b), small);
                if (r.Contains(e.mousePosition))
                {
                    int left = PartySettings.SecondsLeft(b, now);
                    string text = (b.Name.Length > 0 ? b.Name : b.Icon) + (left >= 0 ? "  " + Loc.T("{0}s", left) : "");
                    var tip = new Rect(Mathf.Min(e.mousePosition.x, Area.width - 150), Mathf.Max(0, r.y - 20), 146, 18);
                    ChaosApp.Fill(tip, new Color(0.05f, 0.04f, 0.06f, 0.97f));
                    GUI.Label(tip, text, tiny);
                }
                x += size + 2;
            }
        }

        /// <summary>The gear panel: scale, and the checkboxes of the main client (show the panel, show myself, buffs, numbers, clicking follows, lock). Returns the y under it.</summary>
        float SettingsPanel(ChaosApp app, Rect inner, float y, PartyFrames party)
        {
            var cfg = Settings;
            bool changed = false;
            GUI.Label(new Rect(inner.x + 2, y, 90, 20), Loc.T("Scale: {0}%", cfg.Scale), tiny);
            if (GUI.Button(new Rect(inner.x + 96, y, 24, 20), "-")) { cfg.StepScale(-1); changed = true; }
            if (GUI.Button(new Rect(inner.x + 122, y, 24, 20), "+")) { cfg.StepScale(1); changed = true; }
            y += 22;
            changed |= Check(inner, ref y, Loc.T("Show the panel when in a party"), cfg.Shown, v => cfg.Shown = v);
            changed |= Check(inner, ref y, Loc.T("Show myself"), cfg.ShowSelf, v => cfg.ShowSelf = v);
            changed |= Check(inner, ref y, Loc.T("Show buffs"), cfg.ShowBuffs, v => cfg.ShowBuffs = v);
            changed |= Check(inner, ref y, Loc.T("Show numbers"), cfg.ShowNumbers, v => cfg.ShowNumbers = v);
            changed |= Check(inner, ref y, Loc.T("Clicking a member follows"), cfg.Follow, v => cfg.Follow = v);
            changed |= Check(inner, ref y, Loc.T("Lock the panel"), cfg.Locked, v => cfg.Locked = v);
            if (changed) Save();
            return y + 2;
        }

        static bool Check(Rect inner, ref float y, string text, bool value, Action<bool> set)
        {
            bool v = GUI.Toggle(new Rect(inner.x + 2, y, inner.width - 4, 20), value, text);
            y += 20;
            if (v == value) return false;
            set(v);
            return true;
        }

        string StateText(PartyMember m, bool stale, bool numbers)
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
            if (!numbers) return m.Percent + "%";
            string t = Plate.Short(m.Hp) + " / " + Plate.Short(m.HpMax);
            string d = m.DistanceText();
            return d.Length > 0 ? t + "   " + d : t;
        }
    }
}
