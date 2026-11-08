// The Chaos store (client game_shop, extended opcode 218, server shop.lua): browse the categories, search, see the offers and buy them with Chaos
// Coins the account already has. Nothing about real payment is in this client: the "pay_*" messages (donations, Pix) are ignored, the status
// "buyUrl" is not opened and there is no form that takes payment details. Coins are added on the website.
//
//   client -> server  init | get_page {category, page} | buy {category, page, offer, title, cost, id?, gift?} | search {text} | history
//   server -> client  category_groups [group]            the parents of the tree, before "categories"
//                     categories [category] (+ status)    flat list of what sells; a subcategory names its parent
//                     category_page {category, page, offers}
//                     search_results {text, offers}       each offer has at = {category, page, offer} and path
//                     history [offer with a description line]
//                     message {title, msg} (+ status)     the answer of a purchase
//   every message may carry status {points (the coin balance), buyUrl, ad}
//   category: {name, type item|outfit|image, item, count, outfit, pages, size, parent?, endsIn?}
//   offer:    {type, item|outfit, title, description, cost, oldCost?, tags?, gift?, owned?, id?}
// The server works the price out (sales, featured discount) and the client echoes title and cost, so a price that changed meanwhile is refused.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class StoreCategory
    {
        public int Index;   // 1-based, as the server's pages
        public string Name = "", Type = "", Parent = "";
        public int Item, Count, Pages = 1, Size = -1, EndsIn = -1;
        public Outfit Outfit;
    }

    public sealed class StoreOffer
    {
        public string Type = "", Title = "", Description = "", Id = "";
        public int Item, Count, Category, Page, Row;   // Category / Page / Row: where the server has it (buy sends them); 0 for a history line
        public Outfit Outfit;
        public double Cost, OldCost;
        public bool Gift, Owned;
        public readonly List<string> Tags = new List<string>(), Path = new List<string>();
        public bool Buyable => Category > 0 && Page > 0 && Row > 0;

        public static Outfit ReadOutfit(object o)
        {
            if (!(o is Dictionary<string, object>)) return null;
            return new Outfit(Json.Int(o, "type"), Json.Int(o, "head"), Json.Int(o, "body"), Json.Int(o, "legs"), Json.Int(o, "feet"), Json.Int(o, "addons"), Json.Int(o, "mount"))
            { Wings = Json.Int(o, "wings"), Aura = Json.Int(o, "aura"), Shader = Json.Text(o, "shader") };
        }

        public static StoreOffer From(object e, int category, int page, int row)
        {
            if (!(e is Dictionary<string, object>)) return null;
            var o = new StoreOffer
            {
                Type = Json.Text(e, "type"), Title = Json.Text(e, "title"), Description = Json.Text(e, "description"), Id = IdText(Json.Get(e, "id")),
                Item = Json.Int(e, "item"), Count = Json.Int(e, "count", 1), Outfit = ReadOutfit(Json.Get(e, "outfit")),
                Cost = Json.Number(e, "cost"), OldCost = Json.Number(e, "oldCost"), Gift = Json.Bool(e, "gift"), Owned = Json.Bool(e, "owned"),
                Category = category, Page = page, Row = row,
            };
            foreach (object t in Json.List(e, "tags")) if (t is string s) o.Tags.Add(s);
            foreach (object p in Json.List(e, "path")) if (p is string s) o.Path.Add(s);
            return o;
        }

        static string IdText(object v) => v is string s ? s : v is double d ? d.ToString("0", System.Globalization.CultureInfo.InvariantCulture) : "";
    }

    /// <summary>A node of the category tree: a leaf (a category) or a group (a parent with its subcategories).</summary>
    public sealed class StoreNode
    {
        public bool Group;
        public string Name = "";
        public int Size = -1;
        public StoreCategory Category;   // the leaf's category; a group's first subcategory (its icon)
        public readonly List<StoreNode> Children = new List<StoreNode>();
    }

    public static class StoreTree
    {
        /// <summary>The tree: top categories, and parents that hold their subcategories (list order).</summary>
        public static List<StoreNode> Build(List<StoreCategory> cats, Dictionary<string, int> groupSizes)
        {
            var nodes = new List<StoreNode>();
            var open = new Dictionary<string, StoreNode>();
            foreach (var c in cats)
            {
                var leaf = new StoreNode { Name = c.Name, Size = c.Size, Category = c };
                if (c.Parent.Length > 0)
                {
                    if (!open.TryGetValue(c.Parent, out var g))
                    {
                        g = new StoreNode { Group = true, Name = c.Parent, Category = c };
                        open[c.Parent] = g;
                        nodes.Add(g);
                    }
                    g.Children.Add(leaf);
                }
                else nodes.Add(leaf);
            }
            foreach (var n in nodes)
            {
                if (!n.Group) continue;
                if (groupSizes != null && groupSizes.TryGetValue(n.Name, out int s)) { n.Size = s; continue; }
                int sum = 0; bool any = false;
                foreach (var c in n.Children) if (c.Size >= 0) { sum += c.Size; any = true; }
                n.Size = any ? sum : -1;
            }
            return nodes;
        }

        public sealed class Row { public StoreNode Node; public int Depth; public bool Expanded; }

        /// <summary>The rows the list shows: every top node and the subcategories of the open group.</summary>
        public static List<Row> Rows(List<StoreNode> nodes, string expanded)
        {
            var rows = new List<Row>();
            foreach (var n in nodes)
            {
                bool open = n.Group && n.Name == expanded;
                rows.Add(new Row { Node = n, Depth = 0, Expanded = open });
                if (open) foreach (var c in n.Children) rows.Add(new Row { Node = c, Depth = 1 });
            }
            return rows;
        }

        public static StoreNode GroupOf(List<StoreNode> nodes, int index)
        {
            foreach (var n in nodes) if (n.Group) foreach (var c in n.Children) if (c.Category.Index == index) return n;
            return null;
        }

        public static StoreNode Leaf(List<StoreNode> nodes, int index)
        {
            foreach (var n in nodes)
            {
                if (!n.Group && n.Category.Index == index) return n;
                foreach (var c in n.Children) if (c.Category.Index == index) return c;
            }
            return null;
        }

        public static StoreNode FirstLeaf(List<StoreNode> nodes)
        {
            foreach (var n in nodes)
            {
                if (!n.Group) return n;
                if (n.Children.Count > 0) return n.Children[0];
            }
            return null;
        }

        public static StoreNode Find(List<StoreNode> nodes, string name)
        {
            foreach (var n in nodes)
            {
                if (!n.Group && n.Name == name) return n;
                foreach (var c in n.Children) if (c.Name == name) return c;
            }
            return null;
        }

        /// <summary>Clicking a group: opens it (and selects its first subcategory unless the selection is inside) or closes the open one.</summary>
        public static string Toggle(List<StoreNode> nodes, string expanded, string group, int selected, out int select)
        {
            select = 0;
            StoreNode g = null;
            foreach (var n in nodes) if (n.Group && n.Name == group) g = n;
            if (g == null) return expanded;
            if (expanded == group) return "";
            bool inside = false;
            foreach (var c in g.Children) if (c.Category.Index == selected) inside = true;
            if (!inside && g.Children.Count > 0) select = g.Children[0].Category.Index;
            return group;
        }

        /// <summary>"Wings (21)"; the name alone without a count.</summary>
        public static string Label(string name, int size) => size >= 0 ? name + " (" + size + ")" : name;
    }

    public sealed class StoreState
    {
        public const byte Opcode = 218;
        public const int SearchMin = 2;

        readonly ExtOpcodes ext;
        public readonly List<StoreCategory> Categories = new List<StoreCategory>();
        public readonly Dictionary<string, int> GroupSizes = new Dictionary<string, int>();
        public List<StoreNode> Tree = new List<StoreNode>();
        public readonly List<StoreOffer> Offers = new List<StoreOffer>();
        public readonly List<StoreOffer> History = new List<StoreOffer>();
        public int Selected, Page = 1;
        public string Expanded = "";
        public string Searching = "";
        public bool BrowsingHistory;
        /// <summary>The Chaos Coin balance of the last status, -1 before one came.</summary>
        public double Coins = -1;
        public string MessageTitle = "", MessageText = "";
        public bool Visible, Loaded;
        public StoreOffer ConfirmOffer;
        public Action Changed = delegate { };
        public int Messages;
        string pendingCategory = "";

        public StoreState(ExtOpcodes e)
        {
            ext = e;
            ext.On(Opcode, OnMessage);
        }

        public void Init() { ext.Send(Opcode, "init", new Dictionary<string, object>()); }

        public void Show()
        {
            Visible = true;
            if (!Loaded) Init();
        }

        public void Hide() { Visible = false; ConfirmOffer = null; }
        public void Toggle() { if (Visible) Hide(); else Show(); }

        public int TotalPages => Selected > 0 && Selected <= Categories.Count ? Math.Max(1, Categories[Selected - 1].Pages) : 1;

        /// <summary>Shows a category: its first page. Leaves a search or the history.</summary>
        public void Select(int index)
        {
            if (index < 1 || index > Categories.Count) return;
            Selected = index; Page = 1; BrowsingHistory = false; Searching = "";
            Offers.Clear();
            ext.Send(Opcode, "get_page", new Dictionary<string, object> { { "category", index }, { "page", 1 } });
            Changed();
        }

        public void GoPage(int delta)
        {
            int p = Page + delta;
            if (Selected < 1 || p < 1 || p > TotalPages || Searching.Length > 0 || BrowsingHistory) return;
            ext.Send(Opcode, "get_page", new Dictionary<string, object> { { "category", Selected }, { "page", p } });
        }

        public void ClickGroup(string name)
        {
            Expanded = StoreTree.Toggle(Tree, Expanded, name, Selected, out int sel);
            if (sel > 0) Select(sel);
        }

        /// <summary>Open the store at a category by its name (the stash's Buy Slots button).</summary>
        public void OpenCategory(string name)
        {
            Visible = true;
            var leaf = StoreTree.Find(Tree, name);
            if (leaf == null) { pendingCategory = name; if (!Loaded) Init(); return; }
            Reveal(leaf.Category.Index);
            Select(leaf.Category.Index);
        }

        void Reveal(int index) { var g = StoreTree.GroupOf(Tree, index); Expanded = g != null ? g.Name : ""; }

        public void Search(string text)
        {
            text = (text ?? "").Trim();
            if (text.Length < SearchMin)
            {
                if (Searching.Length > 0) { Searching = ""; if (Selected > 0) Select(Selected); }
                return;
            }
            Searching = text; BrowsingHistory = false;
            ext.Send(Opcode, "search", new Dictionary<string, object> { { "text", text } });
        }

        public void ShowHistory()
        {
            BrowsingHistory = true; Searching = "";
            Offers.Clear();
            ext.Send(Opcode, "history", new Dictionary<string, object>());
            Changed();
        }

        /// <summary>The Buy click: asks for a confirmation (the window draws a box); Confirm sends it.</summary>
        public bool AskBuy(StoreOffer o)
        {
            if (o == null || !o.Buyable || o.Owned) return false;
            ConfirmOffer = o;
            return true;
        }

        public void CancelBuy() { ConfirmOffer = null; }

        public static Dictionary<string, object> BuyData(StoreOffer o, string giftTo)
        {
            var d = new Dictionary<string, object> { { "category", o.Category }, { "page", o.Page }, { "offer", o.Row }, { "title", o.Title }, { "cost", o.Cost } };
            if (o.Id.Length > 0) d["id"] = o.Id;
            if (!string.IsNullOrEmpty(giftTo)) d["gift"] = giftTo;
            return d;
        }

        /// <summary>Sends the confirmed purchase (coins the account has; the server checks the price and the balance).</summary>
        public bool ConfirmBuy(string giftTo = null)
        {
            var o = ConfirmOffer;
            ConfirmOffer = null;
            if (o == null || !o.Buyable) return false;
            return ext.Send(Opcode, "buy", BuyData(o, giftTo));
        }

        void OnMessage(ExtMessage m)
        {
            string action = m.Action;
            if (action.StartsWith("pay_", StringComparison.Ordinal)) return;   // donations: never in this client
            Loaded = true;
            if (Json.Get(m.Root, "status") is Dictionary<string, object> status && Json.Get(status, "points") is double points) Coins = points;
            switch (action)
            {
                case "category_groups":
                    GroupSizes.Clear();
                    if (m.Data is List<object> groups)
                        foreach (object g in groups) { string n = Json.Text(g, "name"); if (n.Length > 0 && Json.Get(g, "size") is double s) GroupSizes[n] = (int)s; }
                    break;
                case "categories": ApplyCategories(m.Data as List<object>); break;
                case "category_page": ApplyPage(m.Data); break;
                case "search_results": ApplySearch(m.Data); break;
                case "history":
                    History.Clear();
                    if (m.Data is List<object> hist) foreach (object e in hist) { var o = StoreOffer.From(e, 0, 0, 0); if (o != null) History.Add(o); }
                    if (BrowsingHistory) { Offers.Clear(); Offers.AddRange(History); }
                    break;
                case "message":
                    MessageTitle = Json.Text(m.Data, "title"); MessageText = Json.Text(m.Data, "msg"); Messages++;
                    break;
            }
            Changed();
        }

        void ApplyCategories(List<object> list)
        {
            string keep = pendingCategory;
            pendingCategory = "";
            if (keep.Length == 0 && Selected > 0 && Selected <= Categories.Count) keep = Categories[Selected - 1].Name;
            Categories.Clear();
            int i = 0;
            foreach (object e in list ?? new List<object>())
            {
                i++;
                var c = new StoreCategory
                {
                    Index = i, Name = Json.Text(e, "name"), Type = Json.Text(e, "type"), Parent = Json.Text(e, "parent"), Item = Json.Int(e, "item"),
                    Count = Json.Int(e, "count", 1), Pages = Math.Max(1, Json.Int(e, "pages", 1)), Size = Json.Get(e, "size") is double sz ? (int)sz : -1,
                    EndsIn = Json.Get(e, "endsIn") is double en ? (int)en : -1, Outfit = StoreOffer.ReadOutfit(Json.Get(e, "outfit")),
                };
                Categories.Add(c);
            }
            Tree = StoreTree.Build(Categories, GroupSizes);
            var leaf = keep.Length > 0 ? StoreTree.Find(Tree, keep) : null;
            if (leaf == null) leaf = StoreTree.FirstLeaf(Tree);
            Selected = leaf != null ? leaf.Category.Index : 0;
            Reveal(Selected);
            if (Searching.Length > 0) ext.Send(Opcode, "search", new Dictionary<string, object> { { "text", Searching } });
            else if (Selected > 0 && !BrowsingHistory)
            {
                Page = 1;
                ext.Send(Opcode, "get_page", new Dictionary<string, object> { { "category", Selected }, { "page", 1 } });
            }
        }

        void ApplyPage(object data)
        {
            int cat = Json.Int(data, "category"), page = Math.Max(1, Json.Int(data, "page", 1));
            if (cat < 1 || cat > Categories.Count) return;
            // a page of another category than the one on screen (the player moved on): ignored
            if (cat != Selected || BrowsingHistory) return;
            if (Searching.Length > 0) { ext.Send(Opcode, "search", new Dictionary<string, object> { { "text", Searching } }); return; }
            Page = page;
            Offers.Clear();
            int row = 0;
            foreach (object e in Json.List(data, "offers"))
            {
                row++;
                var o = StoreOffer.From(e, cat, page, row);
                if (o != null) Offers.Add(o);
            }
        }

        void ApplySearch(object data)
        {
            if (Searching.Length == 0 || Json.Text(data, "text") != Searching) return;
            Offers.Clear();
            foreach (object e in Json.List(data, "offers"))
            {
                object at = Json.Get(e, "at");
                var o = StoreOffer.From(e, Json.Int(at, "category"), Json.Int(at, "page"), Json.Int(at, "offer"));
                if (o == null) continue;
                if (o.Path.Count > 0) o.Description = string.Join(" > ", o.Path) + ": " + o.Description;
                Offers.Add(o);
            }
        }

        public void Clear()
        {
            Categories.Clear(); GroupSizes.Clear(); Tree = new List<StoreNode>(); Offers.Clear(); History.Clear();
            Selected = 0; Page = 1; Expanded = ""; Searching = ""; BrowsingHistory = false; Coins = -1; Visible = Loaded = false; ConfirmOffer = null;
            MessageTitle = MessageText = ""; pendingCategory = "";
        }
    }
}
