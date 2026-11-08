// Supply Stash (client game_stash, extended opcode 110, server stash.lua): the one item storage of a character. Both ways the message is
// {"action":"Stash","data":{"make":...}}.
//
//   client -> server  SendCategories {sendBlocks} | SendItems | Open | Stash {Pos = {x,y,z,stackpos}, ItemId, Count, UpdateList} (deposit one
//                     item of a bag or the map) | Redeem {item, id, row, count} (withdraw: a plain stack by item id + count, a stored item by
//                     row) | StashAllRequest (Stow Everything) | CollectInbox
//   server -> client  tabs {tabs = [{id, name, used, size, locked, affinity, icon, old}], limit, pact, canWithdraw, canDeposit, withdrawWhy,
//                     depositWhy, remote, slots, freeSlots, packs, maxPacks, store, inbox}
//                     addItems {isFirst, isLast, items = [{sprite (client id), count, name, tooltip, id, uniqueId, typee, tab, row?, rarity?}]}
//                     Toggle {remote, open} | access {canWithdraw | canDeposit} | StowReport {stowed, kept, reasons} | StashAll {status}
//                     addCategorys {list = [{name, value}]} | forceBlockList | addBlockItem | found
// Withdrawing works only in a protection zone or a hideout, depositing in town or with the remote unlock; the server checks both again.
// Not in Unity yet: the "never stash" block list and Find my item.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class StashTab
    {
        public int Id, Used, Size;
        public string Name = "";
        public bool Locked, Affinity, Old;
        public int Icon;   // client id of the item that stands for an affinity tab, 0 none
    }

    public sealed class StashItem
    {
        public int Sprite, Count, Id, UniqueId, Tab, Row = -1, Rarity;
        public string Name = "", Tooltip = "", Type = "";
    }

    public sealed class StashState
    {
        public const byte Opcode = 110;

        readonly ExtOpcodes ext;
        public readonly List<StashTab> Tabs = new List<StashTab>();
        public readonly List<StashItem> Items = new List<StashItem>();
        List<StashItem> building = new List<StashItem>();
        public bool CanWithdraw, CanDeposit;
        public string WithdrawWhy = "", DepositWhy = "", RemoteKind = "", StoreCategory = "";
        public int Slots, FreeSlots, Packs, MaxPacks, InboxCount, Limit;
        public bool HasTabs, ItemsLoaded;
        public bool Visible;
        /// <summary>The player asked for the window and the first item list is on its way.</summary>
        public bool Opening;
        public int SelectedTab;
        public string StowReport = "";
        public bool Stowing;
        public Action Changed = delegate { };

        public StashState(ExtOpcodes e)
        {
            ext = e;
            ext.On(Opcode, OnMessage);
        }

        void SendMake(string make, Dictionary<string, object> extra = null)
        {
            var data = new Dictionary<string, object> { { "make", make } };
            if (extra != null) foreach (var kv in extra) data[kv.Key] = kv.Value;
            ext.Send(Opcode, "Stash", data);
        }

        /// <summary>The first requests after the login (the main client waits 100 ms).</summary>
        public void Prefetch() { SendMake("SendCategories", new Dictionary<string, object> { { "sendBlocks", true } }); }

        /// <summary>Opens the window: the item list is asked for, the window shows when it arrives (or at once on a repeat).</summary>
        public void Show()
        {
            Opening = true;
            Visible = true;
            SendMake("SendItems");
        }

        public void Hide() { Visible = false; Opening = false; }
        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void Refresh() { SendMake("SendItems"); }
        /// <summary>Asks the server to open the stash (it answers Toggle, which Unity treats as "show").</summary>
        public void AskOpen() { SendMake("Open"); }

        /// <summary>Withdraws an item: a stored item by its row, a plain stack by item id and count (the server checks place and amounts).</summary>
        public bool Redeem(StashItem it, int count)
        {
            if (it == null || !CanWithdraw) return false;
            var d = new Dictionary<string, object>();
            if (it.Row >= 0) d["row"] = it.Row;
            else { d["item"] = it.Id; d["id"] = it.UniqueId; d["count"] = Math.Max(1, Math.Min(count, it.Count)); }
            SendMake("Redeem", d);
            return true;
        }

        /// <summary>Deposits the item at a bag, inventory or map position. pos is the client position (container slot on the shown page).</summary>
        public bool Deposit(Pos pos, int stackPos, int itemClientId, int count)
        {
            if (!CanDeposit) return false;
            var p = new Dictionary<string, object> { { "x", pos.X }, { "y", pos.Y }, { "z", pos.Z }, { "stackpos", stackPos } };
            SendMake("Stash", new Dictionary<string, object> { { "Pos", p }, { "ItemId", itemClientId }, { "Count", count }, { "UpdateList", true } });
            return true;
        }

        public bool StowAll()
        {
            if (!CanDeposit) return false;
            SendMake("StashAllRequest");
            return true;
        }

        public bool CollectInbox()
        {
            if (!CanWithdraw) return false;
            SendMake("CollectInbox");
            return true;
        }

        /// <summary>The items of a tab (0 = all), sorted by amount, then name, filtered by a search text.</summary>
        public List<StashItem> View(int tab, string search, bool byName)
        {
            var list = new List<StashItem>();
            string needle = (search ?? "").Trim().ToLowerInvariant();
            foreach (var it in Items)
            {
                if (tab != 0 && it.Tab != tab) continue;
                if (needle.Length > 0 && it.Name.ToLowerInvariant().IndexOf(needle, StringComparison.Ordinal) < 0) continue;
                list.Add(it);
            }
            list.Sort((a, b) =>
            {
                if (!byName && a.Count != b.Count) return b.Count.CompareTo(a.Count);
                return string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase);
            });
            return list;
        }

        /// <summary>The label of a tab: name and filled slots ("General 12/30").</summary>
        public static string TabLabel(StashTab t) => t.Size > 0 ? t.Name + " " + t.Used + "/" + t.Size : t.Name;

        void OnMessage(ExtMessage m)
        {
            object d = m.Data;
            if (!(d is Dictionary<string, object>)) return;
            switch (Json.Text(d, "make"))
            {
                case "addItems": AddItems(d); break;
                case "tabs": ApplyTabs(d); break;
                case "access":
                    if (Json.Get(d, "canWithdraw") is bool w) { CanWithdraw = w; WithdrawWhy = ""; }
                    if (Json.Get(d, "canDeposit") is bool dep) { CanDeposit = dep; DepositWhy = ""; RemoteKind = ""; }
                    break;
                case "Toggle":
                    // the stash keeper NPC or a depot locker asks for the window (open): shown when not already
                    if (!Visible) Show();
                    else if (!Json.Bool(d, "open")) Hide();
                    break;
                case "StowReport": StowReport = ReportText(d); break;
                case "StashAll": Stowing = Json.Bool(d, "status"); break;
            }
            Changed();
        }

        void AddItems(object d)
        {
            if (Json.Bool(d, "isFirst")) building = new List<StashItem>();
            foreach (object e in Json.List(d, "items"))
            {
                building.Add(new StashItem
                {
                    Sprite = Json.Int(e, "sprite"), Count = Json.Int(e, "count", 1), Name = Json.Text(e, "name"), Tooltip = Json.Text(e, "tooltip"),
                    Id = Json.Int(e, "id"), UniqueId = Json.Int(e, "uniqueId"), Type = Json.Text(e, "typee"), Tab = Json.Int(e, "tab"),
                    Row = Json.Get(e, "row") is double row ? (int)row : -1, Rarity = Json.Int(e, "rarity"),
                });
            }
            if (!Json.Bool(d, "isLast")) return;
            Items.Clear();
            Items.AddRange(building);
            ItemsLoaded = true;
            Opening = false;
        }

        void ApplyTabs(object d)
        {
            Tabs.Clear();
            foreach (object e in Json.List(d, "tabs"))
                Tabs.Add(new StashTab
                {
                    Id = Json.Int(e, "id"), Name = Json.Text(e, "name"), Used = Json.Int(e, "used"), Size = Json.Int(e, "size"),
                    Locked = Json.Bool(e, "locked"), Affinity = Json.Bool(e, "affinity"), Old = Json.Bool(e, "old"), Icon = Json.Int(e, "icon"),
                });
            HasTabs = true;
            CanWithdraw = Json.Bool(d, "canWithdraw");
            CanDeposit = Json.Bool(d, "canDeposit");
            WithdrawWhy = Json.Text(d, "withdrawWhy");
            DepositWhy = Json.Text(d, "depositWhy");
            RemoteKind = Json.Text(d, "remote");
            StoreCategory = Json.Text(d, "store");
            Slots = Json.Int(d, "slots"); FreeSlots = Json.Int(d, "freeSlots"); Packs = Json.Int(d, "packs"); MaxPacks = Json.Int(d, "maxPacks");
            InboxCount = Json.Int(d, "inbox"); Limit = Json.Int(d, "limit");
            bool known = SelectedTab == 0;
            foreach (var t in Tabs) if (t.Id == SelectedTab) known = true;
            if (!known) SelectedTab = 0;
        }

        /// <summary>The Stow Everything report: "Stowed 12, kept 3: reason (n)".</summary>
        static string ReportText(object d)
        {
            var sb = new System.Text.StringBuilder();
            sb.Append(Loc.T("Stowed {0}, kept {1}.", Json.Int(d, "stowed"), Json.Int(d, "kept")));
            foreach (object r in Json.List(d, "reasons"))
            {
                string label = Json.Text(r, "label");
                if (label.Length == 0) label = Json.Text(r, "reason");
                sb.Append(" ").Append(label).Append(" (").Append(Json.Int(r, "count")).Append(")");
            }
            return sb.ToString();
        }

        /// <summary>The reason a withdrawal or deposit is shut, as a line the player reads ("" when it is open).</summary>
        public string LockedLine(bool withdraw)
        {
            if (withdraw ? CanWithdraw : CanDeposit) return "";
            string why = withdraw ? WithdrawWhy : DepositWhy;
            if (withdraw) return Loc.T("You can take items out only in a protection zone or a hideout.");
            return why == "remote" ? Loc.T("Remote deposit is locked.") : Loc.T("You can deposit items only in town.");
        }

        public void Clear()
        {
            Tabs.Clear(); Items.Clear(); building = new List<StashItem>();
            HasTabs = ItemsLoaded = Visible = Opening = false;
            CanWithdraw = CanDeposit = false;
            SelectedTab = 0; StowReport = ""; Stowing = false;
        }
    }
}
