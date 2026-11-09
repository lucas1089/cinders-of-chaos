// Phase 29 (2026-11-09): the Purse of the inventory window on a real server (O433, unity/README.md "Parity with the 2026-11-09 client fixes (phase 29)").
// Store purchases are delivered to the purse (server store_delivery.lua), the engine's store inbox in inventory slot 11. The Unity inventory window has a Purse button
// (Core/Phase29.cs PurseButton, GameSession.UsePurse): the main client's request, "use the item of slot 11". This scenario sends the same request and reads the answer.
// Opt-in by name (--scenario purse), part of the CI group `newplayer`. No staff command, no db change: a fresh character has an empty purse, which is what is read.
using System;
using System.Globalization;
using System.Linq;
using System.Text;
using Chaos.Core;

namespace Chaos.Core.LiveCheck
{
    public sealed partial class LiveRun
    {
        void ScPurse(ScenarioResult r)
        {
            var p = s.Parser;
            var problems = new StringBuilder();
            var mark = Mark.Of(me);
            int unknown0 = p.Failures.Count(f => f.Unknown);
            // the login's 0x78 for slot 11: the item the button uses
            var held = PurseButton.Held(p.Inventory);
            if (held == null)
            {
                // a server may send the slot a moment after the login; the scenario runs after the hellos, so this is a real absence
                r.Note("inventory slot " + PurseButton.Slot + " is empty: no 0x78 for it in the login (items in the inventory: " + p.Inventory.Count(x => x != null) + ")");
                r.Fail("the server sent no item for the purse slot (" + PurseButton.Slot + "): the Purse button would answer 'You have no purse.' on a character that bought something");
                return;
            }
            r.Note("purse slot " + PurseButton.Slot + ": client item " + held.Id + (held.Type != null ? ", container " + held.Type.Container : ", no type (no dat: the otb gives the flags)") + ", count " + held.Count);
            // the free container id, as ItemSlots.FreeContainerId picks it
            byte cid = 0;
            for (byte i = 0; i < 16; i++) if (!p.Containers.ContainsKey(i)) { cid = i; break; }
            int opens0 = Seen(0x6E);
            if (!s.UsePurse(cid)) { r.Fail("UsePurse found no item although the slot holds one"); return; }
            bool opened = WaitFor(4000, () => Seen(0x6E) > opens0 && p.Containers.ContainsKey(cid));
            Pump(300, () => false);
            if (!opened) problems.Append("no container window (0x6E) came for the use of the purse in 4 s; ");
            else
            {
                var c = p.Containers[cid];
                r.Note("0x6E for container id " + cid + ": '" + c.Name + "', item " + c.ItemId + ", " + c.Items.Count(x => x != null) + " item(s) of " + c.Size + ", capacity " + c.Capacity + ", parent " + c.HasParent);
                if (c.ItemId != held.Id) problems.Append("the opened container is item " + c.ItemId + ", the purse is item " + held.Id + "; ");
                s.CloseContainer(cid);
                bool closed = WaitFor(3000, () => !p.Containers.ContainsKey(cid) || Seen(0x6F) > 0);
                r.Note("close request: " + (closed ? "the container is gone" : "the server kept it listed"));
            }
            // the purchase leg: only an account that has Chaos Coins takes it (a fresh one has none: the local run gives one coins in the local db, and says so in the notes). The cheapest
            // physical offer is bought through the store's own request; the item must be in the purse, the way store_delivery.lua puts it, and the purse window must list it.
            problems.Append(PurseBuyLeg(r, p));
            r.Note("packets: unknown types +" + (p.Failures.Count(f => f.Unknown) - unknown0) + ", parse failures +" + (p.FailureCount - mark.Failures));
            if (p.Failures.Count(f => f.Unknown) > unknown0) problems.Append("an unknown packet type came after the purse request; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("slot " + PurseButton.Slot + " holds the purse (item " + held.Id + "), the main client's use request opened it in container window " + cid + ", closed again" + (purchased ? ", a store purchase landed in it" : "") + ", no unread packet");
        }

        bool purchased;

        /// <summary>A store offer the server delivers as items into the purse. The offer list does not say it (a premium offer carries an item icon too), so the title is read: a potion.</summary>
        static bool IsPhysical(StoreOffer o) => o.Title.IndexOf("Potion", StringComparison.OrdinalIgnoreCase) >= 0;

        /// <summary>Buys the cheapest physical store offer the account can pay and checks that it lands in the purse (the container of slot 11). Returns the problems ("" when none or skipped).</summary>
        string PurseBuyLeg(ScenarioResult r, GameParser p)
        {
            var st = s.Store;
            st.Show();
            WaitFor(5000, () => st.Loaded && st.Categories.Count > 0 && st.Coins >= 0);
            if (!st.Loaded || st.Categories.Count == 0) { r.Note("purchase leg: the store did not answer in 5 s, skipped"); return ""; }
            if (st.Coins < 1) { r.Note("purchase leg: the account has " + st.Coins.ToString("0", CultureInfo.InvariantCulture) + " Chaos Coins, skipped (a fresh account has none)"); return ""; }
            StoreOffer pick = null;
            int visited = 0;
            // one search across the categories first (potions are physical items); the category walk is the fallback
            st.Search("potion");
            WaitFor(3000, () => st.Searching == "potion" && st.Offers.Count > 0);
            foreach (var o in st.Offers.ToList())
                if (o.Buyable && !o.Owned && o.Item > 0 && o.Cost > 0 && o.Cost <= st.Coins && IsPhysical(o) && (pick == null || o.Cost < pick.Cost)) pick = o;
            if (pick != null) r.Note("purchase leg: found by the store search 'potion' among " + st.Offers.Count + " result(s)");
            for (int cat = 1; pick == null && cat <= st.Categories.Count && cat <= 60 && s.Closed == null; cat++)
            {
                int want = cat;
                st.Select(want);
                WaitFor(2500, () => st.Selected == want && st.Offers.Count > 0);
                visited++;
                foreach (var o in st.Offers.ToList())
                    if (o.Buyable && !o.Owned && o.Item > 0 && o.Cost > 0 && o.Cost <= st.Coins && IsPhysical(o) && (pick == null || o.Cost < pick.Cost)) pick = o;
                if (pick != null && pick.Cost <= 5) break;
            }
            if (pick == null) { r.Note("purchase leg: no physical offer within " + st.Coins.ToString("0", CultureInfo.InvariantCulture) + " coins in " + visited + " categories, skipped"); return ""; }
            r.Note("purchase leg: offer '" + pick.Title + "' (item " + pick.Item + " x" + pick.Count + ", " + pick.Cost.ToString("0", CultureInfo.InvariantCulture) + " coins) from category " + pick.Category + "; coins " + st.Coins.ToString("0", CultureInfo.InvariantCulture));
            double coins0 = st.Coins;
            int before = PurseItems(p);
            if (!st.AskBuy(pick)) return "the store refused to ask for the purchase of '" + pick.Title + "'; ";
            st.ConfirmBuy();
            bool paid = WaitFor(6000, () => st.Coins < coins0);
            Pump(800, () => false);
            r.Note("purchase leg: coins " + coins0.ToString("0", CultureInfo.InvariantCulture) + " to " + st.Coins.ToString("0", CultureInfo.InvariantCulture) + (st.MessageTitle.Length > 0 ? ", store message '" + st.MessageTitle + "'" : "") + (paid ? "" : ", no answer in 6 s"));
            if (st.Coins >= coins0) return "the purchase did not take coins (" + coins0 + " to " + st.Coins + "); ";
            int after = PurseItems(p);
            r.Note("purchase leg: the purse held " + before + " item(s) before and holds " + after + " after");
            if (after <= before) return "the bought item is not in the purse (" + before + " before, " + after + " after); ";
            purchased = true;
            return "";
        }

        /// <summary>Opens the purse the way the button does, counts its items, closes it again; -1 when it did not open.</summary>
        int PurseItems(GameParser p)
        {
            byte cid = 0;
            for (byte i = 0; i < 16; i++) if (!p.Containers.ContainsKey(i)) { cid = i; break; }
            int opens0 = Seen(0x6E);
            if (!s.UsePurse(cid)) return -1;
            if (!WaitFor(4000, () => Seen(0x6E) > opens0 && p.Containers.ContainsKey(cid))) return -1;
            Pump(300, () => false);
            var c = p.Containers[cid];
            int n = c.Items.Count(x => x != null);
            s.CloseContainer(cid);
            Pump(300, () => false);
            return n;
        }
    }
}
