// Party and context menu glue of the app: the right-click menu of a creature (attack, follow, invite, join, leave ...), the
// menu of a party frame, the invitation box (Accept / Decline) and the outfit drawn small in a GUI rectangle (party frames,
// character plate, character select).
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        /// <summary>A line in the chat box, as a server message.</summary>
        public void PostLine(string text) { AddChat("", text, 0); }

        // ------------------------------------------------------------------------------------ the menu
        readonly List<KeyValuePair<string, Action>> menuItems = new List<KeyValuePair<string, Action>>();
        Rect menuRect;
        int menuFrame = -10;
        const float MenuRowH = 24f, MenuW = 190f;
        const int MenuWindowId = 9000;

        /// <summary>Opens a menu at a point of the UI (UI units). An empty label is a separator.</summary>
        public void ShowMenu(Vector2 at, List<KeyValuePair<string, Action>> items)
        {
            menuItems.Clear();
            menuItems.AddRange(items);
            menuFrame = Time.frameCount;
            menuRect = new Rect(at.x + 2, at.y + 2, MenuW, 6 + MenuRowH * menuItems.Count);
        }

        void CloseMenu() { menuItems.Clear(); }

        /// <summary>The menu window and the invitation box. Call last in the game GUI, so they sit over the other windows.</summary>
        void PartyGui(float w, float h, float scale)
        {
            if (session == null) return;
            double now = session.Now;
            var party = session.Party;
            if (party.InvitationOpen(now))
            {
                var box = new Rect(w / 2 - 170, 52, 340, 78);
                uiRects.Add(Scaled(box, scale));
                GUI.Window(MenuWindowId + 1, box, _ =>
                {
                    Fill(new Rect(0, 0, box.width, box.height), new Color(0.04f, 0.03f, 0.05f, 0.95f));
                    Fill(new Rect(0, 0, box.width, 3), new Color(0.96f, 0.81f, 0.45f));
                    GUI.Label(new Rect(10, 8, box.width - 20, 24), Loc.T("{0} invited you to join their party.", party.InvitedBy), small);
                    if (GUI.Button(new Rect(10, 40, 150, 28), Loc.T("Accept"))) AcceptInvitation();
                    if (GUI.Button(new Rect(180, 40, 150, 28), Loc.T("Decline"))) party.InvitedBy = "";
                }, GUIContent.none, GUIStyle.none);
                GUI.BringWindowToFront(MenuWindowId + 1);
            }
            if (menuItems.Count == 0) return;
            var e = Event.current;
            // a click outside closes it (not the click that opened it)
            if (e.type == EventType.MouseDown && Time.frameCount != menuFrame && !menuRect.Contains(e.mousePosition)) { CloseMenu(); return; }
            if (e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape) { CloseMenu(); e.Use(); return; }
            menuRect.x = Mathf.Clamp(menuRect.x, 0, Mathf.Max(0, w - menuRect.width));
            menuRect.y = Mathf.Clamp(menuRect.y, 0, Mathf.Max(0, h - menuRect.height));
            uiRects.Add(Scaled(menuRect, scale));
            GUI.Window(MenuWindowId, menuRect, _ =>
            {
                Fill(new Rect(0, 0, menuRect.width, menuRect.height), new Color(0.07f, 0.05f, 0.07f, 0.97f));
                Fill(new Rect(0, 0, menuRect.width, 1), new Color(0.5f, 0.4f, 0.2f));
                for (int i = 0; i < menuItems.Count; i++)
                {
                    var r = new Rect(3, 3 + i * MenuRowH, menuRect.width - 6, MenuRowH - 2);
                    if (menuItems[i].Key.Length == 0) { Fill(new Rect(6, r.y + MenuRowH / 2 - 1, r.width - 6, 1), new Color(1f, 1f, 1f, 0.15f)); continue; }
                    if (GUI.Button(r, menuItems[i].Key))
                    {
                        var act = menuItems[i].Value;
                        CloseMenu();
                        act();
                        return;
                    }
                }
            }, GUIContent.none, GUIStyle.none);
            GUI.BringWindowToFront(MenuWindowId);
        }

        // ------------------------------------------------------------------------------------ party actions
        int MyShield => world?.Player != null ? world.Player.Shield : 0;

        Vector2 MouseUi()
        {
            float scale = UiScale(UnityEngine.Screen.width, UnityEngine.Screen.height, UnityEngine.Screen.dpi);
            return new Vector2(Input.mousePosition.x / scale, (UnityEngine.Screen.height - Input.mousePosition.y) / scale);
        }

        /// <summary>Right-click on a creature of the map. A monster or npc is attacked as before; a player gets the menu.</summary>
        void OnCreatureRightClick(Creature c)
        {
            if (c == null || session == null) return;
            if (c.Type != 0) { session.Attack(c.Id); return; }
            var items = new List<KeyValuePair<string, Action>>();
            uint id = c.Id;
            bool attacked = session.AttackTarget == id;
            items.Add(new KeyValuePair<string, Action>(attacked ? Loc.T("Stop Attack") : Loc.T("Attack"), () => { if (attacked) session.CancelAttack(); else session.Attack(id); }));
            items.Add(new KeyValuePair<string, Action>(Loc.T("Follow"), () => session.Follow(id)));
            var party = PartyMenu.For(MyShield, c.Shield);
            if (party.Count > 0) items.Add(new KeyValuePair<string, Action>("", null));
            foreach (var a in party)
            {
                var action = a;
                items.Add(new KeyValuePair<string, Action>(Loc.T(PartyMenu.Label(a)), () => session.Party.Do(action, id)));
            }
            items.Add(new KeyValuePair<string, Action>("", null));
            string name = c.Name;
            items.Add(new KeyValuePair<string, Action>(Loc.T("Copy Name"), () => GUIUtility.systemCopyBuffer = name));
            ShowMenu(MouseUi(), items);
        }

        /// <summary>Left click on a party frame: follow the member (toggle) when it is in view.</summary>
        public void FollowMember(uint id)
        {
            if (session == null || world == null || !world.Creatures.ContainsKey(id)) return;
            session.Follow(id);
        }

        /// <summary>Right click on a party frame: the member's menu. `at` is in UI units.</summary>
        public void ShowMemberMenu(PartyMember m, Vector2 at)
        {
            if (session == null) return;
            var party = session.Party;
            uint id = m.Id;
            var items = new List<KeyValuePair<string, Action>>();
            bool inView = world != null && world.Creatures.ContainsKey(id);
            if (!m.Self && inView)
            {
                items.Add(new KeyValuePair<string, Action>(Loc.T("Follow"), () => session.Follow(id)));
                items.Add(new KeyValuePair<string, Action>(Loc.T("Stop following"), () => session.CancelAttack()));
                items.Add(new KeyValuePair<string, Action>("", null));
            }
            if (party.ViewerIsLeader && !m.Self)
            {
                items.Add(new KeyValuePair<string, Action>(Loc.T("Pass Leadership"), () => party.Do(PartyAction.PassLeadership, id)));
                items.Add(new KeyValuePair<string, Action>(Loc.T("Remove from the party"), () => party.Kick(id)));
            }
            if (party.ViewerIsLeader)
                items.Add(new KeyValuePair<string, Action>(Loc.T(PartyMenu.Label(PartyShield.SharedEnabled(MyShield) ? PartyAction.ShareOff : PartyAction.ShareOn)),
                    () => party.Do(PartyShield.SharedEnabled(MyShield) ? PartyAction.ShareOff : PartyAction.ShareOn, 0)));
            if (m.Self) items.Add(new KeyValuePair<string, Action>(Loc.T("Leave Party"), () => party.Do(PartyAction.Leave, 0)));
            items.Add(new KeyValuePair<string, Action>("", null));
            string name = m.Name;
            items.Add(new KeyValuePair<string, Action>(Loc.T("Copy Name"), () => GUIUtility.systemCopyBuffer = name));
            ShowMenu(at, items);
        }

        /// <summary>Accepts the invitation: joins by the leader's creature, who must be in view.</summary>
        void AcceptInvitation()
        {
            var party = session.Party;
            string who = party.InvitedBy;
            var candidates = new List<KeyValuePair<uint, string>>();
            if (world != null)
                foreach (var c in world.Creatures.Values) if (c.Type == 0) candidates.Add(new KeyValuePair<uint, string>(c.Id, c.Name));
            uint id = PartyFrames.FindLeader(candidates, who);
            if (id != 0) party.Do(PartyAction.Join, id);
            else { PostLine(Loc.T("{0} is out of sight: go near to join the party.", who)); party.InvitedBy = ""; }
        }

        // ------------------------------------------------------------------------------------ outfits in the GUI
        /// <summary>Draws an outfit (standing, facing south, its colours and addons) into r, in the cell grid of its thing, as DrawItem does for items.</summary>
        public void DrawOutfit(Rect r, Outfit o, Dir facing = Dir.South)
        {
            if (o == null || dat == null || atlas == null) return;
            if (o.LookType == 0)
            {
                if (o.LookTypeEx != 0) DrawItem(r, (ushort)o.LookTypeEx, 1);
                return;
            }
            var t = dat.Outfit(o.LookType);
            if (t == null) return;
            var g = t.Idle;
            int dir = (int)facing;
            if (g.PatternX < 8 && dir > 3) dir = 2;
            dir %= Mathf.Max(1, g.PatternX);
            int n = Mathf.Max(g.Width, g.Height);
            float cell = r.width / n;
            for (int addon = 0; addon < g.PatternY; addon++)
            {
                if (addon > 0 && (o.Addons & (1 << (addon - 1))) == 0) continue;
                for (int hh = 0; hh < g.Height; hh++)
                    for (int ww = 0; ww < g.Width; ww++)
                    {
                        uint baseId = g.Sprite(ww, hh, 0, dir, addon, 0, 0);
                        uint maskId = g.Layers > 1 ? g.Sprite(ww, hh, 1, dir, addon, 0, 0) : 0;
                        int slot;
                        if (maskId == 0) slot = atlas.Sprite(baseId);
                        else
                        {
                            // the same key as the map's outfit cells: the composed frame is shared
                            ulong key = (ulong)baseId << 28 ^ (ulong)(o.Head & 127) << 21 ^ (ulong)(o.Body & 127) << 14 ^ (ulong)(o.Legs & 127) << 7 ^ (ulong)(o.Feet & 127);
                            slot = atlas.Composed(key, () =>
                            {
                                var rgba = atlas.Raw(baseId);
                                var mask = atlas.Raw(maskId);
                                if (rgba != null && mask != null) OutfitColors.Apply(rgba, mask, o);
                                return rgba;
                            });
                        }
                        if (slot == 0) continue;
                        atlas.Upload();
                        var cr = new Rect(r.x + (n - 1 - ww) * cell, r.y + (n - 1 - hh) * cell, cell, cell);
                        GUI.DrawTextureWithTexCoords(cr, atlas.Texture, atlas.Uv(slot));
                    }
            }
        }
    }
}
