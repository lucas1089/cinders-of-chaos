// Regression checks of what the live run against a real server found (O433, unity/README.md "Live check (O433)"), with synthetic packets only,
// and tests of the live check's own logic (Core.LiveCheck: items.otb to item types, the opcode table, the status rules, a whole run on the
// demo tour's fake server).
//   found 2026-11-08: 0xF5 (server ProtocolGame::sendItems, sent after the login's 0x17) was an unknown opcode: the parser stopped there and the
//   rest of that packet was lost (the inventory slots after it, the stats).
using System;
using System.Collections.Generic;
using System.Linq;
using Chaos.Core.LiveCheck;

namespace Chaos.Core.Tests
{
    static class LiveCheckTests
    {
        static bool Throws<T>(Action a) where T : Exception
        {
            try { a(); } catch (T) { return true; }
            return false;
        }

        static GameParser NewParser() => new GameParser(new World(DatFile.Parse(Program.SyntheticDat())));

        public static void Run(Action<bool, string> check)
        {
            ItemList(check);
            Tooltip(check);
            PartyShields(check);
            FloorChanges(check);
            Market(check);
            ExperienceTexts(check);
            WalkSkipsStairs(check);
            Failures(check);
            Otb(check);
            Plan(check);
            Status(check);
            WholeRun(check);
        }

        // ------------------------------------------------------------------------------------------------ 0xF5
        static void ItemList(Action<bool, string> check)
        {
            // server: 0xF5, u16 count (11 slot types + the inventory ids), then per entry u16 client id, u8 0, u16 1
            var w = new ByteWriter().U8(0xF5).U16(3);
            for (int i = 1; i <= 3; i++) w.U16((ushort)(i + 2000)).U8(0).U16(1);
            w.U8(0x1D).U8(0x15).Str("after the list");   // a ping and a text message follow in the same packet
            var p = NewParser();
            string text = null;
            int pings = 0;
            p.Text = t => text = t;
            p.Pinged = () => pings++;
            bool threw = false;
            try { p.Parse(w.ToArray()); } catch (ProtocolException) { threw = true; }
            check(!threw, "0xF5: the item list is read");
            check(p.ItemListCount == 3, "0xF5: the count is kept (" + p.ItemListCount + ")");
            check(pings == 1 && text == "after the list", "0xF5: the messages after the list in the same packet are read");
            check(p.FailureCount == 0 && p.Failures.Count == 0, "0xF5: no parse failure");

            // an empty list, and a list cut short (an error with the opcode and where it began)
            var p2 = NewParser();
            p2.Parse(new ByteWriter().U8(0xF5).U16(0).ToArray());
            check(p2.ItemListCount == 0 && p2.FailureCount == 0, "0xF5: an empty list");
            var p3 = NewParser();
            var cut = new ByteWriter().U8(0x1D).U8(0xF5).U16(2).U16(2001).U8(0).ToArray();   // the second entry is missing
            check(Throws<ProtocolException>(() => p3.Parse(cut)), "0xF5: a cut list throws");
            check(p3.Failures.Count == 1 && p3.Failures[0].Op == 0xF5 && p3.Failures[0].Start == 1 && !p3.Failures[0].Unknown, "0xF5: the failure names the opcode and its offset");
        }

        // ------------------------------------------------------------------------------------------------ 0x9E
        static void Tooltip(Action<bool, string> check)
        {
            // server ProtocolGame::sendTooltipData: 0x9E, u8 count, per entry u8 id, u8 1 + u8 negative + u32 abs + u32 type, or u8 0 + string
            var w = new ByteWriter().U8(0x9E).U8(4);
            w.U8(3).U8(0).Str("test blade");                                  // name (text)
            w.U8(18).U8(1).U8(0).U32(1).U32(0xFFFFFFFF);                      // count (number, no type)
            w.U8(1).U8(1).U8(0).U32(35).U32(0xFFFFFFFF);                      // attack 35
            w.U8(14).U8(1).U8(1).U32(2).U32(5);                               // a skill entry, negative, type 5
            w.U8(0x1D).U8(0x15).Str("after the tooltip");                     // more messages in the same packet
            var p = NewParser();
            string text = null;
            int pings = 0, got = 0;
            p.Text = t => text = t;
            p.Pinged = () => pings++;
            p.TooltipRead = l => got = l.Count;
            bool threw = false;
            try { p.Parse(w.ToArray()); } catch (ProtocolException) { threw = true; }
            check(!threw && p.FailureCount == 0, "0x9E: the tooltip data is read");
            var t0 = p.LastTooltip;
            check(t0 != null && t0.Count == 4 && got == 4 && p.TooltipCount == 1, "0x9E: four entries, the callback ran");
            check(t0 != null && BaseTooltip.Name(t0) == "test blade" && !t0[0].IsNumber, "0x9E: the name is a text entry");
            check(t0 != null && t0[1].IsNumber && t0[1].Value == 1 && t0[1].Type == -1, "0x9E: a number without a type reads as -1");
            check(t0 != null && t0[2].Value == 35 && t0[3].Value == -2 && t0[3].Type == 5, "0x9E: the negative flag and the type are kept");
            check(pings == 1 && text == "after the tooltip", "0x9E: the messages after it in the same packet are read");

            // an empty list, a cut list, a bad entry kind
            var p2 = NewParser();
            p2.Parse(new ByteWriter().U8(0x9E).U8(0).ToArray());
            check(p2.LastTooltip != null && p2.LastTooltip.Count == 0 && p2.FailureCount == 0, "0x9E: an empty list");
            var p3 = NewParser();
            check(Throws<ProtocolException>(() => p3.Parse(new ByteWriter().U8(0x1D).U8(0x9E).U8(2).U8(3).U8(0).Str("one").ToArray())), "0x9E: a cut list throws");
            check(p3.Failures.Count == 1 && p3.Failures[0].Op == 0x9E && p3.Failures[0].Start == 1 && !p3.Failures[0].Unknown, "0x9E: the failure names the opcode and its offset");
            var p4 = NewParser();
            check(Throws<ProtocolException>(() => p4.Parse(new ByteWriter().U8(0x9E).U8(1).U8(3).U8(7).ToArray())), "0x9E: an entry kind that is neither number nor text throws");

            // the requests (server parseTooltip)
            var rv = BaseTooltip.RequestVirtual(2160, 3);
            check(rv.Length == 6 && rv[0] == 0x9F && rv[1] == 0 && rv[2] == 0x70 && rv[3] == 0x08 && rv[4] == 3, "0x9F kind 0: sprite id and count");
            var ri = BaseTooltip.RequestItem(new Pos(0xFFFF, 3, 0), 2160, 1);
            check(ri.Length == 10 && ri[0] == 0x9F && ri[1] == 1 && ri[2] == 0xFF && ri[3] == 0xFF && ri[4] == 3 && ri[5] == 0 && ri[6] == 0 && ri[7] == 0x70 && ri[8] == 0x08 && ri[9] == 1,
                  "0x9F kind 1: position, sprite id, stack position");
        }

        // ------------------------------------------------------------------------------------------------ party shields
        // found 2026-11-08 (phase 21, a real party on a local server): the server shows the inviting leader to the invited player as white and yellow (1) and the
        // invited player to the leader as white and blue (2) (Player::getPartyShield); the menu rules had them the other way round, so Join never showed.
        static void PartyShields(Action<bool, string> check)
        {
            var p = NewParser();
            var w = p.W;
            var leader = new Creature { Id = 0x10000001, Name = "Leader", Type = 0 };
            w.AddThing(new Pos(100, 100, 7), new Thing { Creature = leader });
            w.Creatures[leader.Id] = leader;
            p.Parse(new ByteWriter().U8(0x91).U32(leader.Id).U8(1).ToArray());   // what the invited player is sent for the leader
            check(leader.Shield == 1, "0x91: the shield byte is kept (" + leader.Shield + ")");
            check(PartyShield.InvitedYou(leader.Shield) && !PartyShield.InvitedByYou(leader.Shield), "party shield 1 (white and yellow) means the creature invited us");
            check(PartyMenu.For(PartyShield.None, 1).Contains(PartyAction.Join), "party menu: the leader's white and yellow shield offers Join");
            check(PartyMenu.For(PartyShield.Yellow, 2).Contains(PartyAction.Revoke) && !PartyMenu.For(PartyShield.Yellow, 2).Contains(PartyAction.Join), "party menu: the invited player's white and blue shield offers Revoke to the leader");
            check(!PartyMenu.For(PartyShield.None, 2).Contains(PartyAction.Join), "party menu: white and blue does not offer Join");
        }

        // ------------------------------------------------------------------------------------------------ floor changes and block flags of items.otb
        static void FloorChanges(Action<bool, string> check)
        {
            var o = new List<byte> { 0, 0, 0, 0 };
            o.Add(0xFE); o.Add(0);
            o.AddRange(new byte[] { 0, 0, 0, 0, 1, 4, 0, 1, 0, 0, 0 });
            Node(o, 1, 0, 300, 400);                 // a stair the xml names (floorchange down)
            Node(o, 1, 1u << 9, 301, 401);           // a stair by the otb flag (north)
            Node(o, 1, 0, 302, 402);                 // a plain floor
            Node(o, 5, 1u << 0, 303, 403);           // blocks solid
            Node(o, 5, 1u << 2, 304, 404);           // blocks path finding only
            Node(o, 5, 1u << 1, 305, 405);           // blocks missiles
            o.Add(0xFF);
            var otb = o.ToArray();
            string xml = "<items>\n<item id=\"300\" name=\"stairs\">\n<attribute key=\"floorchange\" value=\"Down\" />\n</item>\n<item id=\"302\" name=\"floor\" />\n" +
                         "<item fromid=\"310\" toid=\"312\" name=\"ramp\"><attribute key=\"floorchange\" value=\"south\" /></item>\n</items>";
            var fc = OtbDat.FloorChanges(xml, otb);
            check(fc.TryGetValue(400, out string v) && v == "down", "floor changes: the xml value, lower case, by client id");
            check(fc.TryGetValue(401, out v) && v == "north", "floor changes: the otb flag bits count");
            check(!fc.ContainsKey(402) && !fc.ContainsKey(310), "floor changes: a plain item, and an id range the otb lacks, give none");
            var dat = OtbDat.Build(otb);
            check(dat.Item(403).NotWalkable && !dat.Item(403).BlockPath && dat.Item(404).BlockPath && !dat.Item(404).NotWalkable && dat.Item(405).BlockMissile && !dat.Item(402).NotWalkable,
                  "otb: the block flags set NotWalkable, BlockPath and BlockMissile");
        }

        // ------------------------------------------------------------------------------------------------ the stock market, 0xF6 to 0xF9 (phase 22)
        // The server never sends them (patch_market.py), but an unknown opcode costs the rest of the packet, so the four are read. The layouts are the writers of
        // ProtocolGame::sendMarketEnter, sendMarketLeave, sendMarketDetail, sendMarketBrowseItem, sendMarketAcceptOffer, sendMarketBrowseOwnOffers, sendMarketBrowseOwnHistory.
        static ByteWriter U64(ByteWriter w, ulong v) => w.Raw(BitConverter.GetBytes(v));

        static void Market(Action<bool, string> check)
        {
            // 0xF6: u64 bank balance, u8 own offers, u16 count, then u16 ware id and u16 amount each
            var w = U64(new ByteWriter().U8(0xF6), 123456789012UL).U8(3).U16(2).U16(2160).U16(40).U16(2148).U16(7);
            w.U8(0x1D);
            var p = NewParser();
            int pings = 0;
            p.Pinged = () => pings++;
            p.Parse(w.ToArray());
            var m = p.Market;
            check(m.Open && m.Balance == 123456789012UL && m.OwnOfferCount == 3 && m.Depot.Count == 2 && m.Depot[2160] == 40 && m.Depot[2148] == 7, "0xF6: the balance, the offer count and the depot goods are read");
            check(pings == 1 && p.FailureCount == 0, "0xF6: the packet after it is read, no failure");
            p.Parse(new ByteWriter().U8(0xF7).U8(0x1D).ToArray());
            check(!m.Open && m.Left == 1 && pings == 2, "0xF7: leaving closes the market and the next packet is read");

            // 0xF9, one ware: u16 id, u32 buy count, each u32 timestamp, u16 counter, u16 amount, u32 price, string; the same for the sell offers
            var b = new ByteWriter().U8(0xF9).U16(2160).U32(2);
            b.U32(1000).U16(1).U16(5).U32(900).Str("Alice");
            b.U32(1001).U16(2).U16(9).U32(850).Str("Bob");
            b.U32(1);
            b.U32(1002).U16(0).U16(3).U32(1200).Str("Carol");
            b.U8(0x1D);
            p.Parse(b.ToArray());
            check(m.BrowseItem == 2160 && m.Buy.Count == 2 && m.Sell.Count == 1 && m.Buy[1].Player == "Bob" && m.Buy[1].Price == 850 && m.Sell[0].Amount == 3 && m.Sell[0].ItemId == 2160, "0xF9: a ware's buy and sell offers");
            check(pings == 3 && p.FailureCount == 0, "0xF9: browse, the packet after it is read");

            // the accept answer (sendMarketAcceptOffer): the same layout with one offer on one side and none on the other
            var acc = new ByteWriter().U8(0xF9).U16(2160).U32(1).U32(1003).U16(4).U16(2).U32(700).Str("Dan").U32(0).U8(0x1D);
            p.Parse(acc.ToArray());
            check(m.Buy.Count == 1 && m.Sell.Count == 0 && m.Buy[0].Player == "Dan", "0xF9: an accepted buy offer");

            // own offers (sendMarketBrowseOwnOffers, also sendMarketCancelOffer): u16 0xFFFE, u32 count, each u32 timestamp, u16 counter, u16 ware, u16 amount, u32 price
            var own = new ByteWriter().U8(0xF9).U16(0xFFFE).U32(1).U32(2000).U16(3).U16(2148).U16(10).U32(5).U32(2).U32(2001).U16(0).U16(2160).U16(1).U32(99).U32(2002).U16(1).U16(2152).U16(20).U32(100).U8(0x1D);
            p.Parse(own.ToArray());
            check(m.OwnKind == 0xFFFE && m.OwnBuy.Count == 1 && m.OwnSell.Count == 2 && m.OwnSell[1].ItemId == 2152 && m.OwnSell[1].Price == 100 && m.OwnBuy[0].ItemId == 2148, "0xF9: own offers (0xFFFE)");

            // history (sendMarketBrowseOwnHistory): each entry also has a u8 state
            var hist = new ByteWriter().U8(0xF9).U16(0xFFFF).U32(1).U32(3000).U16(0).U16(2148).U16(2).U32(8).U8(1).U32(1).U32(3001).U16(1).U16(2160).U16(1).U32(9).U8(2).U8(0x1D);
            p.Parse(hist.ToArray());
            check(m.OwnKind == 0xFFFF && m.OwnBuy[0].State == 1 && m.OwnSell[0].State == 2 && m.OwnSell[0].ItemId == 2160, "0xF9: own history (0xFFFF) with the state byte");

            // 0xF8 detail (sendMarketDetail): u16 id, 15 strings (an empty one is a u16 0), then two blocks of u8 flag and four u32 when 1
            var d = new ByteWriter().U8(0xF8).U16(2160);
            for (int i = 0; i < BaseMarket.DetailLines; i++) { if (i == 0) d.Str("12"); else if (i == 14) d.Str("1.20 oz"); else d.U16(0); }
            d.U8(1).U32(4).U32(4000).U32(1200).U32(800).U8(0).U8(0x1D);
            p.Parse(d.ToArray());
            check(m.Detail != null && m.Detail.ItemId == 2160 && m.Detail.Lines[0] == "12" && m.Detail.Lines[1] == "" && m.Detail.Lines[14] == "1.20 oz", "0xF8: the 15 text lines");
            check(m.Detail.Purchases != null && m.Detail.Purchases[0] == 4 && m.Detail.Purchases[3] == 800 && m.Detail.Sales == null, "0xF8: the purchase statistics, none for the sales");
            check(p.FailureCount == 0 && pings == 7, "0xF8: no failure, the packets after every market packet are read (" + pings + ")");

            // a cut packet throws with the opcode named
            var cut = NewParser();
            check(Throws<ProtocolException>(() => cut.Parse(new ByteWriter().U8(0x1D).U8(0xF9).U16(2160).U32(2).U32(1).ToArray())), "0xF9: a cut offer list throws");
            check(cut.Failures.Count == 1 && cut.Failures[0].Op == 0xF9 && !cut.Failures[0].Unknown, "0xF9: the failure names the opcode and is not marked unknown");

            // the client packets (server parseMarketLeave, parseMarketBrowse, parseMarketCreateOffer, parseMarketCancelOffer, parseMarketAcceptOffer)
            check(BaseMarket.LeaveRequest().Length == 1 && BaseMarket.LeaveRequest()[0] == 0xF4, "0xF4: leave");
            var br = BaseMarket.BrowseRequest(BaseMarket.OwnOffers);
            check(br.Length == 3 && br[0] == 0xF5 && br[1] == 0xFE && br[2] == 0xFF, "0xF5: browse own offers");
            var cr = BaseMarket.CreateRequest(true, 2160, 5, 0x01020304, true);
            check(cr.Length == 11 && cr[0] == 0xF6 && cr[1] == 1 && cr[2] == 0x70 && cr[3] == 0x08 && cr[4] == 5 && cr[5] == 0 && cr[6] == 4 && cr[7] == 3 && cr[8] == 2 && cr[9] == 1 && cr[10] == 1, "0xF6: type, ware, amount, price, anonymous");
            var cn = BaseMarket.CancelRequest(0xAABBCCDD, 7);
            check(cn.Length == 7 && cn[0] == 0xF7 && cn[1] == 0xDD && cn[4] == 0xAA && cn[5] == 7, "0xF7: timestamp and counter");
            var ac = BaseMarket.AcceptRequest(1, 2, 3);
            check(ac.Length == 9 && ac[0] == 0xF8 && ac[1] == 1 && ac[5] == 2 && ac[7] == 3, "0xF8: timestamp, counter, amount");
        }

        // ------------------------------------------------------------------------------------------------ experience texts (phase 22, shared kill)
        static void ExperienceTexts(Action<bool, string> check)
        {
            check(ExperienceText.TryParse("You gained 150 experience points.", out long n) && n == 150, "experience text: the plural");
            check(ExperienceText.TryParse("You gained 1 experience point.", out n) && n == 1, "experience text: the singular");
            check(!ExperienceText.TryParse("You gained 15.3k experience points.", out _) && !ExperienceText.TryParse("You lost 5 experience points.", out _) && !ExperienceText.TryParse("You gained x experience points.", out _) && !ExperienceText.TryParse(null, out _), "experience text: other texts give false");
            // the server's text message with a position and the amount (kind 26): counted, and the amount kept; a damage number of the same shape is only counted
            var w = new ByteWriter().U8(0xB4).U8(26).U16(100).U16(100).U8(7).U32(150).U8(215).Str("You gained 150 experience points.");
            w.U8(0xB4).U8(23).U16(100).U16(100).U8(7).U32(30).U8(180).U32(0).U8(0).Str("");
            w.U8(0x1D);
            var p = NewParser();
            int pings = 0;
            p.Pinged = () => pings++;
            p.Parse(w.ToArray());
            check(p.NumberMessages == 2 && p.ExpGainTexts == 1 && p.LastExpGain == 150 && pings == 1 && p.FailureCount == 0, "experience text: a kind 26 message is counted with its amount, a damage message only counted (" + p.NumberMessages + "/" + p.ExpGainTexts + ")");
        }

        // ------------------------------------------------------------------------------------------------ the walk sweep and stairs (phase 22)
        // found 2026-11-08 (phase 22): the 8 step sweep of a run that starts beside a stair stepped onto it and ended on another floor, so the step counted as
        // wrong. A direction whose target tile holds a floor change item is not tried now.
        static void WalkSkipsStairs(Action<bool, string> check)
        {
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            var fc = new Dictionary<int, string> { { 400, "down" }, { 401, "north" } };
            w.AddThing(new Pos(101, 100, 7), new Thing { Item = new Item { Id = 400 } });                         // east of the start: a stair
            w.AddThing(new Pos(100, 99, 7), new Thing { Item = new Item { Id = 100 } });                          // north: plain ground
            w.AddThing(new Pos(100, 99, 7), new Thing { Item = new Item { Id = 401 } });                          // ... with a ramp on it (the second thing of the tile counts too)
            w.AddThing(new Pos(99, 101, 7), new Thing { Item = new Item { Id = 100 } });                          // south west: plain ground only
            var from = new Pos(100, 100, 7);
            check(LiveRun.StepsOntoFloorChange(w, fc, from, Dir.East), "walk sweep: a stair east of the start is not stepped on");
            check(LiveRun.StepsOntoFloorChange(w, fc, from, Dir.North), "walk sweep: a ramp among the things of the north tile counts");
            check(!LiveRun.StepsOntoFloorChange(w, fc, from, Dir.SouthWest), "walk sweep: plain ground is walked");
            check(!LiveRun.StepsOntoFloorChange(w, fc, from, Dir.West), "walk sweep: a tile not in view is not a stair");
            check(!LiveRun.StepsOntoFloorChange(w, null, from, Dir.East) && !LiveRun.StepsOntoFloorChange(w, new Dictionary<int, string>(), from, Dir.East), "walk sweep: without floor change data every direction is walked");
            check(Array.IndexOf(LiveRun.AllScenarios, "sell") >= 0 && Array.IndexOf(LiveRun.AllScenarios, "market") >= 0 && Array.IndexOf(LiveRun.AllScenarios, "floorchange") >= 0 &&
                  Array.IndexOf(LiveRun.AllScenarios, "sharedkill") >= 0 && Array.IndexOf(LiveRun.AllScenarios, "pvpdeath") >= 0 && LiveRun.AllScenarios.Distinct().Count() == LiveRun.AllScenarios.Length, "scenarios: the phase 22 names are listed once");
            // a server line quoted in a scenario must not put a character or account name into a report (the pvp scenario quotes "The murder of X was not justified")
            string scrubbed = LiveRun.Scrub("Warning! The murder of Aldric Voss was not justified. aldric voss, ALDRIC again; ab is short", new[] { "Aldric Voss", "ALDRIC", "ab", null, "" });
            check(scrubbed == "Warning! The murder of <name> was not justified. <name>, <name> again; ab is short", "scrub: names (any case, longest first) go, names under 3 characters stay (" + scrubbed + ")");
        }

        // ------------------------------------------------------------------------------------------------ the failure record
        static void Failures(Action<bool, string> check)
        {
            var p = NewParser();
            var bad = new ByteWriter().U8(0x1D).U8(0xE9).U8(0x00).ToArray();   // 0xE9 is no opcode of the server
            check(Throws<ProtocolException>(() => p.Parse(bad)), "failure record: an unknown opcode throws");
            check(p.FailureCount == 1 && p.Failures.Count == 1, "failure record: one failure");
            var f = p.Failures[0];
            check(f.Op == 0xE9 && f.Start == 1 && f.Unknown && f.Message.Contains("unknown opcode"), "failure record: opcode 0xE9 at offset 1, marked unknown (" + f + ")");
            check(p.Seen.TryGetValue(0xE9, out int n) && n == 1 && p.Seen[0x1D] == 1, "failure record: the packet types seen count both");

            var p2 = NewParser();
            check(Throws<ProtocolException>(() => p2.Parse(new ByteWriter().U8(0x15).U16(500).ToArray())), "failure record: a string past the end throws");
            check(p2.Failures.Count == 1 && p2.Failures[0].Op == 0x15 && !p2.Failures[0].Unknown && p2.Failures[0].Stop >= p2.Failures[0].Start, "failure record: a read error is not marked unknown");

            var p3 = NewParser();
            for (int i = 0; i < GameParser.MaxFailures + 50; i++) Throws<ProtocolException>(() => p3.Parse(new[] { (byte)0xE9 }));
            check(p3.FailureCount == GameParser.MaxFailures + 50 && p3.Failures.Count == GameParser.MaxFailures, "failure record: the list is capped, the count is not");

            // a failure does not touch the packets after it: the session reads the next packet
            var p4 = NewParser();
            int pings = 0;
            p4.Pinged = () => pings++;
            Throws<ProtocolException>(() => p4.Parse(new[] { (byte)0xE9 }));
            p4.Parse(new[] { (byte)0x1D });
            check(pings == 1 && p4.FailureCount == 1, "failure record: the next packet is read");
        }

        // ------------------------------------------------------------------------------------------------ items.otb to item types
        /// <summary>One OTB node as the file has it: start byte, group, u32 flags, attributes, end byte, with 0xFD 0xFE 0xFF escaped.</summary>
        static void Node(List<byte> o, byte group, uint flags, int server, int client, int top = -1)
        {
            var pl = new List<byte>();
            pl.AddRange(BitConverter.GetBytes(flags));
            pl.Add(0x10); pl.Add(2); pl.Add(0); pl.Add((byte)server); pl.Add((byte)(server >> 8));
            pl.Add(0x11); pl.Add(2); pl.Add(0); pl.Add((byte)client); pl.Add((byte)(client >> 8));
            if (top >= 0) { pl.Add(0x2B); pl.Add(1); pl.Add(0); pl.Add((byte)top); }
            o.Add(0xFE); o.Add(group);
            foreach (byte b in pl) { if (b == 0xFD || b == 0xFE || b == 0xFF) o.Add(0xFD); o.Add(b); }
            o.Add(0xFF);
        }

        static void Otb(Action<bool, string> check)
        {
            var o = new List<byte> { 0, 0, 0, 0 };   // version word
            o.Add(0xFE); o.Add(0);                   // the root node
            o.AddRange(new byte[] { 0, 0, 0, 0, 1, 4, 0, 1, 0, 0, 0 });
            Node(o, 1, 0, 100, 200);                         // ground
            Node(o, 5, 1u << 7, 101, 201);                   // stackable
            Node(o, 12, 0, 102, 202);                        // fluid container
            Node(o, 11, 0, 103, 203);                        // splash
            Node(o, 5, 1u << 24, 104, 204);                  // animation: a phase byte
            Node(o, 5, 1u << 13, 105, 205, 1);               // always on top, order 1: a border
            Node(o, 5, 1u << 13, 106, 206, 2);               // order 2: bottom
            Node(o, 5, 1u << 13, 107, 207, 3);               // order 3: top
            Node(o, 5, 0, 253, 253);                         // 253 is 0xFD: an escaped byte in the ids
            Node(o, 5, 0, 108, 0);                           // no client id: left out
            o.Add(0xFF);                                     // end of the root
            var nodes = OtbDat.ReadNodes(o.ToArray());
            check(nodes.Count == 9, "otb: nine item nodes (" + nodes.Count + ")");
            check(nodes.Any(n => n.Server == 253 && n.Client == 253), "otb: an escaped 0xFD in an id is read back");
            var dat = OtbDat.Build(o.ToArray());
            ThingType T(int id) => dat.Item(id);
            check(T(200).Ground && !T(200).HasSubType, "otb: group 1 is ground");
            check(T(201).Stackable && T(201).HasSubType && !T(201).HasPhaseByte, "otb: stackable gets a count byte");
            check(T(202).Fluid && T(202).HasSubType, "otb: group 12 gets a fluid byte");
            check(T(203).Splash && T(203).HasSubType, "otb: group 11 gets a fluid byte");
            check(T(204).HasPhaseByte && !T(204).HasSubType, "otb: FLAG_ANIMATION gets a phase byte");
            check(T(205).GroundBorder && T(206).OnBottom && T(207).OnTop, "otb: the top order picks border, bottom and top");
            check(World.StackPriority(new Thing { Item = new Item { Id = 205, Type = T(205) } }) < World.StackPriority(new Thing { Item = new Item { Id = 206, Type = T(206) } }) &&
                  World.StackPriority(new Thing { Item = new Item { Id = 207, Type = T(207) } }) < World.StackPriority(new Thing { Item = new Item { Id = 253, Type = T(253) } }),
                  "otb: border, bottom and top stack before plain items");
            check(T(150) == null, "otb: an id the file does not have is not a type");

            // the types decide how many bytes an item takes: a stackable and an animated item on a tile
            var p = new GameParser(new World(dat));
            var w = new ByteWriter().U8(0x6A).U16(100).U16(100).U8(7).U8(1);
            w.U16(201).U8(0xFF).U8(5);              // stackable: count byte
            w.U8(0x6A).U16(100).U16(100).U8(7).U8(2);
            w.U16(204).U8(0xFF).U8(1);              // animated: phase byte
            w.U8(0x1D);
            int pings = 0;
            p.Pinged = () => pings++;
            p.Parse(w.ToArray());
            check(pings == 1 && p.FailureCount == 0, "otb: the item bytes follow the types (a count byte, a phase byte)");
        }

        // ------------------------------------------------------------------------------------------------ the opcode table
        static void Plan(Action<bool, string> check)
        {
            var plan = LiveOps.Plan();
            check(LiveOps.CatalogMissing().Count == 0, "plan: every module of the fake module catalog is in the table (" + string.Join(",", LiveOps.CatalogMissing()) + ")");
            check(plan.Select(x => x.Op).Distinct().Count() == plan.Count, "plan: no opcode twice");
            check(plan.All(x => x.Kind != "request" || x.Action.Length > 0), "plan: a request has an action");
            check(plan.Count(x => x.Kind == "request") >= 60, "plan: at least 60 requests (" + plan.Count(x => x.Kind == "request") + ")");
            check(!plan.Any(x => x.Op == ClientGuard.ChallengeOpcode || x.Op == ClientGuard.HelloOpcode), "plan: the guard opcodes are the session's, not in the table");
            check(plan.Any(x => x.Op == BankState.Opcode && x.Action == "openBank"), "plan: the bank is opened with openBank, as the window does");
        }

        // ------------------------------------------------------------------------------------------------ the status rules
        static void Status(Action<bool, string> check)
        {
            OpStat S(string kind, bool text = false) => new OpStat { Plan = new OpPlan { Op = 1, Name = "x", Kind = kind, Text = text } };
            var a = S("request"); a.Sent = 1;
            check(a.Status() == "no_reply", "status: a request with no answer is no_reply");
            a.RepliesAfterSend = 1;
            check(a.Status() == "ok", "status: a request with an answer is ok");
            a.Invalid = 1;
            check(a.Status() == "parse_error", "status: invalid JSON is a parse error");
            a.Invalid = 0; a.HandlerErrors = 1;
            check(a.Status() == "parse_error", "status: a handler exception is a parse error");
            check(S("request").Status() == "not_sent", "status: a request that never went out is not_sent");
            var t = S("request", true); t.Sent = 1; t.RawReplies = 1;
            check(t.Status() == "ok", "status: a text opcode answers with raw packets");
            var s = S("session"); check(s.Status() == "session_no_reply", "status: session, silent");
            s.Replies = 1; check(s.Status() == "session_ok", "status: session, answered");
            var p = S("push"); check(p.Status() == "push_not_seen", "status: push, not seen");
            p.RawReplies = 1; check(p.Status() == "push_seen", "status: push, seen");
        }

        // ------------------------------------------------------------------------------------------------ a whole run on the fake server
        static void WholeRun(Action<bool, string> check)
        {
            var demo = Hd2dDemo.Synthetic();
            var art = TourArt.FromDemo(DemoIds.Synthetic()).Probe(demo.Dat);
            using (var server = new FakeGameServer(art) { ModuleResponder = true })
            {
                server.Begin();
                var opt = new LiveOptions
                {
                    Host = "127.0.0.1", Port = server.Port, Account = "demo-account-x", Password = "demo-password-x", Seconds = 1,
                    GuardKey = server.GuardKey, Rsa = server.RsaModulus, WarmMs = 200, ReplyWaitMs = 60, SettleMs = 5,
                };
                // the fake login port takes any account: only the shape of the run matters here
                var run = new LiveRun(opt, demo.Dat, "synthetic");
                int code = run.Execute();
                var json = run.JsonReport();   // a Dictionary: Json.Get reads it like a parsed object
                string text = run.TextReport(), raw = Json.Serialize(json);
                var login = Json.Get(json, "login") as Dictionary<string, object>;
                check(login != null && login["ok"] is bool lb && lb, "whole run: the login worked (" + (login == null ? "no login block" : login["error"]) + ")");
                var enter = Json.Get(json, "enter") as Dictionary<string, object>;
                check(enter != null && enter["ok"] is bool eb && eb, "whole run: the game was entered");
                var walk = Json.Get(json, "walk") as Dictionary<string, object>;
                check(walk != null && Convert.ToInt32(walk["directions"]) == 8 && Convert.ToInt32(walk["confirmed"]) >= 1, "whole run: eight directions, the server confirmed steps (" + (walk == null ? "none" : walk["confirmed"].ToString()) + ")");
                check(Json.TryParse(raw) is Dictionary<string, object>, "whole run: the JSON report parses back");
                check(!raw.Contains("demo-account-x") && !raw.Contains("demo-password-x") && !text.Contains("demo-account-x") && !text.Contains("demo-password-x"),
                      "whole run: no account name and no password in either report");
                check(!raw.Contains(FakeGameServer.HeroName), "whole run: no character name in the report");
                var ext = Json.Get(json, "extended") as Dictionary<string, object>;
                check(ext != null && Convert.ToInt32(ext["table"]) == LiveOps.Plan().Count, "whole run: the extended table is in the report");
                check(code == 0 || code == 1, "whole run: an exit code (" + code + ")");
            }
        }
    }
}
