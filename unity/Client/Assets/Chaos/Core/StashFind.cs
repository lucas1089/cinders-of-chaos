// Find my item (O412) and the never-stash list of the Supply Stash, a port of game_stash/stashfind.lua and the block list of stash.lua.
//   client -> server  Find {q, page}   ChangeStash {Pos = {x, y, z, stackpos}} (toggle the item's type) | {RemoveUI = true, itemId}
//   server -> client  found {q, page, pages, total, shown, capped, items = [{loc = equip | bag | purse | inbox | stash, name, count, cid, rarity?,
//                     unique?, slot?, path?, at?, ids?, where?, tab?, tabName?, old?, row?, item?}]} | found {q, error = short | long}
//                     forceBlockList {items = [{sprite, name, id}]} | addBlockItem {status, itemData}
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class StashBlock
    {
        public int Sprite, Id;
        public string Name = "";
    }

    public sealed class FindResult
    {
        public string Loc = "", Name = "", Where = "", TabName = "";
        public int Count = 1, Cid, Rarity, Slot, Tab, Row = -1, Item;
        public bool Unique, Old;
    }

    public sealed class StashFinder
    {
        public const int MinChars = 2, MaxChars = 40;
        public const double DebounceMs = 700, TimeoutMs = 3000;

        readonly Action<string, Dictionary<string, object>> send;
        public string Query;
        public int Page = 1, Pages = 1, Total, Shown;
        public bool Capped, Answered;
        public string Error = "";
        public readonly List<FindResult> Results = new List<FindResult>();
        public double AskedAt = -1e9;
        public Action Changed = delegate { };

        public StashFinder(Action<string, Dictionary<string, object>> sender) { send = sender; }

        /// <summary>The query as it is sent: trimmed, null while too short or too long.</summary>
        public static string CleanQuery(string text)
        {
            string q = (text ?? "").Trim();
            if (q.Length > MaxChars) return null;
            if (q.Replace(" ", "").Length < MinChars) return null;
            return q;
        }

        /// <summary>Asks the server; a null query clears the list.</summary>
        public void Request(string q, int page, double now)
        {
            Query = q; Page = Math.Max(1, page); Answered = false; Error = "";
            if (q == null) { Results.Clear(); Total = Shown = 0; Pages = 1; Changed(); return; }
            AskedAt = now;
            send("Find", new Dictionary<string, object> { { "q", q }, { "page", Page } });
        }

        public void Turn(int delta, double now)
        {
            if (Query == null || !Answered) return;
            int page = Math.Max(1, Math.Min(Pages, Page + delta));
            if (page != Page) Request(Query, page, now);
        }

        public void OnFound(object d)
        {
            // an older answer arriving late is dropped
            if (Query == null || Json.Text(d, "q") != Query) return;
            Answered = true;
            Error = Json.Text(d, "error");
            Page = Math.Max(1, Json.Int(d, "page", 1)); Pages = Math.Max(1, Json.Int(d, "pages", 1));
            Total = Json.Int(d, "total"); Shown = Json.Int(d, "shown"); Capped = Json.Truthy(d, "capped");
            Results.Clear();
            foreach (object r in Json.List(d, "items"))
                Results.Add(new FindResult
                {
                    Loc = Json.Text(r, "loc"), Name = Json.Text(r, "name"), Count = Json.Int(r, "count", 1), Cid = Json.Int(r, "cid"), Rarity = Json.Int(r, "rarity"),
                    Unique = Json.Truthy(r, "unique"), Slot = Json.Int(r, "slot"), Where = Json.Text(r, "where"), Tab = Json.Int(r, "tab"), TabName = Json.Text(r, "tabName"),
                    Old = Json.Truthy(r, "old"), Row = Json.Get(r, "row") is double row ? (int)row : -1, Item = Json.Int(r, "item"),
                });
            Changed();
        }

        // ------------------------------------------------------------------------------------ texts
        public static readonly string[] SlotNames = { "Head", "Necklace", "Backpack", "Armor", "Right hand", "Left hand", "Legs", "Feet", "Ring", "Ammo" };

        public static string SlotName(int slot) => slot >= 1 && slot <= SlotNames.Length ? Loc.T(SlotNames[slot - 1]) : Loc.T("Slot {0}", slot);

        /// <summary>The text of a tab as the main client's stash view names it: the number of a general tab, the name of an affinity tab.</summary>
        public static string TabText(StashTab t)
        {
            if (t.Old) return Loc.T("Old depot");
            if (t.Affinity) return Loc.T(t.Name);
            if (t.Id == 1) return Loc.T("Stash");
            return Loc.T("Old tab {0}", t.Id);
        }

        /// <summary>The line under a result: where it is.</summary>
        public static string WhereText(FindResult r, Func<StashTab, string> tabLabel)
        {
            switch (r.Loc)
            {
                case "equip": return Loc.T("Equipped: {0}", SlotName(r.Slot));
                case "bag": return Loc.T("Carried: {0}", r.Where.Length > 0 ? r.Where : SlotName(r.Slot));
                case "purse": return Loc.T("In your purse");
                case "inbox": return Loc.T("In your inbox");
                case "stash":
                {
                    string label = tabLabel != null ? tabLabel(new StashTab { Id = r.Tab, Name = r.TabName, Affinity = r.TabName.Length > 0, Old = r.Old }) : r.Tab.ToString();
                    return Loc.T("Stash: {0} tab", label);
                }
                default: return "";
            }
        }

        /// <summary>What a click does: stash, container, equip, purse or inbox ("" for an unknown place).</summary>
        public static string Action(FindResult r) => r.Loc == "bag" ? "container" : r.Loc == "equip" || r.Loc == "purse" || r.Loc == "inbox" || r.Loc == "stash" ? r.Loc : "";

        public static string Hint(FindResult r)
        {
            switch (Action(r))
            {
                case "stash": return Loc.T("Click: open the stash at this tab and show the item.");
                case "container": return Loc.T("Click: open the bags it is in and show the item.");
                case "equip": return Loc.T("Click: show the slot.");
                case "purse": return Loc.T("Click: show the purse button. Take the item out of the purse into your backpack.");
                case "inbox": return Loc.T("Click: open the stash. Its Inbox button moves the inbox into your stash (in a protection zone).");
                default: return "";
            }
        }

        /// <summary>The line a click on a result that is not in the stash tells (the Unity window has no bag path opener).</summary>
        public static string GoText(FindResult r)
        {
            switch (Action(r))
            {
                case "container": return Loc.T("Open your bags to reach it: {0}.", r.Where);
                case "equip": return Loc.T("It is worn: {0}.", SlotName(r.Slot));
                case "purse": return Loc.T("It is in your purse: the purse button under your equipment opens it.");
                case "inbox": return Loc.T("It is in your inbox: the Inbox button of the stash moves it into your stash (in a protection zone).");
                default: return "";
            }
        }

        /// <summary>A stash entry of the window is the result's entry.</summary>
        public static bool IsEntry(FindResult r, StashItem it)
        {
            if (r.Loc != "stash") return false;
            if (r.Row >= 0) return it.Row == r.Row;
            return it.Row < 0 && it.Id == r.Item && r.Item > 0;
        }

        public string StatusText()
        {
            if (Error == "short") return Loc.T("Type at least {0} letters.", MinChars);
            if (Error == "long") return Loc.T("Type at most {0} letters.", MaxChars);
            if (Query == null) return "";
            if (!Answered) return Loc.T("Searching...");
            if (Total == 0) return Loc.T("No item found.");
            if (Capped || Shown < Total) return Loc.T("{0} found, the first {1} listed. Type more of the name.", Total, Shown);
            return Loc.T("{0} found.", Total);
        }

        public string PageText() => Pages <= 1 ? "" : Loc.T("Page {0} of {1}", Page, Pages);

        public static string Title(FindResult r)
        {
            string name = r.Name.Length > 0 ? char.ToUpperInvariant(r.Name[0]) + r.Name.Substring(1) : "";
            string text = name + (r.Count > 1 ? " x" + r.Count : "");
            if (r.Unique) return text + " (" + Loc.T("Unique") + ")";
            string rn = ItemRarity.Name(ItemRarity.Canon(r.Rarity));
            return rn != null ? text + " (" + Loc.T(rn) + ")" : text;
        }

        public static string Color(FindResult r) => r.Unique ? ItemRarity.UniqueColor : ItemRarity.Color(ItemRarity.Canon(r.Rarity)) ?? "#e4d8c0";
    }
}
