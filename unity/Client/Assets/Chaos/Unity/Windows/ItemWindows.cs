// Windows of the item and economy utilities (track O): Auto Loot, Loot Bag and Auto Seller, Orb Exchange, Gambler, Ember Cache, Unveil, Item Finder, Loadouts,
// Spell Supports, Chaos Pact and Candlemarks. Models: Core/WorldItems.cs and WorldItems2.cs. None has a Ctrl hotkey: the top menu or the server opens them.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>Base of a window whose open state follows a model's Visible flag.</summary>
    public abstract class SyncedWindow : GameWindow
    {
        bool lastVisible;
        protected GUIStyle st, small;
        public override void Reset() { lastVisible = false; Open = false; OnReset(); }
        protected virtual void OnReset() { }
        protected abstract bool Visible(ChaosApp app, out System.Action show, out System.Action hide);

        public override void Tick(ChaosApp app)
        {
            if (!Visible(app, out var show, out var hide)) return;
            bool vis = IsVisible(app);
            WindowSync.Run(ref lastVisible, this, vis, show, hide);
        }

        protected abstract bool IsVisible(ChaosApp app);

        protected void Styles(ChaosApp app)
        {
            if (st == null) { st = new GUIStyle(app.SmallStyle) { fontSize = 13 }; small = Ui.Wrap(app, 11); }
        }
    }

    // ------------------------------------------------------------------------------------------------ auto loot
    public sealed class AutoLootWindow : SyncedWindow
    {
        public override string Title => Loc.T("Auto Loot");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 170, 80, 340, 420);
        string text = "";
        Vector2 scroll;

        protected override void OnReset() { text = ""; }
        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var a = app.Session?.Utils?.AutoLoot; show = null; hide = null; if (a == null) return false; show = a.Open; hide = () => a.Visible = false; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.AutoLoot.Visible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var a = app.Session?.Utils?.AutoLoot;
            if (a == null) return;
            Styles(app);
            float x = inner.x + 4, y = inner.y + 2, w = inner.width - 8;
            GUI.SetNextControlName("lootAdd");
            text = GUI.TextField(new Rect(x, y, w - 70, 24), text, 40);
            if (GUI.GetNameOfFocusedControl() == "lootAdd") app.MarkTextEditing();
            if (GUI.Button(new Rect(x + w - 66, y, 66, 24), Loc.T("Add")) || (GUI.GetNameOfFocusedControl() == "lootAdd" && Event.current.type == EventType.KeyDown && Event.current.keyCode == KeyCode.Return))
                if (a.AddText(text)) text = "";
            y += 30;
            GUI.Label(new Rect(x, y, w, 20), a.SlotsText(), st);
            y += 24;
            float listH = inner.yMax - y - 34;
            scroll = GUI.BeginScrollView(new Rect(x, y, w, listH), scroll, new Rect(0, 0, w - 18, a.Rows.Count * 34 + 2));
            for (int i = 0; i < a.Rows.Count; i++)
            {
                var r = a.Rows[i];
                var rr = new Rect(0, i * 34, w - 18, 32);
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                app.DrawItem(new Rect(rr.x + 2, rr.y, 32, 32), (ushort)r.ClientId, 1);
                GUI.Label(new Rect(rr.x + 40, rr.y + 6, rr.width - 112, 22), r.Name, st);
                if (GUI.Button(new Rect(rr.xMax - 70, rr.y + 4, 66, 24), Loc.T("Remove"))) a.RemoveName(r.Name);
            }
            GUI.EndScrollView();
            if (GUI.Button(new Rect(x, inner.yMax - 28, w, 26), Loc.T("Clear the list"))) a.Clear();
        }
    }

    // ------------------------------------------------------------------------------------------------ pouches
    public sealed class PouchesWindow : SyncedWindow
    {
        public override string Title => Loc.T("Loot Bag");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 190, 70, 380, 430);
        static readonly string[] Labels = { "Items of the Auto Loot list", "Gold", "Unique items", "Gear", "Supplies", "Gems", "Everything else", "Take what a full Orbs or Rift Key pouch passes on" };

        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var p = app.Session?.Utils?.Pouches; show = null; hide = null; if (p == null) return false; show = p.Open; hide = () => p.Visible = false; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.Pouches.Visible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var p = app.Session?.Utils?.Pouches;
            if (p == null) return;
            Styles(app);
            float x = inner.x + 6, y = inner.y + 2, w = inner.width - 12;
            y = Ui.Para(p.StatusText(), small, x, y, w, "#d6c9ae");
            y += 4;
            for (int i = 0; i < PouchesState.Flags.Length; i++)
            {
                string f = PouchesState.Flags[i];
                bool on = p.Flag(f);
                if (Ui.Check(new Rect(x, y, w, 22), on, Loc.T(Labels[i]), st) != on) p.SetFlag(f, !on);
                if (f == "gear")
                {
                    int idx = PouchesState.RarityIndex(p.Rules.MinRarity);
                    GUI.enabled = p.Rules.Gear;
                    if (GUI.Button(new Rect(x + w - 110, y, 108, 22), p.RarityName(idx) + "+")) p.SetMinRarity(PouchesState.RarityIds[(idx + 1) % PouchesState.RarityIds.Length]);
                    GUI.enabled = true;
                }
                y += 26;
            }
            y += 6;
            GUI.Label(new Rect(x, y, w, 20), Loc.T("Saved on your character at once."), small);
            if (GUI.Button(new Rect(x, inner.yMax - 30, w, 26), Loc.T("Auto Seller"))) p.SellerOpen();
        }
    }

    public sealed class AutoSellerWindow : SyncedWindow
    {
        public override string Title => Loc.T("Auto Seller");
        protected override Rect Place(float w, float h) => new Rect(w / 2 - 200, 70, 400, 470);
        string item = "";

        protected override void OnReset() { item = ""; }
        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var p = app.Session?.Utils?.Pouches; show = null; hide = null; if (p == null) return false; show = () => p.SellerOpen(); hide = () => p.SellerVisible = false; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.Pouches.SellerVisible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var p = app.Session?.Utils?.Pouches;
            if (p == null) return;
            Styles(app);
            var s = p.Seller;
            float x = inner.x + 6, y = inner.y + 2, w = inner.width - 12;
            int left = s.CooldownLeft(app.Session.Now);
            GUI.enabled = s.SellEnabled(left);
            if (GUI.Button(new Rect(x, y, w, 28), s.SellText(left))) p.Sell();
            GUI.enabled = true;
            y += 32;
            GUI.Label(new Rect(x, y, w, 20), s.LastSaleText(), small); y += 22;
            GUI.enabled = s.Unlocked;
            GUI.Label(new Rect(x, y, w, 20), Loc.T("Sell these rarities"), st); y += 22;
            for (int i = 0; i < s.Tiers.Count; i++)
            {
                var t = s.Tiers[i];
                var r = new Rect(x + (i % 3) * (w / 3), y + (i / 3) * 24, w / 3, 22);
                var old = GUI.contentColor; GUI.contentColor = Ui.Hex(t.Color);
                bool v = Ui.Check(r, t.On, Loc.T(t.Name), small);
                GUI.contentColor = old;
                if (v != t.On) p.SetTier(t.Key, v);
            }
            y += 52;
            bool corpse = !s.Paused;
            if (Ui.Check(new Rect(x, y, w, 22), corpse, Loc.T("Sell what corpses drop"), st) != corpse) p.SetPaused(corpse);
            y += 26;
            GUI.Label(new Rect(x, y, 100, 22), Loc.T("Sell every"), st);
            var opts = new List<int> { 0 };
            opts.AddRange(s.IntervalChoices);
            if (GUI.Button(new Rect(x + 100, y, 120, 22), s.IntervalLabel(s.Interval))) p.SetEvery(opts[(opts.IndexOf(s.Interval) + 1) % opts.Count]);
            y += 28;
            y = Ui.Para(s.ListText(), small, x, y, w);
            GUI.SetNextControlName("sellItem");
            item = GUI.TextField(new Rect(x, y, w - 190, 22), item, 40);
            if (GUI.GetNameOfFocusedControl() == "sellItem") app.MarkTextEditing();
            if (GUI.Button(new Rect(x + w - 186, y, 60, 22), Loc.T("Add")) && p.ListRequest("add", item)) item = "";
            if (GUI.Button(new Rect(x + w - 122, y, 60, 22), Loc.T("Remove")) && p.ListRequest("remove", item)) item = "";
            if (GUI.Button(new Rect(x + w - 58, y, 58, 22), Loc.T("Clear"))) p.ListRequest("clear", "");
            GUI.enabled = true;
            y += 30;
            string tip = s.Notice.Length > 0 ? s.Notice : s.LockedTip();
            Ui.Para(tip, small, x, y, w, "#e0a050");
        }
    }

    // ------------------------------------------------------------------------------------------------ orb exchange
    public sealed class OrbExchangeWindow : SyncedWindow
    {
        public override string Title => Loc.T("Orb Exchange");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 330), 50, Mathf.Min(660, w - 16), Mathf.Min(560, h - 60));
        readonly OrbForm form = new OrbForm();
        Vector2 scrollBook, scrollMine;
        double nextRefresh;

        protected override void OnReset() { form.Qty = form.Price = ""; }
        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var o = app.Session?.Utils?.Orbs; show = null; hide = null; if (o == null) return false; show = o.Open; hide = () => o.Visible = false; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.Orbs.Visible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var o = app.Session?.Utils?.Orbs;
            if (o == null) return;
            Styles(app);
            float x = inner.x + 4, y = inner.y + 2, w = inner.width - 8;
            if (o.Meta == null) { GUI.Label(new Rect(x, y, w, 22), Loc.T("Waiting for the server..."), st); return; }
            // wallet and the orb strip
            GUI.Label(new Rect(x, y, w, 20), Loc.T("Gold: {0}", OrbExchangeState.Money(o.GoldHeld())) + "   " + Loc.T("Orbs of this kind: {0}", OrbExchangeState.Money(o.Have(o.Base))), small);
            y += 22;
            var keys = o.OrbKeys();
            float bw = Mathf.Min(120, (w - 4) / Mathf.Max(1, keys.Count));
            for (int i = 0; i < keys.Count; i++)
                if (GUI.Toggle(new Rect(x + i * bw, y, bw - 2, 24), o.Base == keys[i], o.ShortName(keys[i]), GUI.skin.button) && o.Base != keys[i]) o.SelectBase(keys[i]);
            y += 28;
            var quotes = o.Quotes(o.Base);
            GUI.Label(new Rect(x, y, 60, 22), Loc.T("Priced in"), small);
            if (GUI.Button(new Rect(x + 64, y, 140, 22), o.AssetName(o.Quote))) o.SelectQuote(quotes[(Mathf.Max(0, quotes.IndexOf(o.Quote)) + 1) % quotes.Count]);
            if (GUI.Toggle(new Rect(w - 160, y, 78, 22), o.Tab == 0, Loc.T("Book"), GUI.skin.button) && o.Tab != 0) { o.Tab = 0; o.RequestBook(); }
            if (GUI.Toggle(new Rect(w - 78, y, 82, 22), o.Tab == 1, Loc.T("My orders"), GUI.skin.button) && o.Tab != 1) { o.Tab = 1; o.RequestMine(); }
            y += 28;
            if (o.Status.Length > 0) { Ui.Text(new Rect(x, y, w, 20), o.Status, small, o.StatusGood ? "#6cc46c" : "#e05a4a"); }
            y += 20;
            if (o.Tab == 0) Book(app, o, new Rect(x, y, w, inner.yMax - y));
            else Mine(app, o, new Rect(x, y, w, inner.yMax - y));
            if (o.Tab == 0 && Time.realtimeSinceStartupAsDouble > nextRefresh) { nextRefresh = Time.realtimeSinceStartupAsDouble + OrbExchangeState.RefreshSeconds; o.RequestBook(); }
        }

        void PriceChartBox(OrbExchangeState o, Rect r)
        {
            int hours = Json.Int(o.Book, "hours", 24);
            var pts = PriceChart.Points(Json.Get(o.Book, "points"));
            GUI.Label(new Rect(r.x, r.y, r.width, 16), Loc.T("Average price per hour, last {0} hours", hours), small);
            var box = new Rect(r.x, r.y + 18, r.width, r.height - 18);
            ChaosApp.Fill(box, new Color(0.08f, 0.07f, 0.09f, 1f));
            var rects = PriceChart.Rects(pts, hours, (int)box.width - 4, (int)box.height - 4);
            if (rects.Count == 0) { GUI.Label(box, Loc.T("No trades yet"), small); return; }
            foreach (var cr in rects)
                ChaosApp.Fill(new Rect(box.x + 2 + cr.X, box.y + 2 + cr.Y, cr.W, cr.H), cr.Line ? new Color(0.91f, 0.72f, 0.29f, 1f) : new Color(0.23f, 0.2f, 0.22f, 1f));
            if (Json.Get(o.Book, "high") is double hi && Json.Get(o.Book, "low") is double lo)
                GUI.Label(new Rect(box.x + 4, box.y + 1, box.width - 8, 16), Loc.T("High {0}  Low {1}", OrbExchangeState.PriceText(hi), OrbExchangeState.PriceText(lo)), small);
        }

        void Book(ChaosApp app, OrbExchangeState o, Rect b)
        {
            float lw = b.width * 0.5f;
            var rows = OrbExchangeState.BookRows(o.Book);
            if (o.Book != null)
            {
                string ch = OrbExchangeState.ChangeText(Json.Get(o.Book, "change"), out string col);
                Ui.Text(new Rect(b.x, b.y, lw, 20), Loc.T("Last") + " " + (Json.Get(o.Book, "last") is double l ? OrbExchangeState.PriceText(l) : "-") + "   " + ch, small, col);
            }
            float y = b.y + 22;
            // the price chart of the book (game_orbexchange statsFrame): the average price per hour and the volume, at the bottom of the left column
            float chartH = o.Book != null && b.height > 260 ? 104f : 0f;
            if (chartH > 0) PriceChartBox(o, new Rect(b.x, b.yMax - chartH, lw - 4, chartH));
            scrollBook = GUI.BeginScrollView(new Rect(b.x, y, lw, b.yMax - y - (chartH > 0 ? chartH + 4 : 0)), scrollBook, new Rect(0, 0, lw - 18, rows.Count * 22 + 2));
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                var rr = new Rect(0, i * 22, lw - 18, 20);
                if (r.Kind == "spread") { GUI.Label(rr, r.Price + "  " + r.Qty, small); continue; }
                ChaosApp.Fill(new Rect(rr.x, rr.y, rr.width * (float)r.Bar, rr.height), r.Kind == "ask" ? new Color(0.88f, 0.35f, 0.29f, 0.25f) : new Color(0.42f, 0.77f, 0.42f, 0.25f));
                if (Ui.Row(rr, false) && OrbExchangeState.FromRow(r, out var f)) { form.Side = f.Side; form.Price = f.Price; form.Qty = f.Qty; }
                var old = GUI.contentColor; GUI.contentColor = Ui.Hex(r.Kind == "ask" ? "#e05a4a" : "#6cc46c");
                GUI.Label(new Rect(rr.x + 2, rr.y, 90, 20), r.Price, small);
                GUI.contentColor = old;
                GUI.Label(new Rect(rr.x + 94, rr.y, 80, 20), r.Qty, small);
                GUI.Label(new Rect(rr.x + 176, rr.y, rr.width - 176, 20), r.Total, small);
            }
            GUI.EndScrollView();
            // order form
            float fx = b.x + lw + 8, fw = b.width - lw - 8, fy = b.y;
            if (GUI.Toggle(new Rect(fx, fy, fw / 2 - 2, 24), form.Side == "buy", Loc.T("Buy"), GUI.skin.button)) form.Side = "buy";
            if (GUI.Toggle(new Rect(fx + fw / 2 + 2, fy, fw / 2 - 2, 24), form.Side == "sell", Loc.T("Sell"), GUI.skin.button)) form.Side = "sell";
            fy += 30;
            GUI.Label(new Rect(fx, fy, 70, 22), Loc.T("Amount"), small);
            GUI.SetNextControlName("orbQty");
            form.Qty = GUI.TextField(new Rect(fx + 72, fy, fw - 72, 22), form.Qty, 14);
            fy += 26;
            GUI.Label(new Rect(fx, fy, 70, 22), Loc.T("Price"), small);
            GUI.SetNextControlName("orbPrice");
            form.Price = GUI.TextField(new Rect(fx + 72, fy, fw - 72, 22), form.Price, 14);
            string foc = GUI.GetNameOfFocusedControl();
            if (foc == "orbQty" || foc == "orbPrice") app.MarkTextEditing();
            fy += 26;
            var days = Json.List(o.Meta, "durations");
            if (days.Count > 0)
            {
                if (form.Days == 0) form.Days = Json.Int(o.Meta, "defaultDuration", 7);
                GUI.Label(new Rect(fx, fy, 70, 22), Loc.T("Days"), small);
                if (GUI.Button(new Rect(fx + 72, fy, 60, 22), form.Days.ToString()))
                {
                    int idx = 0; for (int i = 0; i < days.Count; i++) if (days[i] is double d && (int)d == form.Days) idx = i;
                    form.Days = days[(idx + 1) % days.Count] is double nd ? (int)nd : 7;
                }
                fy += 26;
            }
            bool ok = o.Form(form, o.Base, o.Quote, out var req, out string why, out double total, out double fee, out double placeFee, out _);
            double qty = OrbExchangeState.ParseAmount(form.Qty);
            string pre = ok ? o.PreviewText(req, form.Side, o.Base, o.Quote, total, qty, fee, placeFee) : (form.Qty.Length + form.Price.Length > 0 ? why : "");
            fy = Ui.Para(pre, small, fx, fy, fw, ok ? null : "#e0a050");
            GUI.enabled = ok;
            if (GUI.Button(new Rect(fx, fy + 2, fw, 28), form.Side == "buy" ? Loc.T("Place buy order") : Loc.T("Place sell order"))) o.Place(req);
            GUI.enabled = true;
        }

        void Mine(ChaosApp app, OrbExchangeState o, Rect b)
        {
            var open = Json.List(o.Mine, "open");
            var fills = Json.List(o.Mine, "fills");
            float total = 24 + open.Count * 54 + 30 + fills.Count * 20 + 10;
            scrollMine = GUI.BeginScrollView(b, scrollMine, new Rect(0, 0, b.width - 18, total));
            float y = 0;
            GUI.Label(new Rect(0, y, b.width, 20), Loc.T("Open orders") + " (" + open.Count + ")", st); y += 22;
            foreach (object ord in open)
            {
                var rr = new Rect(0, y, b.width - 18, 50);
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                GUI.Label(new Rect(rr.x + 4, rr.y + 2, rr.width - 90, 20), o.OrderTitle(ord), small);
                GUI.Label(new Rect(rr.x + 4, rr.y + 20, rr.width - 90, 18), o.OrderSub(ord), small);
                ChaosApp.Fill(new Rect(rr.x + 4, rr.y + 40, (rr.width - 98) * (float)OrbExchangeState.Progress(ord), 6), Ui.Hex("#6cc46c"));
                GUI.enabled = Json.Text(ord, "state") == "active";
                if (GUI.Button(new Rect(rr.xMax - 80, rr.y + 12, 76, 24), Loc.T("Cancel"))) o.Cancel(Json.Int(ord, "id"));
                GUI.enabled = true;
                y += 54;
            }
            if (open.Count == 0) { GUI.Label(new Rect(0, y, b.width, 20), Loc.T("No open orders."), small); y += 22; }
            y += 8;
            GUI.Label(new Rect(0, y, b.width, 20), Loc.T("Recent fills"), st); y += 22;
            foreach (object f in fills) { Ui.Text(new Rect(4, y, b.width - 22, 18), o.FillText(f), small, Json.Text(f, "role") == "maker" ? "#d6c9ae" : "#f6cf72"); y += 20; }
            if (fills.Count == 0) GUI.Label(new Rect(0, y, b.width, 20), Loc.T("No fills yet."), small);
            GUI.EndScrollView();
        }
    }

    // ------------------------------------------------------------------------------------------------ gambler
    public sealed class GambleWindow : SyncedWindow
    {
        public override string Title => Loc.T("The Gambler");
        public override string TravelKey => "gambler";
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 300), 60, Mathf.Min(600, w - 16), Mathf.Min(480, h - 70));
        Vector2 scroll;

        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var g = app.Session?.Utils?.Gamble; show = null; hide = null; if (g == null) return false; show = g.Open; hide = g.Hide; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.Gamble.Visible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var g = app.Session?.Utils?.Gamble;
            if (g == null) return;
            Styles(app);
            float x = inner.x + 4, y = inner.y + 2, w = inner.width - 8;
            if (g.State == null) { GUI.Label(new Rect(x, y, w, 22), Loc.T("Waiting for the server..."), st); return; }
            y = Ui.Para(g.Header(), small, x, y, w);
            string near = g.NearText(out string nc);
            y = Ui.Para(near, small, x, y, w, nc);
            GUI.Label(new Rect(x, y, w, 20), g.RefreshText((g.Clock() - g.ReceivedAt) / 1000), small); y += 22;
            var cells = g.Cells();
            const float cw = 92, ch = 112;
            int per = Mathf.Max(1, (int)((w - 18) / (cw + 4)));
            float gridH = inner.yMax - y - 120;
            scroll = GUI.BeginScrollView(new Rect(x, y, w, gridH), scroll, new Rect(0, 0, w - 18, ((cells.Count + per - 1) / per) * (ch + 4)));
            for (int i = 0; i < cells.Count; i++)
            {
                var c = cells[i];
                var r = new Rect((i % per) * (cw + 4), (i / per) * (ch + 4), cw, ch);
                ChaosApp.Fill(r, new Color(0.11f, 0.09f, 0.12f, c.Sold ? 0.4f : 1f));
                if (c.ClientId > 0) app.DrawItem(new Rect(r.x + 30, r.y + 4, 32, 32), (ushort)c.ClientId, 1);
                GUI.Label(new Rect(r.x + 2, r.y + 38, r.width - 4, 16), c.SlotText, small);
                GUI.Label(new Rect(r.x + 2, r.y + 52, r.width - 4, 16), c.LevelText, small);
                Ui.Text(new Rect(r.x + 2, r.y + 66, r.width - 4, 16), c.PriceText, small, c.PriceColor);
                GUI.enabled = c.CanBuy && !g.Buying;
                if (GUI.Button(new Rect(r.x + 4, r.y + 86, r.width - 8, 22), c.BuyText)) g.Buy(c);
                GUI.enabled = true;
                if (r.Contains(Event.current.mousePosition)) app.SetTip(c.Tip);
            }
            GUI.EndScrollView();
            y += gridH + 4;
            string rt = g.RerollText(out bool ok, out string tip);
            GUI.enabled = ok;
            if (GUI.Button(new Rect(x, y, 170, 26), new GUIContent(rt, tip))) g.Reroll();
            GUI.enabled = true;
            if (GUI.Button(new Rect(x + 176, y, 90, 26), Loc.T("Refresh"))) g.Refresh();
            y += 30;
            if (g.Status.Length > 0) y = Ui.Para(g.Status, small, x, y, w, g.StatusColor);
            Ui.Para(g.OddsText(), small, x, y, w, "#8c8070");
        }
    }

    // ------------------------------------------------------------------------------------------------ ember cache
    public sealed class EmberCacheWindow : SyncedWindow
    {
        public override string Title => Loc.T("Ember Cache");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 280), 60, Mathf.Min(560, w - 16), Mathf.Min(540, h - 70));
        Vector2 scroll;

        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var e = app.Session?.Utils?.Ember; show = null; hide = null; if (e == null) return false; show = e.Open; hide = e.Hide; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.Ember.Visible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var e = app.Session?.Utils?.Ember;
            if (e == null) return;
            Styles(app);
            float x = inner.x + 6, w = inner.width - 12;
            if (e.State == null) { GUI.Label(new Rect(x, inner.y + 2, w, 22), Loc.T("Waiting for the server..."), st); return; }
            float footer = e.QuoteVisible ? 100 : 36;
            var view = new Rect(inner.x, inner.y, inner.width, inner.height - footer);
            scroll = GUI.BeginScrollView(view, scroll, new Rect(0, 0, inner.width - 18, 760));
            float y = 2, cw = inner.width - 30;
            GUI.Label(new Rect(6, y, cw, 22), e.WeekLine(), st); y += 22;
            GUI.Label(new Rect(6, y, cw, 20), e.WeekEndsLine(), small); y += 22;
            foreach (var t in e.Tiers())
            {
                var rr = new Rect(6, y, cw, 44);
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                Ui.Text(new Rect(rr.x + 4, rr.y + 2, rr.width - 100, 20), t.Title, st, t.Reached ? "#7ccf5c" : "#c8b89a");
                Ui.Text(new Rect(rr.xMax - 96, rr.y + 2, 92, 20), t.Status, small, t.Reached ? "#7ccf5c" : "#c8b89a");
                GUI.Label(new Rect(rr.x + 4, rr.y + 22, rr.width - 8, 20), t.Reward, small);
                y += 48;
            }
            GUI.Label(new Rect(6, y, cw, 20), e.SparksLine(), small); y += 24;
            GUI.Label(new Rect(6, y, cw, 22), e.TodayLine(), st); y += 22;
            string spark = e.SparkLine(out bool lit);
            Ui.Text(new Rect(6, y, cw, 20), spark, small, lit ? "#7ccf5c" : "#c8b89a"); y += 20;
            GUI.Label(new Rect(6, y, cw, 20), e.SparkReward(), small); y += 20;
            GUI.Label(new Rect(6, y, cw, 20), e.BonusLine(), small); y += 28;
            GUI.Label(new Rect(6, y, cw, 22), Loc.T("Today's book"), st); y += 22;
            foreach (var r in e.BookRows()) { GUI.Label(new Rect(10, y, cw * 0.6f, 20), r[0], small); GUI.Label(new Rect(cw * 0.6f, y, cw * 0.4f, 20), r[1], small); y += 20; }
            y += 8;
            GUI.Label(new Rect(6, y, cw, 22), Loc.T("How to earn points"), st); y += 22;
            foreach (var r in EmberCacheState.SourceRows(Json.Get(e.State, "src")))
            {
                GUI.Label(new Rect(10, y, cw * 0.55f, 20), r[0], small); GUI.Label(new Rect(cw * 0.55f, y, cw * 0.2f, 20), r[1], small); GUI.Label(new Rect(cw * 0.75f, y, cw * 0.25f, 20), r[2], small);
                y += 20;
            }
            GUI.EndScrollView();
            float by = inner.yMax - footer + 4;
            if (e.QuoteVisible)
            {
                string text = EmberCacheState.OfferText(e.Quote, out bool can);
                Ui.Para(text, small, x, by, w);
                GUI.enabled = can;
                if (GUI.Button(new Rect(x, inner.yMax - 30, 90, 26), Loc.T("Yes"))) e.Offer();
                GUI.enabled = true;
                if (GUI.Button(new Rect(x + 96, inner.yMax - 30, 90, 26), Loc.T("No"))) e.QuoteVisible = false;
            }
            else if (GUI.Button(new Rect(x, by, w, 26), Loc.T("Offer junk orbs"))) e.AskOffer();
        }
    }

    // ------------------------------------------------------------------------------------------------ unveil
    public sealed class UnveilWindow : SyncedWindow
    {
        public override string Title => Loc.T("Unveil");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 270), 100, Mathf.Min(540, w - 16), 340);

        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var u = app.Session?.Utils?.Unveil; show = null; hide = null; if (u == null) return false; show = () => u.Visible = true; hide = u.Hide; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.Unveil.Visible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var u = app.Session?.Utils?.Unveil;
            if (u == null) return;
            Styles(app);
            float x = inner.x + 6, y = inner.y + 2, w = inner.width - 12;
            if (u.Data == null) { GUI.Label(new Rect(x, y, w, 22), Loc.T("Use an Orb of Unveiling on a veiled item."), st); return; }
            GUI.Label(new Rect(x, y, w, 22), u.HeaderText(), st); y += 22;
            GUI.Label(new Rect(x, y, w, 20), u.OrbsText(), small); y += 24;
            var cards = u.Cards();
            float cw = (w - 8) / 3;
            for (int i = 0; i < cards.Count; i++)
            {
                var c = cards[i];
                var r = new Rect(x + i * (cw + 4), y, cw, 170);
                if (Ui.Row(r, u.Selected == c.I) && !u.Done) u.Selected = c.I;
                Ui.Text(new Rect(r.x + 4, r.y + 2, r.width - 8, 20), c.Name, st, "#d9c8ff");
                Ui.Text(new Rect(r.x + 4, r.y + 22, r.width - 8, 18), c.TierText, small, c.TierColor);
                float cy = r.y + 42;
                cy = Ui.Para(c.Text, small, r.x + 4, cy, r.width - 8, "#d6c9ae");
                if (c.RangeText.Length > 0) { Ui.Text(new Rect(r.x + 4, cy, r.width - 8, 18), c.RangeText, small, "#8c8070"); cy += 18; }
                if (c.HookText.Length > 0) Ui.Text(new Rect(r.x + 4, cy, r.width - 8, 18), c.HookText, small, "#ff9a3c");
            }
            y += 176;
            y = Ui.Para(u.Result.Length > 0 ? u.Result : u.StatusText(), small, x, y, w, u.Result.Length > 0 ? u.ResultColor : "#d6c9ae");
            GUI.enabled = u.CanConfirm(u.Selected) && !u.Done;
            if (GUI.Button(new Rect(x, inner.yMax - 32, w * 0.5f - 3, 28), Loc.T("Unveil"))) u.Confirm();
            GUI.enabled = true;
            if (GUI.Button(new Rect(x + w * 0.5f + 3, inner.yMax - 32, w * 0.5f - 3, 28), Loc.T("Close"))) u.Hide();
        }
    }

    // ------------------------------------------------------------------------------------------------ item finder
    public sealed class ItemFinderWindow : SyncedWindow
    {
        public override string Title => Loc.T("Item Finder");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 320), 50, Mathf.Min(640, w - 16), Mathf.Min(560, h - 60));
        string query = "";
        Vector2 scroll;

        protected override void OnReset() { query = ""; }
        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var f = app.Session?.Utils?.Finder; show = null; hide = null; if (f == null) return false; show = f.Open; hide = () => f.Visible = false; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.Finder.Visible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var f = app.Session?.Utils?.Finder;
            if (f == null) return;
            Styles(app);
            float x = inner.x + 4, y = inner.y + 2, w = inner.width - 8;
            GUI.enabled = f.Item != null;
            if (GUI.Button(new Rect(x, y, 60, 24), Loc.T("Back"))) f.Back();
            GUI.enabled = true;
            GUI.SetNextControlName("finderQuery");
            string nq = GUI.TextField(new Rect(x + 66, y, w - 66, 24), query, ItemFinderState.MaxQuery);
            if (GUI.GetNameOfFocusedControl() == "finderQuery") app.MarkTextEditing();
            if (nq != query) { query = nq; f.TypeAhead(query); f.Item = null; }
            y += 30;
            if (f.Status.Length > 0) y = Ui.Para(f.Status, small, x, y, w, "#e0a050");
            var area = new Rect(x, y, w, inner.yMax - y);
            if (f.Item != null) ItemView(app, f, area);
            else if (f.Results != null) Results(app, f, area);
            else GUI.Label(area, Loc.T("Type at least two letters of an item name."), small);
        }

        void Results(ChaosApp app, ItemFinderState f, Rect a)
        {
            var r = f.Results;
            scroll = GUI.BeginScrollView(a, scroll, new Rect(0, 0, a.width - 18, r.Rows.Count * 40 + 40));
            for (int i = 0; i < r.Rows.Count; i++)
            {
                var h = r.Rows[i];
                var rr = new Rect(0, i * 40, a.width - 18, 38);
                if (Ui.Row(rr, false)) { f.ShowItem(h.Id, h.Cid); scroll = Vector2.zero; }
                if (h.Cid > 0) app.DrawItem(new Rect(rr.x + 3, rr.y + 3, 32, 32), (ushort)h.Cid, 1);
                GUI.Label(new Rect(rr.x + 40, rr.y + 2, rr.width - 44, 18), h.Name, st);
                GUI.Label(new Rect(rr.x + 40, rr.y + 19, rr.width - 44, 16), ItemFinderState.KindsText(h.Kinds), small);
            }
            float py = r.Rows.Count * 40 + 4;
            if (r.Pages > 1)
            {
                GUI.enabled = r.P > 1; if (GUI.Button(new Rect(0, py, 40, 24), "<")) f.Search(r.Q, r.P - 1);
                GUI.enabled = r.P < r.Pages; if (GUI.Button(new Rect(44, py, 40, 24), ">")) f.Search(r.Q, r.P + 1);
                GUI.enabled = true;
                GUI.Label(new Rect(90, py + 2, 100, 22), ItemFinderState.PageText(r.P, r.Pages), small);
            }
            GUI.EndScrollView();
        }

        void ItemView(ChaosApp app, ItemFinderState f, Rect a)
        {
            var it = f.Item;
            float total = 40;
            foreach (var s in it.Secs) total += 24 + s.Rows.Count * 38 + 30;
            scroll = GUI.BeginScrollView(a, scroll, new Rect(0, 0, a.width - 18, total + 40));
            float y = 0, w = a.width - 22;
            if (it.Cid > 0) app.DrawItem(new Rect(0, y, 32, 32), (ushort)it.Cid, 1);
            GUI.Label(new Rect(40, y, w - 40, 20), WorldText.Cap(it.Name), st);
            GUI.Label(new Rect(40, y + 18, w - 40, 18), it.None ? Loc.T("No known source.") : ItemFinderState.TotalText(it.Total), small);
            // the item's Codex page when the Codex has one (game_itemfinder codexButton)
            string codexId = it.None ? null : CodexLinks.ForItem(InfoStore.Codex, it.Id);
            if (codexId != null && GUI.Button(new Rect(w - 88, y, 88, 24), new GUIContent(Loc.T("Codex"), Loc.T("Open its page in the Codex.")))) app.OpenCodex(codexId);
            y += 42;
            foreach (var s in it.Secs)
            {
                GUI.Label(new Rect(0, y, w, 20), ItemFinderState.SectionHead(s), st); y += 22;
                foreach (var r in s.Rows)
                {
                    ItemFinderState.RowTexts(r, out string main, out string desc, out string value);
                    var rr = new Rect(0, y, w, 36);
                    if (Ui.Row(rr, false) && r.I > 0) { f.ShowItem(r.I, 0); scroll = Vector2.zero; GUI.EndScrollView(); return; }
                    GUI.Label(new Rect(rr.x + 4, rr.y + 1, rr.width * 0.6f, 18), main, small);
                    GUI.Label(new Rect(rr.x + rr.width * 0.6f, rr.y + 1, rr.width * 0.4f - 4, 18), value, small);
                    string line = desc;
                    if (r.Materials.Count > 0)
                    {
                        var mats = new List<string>();
                        foreach (var m in r.Materials) mats.Add(ItemFinderState.MaterialText(m));
                        line = (line.Length > 0 ? line + "  " : "") + string.Join(", ", mats);
                    }
                    GUI.Label(new Rect(rr.x + 4, rr.y + 17, rr.width - 8, 18), line, small);
                    y += 38;
                }
                if (s.Pages > 1)
                {
                    GUI.enabled = s.P > 1; if (GUI.Button(new Rect(0, y, 40, 22), "<")) f.Page(s.K, s.P - 1);
                    GUI.enabled = s.P < s.Pages; if (GUI.Button(new Rect(44, y, 40, 22), ">")) f.Page(s.K, s.P + 1);
                    GUI.enabled = true;
                    GUI.Label(new Rect(90, y, 100, 22), ItemFinderState.PageText(s.P, s.Pages), small);
                    y += 26;
                }
                y += 4;
            }
            GUI.EndScrollView();
        }
    }

    // ------------------------------------------------------------------------------------------------ loadouts
    public sealed class LoadoutsWindow : SyncedWindow
    {
        public override string Title => Loc.T("Loadouts");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 300), 60, Mathf.Min(600, w - 16), Mathf.Min(500, h - 70));
        string nameEdit = "";
        int nameFor = -1;
        Vector2 scrollList, scrollDetail;

        GameSession wiredFor;
        HotbarProfiles profiles;

        protected override void OnReset() { nameEdit = ""; nameFor = -1; wiredFor = null; }

        // the action bar profile of a slot: saving a loadout keeps the hotkey bar, loading it puts the bar back (game_loadouts)
        public override void Tick(ChaosApp app)
        {
            base.Tick(app);
            var s = app.Session;
            var l = s?.Utils?.Loadouts;
            if (l == null || wiredFor == s) return;
            wiredFor = s;
            profiles = new HotbarProfiles(k => { try { return PlayerPrefs.GetString(k, ""); } catch { return ""; } }, (k, v) => { try { PlayerPrefs.SetString(k, v); PlayerPrefs.Save(); } catch { } });
            l.ProfileSaved = slot =>
            {
                var bar = app.FindWindow<HotkeyBarWindow>();
                string who = app.World?.Player?.Name;
                if (bar != null && who != null) profiles.Remember(who, slot, bar.SnapshotBar());
            };
            l.ProfileLoaded = slot =>
            {
                var bar = app.FindWindow<HotkeyBarWindow>();
                string who = app.World?.Player?.Name;
                var saved = who != null ? profiles.Recall(who, slot, 12) : null;
                if (bar != null && saved != null) bar.ApplyBar(saved);
            };
        }

        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var l = app.Session?.Utils?.Loadouts; show = null; hide = null; if (l == null) return false; show = l.Open; hide = () => l.Visible = false; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.Loadouts.Visible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var l = app.Session?.Utils?.Loadouts;
            if (l == null) return;
            Styles(app);
            if (l.State == null) { GUI.Label(new Rect(inner.x + 6, inner.y + 2, inner.width, 22), Loc.T("Waiting for the server..."), st); return; }
            double now = l.Clock();
            float lw = inner.width * 0.42f;
            var slots = Json.List(l.State, "slots");
            scrollList = GUI.BeginScrollView(new Rect(inner.x, inner.y, lw, inner.height - 4), scrollList, new Rect(0, 0, lw - 18, slots.Count * 46 + 2));
            for (int i = 0; i < slots.Count; i++)
            {
                var row = l.SlotRow(slots[i]);
                int n = Json.Int(slots[i], "slot");
                var rr = new Rect(0, i * 46, lw - 18, 44);
                if (Ui.Row(rr, n == l.Selected)) l.Select(n);
                var old = GUI.contentColor; GUI.contentColor = row.Dim ? Ui.Hex("#8c8070") : Ui.Hex(LoadoutsState.Gold);
                GUI.Label(new Rect(rr.x + 6, rr.y + 2, rr.width - 70, 20), row.Title, st);
                GUI.contentColor = old;
                GUI.Label(new Rect(rr.x + 6, rr.y + 22, rr.width - 12, 18), row.Sub, small);
                Ui.Text(new Rect(rr.xMax - 64, rr.y + 2, 62, 18), row.Tag, small, row.TagColor);
            }
            GUI.EndScrollView();
            float x = inner.x + lw + 6, w = inner.width - lw - 8, y = inner.y;
            var slot = l.SlotOf(l.Selected);
            if (nameFor != l.Selected) { nameFor = l.Selected; nameEdit = slot != null && !Json.Bool(slot, "empty") ? Json.Text(slot, "name") : ""; }
            GUI.Label(new Rect(x, y, w, 22), l.SlotRow(slot).Title, st); y += 24;
            string hint = l.SwitchHint(now, out string hc);
            y = Ui.Para(hint, small, x, y, w, hc);
            float sh = inner.yMax - y - 100;
            string who = app.World?.Player?.Name;
            var lines = l.Summary(slot, profiles != null && who != null && slot != null && !Json.Bool(slot, "empty") ? profiles.ProfileOf(who, Json.Int(slot, "slot")) : "");
            float th = 0; foreach (var ln in lines) th += Ui.Height(ln.Text, small, w - 20) + 2;
            scrollDetail = GUI.BeginScrollView(new Rect(x, y, w, sh), scrollDetail, new Rect(0, 0, w - 18, th + 4));
            float cy = 0;
            foreach (var ln in lines) cy = Ui.Para(ln.Text, small, 0, cy, w - 20, ln.Color);
            GUI.EndScrollView();
            y += sh + 4;
            GUI.SetNextControlName("loadoutName");
            nameEdit = GUI.TextField(new Rect(x, y, w - 90, 22), nameEdit, 24);
            if (GUI.GetNameOfFocusedControl() == "loadoutName") app.MarkTextEditing();
            if (GUI.Button(new Rect(x + w - 86, y, 86, 22), l.IconChoice)) l.CycleIcon();
            y += 26;
            var b = l.Buttons(slot, now);
            float bw = (w - 9) / 4;
            GUI.enabled = b.Save; if (GUI.Button(new Rect(x, y, bw, 26), b.SaveText.Length > 0 ? b.SaveText : Loc.T("Save"))) l.Save(nameEdit);
            GUI.enabled = b.Load; if (GUI.Button(new Rect(x + bw + 3, y, bw, 26), Loc.T("Load"))) l.Load();
            GUI.enabled = b.Rename; if (GUI.Button(new Rect(x + 2 * (bw + 3), y, bw, 26), Loc.T("Rename"))) l.Rename(nameEdit);
            GUI.enabled = b.Delete; if (GUI.Button(new Rect(x + 3 * (bw + 3), y, bw, 26), l.ConfirmDelete == l.Selected ? Loc.T("Confirm") : Loc.T("Delete"))) l.Delete();
            GUI.enabled = true;
            y += 30;
            if (l.Status.Length > 0) Ui.Para(l.Status, small, x, y, w, l.StatusColor);
        }
    }

    // ------------------------------------------------------------------------------------------------ spell supports
    public sealed class SpellSupportsWindow : SyncedWindow
    {
        public override string Title => Loc.T("Spell Supports");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 340), 50, Mathf.Min(680, w - 16), Mathf.Min(560, h - 60));
        Vector2 scrollSpells, scrollDetail, scrollRunes;
        double dragRune = -1;   // a rune picked up from the list, dropped on a free socket
        readonly System.Collections.Generic.List<SocketTarget> sockets = new System.Collections.Generic.List<SocketTarget>();

        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var s = app.Session?.Utils?.Supports; show = null; hide = null; if (s == null) return false; show = s.Open; hide = () => s.Visible = false; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.Supports.Visible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var s = app.Session?.Utils?.Supports;
            if (s == null) return;
            Styles(app);
            if (s.State == null) { GUI.Label(new Rect(inner.x + 6, inner.y + 2, inner.width, 22), Loc.T("Waiting for the server..."), st); return; }
            double now = app.Session.Now;
            float lw = inner.width * 0.34f, x = inner.x, y = inner.y;
            var spells = s.Spells();
            float listH = inner.height - 4;
            scrollSpells = GUI.BeginScrollView(new Rect(x, y, lw, listH), scrollSpells, new Rect(0, 0, lw - 18, spells.Count * 44 + 2));
            for (int i = 0; i < spells.Count; i++)
            {
                var sp = spells[i];
                var rr = new Rect(0, i * 44, lw - 18, 42);
                if (Ui.Row(rr, Json.Number(sp, "id") == s.SelectedSpell)) s.SelectedSpell = Json.Number(sp, "id");
                var old = GUI.contentColor; GUI.contentColor = Json.Int(s.State, "level") < Json.Int(sp, "level") ? Ui.Hex("#6b6258") : Color.white;
                GUI.Label(new Rect(rr.x + 6, rr.y + 2, rr.width - 8, 20), Json.Text(sp, "name"), st);
                GUI.contentColor = old;
                GUI.Label(new Rect(rr.x + 6, rr.y + 22, rr.width - 60, 18), SpellSupportsState.KindLine(sp), small);
                int count = Json.Int(sp, "count"), max = Json.Get(sp, "max") is double m ? (int)m : 3;
                for (int k = 1; k <= max; k++)
                {
                    var rune = SpellSupportsState.RuneAt(sp, k);
                    var c = rune != null ? Ui.Hex(Json.Text(rune, "color", "#d6c9ae")) : k <= count ? new Color(0.29f, 0.24f, 0.26f) : new Color(0.08f, 0.06f, 0.07f);
                    ChaosApp.Fill(new Rect(rr.xMax - 12 - (max - k) * 12, rr.y + 26, 9, 9), c);
                }
            }
            GUI.EndScrollView();
            float dx = x + lw + 6, dw = inner.width - lw - 8;
            float runesH = Mathf.Min(150, inner.height * 0.3f);
            var spell = s.SpellById(s.SelectedSpell);
            var detail = new Rect(dx, y, dw, inner.height - runesH - 10);
            scrollDetail = GUI.BeginScrollView(detail, scrollDetail, new Rect(0, 0, dw - 18, 420));
            sockets.Clear();
            float cy = 0;
            if (spell == null) GUI.Label(new Rect(0, 0, dw, 22), Loc.T("Pick a spell on the left."), small);
            else
            {
                GUI.Label(new Rect(0, cy, dw - 20, 22), Json.Text(spell, "name") + "  (" + Json.Text(spell, "words") + ")", st); cy += 24;
                cy = Ui.Para(s.InfoLine(spell), small, 0, cy, dw - 20);
                int spellId = Json.Int(spell, "id");
                int max = Json.Get(spell, "max") is double mm ? (int)mm : 3;
                for (int slot = 1; slot <= max; slot++)
                {
                    var v = s.Socket(spell, slot, now);
                    var rr = new Rect(0, cy, dw - 20, 66);
                    // a free socket takes a rune dragged from the list or an item dragged from a bag (window coordinates)
                    sockets.Add(new SocketTarget { X = detail.x + rr.x - scrollDetail.x, Y = detail.y + rr.y - scrollDetail.y, W = rr.width, H = rr.height, Spell = spellId, Slot = slot, Free = v.Open && !v.HasRune });
                    ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                    Ui.Text(new Rect(rr.x + 6, rr.y + 2, rr.width - 140, 18), v.Name, st, v.HasRune ? Json.Text(v.Rune, "color", "#d6c9ae") : "#d6c9ae");
                    GUI.Label(new Rect(rr.x + 6, rr.y + 20, rr.width - 140, 44), v.Text, Ui.Wrap(app, 11));
                    if (v.Button1.Length > 0)
                    {
                        GUI.enabled = v.Button1On;
                        if (GUI.Button(new Rect(rr.xMax - 130, rr.y + 4, 126, 24), v.Button1))
                        {
                            if (v.HasRune) s.Remove(spellId, slot, true);
                            else if (!v.Open) s.Unlock(spellId);
                            else if (s.SelectedRune >= 0) s.SocketRune(spellId, slot, (int)s.SelectedRune);
                        }
                        GUI.enabled = true;
                    }
                    if (v.Button2.Length > 0 && GUI.Button(new Rect(rr.xMax - 130, rr.y + 34, 126, 24), v.Button2)) s.Shatter(spellId, slot, now);
                    cy += 70;
                }
            }
            GUI.EndScrollView();
            // runes
            float ry = detail.yMax + 4;
            GUI.Label(new Rect(dx, ry, dw, 20), Loc.T("Support runes you carry"), st);
            var runes = s.Runes();
            var rview = new Rect(dx, ry + 22, dw, runesH - 52);
            int per = Mathf.Max(1, (int)((dw - 18) / 40));
            scrollRunes = GUI.BeginScrollView(rview, scrollRunes, new Rect(0, 0, dw - 18, ((runes.Count + per - 1) / per) * 40 + 2));
            for (int i = 0; i < runes.Count; i++)
            {
                var r = runes[i];
                var rr = new Rect((i % per) * 40, (i / per) * 40, 36, 36);
                ChaosApp.Fill(rr, new Color(0.11f, 0.09f, 0.12f, 1f));
                Ui.Frame(rr, Json.Number(r, "id") == s.SelectedRune ? Ui.Hex("#e8b84a") : Ui.Hex(Json.Text(r, "color", "#6b6258")));
                int cid = Json.Int(s.State, "orbClientId");
                GUI.Label(new Rect(rr.x + 2, rr.y + 2, 32, 32), Json.Text(r, "name").Length > 0 ? Json.Text(r, "name").Substring(0, 1) : "?", st);
                if (Json.Int(r, "count") > 1) GUI.Label(new Rect(rr.x + 20, rr.y + 20, 16, 16), Json.Int(r, "count").ToString(), small);
                if (Ui.Row(rr, false)) s.SelectedRune = Json.Number(r, "id");
                if (rr.Contains(Event.current.mousePosition))
                {
                    app.SetTip(SpellSupportsState.RuneTip(r));
                    if (Event.current.type == EventType.MouseDrag && Event.current.button == 0 && dragRune < 0) { dragRune = Json.Number(r, "id"); s.SelectedRune = dragRune; }
                }
            }
            GUI.EndScrollView();
            // drag and drop: a rune of the list (or an item of a bag) dropped on a free socket of the selected spell
            var ev = Event.current;
            if (dragRune >= 0)
            {
                if (ev.type == EventType.Repaint)
                {
                    var dr = s.RuneById(dragRune);
                    ChaosApp.Fill(new Rect(ev.mousePosition.x - 14, ev.mousePosition.y - 14, 28, 28), Ui.Hex(dr != null ? Json.Text(dr, "color", "#d6c9ae") : "#d6c9ae") * new Color(1f, 1f, 1f, 0.8f));
                }
                if (ev.type == EventType.MouseUp && ev.button == 0)
                {
                    int hit = SupportDrop.Hit(sockets, ev.mousePosition.x, ev.mousePosition.y, detail.y, detail.yMax);
                    if (hit >= 0) s.SocketRune(sockets[hit].Spell, sockets[hit].Slot, (int)dragRune);
                    dragRune = -1;
                    ev.Use();
                }
                else if (ev.type == EventType.MouseUp || (ev.rawType == EventType.MouseUp)) dragRune = -1;
            }
            else
                foreach (var tgt in sockets)
                    if (tgt.Free && tgt.Y >= detail.y - tgt.H && tgt.Y <= detail.yMax)
                    {
                        var t2 = tgt;
                        ItemSlots.Drop(new Rect(tgt.X, Mathf.Max(tgt.Y, detail.y), tgt.W, Mathf.Min(tgt.Y + tgt.H, detail.yMax) - Mathf.Max(tgt.Y, detail.y)), (pos, id, stack, count) => s.SocketItem(t2.Spell, t2.Slot, pos, id));
                    }
            ItemSlots.Ghost(app, new Rect(0, 0, Area.width, Area.height));
            var sel = s.RuneById(s.SelectedRune);
            float fy = inner.yMax - 28;
            if (sel != null) Ui.Text(new Rect(dx, fy - 22, dw, 20), s.RuneInfo(sel), small, Json.Text(sel, "color", "#d6c9ae"));
            GUI.enabled = s.CanCombine(sel);
            if (GUI.Button(new Rect(dx, fy, 120, 24), Loc.T("Combine 3"))) s.Combine();
            GUI.enabled = true;
            if (s.Result.Length > 0) Ui.Text(new Rect(dx + 126, fy + 2, dw - 126, 22), s.Result, small, s.ResultOk ? "#9fdc7f" : "#e03a1e");
        }
    }

    // ------------------------------------------------------------------------------------------------ pact
    public sealed class PactWindow : SyncedWindow
    {
        public override string Title => Loc.T("Chaos Pact");
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 300), 50, Mathf.Min(600, w - 16), Mathf.Min(580, h - 60));
        Vector2 scroll;
        string buildName = "";

        protected override void OnReset() { buildName = ""; }
        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var p = app.Session?.Utils?.Pact; show = null; hide = null; if (p == null) return false; show = p.Open; hide = () => p.Visible = false; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.Pact.Visible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var p = app.Session?.Utils?.Pact;
            if (p == null) return;
            Styles(app);
            float w = inner.width - 12;
            string line;
            string title = p.StatusTitle(out line);
            var builds = p.BuildRows(); var shelf = p.ShelfRows(); var limits = p.LimitRows();
            float total = 360 + builds.Count * 48 + shelf.Count * 28 + limits.Count * 20;
            scroll = GUI.BeginScrollView(inner, scroll, new Rect(0, 0, inner.width - 18, total));
            float x = 6, y = 2;
            GUI.Label(new Rect(x, y, w, 22), title, st); y += 22;
            y = Ui.Para(line, small, x, y, w - 20);
            string claim = p.ClaimText(out bool can);
            GUI.enabled = can;
            if (GUI.Button(new Rect(x, y, 220, 26), claim)) p.Claim();
            GUI.enabled = true;
            y += 32;
            y = Ui.Para(p.MarksLine(), small, x, y, w - 20);
            y = Ui.Para(p.MonthLine(), small, x, y, w - 20);
            y += 4;
            foreach (var r in shelf)
            {
                GUI.Label(new Rect(x, y, w * 0.5f, 22), r.Name, small);
                GUI.Label(new Rect(x + w * 0.5f, y, 80, 22), r.Price, small);
                GUI.enabled = r.CanBuy;
                if (GUI.Button(new Rect(x + w - 90, y, 80, 22), r.Button)) p.Buy(r.Key);
                GUI.enabled = true;
                y += 26;
            }
            y += 6;
            GUI.Label(new Rect(x, y, w, 20), Loc.T("Limits"), st); y += 22;
            string[] head = { Loc.T("Perk"), Loc.T("Free"), Loc.T("Pact"), Loc.T("Bought"), Loc.T("Yours") };
            float[] cols = { 0.36f, 0.12f, 0.2f, 0.16f, 0.16f };
            float cx = x;
            for (int i = 0; i < 5; i++) { GUI.Label(new Rect(cx, y, w * cols[i], 20), head[i], small); cx += w * cols[i]; }
            y += 20;
            foreach (var r in limits)
            {
                cx = x;
                for (int i = 0; i < 5; i++) { GUI.Label(new Rect(cx, y, w * cols[i], 20), r[i], small); cx += w * cols[i]; }
                y += 20;
            }
            y = Ui.Para(p.SpecialText(), small, x, y + 4, w - 20);
            y += 6;
            GUI.Label(new Rect(x, y, w, 20), p.BuildHeader(), st); y += 22;
            GUI.SetNextControlName("pactBuild");
            buildName = GUI.TextField(new Rect(x, y, w - 20, 22), buildName, 24);
            if (GUI.GetNameOfFocusedControl() == "pactBuild") app.MarkTextEditing();
            y += 26;
            foreach (var r in builds)
            {
                var rr = new Rect(x, y, w - 20, 44);
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                GUI.Label(new Rect(rr.x + 4, rr.y + 2, rr.width - 250, 20), r.Name, st);
                GUI.Label(new Rect(rr.x + 4, rr.y + 22, rr.width - 250, 18), r.Sub, small);
                float bx = rr.xMax - 244;
                GUI.enabled = r.Saved;
                if (GUI.Button(new Rect(bx, rr.y + 10, 56, 24), Loc.T("Load"))) p.LoadBuild(r.Slot);
                GUI.enabled = r.Editable;
                if (GUI.Button(new Rect(bx + 60, rr.y + 10, 56, 24), Loc.T("Save"))) p.Save(r.Slot, r.Saved && buildName.Length == 0 ? r.Name : buildName);
                GUI.enabled = r.Saved && r.Editable;
                if (GUI.Button(new Rect(bx + 120, rr.y + 10, 56, 24), Loc.T("Rename")) && buildName.Length > 0) p.Rename(r.Slot, buildName);
                if (GUI.Button(new Rect(bx + 180, rr.y + 10, 60, 24), p.ArmedDelete == r.Slot ? Loc.T("Confirm") : Loc.T("Delete"))) p.Delete(r.Slot);
                GUI.enabled = true;
                y += 48;
            }
            if (p.Note.Length > 0) Ui.Para(p.Note, small, x, y, w - 20, p.NoteColor);
            GUI.EndScrollView();
        }
    }

    // ------------------------------------------------------------------------------------------------ candlemarks
    public sealed class CandlemarksWindow : SyncedWindow
    {
        public override string Title => Loc.T("Candlemarks");
        public override string TravelKey => "candlemarks";
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, w / 2 - 280), 60, Mathf.Min(560, w - 16), Mathf.Min(520, h - 70));
        Vector2 scroll;

        protected override bool Visible(ChaosApp app, out System.Action show, out System.Action hide)
        {
            var c = app.Session?.Utils?.Candles; show = null; hide = null; if (c == null) return false; show = c.Open; hide = () => c.Visible = false; return true;
        }
        protected override bool IsVisible(ChaosApp app) => app.Session.Utils.Candles.Visible;

        protected override void Body(ChaosApp app, Rect inner)
        {
            var c = app.Session?.Utils?.Candles;
            if (c == null) return;
            Styles(app);
            float x = inner.x + 6, y = inner.y + 2, w = inner.width - 12;
            if (c.State == null) { GUI.Label(new Rect(x, y, w, 22), Loc.T("Waiting for the server..."), st); return; }
            GUI.Label(new Rect(x, y, w, 22), c.HeaderBalance(), st); y += 22;
            GUI.Label(new Rect(x, y, w, 20), c.HeaderNext(), small); y += 20;
            GUI.Label(new Rect(x, y, w, 20), c.HeaderWeek(), small); y += 20;
            y = Ui.Para(c.HeaderShop(), small, x, y, w, "#8c8070");
            var offers = c.Offers();
            float listH = inner.yMax - y - (c.Result.Length > 0 ? 28 : 4);
            scroll = GUI.BeginScrollView(new Rect(inner.x, y, inner.width, listH), scroll, new Rect(0, 0, inner.width - 18, offers.Count * 58 + 2));
            for (int i = 0; i < offers.Count; i++)
            {
                var o = offers[i];
                var rr = new Rect(4, i * 58, inner.width - 26, 56);
                ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                if (o.Cid > 0) app.DrawItem(new Rect(rr.x + 3, rr.y + 12, 32, 32), (ushort)o.Cid, 1);
                GUI.Label(new Rect(rr.x + 40, rr.y + 2, rr.width - 150, 18), CandlemarksState.OfferTitle(o), st);
                GUI.Label(new Rect(rr.x + 40, rr.y + 20, rr.width - 150, 16), o.Desc, small);
                Ui.Text(new Rect(rr.x + 40, rr.y + 37, rr.width - 150, 16), CandlemarksState.OfferPrice(o) + (CandlemarksState.OfferLimit(o).Length > 0 ? "   " + CandlemarksState.OfferLimit(o) : ""), small, "#e8b84a");
                GUI.enabled = o.CanBuy && !c.Buying;
                if (GUI.Button(new Rect(rr.xMax - 100, rr.y + 8, 96, 26), Loc.T("Buy"))) c.Buy(o);
                GUI.enabled = true;
                if (o.Why.Length > 0) Ui.Text(new Rect(rr.xMax - 104, rr.y + 36, 104, 16), o.Why.Length > 22 ? o.Why.Substring(0, 20) + ".." : o.Why, small, "#e05040");
                if (rr.Contains(Event.current.mousePosition) && o.Why.Length > 0) app.SetTip(o.Why);
            }
            GUI.EndScrollView();
            if (c.Result.Length > 0) Ui.Text(new Rect(x, inner.yMax - 24, w, 20), c.Result, small, c.ResultColor);
        }
    }
}
