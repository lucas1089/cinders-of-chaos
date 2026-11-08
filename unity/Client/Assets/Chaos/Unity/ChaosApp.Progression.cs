// The top menu of the app (the main client's client_chaos_topbar) and the glue the progression windows share: opening a window by its
// class name, an Info page, the "where" buttons of the goals. The pure part (entries, unlock state, sorting): Core/TopMenu.cs.
//
// Category buttons sit where the flat toolbar was (ToolbarRect: 7 buttons). A click opens the drop-down under the button, a second click
// or a click elsewhere closes it. Entries are sorted by their shown text; an entry of a system the character has not unlocked is hidden,
// the next one to unlock shows grey with its level (opcode 115). The last category, Windows, lists every window that no entry names,
// so a window added to ChaosApp.MakeWindows is always reachable. A new unlock shows a text on the screen and a small box with Go.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        int topMenuOpen = -1;
        int topMenuFrame = -10;
        double announceSeen = -1;
        UnlockAnnouncement announceShown;
        bool announceBox;

        const float TopRowH = 24f, TopMenuW = 190f;
        Rect topBarRect;

        // ------------------------------------------------------------------------------------ opening things
        /// <summary>The window of that class name, or null.</summary>
        public GameWindow WindowNamed(string className)
        {
            if (windows.Count == 0) MakeWindows();
            foreach (var win in windows) if (win.GetType().Name == className) return win;
            return null;
        }

        public void OpenInfoPage(string page)
        {
            var info = FindWindow<InfoWindow>();
            if (info == null) return;
            info.Show(this, page);
        }

        static readonly Dictionary<string, string> ModuleWindows = new Dictionary<string, string>
        {
            { "game_skills", "SkillsWindow" }, { "game_spellbook", "SpellbookWindow" }, { "game_passivetree", "PassiveTreeWindow" },
            { "game_hunt", "HuntWindow" }, { "game_goals", "GoalsWindow" }, { "game_battle", "BattleListWindow" }, { "game_minimap", "MinimapWindow" },
            { "game_partyframes", "PartyFramesWindow" }, { "game_party_list", "PartyFramesWindow" }, { "game_inventory", "EquipmentWindow" },
            { "game_hotkeys", "HotkeyBarWindow" }, { "game_chaosinfo", "InfoWindow" },
        };

        /// <summary>What a "where" button of the goals does: a window, an Info page, a mark on the map. False when this client has no such window.</summary>
        public bool RunWhere(GoalWhere w)
        {
            if (w == null) return false;
            if (w.K == "info" && w.Page.Length > 0) { OpenInfoPage(w.Page); return true; }
            if (w.K == "window" && ModuleWindows.TryGetValue(w.M, out string cls))
            {
                var win = WindowNamed(cls);
                if (win != null) { win.Open = true; return true; }
            }
            if (w.HasPos)
            {
                PostLine(Loc.T("Marked on your map: {0}", w.Label.Length > 0 ? w.Label : w.X + ", " + w.Y + ", " + w.Z));
                return true;
            }
            PostLine(Loc.T("That window is not available."));
            return false;
        }

        // ------------------------------------------------------------------------------------ the menu
        sealed class MenuItem
        {
            public MenuEntry Entry;
            public string Text;
            public Action Run;
            public int LockedLevel;
            public bool IsNew;
        }

        MenuItem Resolve(MenuEntry e, bool windowsCategory = false)
        {
            var prog = session?.Progress;
            string text = windowsCategory ? e.Text : Loc.T(e.Text);
            int level = 0;
            var status = prog != null && !windowsCategory ? prog.Unlocks.Status(e.Text, out level) : MenuStatus.Open;
            if (status == MenuStatus.Hidden) return null;
            var item = new MenuItem { Entry = e, Text = text, LockedLevel = status == MenuStatus.Locked ? level : 0, IsNew = prog != null && !windowsCategory && prog.Unlocks.IsNew(e.Text) };
            string t = e.Target;
            if (t.StartsWith("win:", StringComparison.Ordinal))
            {
                var win = WindowNamed(t.Substring(4));
                if (win == null) return null;
                item.Run = () => win.Open = !win.Open;
            }
            else if (t.StartsWith("info:", StringComparison.Ordinal))
            {
                string page = t.Substring(5);
                if (prog != null && !prog.Info.IsPageOffered(page)) return null;
                item.Run = () => OpenInfoPage(page);
            }
            else if (t == "act:killtasks")
            {
                if (session?.Bestiary == null) return null;
                item.Run = () => { session.Bestiary.ShowTasks(); var w = FindWindow<BestiaryWindow>(); if (w != null) w.Open = true; };
            }
            else if (t == "act:tracker")
            {
                if (session?.Bestiary == null) return null;
                item.Run = () => session.Bestiary.Tracker.Toggle(Chaos.Core.TaskTrackerState.Rows(session.Bestiary.TrackerRows).Count);
            }
            else if (t == "act:logout")
            {
                item.Run = () => { session?.Logout(); Leave("Logged out."); };
            }
            else return null;
            return item;
        }

        List<MenuItem> CategoryItems(int index)
        {
            var list = new List<MenuItem>();
            if (index < TopMenu.Categories.Length)
            {
                foreach (var e in TopMenu.Sorted(TopMenu.Categories[index].Entries, x => Loc.T(x.Text)))
                {
                    var item = Resolve(e);
                    if (item != null) list.Add(item);
                }
                return list;
            }
            // Windows: everything no entry names, sorted by title
            var named = new HashSet<string>();
            foreach (var c in TopMenu.Categories)
                foreach (var e in c.Entries)
                    if (e.Target.StartsWith("win:", StringComparison.Ordinal)) named.Add(e.Target.Substring(4));
            var extras = new List<MenuEntry>();
            foreach (var win in windows)
            {
                if (named.Contains(win.GetType().Name) || !win.InMenu) continue;
                extras.Add(new MenuEntry { Text = win.Title, Target = "win:" + win.GetType().Name });
            }
            foreach (var e in TopMenu.Sorted(extras, x => x.Text))
            {
                var item = Resolve(e, true);
                if (item != null) list.Add(item);
            }
            return list;
        }

        string CategoryText(int index) => index < TopMenu.Categories.Length ? Loc.T(TopMenu.Categories[index].Text) : Loc.T("Windows");

        /// <summary>The category buttons and the open drop-down. Called from DrawWindows in place of the old toolbar.</summary>
        void TopbarGui(float w, float h, float scale)
        {
            if (windows.Count == 0) MakeWindows();
            int count = TopMenu.Categories.Length + 1;
            var tbShift = HudShift("toolbar", ToolbarRect(w));   // the movable top menu (ChaosApp.Visual.cs): the fitted row moves as a whole
            var e = Event.current;
            // each button is as wide as its label, the row ends before Log out and wraps when it does not fit
            var bs = GUI.skin.button;
            var widths = new float[count];
            for (int i = 0; i < count; i++) widths[i] = bs.CalcSize(new GUIContent(CategoryText(i))).x;
            var cells = TopbarLayout.Fit(widths, 10f, 56f, 4f, StatusRect().xMax + 8f, w - 104f);
            Rect bar = default;
            for (int i = 0; i < count; i++)
            {
                var b = new Rect(cells[i].X + tbShift.x, 8 + cells[i].Row * 32 + tbShift.y, cells[i].W, 30);
                bar = i == 0 ? b : Rect.MinMaxRect(Mathf.Min(bar.xMin, b.xMin), bar.yMin, Mathf.Max(bar.xMax, b.xMax), Mathf.Max(bar.yMax, b.yMax));
                uiRects.Add(Scaled(b, scale));
                bool on = topMenuOpen == i;
                if (GUI.Toggle(b, on, CategoryText(i), GUI.skin.button) != on)
                {
                    topMenuOpen = on ? -1 : i;
                    topMenuFrame = Time.frameCount;
                }
            }
            topBarRect = bar;
            if (topMenuOpen >= 0 && topMenuOpen < count)
            {
                var items = CategoryItems(topMenuOpen);
                float rowH = TopRowH;
                var cell = cells[topMenuOpen];
                var box = new Rect(cell.X + tbShift.x + cell.W / 2f - TopMenuW / 2f, 8 + cell.Row * 32 + 32 + tbShift.y, TopMenuW, 6 + rowH * Mathf.Max(1, items.Count));
                box.x = Mathf.Clamp(box.x, 4, Mathf.Max(4, w - box.width - 4));
                uiRects.Add(Scaled(box, scale));
                // a click outside closes it (not the click that opened it)
                if (e.type == EventType.MouseDown && Time.frameCount != topMenuFrame && !box.Contains(e.mousePosition))
                {
                    if (!bar.Contains(e.mousePosition)) topMenuOpen = -1;
                }
                if (e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape) { topMenuOpen = -1; e.Use(); }
                if (topMenuOpen >= 0)
                {
                    // a window of its own, so it sits over the game windows (as the party menu does)
                    var snapshot = items;
                    GUI.Window(MenuWindowId + 10, box, _ =>
                    {
                        ChaosApp.Fill(new Rect(0, 0, box.width, box.height), new Color(0.05f, 0.04f, 0.06f, 0.97f));
                        ChaosApp.Fill(new Rect(0, 0, box.width, 1), new Color(0.6f, 0.5f, 0.3f));
                        if (snapshot.Count == 0) GUI.Label(new Rect(8, 3, box.width - 16, rowH), Loc.T("Nothing here yet."), small);
                        for (int i = 0; i < snapshot.Count; i++)
                        {
                            var it = snapshot[i];
                            var r = new Rect(3, 3 + i * rowH, box.width - 6, rowH - 1);
                            string text = it.Text + (it.LockedLevel > 0 ? "  " + Loc.T("Level {0}", it.LockedLevel) : it.IsNew ? "  " + Loc.T("New") : "");
                            var old = GUI.color;
                            if (it.LockedLevel > 0) GUI.color = new Color(1f, 1f, 1f, 0.45f);
                            bool open = it.Entry.Target.StartsWith("win:", StringComparison.Ordinal) && WindowNamed(it.Entry.Target.Substring(4))?.Open == true;
                            if (GUI.Button(r, (open ? "> " : "") + text) && it.LockedLevel == 0)
                            {
                                it.Run();
                                session?.Progress?.Unlocks.MarkSeen(it.Entry.Text);
                                topMenuOpen = -1;
                            }
                            GUI.color = old;
                        }
                    }, GUIContent.none, GUIStyle.none);
                    GUI.BringWindowToFront(MenuWindowId + 10);
                }
            }
            UnlockGui(w, h, scale);
        }

        /// <summary>A new unlock: a big text on the screen for a few seconds and a small box with Go and Close for 30 seconds.</summary>
        void UnlockGui(float w, float h, float scale)
        {
            var u = session?.Progress?.Unlocks;
            if (u == null || u.Announcement == null) return;
            if (!ReferenceEquals(announceShown, u.Announcement))
            {
                announceShown = u.Announcement;
                announceSeen = session.Now;
                announceBox = true;
            }
            double age = session.Now - announceSeen;
            var a = announceShown;
            if (age < MenuUnlocks.TextMs + 900)
            {
                float alpha = age < MenuUnlocks.TextMs ? 1f : 1f - (float)((age - MenuUnlocks.TextMs) / 900);
                var st = new GUIStyle(small) { fontSize = 30, alignment = TextAnchor.MiddleCenter, fontStyle = FontStyle.Bold };
                var r = new Rect(0, h * 0.22f, w, 44);
                st.normal.textColor = new Color(0f, 0f, 0f, 0.8f * alpha);
                GUI.Label(new Rect(r.x + 2, r.y + 2, r.width, r.height), Loc.T("New: {0}!", a.Title), st);
                st.normal.textColor = new Color(0.97f, 0.82f, 0.45f, alpha);
                GUI.Label(r, Loc.T("New: {0}!", a.Title), st);
            }
            if (announceBox && age < MenuUnlocks.WindowSeconds * 1000)
            {
                var box = new Rect(w / 2 - 190, h * 0.22f + 52, 380, 118);
                uiRects.Add(Scaled(box, scale));
                GUI.Window(MenuWindowId + 11, box, _ =>
                {
                    ChaosApp.Fill(new Rect(0, 0, box.width, box.height), new Color(0.05f, 0.04f, 0.06f, 0.96f));
                    ChaosApp.Fill(new Rect(0, 0, box.width, 3), new Color(0.96f, 0.81f, 0.45f));
                    var ts = new GUIStyle(small) { fontSize = 15, fontStyle = FontStyle.Bold };
                    GUI.Label(new Rect(10, 8, box.width - 20, 22), a.Title, ts);
                    var ls = new GUIStyle(small) { wordWrap = true };
                    GUI.Label(new Rect(10, 32, box.width - 20, 44), a.Line1 + (a.Line2.Length > 0 ? "\n" + a.Line2 : ""), ls);
                    if (GUI.Button(new Rect(10, box.height - 34, 100, 26), Loc.T("Go")))
                    {
                        announceBox = false;
                        foreach (var c in TopMenu.Categories)
                            foreach (var en in c.Entries)
                                if (en.Text == a.Menu) { Resolve(en)?.Run?.Invoke(); u.MarkSeen(en.Text); }
                    }
                    if (GUI.Button(new Rect(120, box.height - 34, 100, 26), Loc.T("Close"))) announceBox = false;
                }, GUIContent.none, GUIStyle.none);
                GUI.BringWindowToFront(MenuWindowId + 11);
            }
        }
    }
}
