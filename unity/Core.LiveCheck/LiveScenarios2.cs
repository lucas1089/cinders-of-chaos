// More play scenarios of the live check (O433 phase 22): sell, market, floorchange, sharedkill, pvpdeath. Same rules as LiveScenarios.cs: opt-in by --scenario, a time
// limit, a pass, fail or skip with the reason, and what was opened is closed again.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace Chaos.Core.LiveCheck
{
    public sealed partial class LiveRun
    {
        // ------------------------------------------------------------------------------------ helpers
        /// <summary>How many of an item the client knows it carries: the inventory slots and the open containers (a sub-container that is not open is not counted).</summary>
        static int CarriedCount(LiveClient a, int clientId) => CarriedCount(a.S.Parser, clientId);

        internal static int CarriedCount(GameParser p, int clientId)
        {
            int n = 0;
            for (int i = 1; i < p.Inventory.Length; i++) if (p.Inventory[i] != null && p.Inventory[i].Id == clientId) n += Math.Max(1, p.Inventory[i].Count);
            foreach (var c in p.Containers.Values) foreach (var it in c.Items) if (it != null && it.Id == clientId) n += Math.Max(1, it.Count);
            return n;
        }

        /// <summary>Opens the backpack (inventory slot 3) when no container is open, so what moves in and out of it can be seen.</summary>
        void EnsureBagOpen(LiveClient a)
        {
            var p = a.S.Parser;
            if (p.Containers.Count > 0 || p.Inventory.Length <= 3 || p.Inventory[3] == null) return;
            a.S.UseItem(GameSession.InventoryPos(3), (ushort)p.Inventory[3].Id, 0);
            WaitFor(2500, () => p.Containers.Count > 0);
        }

        /// <summary>The bag check of the sell scenario (phase 23), the same on both identities: how many of an item the open bags and the slots show, when the goods list says the
        /// character carries `expected` of it. When fewer show, the backpack is closed and opened again (the first use of it can be dropped or answered late), then the bags inside it
        /// are opened one by one (a bought item goes into a bag in the backpack when the backpack itself is full). `how` says what was done, for the report.</summary>
        int CarriedChecked(LiveClient a, int clientId, int expected, out string how)
        {
            how = "";
            int n = CarriedCount(a, clientId);
            if (n >= expected || expected <= 0) return n;
            var p = a.S.Parser;
            if (p.Inventory.Length <= 3 || p.Inventory[3] == null) { how = "no backpack in slot 3"; return n; }
            ushort bagId = (ushort)p.Inventory[3].Id;
            for (int attempt = 1; attempt <= 2 && n < expected; attempt++)
            {
                foreach (var cid in p.Containers.Keys.ToList()) a.S.CloseContainer(cid);
                Pump(500, () => false);
                int opened0 = a.S.Parser.Seen.TryGetValue(0x6E, out int o0) ? o0 : 0;
                a.S.UseItem(GameSession.InventoryPos(3), bagId, 0);
                WaitFor(3000, () => p.Containers.Count > 0);
                Pump(500, () => false);
                int opened = (a.S.Parser.Seen.TryGetValue(0x6E, out int o1) ? o1 : 0) - opened0;
                n = CarriedCount(a, clientId);
                how += (how.Length > 0 ? "; " : "") + "backpack opened again (try " + attempt + "): 0x6E x" + opened + ", " + p.Containers.Count + " container(s) open, the item shows " + n + " time(s)";
            }
            if (n < expected)
            {
                // a bag inside the backpack: open each one (the server sends its content as one more container)
                var inner = new List<(byte cid, int index, ushort id)>();
                foreach (var c in p.Containers.Values)
                    for (int i = 0; i < c.Items.Count; i++)
                        if (c.Items[i] != null && c.Items[i].Type != null && c.Items[i].Type.Container) inner.Add((c.Id, i + c.FirstIndex, (ushort)c.Items[i].Id));
                int tried = 0;
                foreach (var b in inner.Take(6))
                {
                    a.S.UseItem(GameSession.ContainerPos(b.cid, b.index), b.id, (byte)b.index);
                    Pump(900, () => false);
                    tried++;
                    n = CarriedCount(a, clientId);
                    if (n >= expected) break;
                }
                how += (how.Length > 0 ? "; " : "") + "bags inside the backpack opened: " + tried + " of " + inner.Count + ", the item shows " + n + " time(s)";
            }
            return n;
        }

        /// <summary>Runs an administrator panel action (extended opcode 120, the way the panel does) and waits for its result. Null when no answer came.</summary>
        (bool ok, string message)? AdminRun(LiveClient a, string id, Dictionary<string, object> pars)
        {
            bool got = false, ok = false;
            string msg = "";
            a.S.Ext.On(120, m =>
            {
                if (m.Action != "result" || m.Data == null) return;
                if (Json.Text(m.Data, "id") != id) return;
                got = true; ok = Json.Truthy(m.Data, "ok"); msg = Json.Text(m.Data, "message");
            });
            a.S.Ext.Send(120, "run", new Dictionary<string, object> { { "id", id }, { "rid", 1 }, { "params", pars } });
            if (!WaitFor(5000, () => got)) return null;
            return (ok, msg);
        }

        /// <summary>The monster that appeared in the client's view since `before`, or null.</summary>
        static Creature NewMonster(LiveClient a, HashSet<uint> before) => a.World.Creatures.Values.FirstOrDefault(c => c.Type == 1 && !before.Contains(c.Id));

        // ------------------------------------------------------------------------------------ sell
        void ScSell(ScenarioResult r)
        {
            var p = s.Parser;
            var mark = Mark.Of(me);
            var problems = new StringBuilder();
            if (!OpenShop(r)) return;
            EnsureBagOpen(me);
            var row = p.Trade.SellList(null).OrderBy(i => i.Sell).FirstOrDefault();
            if (row == null)
            {
                // nothing carried that the NPC buys: buy the cheapest good it also buys back
                var buy = p.Trade.Items.Where(i => i.Buyable && i.Sellable && i.Buy <= p.Trade.Balance).OrderBy(i => i.Buy).FirstOrDefault();
                int g0 = Seen(0x7B);
                if (buy != null)
                {
                    bool ignoreCap = false;
                    if (!s.NpcBuy(buy, 1, false)) { ignoreCap = true; if (!s.NpcBuy(buy, 1, true)) { s.NpcClose(); r.Skip("the buy rules forbid buying '" + buy.Name + "' to have something to sell"); return; } }
                    WaitFor(5000, () => Seen(0x7B) > g0 && p.Trade.GoodsCount(buy.Id) > 0);
                    Pump(600, () => false);
                    r.Note("nothing to sell was carried: bought 1 x " + buy.Name + " for " + buy.Buy + (ignoreCap ? " (capacity ignored)" : ""));
                    row = p.Trade.SellList(null).FirstOrDefault(i => i.Id == buy.Id);
                    if (row == null) { s.NpcClose(); r.Fail("bought 1 x " + buy.Name + " but it is not in the sell list (goods " + p.Trade.Goods.Count + ", 0x7B " + Seen(0x7B) + ")"); return; }
                }
                else
                {
                    // the staff command /i gives the cheapest thing the NPC buys (the character needs the administrator rights)
                    var want = p.Trade.Items.Where(i => i.Sellable).OrderBy(i => i.Sell).FirstOrDefault();
                    if (want == null) { s.NpcClose(); r.Skip(o.NpcName + " buys nothing (" + p.Trade.Items.Count + " goods, none with a sell price); give --npc a shop that buys, with --npc-at"); return; }
                    int server = serverToClient == null ? 0 : serverToClient.Where(kv => kv.Value == want.Id).Select(kv => kv.Key).DefaultIfEmpty(0).First();
                    int say0 = me.Said.Count;
                    s.Say("/i " + (server > 0 ? server.ToString(CultureInfo.InvariantCulture) : want.Name));
                    bool got = WaitFor(3500, () => p.Trade.GoodsCount(want.Id) > 0);
                    if (!got) { s.SayToNpc("trade"); got = WaitFor(5000, () => p.Trade.GoodsCount(want.Id) > 0); }
                    Pump(500, () => false);
                    row = p.Trade.SellList(null).FirstOrDefault(i => i.Id == want.Id);
                    if (row == null)
                    {
                        var texts = me.ServerTexts(say0).Take(3).ToList();
                        s.NpcClose();
                        r.Skip("the character carries nothing " + o.NpcName + " buys, the buy-back rule found nothing, and the staff command '/i " + (server > 0 ? server.ToString(CultureInfo.InvariantCulture) : want.Name) + "' gave no " + want.Name + " (the character needs the administrator rights)" + (texts.Count > 0 ? "; server said: " + string.Join(" | ", texts) : ""));
                        return;
                    }
                    r.Note("nothing to sell was carried: the staff command gave 1 x " + want.Name);
                }
            }
            ulong money0 = p.Trade.Money;
            int have0 = p.Trade.GoodsCount(row.Id);
            EnsureBagOpen(me);
            int carried0 = CarriedChecked(me, row.Id, have0, out string bagHow);
            if (bagHow.Length > 0) r.Note("bag check before the sale: " + bagHow);
            r.Note("bag check: goods list says " + have0 + ", the open bags and slots show " + carried0 + ", " + p.Containers.Count + " container(s) open");
            int goods0 = Seen(0x7B), cont0 = Seen(0x70) + Seen(0x71) + Seen(0x72) + Seen(0x78) + Seen(0x79);
            r.Note("selling 1 x " + row.Name + " (price " + row.Sell + "): goods say " + have0 + ", the open bags and slots hold " + carried0 + ", money " + money0);
            if (!s.NpcSell(row, 1, true)) { s.NpcClose(); r.Fail("the sell rules forbid selling '" + row.Name + "' (goods " + have0 + ")"); return; }
            bool updated = WaitFor(5000, () => Seen(0x7B) > goods0 || p.Trade.Money != money0);
            Pump(800, () => false);
            int have1 = p.Trade.GoodsCount(row.Id), carried1 = CarriedCount(me, row.Id), cont1 = Seen(0x70) + Seen(0x71) + Seen(0x72) + Seen(0x78) + Seen(0x79);
            r.Note("after the sale: money " + money0 + " to " + p.Trade.Money + ", goods " + have0 + " to " + have1 + ", carried " + carried0 + " to " + carried1 + ", container/slot packets +" + (cont1 - cont0) + ", 0x7B again " + (Seen(0x7B) - goods0) + " time(s)");
            if (!updated) problems.Append("no goods update (0x7B) after the sale; ");
            if (p.Trade.Money <= money0) problems.Append("the money did not rise (" + money0 + " to " + p.Trade.Money + "); ");
            else if (p.Trade.Money - money0 != row.Sell) problems.Append("the money rose by " + (p.Trade.Money - money0) + ", the price is " + row.Sell + "; ");
            if (have1 != have0 - 1) problems.Append("the goods list says " + have1 + " after the sale, expected " + (have0 - 1) + "; ");
            if (have0 > 0 && carried0 == 0) problems.Append("the goods list says the character carries " + have0 + " x " + row.Name + " but no open bag or slot shows one (" + p.Containers.Count + " container(s) open; " + bagHow + "); ");
            else if (carried0 > 0 && carried1 != carried0 - 1) problems.Append("the item is not gone from the bag or slot (" + carried0 + " to " + carried1 + "; texts: " + string.Join(" | ", me.ServerTexts(0).TakeLast(3)) + "); ");
            s.NpcClose();
            s.SayToNpc("bye");
            Pump(600, () => false);
            if (p.Trade.Open) problems.Append("the trade window state stayed open after closing; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("sold 1 x " + row.Name + " for " + row.Sell + ": 0x7B read, money up by the price, the item gone from the goods and the bag (" + carried0 + " to " + carried1 + ")");
        }

        // ------------------------------------------------------------------------------------ market
        void ScMarket(ScenarioResult r)
        {
            var mark = Mark.Of(me);
            int n0 = Seen(0xF6) + Seen(0xF7) + Seen(0xF8) + Seen(0xF9);
            int opened0 = s.Parser.Market.Entered;
            // the engine takes the market packets only from a player inside the market (Player::isInMarket); nothing here can put the character in it
            s.SendRaw(BaseMarket.BrowseRequest(BaseMarket.OwnOffers));
            s.SendRaw(BaseMarket.BrowseRequest(BaseMarket.OwnHistory));
            s.SendRaw(BaseMarket.BrowseRequest(2160));
            s.SendRaw(BaseMarket.LeaveRequest());
            Pump(1800, () => false);
            int got = Seen(0xF6) + Seen(0xF7) + Seen(0xF8) + Seen(0xF9) - n0;
            r.Note("market packets from the server after browse (own offers, history, one ware) and leave: " + got + "; entered " + (s.Parser.Market.Entered - opened0) + " time(s)");
            var problems = new StringBuilder();
            if (s.Closed != null) problems.Append("the connection closed after the market packets: " + s.Closed + "; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) { r.Fail(problems.ToString().Trim()); return; }
            if (got > 0)
            {
                r.Pass(got + " market packet(s) came from the server and parsed (0xF6 " + s.Parser.Market.Entered + ", 0xF9 " + s.Parser.Market.Browses + "): the stock market is on");
                return;
            }
            r.Skip("the stock market is off on this server (patch_market.py comments out the depot locker's market action, item 14405, in actions.xml; ProtocolGame::sendMarketEnter is called by that action and by an offer made inside the market only), so the server never sends 0xF6 to 0xF9; " +
                   "the client packets 0xF4 to 0xF8 were refused outside the market with no answer and no failure. The four server packets are covered by synthetic cases in Core.Tests (LiveCheckTests Market)");
        }

        // ------------------------------------------------------------------------------------ floor change
        void ScFloorChange(ScenarioResult r)
        {
            if (floorChanges == null) { r.Skip("no items.xml: the floor changes of stairs and holes come from it"); return; }
            var found = FindFloorChange(me, 0);
            if (found == null && o.StairsAt.HasValue)
            {
                var hint = o.StairsAt.Value;
                if (hint.Z == me.Pos.Z) WalkTo(me, hint, 3, o.ScenarioMs, false, out _);
                found = FindFloorChange(me, 0);
            }
            if (found == null) { r.Skip("no stair, ramp or hole in view of " + P(me.Pos) + " (give --stairs-at X,Y,Z)"); return; }
            var problems = new StringBuilder();
            int up0 = Seen(0xBE), down0 = Seen(0xBF), map0 = Seen(0x64), floors0 = Seen(0x4B);
            var (tile, kind) = found.Value;
            int firstZ = me.Pos.Z, changes = 0;
            if (!TakeStairs(me, tile, kind, r, "change 1", problems)) { r.Fail(problems.ToString().Trim()); return; }
            changes++;
            var back = FindFloorChange(me, -FloorDelta(kind));
            if (back != null && TakeStairs(me, back.Value.tile, back.Value.kind, r, "change 2", problems)) changes++;
            // stock 0xBE (up) and 0xBF (down) carry the new floors with the move; this engine moves the player between floors as a teleport (Map::moveCreature,
            // src/map.cpp:255: areInRange<1, 1, 0> is false when z differs), so a stair gives a full map (0x64, or 0x4B floors for the Chaos identity) and never 0xBE or 0xBF
            int up = Seen(0xBE) - up0, down = Seen(0xBF) - down0, map = Seen(0x64) - map0, floors = Seen(0x4B) - floors0;
            r.Note("floor changes " + changes + ": 0xBE x" + up + ", 0xBF x" + down + ", full map 0x64 x" + map + ", floors 0x4B x" + floors);
            if (up + down == 0 && map + floors == 0) problems.Append("no map data came with the change of floor; ");
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else if (up + down > 0) r.Pass(changes + " change(s) of floor, " + (up + down) + " stock floor change packet(s) 0xBE / 0xBF read, view centred, no parse failure");
            else r.Pass(changes + " change(s) of floor (" + firstZ + " to " + (firstZ + FloorDelta(kind)) + (changes > 1 ? " and back" : "") + ") came as a full map (0x64 x" + map + ", 0x4B x" + floors + "), never 0xBE or 0xBF: this engine moves between floors as a teleport (src/map.cpp:255), view centred, no parse failure");
        }

        // ------------------------------------------------------------------------------------ party helper
        /// <summary>Invite, join and switch shared experience on, between the primary (leader) and the partner. True when both are in the party.</summary>
        bool FormParty(StringBuilder problems, ScenarioResult r)
        {
            var pCreature = Seeing(me, partner.Character);
            var mCreature = Seeing(partner, me.Character);
            if (pCreature == null || mCreature == null) { problems.Append("the characters do not see each other; "); return false; }
            if (me.S.Party.InParty) me.S.Party.Do(PartyAction.Leave, 0);
            if (partner.S.Party.InParty) partner.S.Party.Do(PartyAction.Leave, 0);
            Pump(800, () => false);
            me.S.Party.Do(PartyAction.Invite, pCreature.Id);
            if (!WaitFor(5000, () => partner.S.Party.InvitedBy.Length > 0 && PartyShield.InvitedYou(mCreature.Shield))) { problems.Append("the invitation did not show; "); return false; }
            partner.S.Party.Do(PartyAction.Join, mCreature.Id);
            if (!WaitFor(6000, () => me.S.Party.InParty && partner.S.Party.InParty && me.S.Party.Members.Count == 2 && partner.S.Party.Members.Count == 2)) { problems.Append("joining did not complete; "); return false; }
            me.S.Party.Do(PartyAction.ShareOn, 0);
            Pump(1200, () => false);
            r.Note("party of two, shared experience switch asked: xp state " + me.S.Party.XpOn + " / " + partner.S.Party.XpOn);
            return true;
        }

        void LeaveParty()
        {
            if (partner != null && partner.S.Party.InParty) partner.S.Party.Do(PartyAction.Leave, 0);
            Pump(600, () => false);
            if (me.S.Party.InParty) me.S.Party.Do(PartyAction.Leave, 0);
            Pump(600, () => false);
        }

        // ------------------------------------------------------------------------------------ shared kill
        void ScSharedKill(ScenarioResult r)
        {
            string err = EnsurePartner();
            if (err != null) { r.Skip(err); return; }
            err = MeetPartner();
            if (err != null) { r.Skip("the two characters cannot be brought together: " + err); return; }
            var markA = Mark.Of(me);
            var markB = Mark.Of(partner);
            var problems = new StringBuilder();
            if (!FormParty(problems, r)) { r.Fail(problems.ToString().Trim()); LeaveParty(); return; }
            // out of the protection zone: the partner (staff) follows, summons the monster and then gives up its rights (staff gain no experience: group flag notgainexperience)
            if (!LeavePz(me, r)) { LeaveParty(); return; }
            int pSay = partner.Said.Count;
            partner.S.Say("/goto " + me.Character);
            if (!WaitFor(8000, () => partner.Pos.Z == me.Pos.Z && PathFinder.Cheb(partner.Pos, me.Pos) <= 3))
            {
                var texts = partner.ServerTexts(pSay).Take(3).ToList();
                r.Skip("the partner is not staff (/goto did not bring it to the character)" + (texts.Count > 0 ? "; server said: " + string.Join(" | ", texts) : ""));
                LeaveParty();
                return;
            }
            // two monsters: the partner kills the first (it has then hurt something lately: a member that did nothing lately takes no share), the character kills the second
            var before = new HashSet<uint>(me.World.Creatures.Values.Where(c => c.Type == 1).Select(c => c.Id));
            partner.S.Say("/m " + o.Weak);
            if (!WaitFor(6000, () => NewMonster(me, before) != null && NewMonster(partner, before) != null))
            {
                var texts = partner.ServerTexts(pSay).Take(4).ToList();
                // /goto brought the partner here, so it has the staff rights: a missing monster is a fault of the set-up, not a missing right
                r.Fail("no monster appeared after '/m " + o.Weak + "' although /goto worked (no free tile beside the partner, or the name is not a monster)" + (texts.Count > 0 ? "; server said: " + string.Join(" | ", texts) : ""));
                LeaveParty();
                return;
            }
            var first = NewMonster(me, before);
            uint firstId = first.Id;
            before.Add(firstId);
            partner.S.Say("/m " + o.Weak);
            WaitFor(6000, () => NewMonster(me, before) != null);
            var mon = NewMonster(me, before);
            if (mon == null) { r.Skip("the second '/m " + o.Weak + "' made no monster"); LeaveParty(); return; }
            uint monId = mon.Id;
            r.Note("summoned two " + mon.Name + ", " + PathFinder.Cheb(first.Position, me.Pos) + " and " + PathFinder.Cheb(mon.Position, me.Pos) + " tiles from the character");
            // the partner gives up staff rights: a staff member gains nothing, and the group is checked at every gain
            var demote = AdminRun(partner, "players.set_group", new Dictionary<string, object> { { "player", partner.Character }, { "group", 1 } });
            r.Note("partner demoted to a plain player: " + (demote == null ? "no answer" : demote.Value.ok ? "ok" : "refused (" + demote.Value.message + ")"));
            if (demote == null || !demote.Value.ok) { r.Skip("the partner could not give up its staff rights (the experience would not count): " + (demote == null ? "no answer from the admin panel" : demote.Value.message)); LeaveParty(); return; }
            me.S.SetFightModes(new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = true });
            partner.S.SetFightModes(new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = true });
            Pump(300, () => false);
            // the partner kills the first monster alone ...
            partner.S.Attack(firstId);
            long end1 = Tick + 30000;
            for (int k = 0; Tick < end1 && me.World.Creatures.ContainsKey(firstId) && me.S.Closed == null; k++)
            {
                Pump(250, () => !me.World.Creatures.ContainsKey(firstId));
                if (k % 8 == 7) partner.S.Attack(firstId);
            }
            Pump(1500, () => false);
            // ... then the character kills the second one with the partner's hit not a minute old: the share goes to both
            long expBefore1 = (long)me.S.Parser.Experience, expBefore2 = (long)partner.S.Parser.Experience;
            int texts1 = me.S.Parser.ExpGainTexts, texts2 = partner.S.Parser.ExpGainTexts, stats1 = Seen(0xA0), stats2 = partner.S.Parser.Seen.TryGetValue(0xA0, out int sn) ? sn : 0;
            r.Note("the partner killed the first monster: experience texts " + texts2 + ", " + (me.World.Creatures.ContainsKey(firstId) ? "it is still alive" : "it died"));
            me.S.Attack(monId);
            long end = Tick + 40000;
            for (int k = 0; Tick < end && me.World.Creatures.ContainsKey(monId) && me.S.Closed == null; k++)
            {
                Pump(250, () => !me.World.Creatures.ContainsKey(monId));
                if (k % 8 == 7) me.S.Attack(monId);
            }
            bool dead = !me.World.Creatures.ContainsKey(monId);
            Pump(2500, () => false);
            long exp1 = (long)me.S.Parser.Experience, exp2 = (long)partner.S.Parser.Experience;
            int gain1 = me.S.Parser.ExpGainTexts - texts1, gain2 = partner.S.Parser.ExpGainTexts - texts2;
            r.Note("the monster " + (dead ? "died" : "is still alive") + "; experience text 'You gained N experience points.': primary x" + gain1 + " (last " + me.S.Parser.LastExpGain + "), partner x" + gain2 + " (last " + partner.S.Parser.LastExpGain + ")");
            r.Note("stats: experience primary " + expBefore1 + " to " + exp1 + ", partner " + expBefore2 + " to " + exp2 + "; 0xA0 packets +" + (Seen(0xA0) - stats1) + " / +" + ((partner.S.Parser.Seen.TryGetValue(0xA0, out int sn2) ? sn2 : 0) - stats2));
            if (!dead) problems.Append("the monster did not die within the time limit; ");
            else
            {
                if (gain1 == 0) problems.Append("the primary got no experience text; ");
                if (gain2 == 0) problems.Append("the partner got no experience text (shared experience off? server said: " + string.Join(" | ", partner.ServerTexts(0).TakeLast(2).Concat(me.ServerTexts(0).TakeLast(2))) + "); ");
                if (exp1 <= expBefore1) problems.Append("the primary's experience did not rise (0xA0); ");
                if (exp2 <= expBefore2) problems.Append("the partner's experience did not rise (0xA0); ");
            }
            LeaveParty();
            problems.Append(markA.Diff(me, "primary"));
            problems.Append(markB.Diff(partner, "partner"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a shared kill of a " + mon.Name + ": both characters got the experience text (" + me.S.Parser.LastExpGain + " and " + partner.S.Parser.LastExpGain + ") and a stats packet that raised the experience, no parse failure");
        }

        // ------------------------------------------------------------------------------------ pvp death
        void ScPvpDeath(ScenarioResult r)
        {
            string err = EnsurePartner();
            if (err != null) { r.Skip(err); return; }
            err = MeetPartner();
            if (err != null) { r.Skip("the two characters cannot be brought together: " + err); return; }
            var markA = Mark.Of(me);
            var problems = new StringBuilder();
            if (!LeavePz(me, r)) return;
            if (!LeavePz(partner, r)) return;
            err = MeetPartner();
            if (err != null) { r.Skip("the two characters cannot be brought together outside the protection zone: " + err); return; }
            var victim = partner;
            var victimSeen = Seeing(me, victim.Character);
            var killerSeen = Seeing(victim, me.Character);
            if (victimSeen == null || killerSeen == null) { r.Skip("the characters do not see each other outside the protection zone"); return; }
            r.Note("both outside a protection zone at " + P(me.Pos) + " and " + P(victim.Pos) + ", victim health " + victim.S.Parser.Health + "/" + victim.S.Parser.MaxHealth + ", skulls before: " + killerSeen.Skull + " / " + victimSeen.Skull);
            // secure mode off on the attacker (the engine refuses an unmarked player: Combat::canTargetCreature) and on the victim (the base script data/events/scripts/creature.lua
            // checks the target's secure mode, not the attacker's: a victim with secure mode on cannot be attacked at all)
            me.S.SetFightModes(new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = false });
            victim.S.SetFightModes(new FightModes { Fight = FightModes.Defensive, Chase = false, Secure = false });
            Pump(300, () => false);
            int say0 = me.Said.Count, deaths0 = victim.S.Parser.Seen.TryGetValue(0x28, out int dn) ? dn : 0;
            int hp0 = victim.S.Parser.Health;
            byte maxKillerSkull = 0, maxVictimSkull = 0;
            me.S.Attack(victimSeen.Id);
            long end = Tick + Math.Max(60000, o.ScenarioMs);
            int tick = 0;
            while (Tick < end && !victim.S.Parser.Dead && me.S.Closed == null && victim.S.Closed == null)
            {
                Pump(250, () => victim.S.Parser.Dead);
                // the skull of the attacker, as the victim's client and the attacker's own client see it
                var ks = Seeing(victim, me.Character); if (ks != null) maxKillerSkull = Math.Max(maxKillerSkull, ks.Skull);
                var own = me.World.Player; if (own != null) maxKillerSkull = Math.Max(maxKillerSkull, own.Skull);
                var vs = Seeing(me, victim.Character); if (vs != null) maxVictimSkull = Math.Max(maxVictimSkull, vs.Skull);
                if (++tick % 8 == 0 && !victim.S.Parser.Dead) me.S.Attack(Seeing(me, victim.Character)?.Id ?? victimSeen.Id);
            }
            if (!victim.S.Parser.Dead)
            {
                var texts = me.ServerTexts(say0).Take(4).ToList();
                bool hurt = victim.S.Parser.Health < hp0 || maxKillerSkull > 0;
                string why = "the victim did not die within " + (Math.Max(60000, o.ScenarioMs) / 1000) + " s (health " + hp0 + " to " + victim.S.Parser.Health + ", attacker skull " + maxKillerSkull + ")" + (texts.Count > 0 ? "; server said: " + string.Join(" | ", texts) : "");
                if (texts.Any(x => x.IndexOf("another character from your connection", StringComparison.OrdinalIgnoreCase) >= 0))
                    why += " (the multi-client PvP block: two accounts from one IP cannot fight; Chaos.multiClient in chaos_constants.lua, and the game storage 7100990 = 1 switches it off for tests)";
                if (hurt) r.Fail(why); else r.Skip("no player versus player damage was possible here: " + why);
                return;
            }
            Pump(2000, () => false);
            var vp = victim.S.Parser;
            int deaths = (vp.Seen.TryGetValue(0x28, out int dn2) ? dn2 : 0) - deaths0;
            r.Note("death packet 0x28 on the victim x" + deaths + ": type " + vp.DeathType + ", penalty " + vp.DeathPenalty + "%; skulls seen: attacker " + maxKillerSkull + ", victim " + maxVictimSkull + "; the killer's own state: health " + me.S.Parser.Health + "/" + me.S.Parser.MaxHealth);
            if (deaths != 1) problems.Append("0x28 seen " + deaths + " times on the victim; ");
            if (vp.DeathType != 0 && vp.DeathType != 1) problems.Append("death type " + vp.DeathType + "; ");
            if (vp.DeathPenalty < 0 || vp.DeathPenalty > 100) problems.Append("death penalty " + vp.DeathPenalty + "; ");
            if (maxKillerSkull == 0) problems.Append("the attacker showed no skull on either client after an unjustified attack and kill; ");
            var texts2 = me.ServerTexts(say0).Take(4).ToList();
            if (texts2.Count > 0) r.Note("the killer's server messages: " + string.Join(" | ", texts2));
            problems.Append(markA.Diff(me, "primary"));
            if (victim.S.Parser.FailureCount > 0 || victim.Thrown.Count > 0) problems.Append("victim: " + victim.S.Parser.FailureCount + " parse failure(s), " + victim.Thrown.Count + " exception(s); ");
            // the victim logs in again
            string vname = victim.Character;
            victim.Close();
            var again = LiveClient.Connect(o, dat, o.Account2, o.Password2, vname, out string lerr);
            if (again == null) { partner = null; r.Fail("the victim's login after the death failed: " + lerr + (problems.Length > 0 ? "; " + problems : "")); return; }
            partner = again;
            bool back = WaitFor(15000, () => again.Entered || again.S.Closed != null);
            Pump(3000, () => false);
            if (!back || again.S.Closed != null) { r.Fail("the victim did not enter again after the death" + (again.S.Closed != null ? ": " + again.S.Closed : "")); return; }
            var np = again.S.Parser;
            r.Note("the victim logged in again: entered at " + P(again.Pos) + ", health " + np.Health + "/" + np.MaxHealth + ", level " + np.Level + ", dead flag " + np.Dead);
            if (np.Dead) problems.Append("the new session starts dead; ");
            if (np.Health <= 0) problems.Append("the victim comes back with " + np.Health + " health; ");
            if (np.FailureCount > 0) problems.Append("login after the death: " + np.FailureCount + " parse failure(s) (" + string.Join("; ", np.Failures.Take(3).Select(f => f.ToString())) + "); ");
            bool moved = StepAfterLogin(again);
            r.Note("a step after the death: " + (moved ? "confirmed" : "not confirmed"));
            if (!moved) problems.Append("the victim could not take a step after coming back; ");
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("player killed by player: 0x28 read on the victim (type " + vp.DeathType + ", penalty " + vp.DeathPenalty + "%), the attacker's skull " + maxKillerSkull + " parsed, the victim logged in again alive and walking");
        }
    }
}
