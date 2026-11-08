// The Chaos store (Ctrl+T): the category tree, search, the offers of a page and Buy with Chaos Coins the account already has (extended opcode 218,
// Core/Store.cs). A purchase asks first and the server checks the price again. There is no payment of any kind in this window: the donation
// messages are ignored and coins are added on the website.
using System.Globalization;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class StoreWindow : GameWindow
    {
        public override string Title => Loc.T("Store");
        public override KeyCode Hotkey => KeyCode.T;
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 350, 48, 700, 480);

        const float RowH = 66f, SideW = 190f;
        bool lastVisible;
        string search = "", searchSent = "";
        double searchAt = -1;
        Vector2 catScroll, offerScroll;
        int seenMessages;
        string messageTitle = "", messageText = "";

        public override void Reset() { lastVisible = false; search = searchSent = ""; Open = false; seenMessages = 0; messageText = ""; }

        public override void Tick(ChaosApp app)
        {
            var st = app.Session?.Store;
            if (st == null) return;
            WindowSync.Run(ref lastVisible, this, st.Visible, st.Show, st.Hide);
            if (st.Messages != seenMessages) { seenMessages = st.Messages; messageTitle = st.MessageTitle; messageText = st.MessageText; Open = true; }
        }

        static string Short(double n)
        {
            double a = System.Math.Abs(n);
            if (a >= 1000000) return (n / 1000000).ToString("0.##", CultureInfo.InvariantCulture) + "M";
            if (a >= 10000) return (n / 1000).ToString("0.#", CultureInfo.InvariantCulture) + "k";
            return n.ToString("0", CultureInfo.InvariantCulture);
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session;
            var st = s?.Store;
            if (st == null) return;
            var e = Event.current;
            bool modal = st.ConfirmOffer != null || messageText.Length > 0;

            // header: search, history, coins
            var sr = new Rect(inner.x + 2, inner.y + 2, 250, 24);
            GUI.enabled = !modal;
            GUI.SetNextControlName("storeSearch");
            string typed = GUI.TextField(sr, search, 40);
            if (GUI.GetNameOfFocusedControl() == "storeSearch") app.MarkTextEditing();
            if (typed != search) { search = typed; searchAt = s.Now + 400; }
            if (search.Length == 0 && e.type == EventType.Repaint && GUI.GetNameOfFocusedControl() != "storeSearch") GUI.Label(sr, "  " + Loc.T("Search the store"), app.SmallStyle);
            if (searchAt >= 0 && s.Now >= searchAt) { searchAt = -1; searchSent = search; st.Search(search); }
            if (GUI.Button(new Rect(inner.x + 258, inner.y + 2, 120, 24), Loc.T("History"))) st.ShowHistory();
            GUI.enabled = true;
            var coins = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleRight, fontStyle = FontStyle.Bold };
            coins.normal.textColor = new Color(0.96f, 0.81f, 0.3f);
            GUI.Label(new Rect(inner.xMax - 240, inner.y + 2, 238, 24), st.Coins >= 0 ? Loc.T("Chaos Coins: {0}", Short(st.Coins)) : Loc.T("Chaos Coins: {0}", "-"), coins);

            // categories
            var side = new Rect(inner.x + 2, inner.y + 32, SideW, inner.height - 54);
            ChaosApp.Fill(side, new Color(1f, 1f, 1f, 0.04f));
            var rows = StoreTree.Rows(st.Tree, st.Expanded);
            catScroll = GUI.BeginScrollView(side, catScroll, new Rect(0, 0, SideW - 18, Mathf.Max(side.height, rows.Count * 28f)));
            for (int i = 0; i < rows.Count; i++)
            {
                var row = rows[i];
                var r = new Rect(row.Depth * 14f, i * 28f, SideW - 18 - row.Depth * 14f, 26);
                bool on = !row.Node.Group && row.Node.Category.Index == st.Selected && !st.BrowsingHistory && st.Searching.Length == 0;
                ChaosApp.Fill(r, on ? new Color(0.6f, 0.45f, 0.12f, 0.4f) : new Color(1f, 1f, 1f, 0.05f));
                string label = (row.Node.Group ? (row.Expanded ? "- " : "+ ") : "") + StoreTree.Label(row.Node.Name, row.Node.Size);
                var cat = row.Node.Category;
                if (cat != null && cat.Type == "item" && cat.Item != 0) { app.DrawItem(new Rect(r.x + 1, r.y + 1, 24, 24), (ushort)cat.Item, 1); }
                else if (cat != null && cat.Type == "outfit") app.DrawOutfit(new Rect(r.x + 1, r.y + 1, 24, 24), cat.Outfit);
                GUI.Label(new Rect(r.x + 28, r.y + 3, r.width - 28, 22), label, app.SmallStyle);
                if (!modal && e.type == EventType.MouseDown && e.button == 0 && r.Contains(e.mousePosition))
                {
                    if (row.Node.Group) st.ClickGroup(row.Node.Name);
                    else { search = ""; searchSent = ""; st.Select(row.Node.Category.Index); }
                    e.Use();
                }
            }
            GUI.EndScrollView();
            GUI.Label(new Rect(side.x, side.yMax + 2, side.width, 20), Loc.T("Chaos Coins are added on the website."), app.SmallStyle);

            // path and offers
            var main = new Rect(side.xMax + 6, inner.y + 32, inner.width - SideW - 10, inner.height - 54);
            string path = st.BrowsingHistory ? Loc.T("Transaction history") : st.Searching.Length > 0 ? Loc.T("Search \"{0}\": {1} offers", st.Searching, st.Offers.Count) : PathOf(st);
            GUI.Label(new Rect(main.x, main.y - 2, main.width, 20), path, app.SmallStyle);
            var list = new Rect(main.x, main.y + 20, main.width, main.height - 20 - 26);
            ChaosApp.Fill(list, new Color(1f, 1f, 1f, 0.03f));
            offerScroll = GUI.BeginScrollView(list, offerScroll, new Rect(0, 0, list.width - 18, Mathf.Max(list.height, st.Offers.Count * RowH)));
            for (int i = 0; i < st.Offers.Count; i++) OfferRow(app, st, st.Offers[i], new Rect(0, i * RowH, list.width - 18, RowH - 2), modal);
            GUI.EndScrollView();
            if (st.Offers.Count == 0)
                GUI.Label(new Rect(list.x + 8, list.y + 8, list.width - 16, 40), st.Loaded ? Loc.T("Nothing here.") : Loc.T("Loading the store..."), app.SmallStyle);

            // pages
            if (!st.BrowsingHistory && st.Searching.Length == 0)
            {
                GUI.enabled = !modal && st.Page > 1;
                if (GUI.Button(new Rect(main.x, main.yMax - 24, 80, 24), Loc.T("Previous"))) st.GoPage(-1);
                GUI.enabled = !modal && st.Page < st.TotalPages;
                if (GUI.Button(new Rect(main.xMax - 80, main.yMax - 24, 80, 24), Loc.T("Next"))) st.GoPage(1);
                GUI.enabled = true;
                GUI.Label(new Rect(main.x + 84, main.yMax - 22, main.width - 168, 22), Loc.T("Page {0} of {1}", st.Page, st.TotalPages), new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleCenter });
            }

            if (st.ConfirmOffer != null) ConfirmBox(app, st, inner);
            else if (messageText.Length > 0) MessageBox(app, inner);
        }

        static string PathOf(StoreState st)
        {
            var leaf = StoreTree.Leaf(st.Tree, st.Selected);
            if (leaf == null) return "";
            return leaf.Category.Parent.Length > 0 ? leaf.Category.Parent + " > " + leaf.Name : leaf.Name;
        }

        void OfferRow(ChaosApp app, StoreState st, StoreOffer o, Rect r, bool modal)
        {
            ChaosApp.Fill(r, new Color(1f, 1f, 1f, 0.06f));
            var pic = new Rect(r.x + 4, r.y + 4, 56, 56);
            ChaosApp.Fill(pic, new Color(0.11f, 0.09f, 0.12f, 1f));
            if (o.Type == "item" && o.Item != 0) app.DrawItem(new Rect(pic.x + 4, pic.y + 4, 48, 48), (ushort)o.Item, o.Count);
            else if (o.Type == "outfit" && o.Outfit != null) app.DrawOutfit(new Rect(pic.x + 4, pic.y + 4, 48, 48), o.Outfit);
            var ts = new GUIStyle(app.SmallStyle) { fontStyle = FontStyle.Bold };
            GUI.Label(new Rect(r.x + 66, r.y + 2, r.width - 66 - 96, 20), Loc.T("{0} ({1} coins)", o.Title, Short(o.Cost)), ts);
            var ds = new GUIStyle(app.SmallStyle) { fontSize = 11, wordWrap = true };
            string desc = o.Description;
            if (o.Tags.Count > 0) desc = string.Join("  ", o.Tags) + "  " + desc;
            GUI.Label(new Rect(r.x + 66, r.y + 22, r.width - 66 - 96, r.height - 24), desc, ds);
            if (o.OldCost > o.Cost) GUI.Label(new Rect(r.xMax - 94, r.y + 4, 90, 18), Loc.T("was {0}", Short(o.OldCost)), ds);
            if (o.Buyable)
            {
                GUI.enabled = !modal && !o.Owned;
                if (GUI.Button(new Rect(r.xMax - 90, r.y + 24, 84, 28), o.Owned ? Loc.T("Owned") : Loc.T("Buy"))) st.AskBuy(o);
                GUI.enabled = true;
            }
        }

        void ConfirmBox(ChaosApp app, StoreState st, Rect inner)
        {
            var o = st.ConfirmOffer;
            var box = new Rect(inner.x + inner.width / 2 - 170, inner.y + 150, 340, 120);
            ChaosApp.Fill(new Rect(box.x - 2, box.y - 2, box.width + 4, box.height + 4), new Color(0.5f, 0.4f, 0.2f, 1f));
            ChaosApp.Fill(box, new Color(0.06f, 0.05f, 0.07f, 1f));
            var ms = new GUIStyle(app.SmallStyle) { wordWrap = true };
            GUI.Label(new Rect(box.x + 8, box.y + 8, box.width - 16, 60), Loc.T("Do you want to buy {0} for {1} Chaos Coins?", o.Title, ((long)o.Cost).ToString("N0", CultureInfo.InvariantCulture)), ms);
            if (GUI.Button(new Rect(box.x + 8, box.yMax - 38, 150, 28), Loc.T("Yes"))) st.ConfirmBuy();
            if (GUI.Button(new Rect(box.xMax - 158, box.yMax - 38, 150, 28), Loc.T("No"))) st.CancelBuy();
        }

        void MessageBox(ChaosApp app, Rect inner)
        {
            var box = new Rect(inner.x + inner.width / 2 - 180, inner.y + 140, 360, 140);
            ChaosApp.Fill(new Rect(box.x - 2, box.y - 2, box.width + 4, box.height + 4), new Color(0.5f, 0.4f, 0.2f, 1f));
            ChaosApp.Fill(box, new Color(0.06f, 0.05f, 0.07f, 1f));
            var ts = new GUIStyle(app.SmallStyle) { fontStyle = FontStyle.Bold };
            GUI.Label(new Rect(box.x + 8, box.y + 6, box.width - 16, 22), messageTitle, ts);
            var ms = new GUIStyle(app.SmallStyle) { wordWrap = true, fontSize = 13 };
            GUI.Label(new Rect(box.x + 8, box.y + 30, box.width - 16, 70), messageText, ms);
            if (GUI.Button(new Rect(box.x + 8, box.yMax - 34, box.width - 16, 28), Loc.T("Ok"))) { messageText = ""; messageTitle = ""; }
        }
    }
}
