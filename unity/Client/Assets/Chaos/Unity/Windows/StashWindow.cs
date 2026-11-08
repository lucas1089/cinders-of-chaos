// Supply Stash (Ctrl+H): the character's item storage (extended opcode 110, Core/Stash.cs). Tabs, search, sort by amount or name, the items as a
// grid; click one to see its text and take it out (an amount for a stack). Drag an item of a bag onto the window to deposit it. Stow Everything,
// Collect inbox and the store link are buttons. Taking out works only in a protection zone or a hideout, depositing in town: the server decides.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class StashWindow : GameWindow
    {
        public override string Title => Loc.T("Stash");
        public override KeyCode Hotkey => KeyCode.H;
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 250, 60, 500, 470);

        const float Cell = 40f, Gap = 3f;
        bool lastVisible;
        string search = "", amountText = "1";
        bool byName;
        StashItem selected;
        Vector2 scroll;

        public override void Reset() { lastVisible = false; selected = null; search = ""; Open = false; scroll = Vector2.zero; }

        public override void Tick(ChaosApp app)
        {
            var st = app.Session?.Stash;
            if (st == null) return;
            WindowSync.Run(ref lastVisible, this, st.Visible, st.Show, st.Hide);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            var st = s?.Stash;
            if (st == null) return;
            var e = Event.current;

            // tabs
            float x = inner.x + 2, y = inner.y + 2;
            if (Tab(app, ref x, y, Loc.T("All"), st.SelectedTab == 0)) { st.SelectedTab = 0; scroll = Vector2.zero; }
            foreach (var t in st.Tabs)
            {
                if (x + 70 > inner.xMax) { x = inner.x + 2; y += 26; }
                if (Tab(app, ref x, y, StashState.TabLabel(t), st.SelectedTab == t.Id, t.Locked)) { st.SelectedTab = t.Id; scroll = Vector2.zero; }
            }
            y += 30;

            // search and sort
            var sr = new Rect(inner.x + 2, y, inner.width - 130, 22);
            GUI.SetNextControlName("stashSearch");
            search = GUI.TextField(sr, search, 40);
            if (GUI.GetNameOfFocusedControl() == "stashSearch") app.MarkTextEditing();
            if (search.Length == 0 && e.type == EventType.Repaint && GUI.GetNameOfFocusedControl() != "stashSearch") GUI.Label(sr, "  " + Loc.T("Search"), app.SmallStyle);
            byName = GUI.Toggle(new Rect(inner.xMax - 124, y, 120, 22), byName, byName ? Loc.T("Sorted by name") : Loc.T("Sorted by amount"), GUI.skin.button);
            y += 28;

            // the grid
            float footer = 118f;
            var grid = new Rect(inner.x + 2, y, inner.width - 4, inner.height - (y - inner.y) - footer);
            ChaosApp.Fill(grid, new Color(1f, 1f, 1f, 0.04f));
            var items = st.View(st.SelectedTab, search, byName);
            int per = Mathf.Max(1, (int)((grid.width - 18) / (Cell + Gap)));
            int rows = (items.Count + per - 1) / per;
            scroll = GUI.BeginScrollView(grid, scroll, new Rect(0, 0, grid.width - 18, Mathf.Max(grid.height, rows * (Cell + Gap))));
            StashItem hover = null;
            for (int i = 0; i < items.Count; i++)
            {
                var it = items[i];
                var r = new Rect((i % per) * (Cell + Gap), (i / per) * (Cell + Gap), Cell, Cell);
                ChaosApp.Fill(r, it == selected ? new Color(0.45f, 0.33f, 0.1f, 1f) : new Color(0.11f, 0.09f, 0.12f, 1f));
                var pic = new Rect(r.x + 2, r.y + 2, r.width - 4, r.height - 4);
                app.DrawItem(pic, (ushort)it.Sprite, it.Count);
                if (it.Rarity > 0) ItemSlots.Frame(pic, ItemRarity.FrameColor(it.Rarity, false));
                if (r.Contains(e.mousePosition))
                {
                    hover = it;
                    if (e.type == EventType.Repaint) ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.1f));
                    if (e.type == EventType.MouseDown && e.button == 0) { selected = it; amountText = it.Count.ToString(); e.Use(); }
                    else if (e.type == EventType.MouseDown && e.button == 1) { selected = it; amountText = it.Count.ToString(); st.Redeem(it, it.Count); e.Use(); }
                }
            }
            GUI.EndScrollView();
            if (items.Count == 0)
                GUI.Label(new Rect(grid.x + 6, grid.y + 6, grid.width - 12, 40), st.ItemsLoaded ? Loc.T("Nothing here.") : Loc.T("Loading the stash..."), app.SmallStyle);

            // detail
            var shown = hover ?? selected;
            float fy = grid.yMax + 4;
            if (shown != null)
            {
                string line = shown.Name + "  x" + shown.Count;
                var ns = new GUIStyle(app.SmallStyle) { fontStyle = FontStyle.Bold };
                ns.normal.textColor = ColorOf(ItemRarity.FrameColor(shown.Rarity, false), Color.white);
                GUI.Label(new Rect(inner.x + 4, fy, inner.width - 8, 20), line, ns);
                string tip = shown.Tooltip.Replace("\n", "  ");
                GUI.Label(new Rect(inner.x + 4, fy + 18, inner.width - 8, 20), tip.Length > 90 ? tip.Substring(0, 90) + "..." : tip, app.SmallStyle);
            }
            fy += 42;
            // take out
            bool canTake = selected != null && st.CanWithdraw && items.Contains(selected);
            GUI.enabled = canTake;
            if (selected != null && selected.Row < 0 && selected.Count > 1)
            {
                GUI.SetNextControlName("stashAmount");
                amountText = BankMath.Digits(GUI.TextField(new Rect(inner.x + 4, fy, 70, 24), amountText, 8));
                if (GUI.GetNameOfFocusedControl() == "stashAmount") app.MarkTextEditing();
            }
            if (GUI.Button(new Rect(inner.x + 80, fy, 100, 24), Loc.T("Take out")) && canTake)
            {
                int n = selected.Row >= 0 ? 1 : Mathf.Clamp((int)BankMath.Parse(amountText, selected.Count), 1, selected.Count);
                st.Redeem(selected, n);
            }
            GUI.enabled = st.CanDeposit;
            if (GUI.Button(new Rect(inner.x + 188, fy, 130, 24), Loc.T("Stow everything"))) st.StowAll();
            GUI.enabled = st.CanWithdraw && st.InboxCount > 0;
            if (GUI.Button(new Rect(inner.x + 324, fy, 100, 24), Loc.T("Inbox ({0})", st.InboxCount))) st.CollectInbox();
            GUI.enabled = st.StoreCategory.Length > 0;
            if (GUI.Button(new Rect(inner.xMax - 66, fy, 64, 24), Loc.T("Slots")))
            {
                st.Hide();
                s.Store.OpenCategory(st.StoreCategory);
            }
            GUI.enabled = true;
            fy += 28;
            string status = !st.CanWithdraw ? st.LockedLine(true) : !st.CanDeposit ? st.LockedLine(false) : st.StowReport;
            if (status.Length == 0) status = Loc.T("Drag an item here to store it.");
            GUI.Label(new Rect(inner.x + 4, fy, inner.width - 8, 22), status, app.SmallStyle);

            // an item dragged from a bag and dropped on the window goes in
            var all = new Rect(0, 0, Area.width, Area.height);
            ItemSlots.Drop(all, (pos, id, stack, count) =>
            {
                if (pos.X == 0xFFFF && pos.Y >= 0x40 && s.Parser.Containers.TryGetValue((byte)(pos.Y - 0x40), out var c)) pos = new Pos(pos.X, pos.Y, pos.Z - c.FirstIndex);
                if (!st.Deposit(pos, stack, id, count)) app.PostLine(st.LockedLine(false));
            });
            ItemSlots.Ghost(app, all);
        }

        static Color ColorOf(string hex, Color fallback) => hex != null && ColorUtility.TryParseHtmlString(hex, out var c) ? c : fallback;

        bool Tab(ChaosApp app, ref float x, float y, string label, bool on, bool locked = false)
        {
            float w = Mathf.Max(48f, 18f + label.Length * 7f);
            var r = new Rect(x, y, w, 24);
            x += w + 3;
            var prev = GUI.contentColor;
            if (locked) GUI.contentColor = new Color(0.8f, 0.5f, 0.45f);
            bool hit = GUI.Toggle(r, on, label, GUI.skin.button) && !on;
            GUI.contentColor = prev;
            return hit;
        }
    }
}
