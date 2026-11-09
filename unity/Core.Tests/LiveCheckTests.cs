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

        static string Hex(byte[] b) => string.Concat(b.Select(x => x.ToString("x2")));

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
            SecureModeRule(check);
            SecureModeSession(check);
            ModalTalesFlow(check);
            BagCount(check);
            RiftBossHud(check);
            ScenarioList(check);
            EndgameScenarioList(check);
            OmenAndFailedRiftHud(check);
            ExtErrorCount(check);
            Phase25ScenarioList(check);
            LastLifeAndTwinHud(check);
            Phase26ScenarioList(check);
            SoloDeathHudAndNova(check);
            Phase27ScenarioList(check);
            FirstHourHelpers(check);
            Phase28ScenarioList(check);
            WelcomeToastOpensHelper(check);
            SystemUnlockAnnouncement(check);
            QuestLogWire(check);
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
        // ------------------------------------------------------------------------------------------------ secure mode (phase 23)
        static void SecureModeRule(Action<bool, string> check)
        {
            // the default is secure on, like the main client, and the wire byte is 1 for on (Player::secureMode, found live in phase 22)
            var def = new FightModes();
            check(def.Secure && def.Packet()[3] == 1, "secure: the default is on and goes out as byte 1");
            check(new FightModes { Secure = false }.Packet()[3] == 0, "secure: off goes out as byte 0");
            check(FightModes.Decode("").Secure && FightModes.Decode("2,0,1").Secure && !FightModes.Decode("2,0,0").Secure, "secure: no saved choice means on, 1 is on, 0 is off");
            var back = FightModes.Decode(new FightModes { Fight = FightModes.Defensive, Chase = true, Secure = false }.Encode());
            check(back.Fight == FightModes.Defensive && back.Chase && !back.Secure && back.Packet()[3] == 0, "secure: the saved form round-trips an off choice");
            check(FightModes.Decode(new FightModes().Encode()).Packet()[3] == 1, "secure: the saved form round-trips the default");

            // the guard of a match: the arena, the battleground and the Marches hold secure off and give it back
            var modes = new FightModes { Fight = FightModes.Offensive, Chase = true, Secure = true };
            var sent = new List<FightModes>();
            var g = new SecureGuard(() => modes, m => { modes = m; sent.Add(m); });
            check(!g.Active && g.Before == null, "secure guard: nothing held at the start");
            g.Off();
            check(g.Active && g.Before == true && !modes.Secure && sent.Count == 1 && sent[0].Packet()[3] == 0, "secure guard: a match sends secure off (byte 0) once");
            check(modes.Fight == FightModes.Offensive && modes.Chase, "secure guard: fight and chase modes are kept");
            g.Off();
            check(sent.Count == 1 && g.Before == true, "secure guard: a second match inside the first sends nothing and keeps the first choice");
            g.On();
            check(modes.Secure && sent.Count == 2 && sent[1].Packet()[3] == 1 && !g.Active && modes.Fight == FightModes.Offensive && modes.Chase, "secure guard: the end of the match sends secure on (byte 1)");
            g.On();
            check(sent.Count == 2, "secure guard: an end without a match sends nothing");

            // a player who runs with secure off keeps it off
            modes = new FightModes { Secure = false };
            sent.Clear();
            g.Off();
            check(sent.Count == 0 && g.Before == false, "secure guard: secure already off, nothing is sent");
            g.On();
            check(sent.Count == 0 && !modes.Secure, "secure guard: and nothing is turned on afterwards");

            // the Fight window while a match holds secure off: the window shows off, the saved choice stays on
            modes = new FightModes { Fight = FightModes.Balanced, Secure = true };
            g.Off();
            var shown = new FightModes { Fight = FightModes.Defensive, Chase = false, Secure = modes.Secure };
            var saved = g.ToSave(shown, false);
            check(saved.Secure && saved.Fight == FightModes.Defensive, "secure guard: changing the fight mode during a match saves the player's own secure choice (on)");
            check(g.ToSave(new FightModes { Secure = true }, true).Secure, "secure guard: a change of the switch itself is saved as chosen");
            g.UserChose(false);
            check(g.Before == false && !g.ToSave(shown, false).Secure, "secure guard: after the player turns it off in the window, off is their choice");
            sent.Clear();
            g.On();
            check(!modes.Secure && sent.Count == 0, "secure guard: and the match's end does not turn it on");
            modes = new FightModes { Secure = true };
            check(!new SecureGuard(() => modes, m => modes = m).ToSave(new FightModes { Secure = false }, false).Secure, "secure guard: with no match, the window's state is saved as shown");
            g.Off();
            g.Reset();
            check(!g.Active, "secure guard: a new session holds nothing");
        }

        /// <summary>A new session starts with secure mode on and keeps the modes it is given; the packet is the one the window shows.</summary>
        static void SecureModeSession(Action<bool, string> check)
        {
            var world = new World(DatFile.Parse(Program.SyntheticDat()));
            var s = new GameSession(world, new GameSession.Options { Host = "127.0.0.1", Port = 1, Account = "a", Password = "b", Character = "c" });
            check(s.Modes.Secure && s.Modes.Packet()[3] == 1, "secure: a new session starts with secure mode on");
            s.SetFightModes(new FightModes { Secure = false });
            check(!s.Modes.Secure && s.Modes.Packet()[3] == 0, "secure: the session keeps the mode it was given");
            s.Dispose();
        }

        // ------------------------------------------------------------------------------------------------ modal windows, the tales list (phase 23)
        static void ModalTalesFlow(Action<bool, string> check)
        {
            // what the Archivist's "tales" sends (tales.lua sendList): window 7170 with Read (1) and Close (2) and one choice per tale, then the tale as window 7171 after the answer
            var p = NewParser();
            var sent = new List<byte[]>();
            p.Modals.Send = x => sent.Add(x);
            var list = new ByteWriter().U8(0xFA).U32(7170).Str("Tales").Str("Choose a tale.").U8(2).Str("Read").U8(1).Str("Close").U8(2).U8(3).Str("The first").U8(1).Str("The second").U8(2).Str("The third").U8(3).U8(2).U8(1).U8(0);
            list.U8(0x1D);   // a ping in the same packet
            int pings = 0;
            p.Pinged = () => pings++;
            p.Parse(list.ToArray());
            var w = p.Modals.Current;
            check(w != null && w.Id == 7170 && w.Buttons.Count == 2 && w.Choices.Count == 3 && w.Choices[2].Text == "The third" && w.EscapeButton == 2 && w.EnterButton == 1 && !w.Priority && pings == 1 && p.FailureCount == 0,
                  "modal tales: the list window and the ping behind it are read");
            check(p.Modals.Received == 1 && Hex(ModalWindows.AnswerPacket(7170, 1, 1)) == "f9" + "021c0000" + "01" + "01", "modal tales: the answer packet is 0xF9, id 7170 (02 1c 00 00), Read, first choice");
            p.Modals.Answer(1, 1);
            check(sent.Count == 1 && Hex(sent[0]) == "f9021c00000101" && p.Modals.Current == null, "modal tales: answering sends the packet and takes the window off");
            var tale = new ByteWriter().U8(0xFA).U32(7171).Str("The first").Str("A long tale text.").U8(2).Str("Accept").U8(1).Str("Close").U8(3).U8(0).U8(3).U8(1).U8(0);
            p.Parse(tale.ToArray());
            check(p.Modals.Current != null && p.Modals.Current.Id == 7171 && p.Modals.Current.Choices.Count == 0 && p.Modals.Received == 2, "modal tales: the server's reaction is window 7171 without choices");
            p.Modals.Cancel();
            check(sent.Count == 2 && Hex(sent[1]) == "f9031c0000" + "03" + "ff" && p.Modals.Current == null, "modal tales: escape answers with the escape button (3) and no choice (ff)");
            // a window without buttons or title is still read and answered with button 0
            p.Parse(new ByteWriter().U8(0xFA).U32(5).Str("").Str("").U8(0).U8(0).U8(0).U8(0).U8(0).ToArray());
            check(p.Modals.Current != null && p.Modals.Current.Buttons.Count == 0 && p.Modals.Answer(0, ModalWindows.NoChoice) && Hex(sent[2]) == "f90500000000ff", "modal tales: an empty window is read and answered");
            // a truncated window is a parse failure with the opcode, not a hang
            var p2 = NewParser();
            bool threw = false;
            try { p2.Parse(new ByteWriter().U8(0xFA).U32(9).Str("T").ToArray()); } catch (ProtocolException) { threw = true; }
            check(threw || p2.FailureCount > 0, "modal tales: a cut window is a failure");
        }

        // ------------------------------------------------------------------------------------------------ the bag count of the sell scenario (phase 23)
        static void BagCount(Action<bool, string> check)
        {
            var p = NewParser();
            check(LiveRun.CarriedCount(p, 101) == 0, "bag count: nothing carried is 0");
            var w = new ByteWriter().U8(0x6E).U8(2).U16(100).U8(0xFF).Str("Backpack").U8(20).U8(1).U8(1).U8(0).U16(2).U16(0).U8(2);
            w.U16(101).U8(0xFF).U8(5).U8(0).U16(100).U8(0xFF);
            p.Parse(w.ToArray());
            check(LiveRun.CarriedCount(p, 101) == 5 && LiveRun.CarriedCount(p, 100) == 1, "bag count: a stack counts its size, a single item 1");
            p.Parse(new ByteWriter().U8(0x70).U8(2).U16(0).U16(101).U8(0xFF).U8(9).U8(0).ToArray());
            check(LiveRun.CarriedCount(p, 101) == 14, "bag count: an item added to the open bag shows");
            p.Parse(new ByteWriter().U8(0x72).U8(2).U16(0).U16(0).ToArray());
            check(LiveRun.CarriedCount(p, 101) == 5, "bag count: an item taken out is gone");
            p.Parse(new ByteWriter().U8(0x6F).U8(2).ToArray());
            check(LiveRun.CarriedCount(p, 101) == 0, "bag count: a closed bag shows nothing (the scenario opens the backpack again before it judges)");
            // items.otb group 2 is a container: the sell scenario opens the bags inside the backpack and the riftboss one finds the chest by id
            var o = new List<byte> { 0, 0, 0, 0 };
            o.Add(0xFE); o.Add(0);
            o.AddRange(new byte[] { 0, 0, 0, 0, 1, 4, 0, 1, 0, 0, 0 });
            Node(o, 2, 0, 300, 400);
            Node(o, 5, 0, 301, 401);
            o.Add(0xFF);
            var dat = OtbDat.Build(o.ToArray());
            check(dat.Item(400).Container && !dat.Item(401).Container, "otb: group 2 is a container");
        }

        // ------------------------------------------------------------------------------------------------ the rift boss HUD (phase 23)
        static void RiftBossHud(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            double now = 1000;
            var r = new RiftHud(ext) { Clock = () => now };
            var seq = new List<string>();
            r.Changed = () => seq.Add(r.Boss + "/" + r.State + "/" + r.Killed);
            Action<string> msg = json => ext.Receive(228, ExtOpcodes.ToWire(json));
            // what rift.lua sends live (hudData): start waiting, updates while the packs die, the guardian alive, the end
            msg("{\"action\":\"start\",\"data\":{\"tier\":1,\"theme\":\"Ash\",\"left\":600,\"limit\":600,\"total\":240,\"killed\":0,\"bossAt\":180,\"boss\":\"waiting\",\"state\":\"running\",\"bossName\":\"Sanctum Warden\",\"mods\":[],\"notes\":[\"2 more packs gather.\"]}}");
            msg("{\"action\":\"update\",\"data\":{\"tier\":1,\"left\":580,\"limit\":600,\"total\":240,\"killed\":150,\"bossAt\":180,\"boss\":\"waiting\",\"state\":\"running\",\"bossName\":\"Sanctum Warden\"}}");
            check(r.BossPercent() == 83 && r.BossLine() == "Guardian in 30 kills", "rift boss: the guardian line counts the kills still needed");
            msg("{\"action\":\"update\",\"data\":{\"tier\":1,\"left\":570,\"limit\":600,\"total\":240,\"killed\":240,\"bossAt\":180,\"boss\":\"alive\",\"state\":\"running\",\"bossName\":\"Sanctum Warden\"}}");
            check(r.Boss == "alive" && r.BossLine() == "The guardian Sanctum Warden is here!" && r.BossPercent() == 100, "rift boss: alive after bossAt kills");
            msg("{\"action\":\"end\",\"data\":{\"result\":\"success\",\"text\":\"The rift is sealed! Open the chest within 60 seconds.\",\"exitIn\":60}}");
            check(r.State == "success" && r.Boss == "dead" && r.Result == "success" && r.ExitIn == 60 && r.BossLine() == "The guardian is slain." && r.Active, "rift boss: the end message seals the run and keeps the HUD for the exit time");
            check(r.HideAt == now + 62000, "rift boss: the HUD hides 2 s after the exit");
            check(seq.Count == 4 && seq[0] == "waiting/running/0" && seq[3] == "dead/success/240", "rift boss: the HUD went waiting, waiting, alive, dead (" + string.Join(" > ", seq) + ")");
            // a second end message (the rift script sends one at the exit too) does not break the state
            msg("{\"action\":\"end\",\"data\":{\"result\":\"left\",\"text\":\"\",\"exitIn\":0}}");
            check(r.Active && r.Result == "left", "rift boss: a second end message at the exit is read");
            // a failed rift (the staff command or the timer)
            var r2 = new RiftHud(ext);
            r2.Handle("start", Json.TryParse("{\"tier\":1,\"boss\":\"waiting\",\"state\":\"running\",\"total\":10,\"bossAt\":8}"));
            r2.Handle("end", Json.TryParse("{\"result\":\"failed\",\"text\":\"A gamemaster closed the rift.\",\"exitIn\":5}"));
            check(r2.State == "failed" && r2.Boss == "waiting" && r2.ResultText.StartsWith("A gamemaster"), "rift boss: a failed end keeps the boss state and shows the text");
        }

        static void ScenarioList(Action<bool, string> check)
        {
            var all = LiveRun.AllScenarios.ToList();
            check(all.Contains("modal") && all.Contains("riftboss") && all.IndexOf("riftboss") > all.IndexOf("rift") && all.IndexOf("modal") < all.IndexOf("party"), "scenarios: modal and riftboss are in the list, riftboss after rift");
            var o = new LiveOptions();
            check(o.ModalNpc == "Archivist Maelis" && o.ModalWord == "tales" && o.RiftKill == "/rkill" && o.RiftNear == "/rnear" && o.RiftChestServerId == 32311 && o.RiftChestFallbackServerId == 21584, "scenarios: the defaults of the phase 23 options");
        }


        // ------------------------------------------------------------------------------------------------ endgame scenarios (phase 24)
        static void EndgameScenarioList(Action<bool, string> check)
        {
            var all = LiveRun.AllScenarios.ToList();
            check(all.Contains("moremodals") && all.IndexOf("moremodals") > all.IndexOf("modal") && all.IndexOf("moremodals") < all.IndexOf("party"), "endgame scenarios: moremodals follows modal");
            bool order = true;
            foreach (string n in new[] { "partyrift", "rifttier", "riftfail", "omen", "coffer" })
                order &= all.Contains(n) && all.IndexOf(n) > all.IndexOf("riftboss") && all.IndexOf(n) < all.IndexOf("death");
            check(order, "endgame scenarios: partyrift, rifttier, riftfail, omen and coffer run after riftboss and before the death scenarios");
            check(all.Count == all.Distinct().Count() && all[all.Count - 1] == "pvpdeath" && all[all.Count - 2] == "death", "endgame scenarios: no name twice, the two death scenarios last");
            var o = new LiveOptions();
            check(o.RiftTier == 2 && o.RiftMods == null && o.RiftFailSeconds == 12 && o.RiftTime == "/rtime" && o.RiftGo == "/rgo" && o.RiftKeys == "/rkeys", "endgame scenarios: the defaults of the rift options");
            check(o.OmenKeyServerId == 32072 && o.CofferServerId == 32312 && o.CofferFallbackServerId == 12664 && o.KeeperNpc == "Keeper of Trials" && !o.KeeperAt.HasValue, "endgame scenarios: the item ids and the Keeper default");
        }

        // The HUD of an Omen arena and of a rift that ran out of time, as rift.lua sends them (hudData: omen, title, total 0, bossAt 0; fail: an end message without exitIn).
        static void OmenAndFailedRiftHud(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            double now = 5000;
            var r = new RiftHud(ext) { Clock = () => now };
            Action<string> msg = json => ext.Receive(228, ExtOpcodes.ToWire(json));
            msg("{\"action\":\"start\",\"data\":{\"tier\":15,\"theme\":\"Ashen Crypt\",\"left\":720,\"limit\":720,\"total\":0,\"killed\":0,\"bossAt\":0,\"boss\":\"waiting\",\"state\":\"running\",\"bossName\":\"Sangrith the Bloodmoon Herald\",\"mods\":[],\"notes\":[],\"lives\":3,\"livesMax\":3,\"omen\":\"Bloodmoon\",\"title\":\"Omen - Bloodmoon\"}}");
            check(r.Active && r.Omen == "Bloodmoon" && r.Title == "Omen - Bloodmoon" && r.Total == 0 && r.BossAt == 0 && r.Lives == 3 && r.LivesMax == 3, "omen HUD: the start message names the omen, the title and the shared lives");
            check(r.BossLine() == "The guardian Sangrith the Bloodmoon Herald is coming..." && r.BossPercent() == 100, "omen HUD: the waiting guardian line is 'coming', not a kill count (bossAt 0)");
            msg("{\"action\":\"update\",\"data\":{\"tier\":15,\"left\":715,\"limit\":720,\"total\":0,\"killed\":0,\"bossAt\":0,\"boss\":\"alive\",\"state\":\"running\",\"bossName\":\"Sangrith the Bloodmoon Herald\",\"omen\":\"Bloodmoon\",\"title\":\"Omen - Bloodmoon\"}}");
            check(r.Boss == "alive" && r.BossLine() == "The guardian Sangrith the Bloodmoon Herald is here!", "omen HUD: the guardian comes after the start delay");
            msg("{\"action\":\"end\",\"data\":{\"result\":\"success\",\"text\":\"The guardian falls! Open its chest within 60 seconds.\",\"exitIn\":60}}");
            check(r.State == "success" && r.Boss == "dead" && r.Omen == "Bloodmoon" && r.HideAt == now + 62000, "omen HUD: the end message keeps the omen and the exit time");
            // a rift that ran out of time: removePlayer sends {result = "failed", text} with no exitIn; the players leave at once
            var f = new RiftHud(ext) { Clock = () => now };
            f.Handle("start", Json.TryParse("{\"tier\":2,\"boss\":\"waiting\",\"state\":\"running\",\"total\":205,\"killed\":139,\"bossAt\":154,\"lives\":3,\"livesMax\":3}"));
            f.Handle("end", Json.TryParse("{\"result\":\"failed\",\"text\":\"Time is up! The rift collapses and the key is lost.\"}"));
            check(f.Result == "failed" && f.State == "failed" && f.Boss == "waiting" && f.ExitIn == 0 && f.HideAt == now + 8000 && f.ResultText.StartsWith("Time is up!"), "failed rift HUD: result failed, the boss state kept, hides after 8 s without an exit time");
            check(f.LivesLine() == "Lives: 3 / 3" && f.Killed == 139, "failed rift HUD: the lives and the kills of the last update stay");
            // a member who fell with lives left gets {result = "left"} while the run goes on for the others
            var l = new RiftHud(ext) { Clock = () => now };
            l.Handle("start", Json.TryParse("{\"tier\":1,\"boss\":\"alive\",\"state\":\"running\",\"total\":10,\"killed\":10,\"bossAt\":8,\"lives\":3,\"livesMax\":4}"));
            l.Handle("end", Json.TryParse("{\"result\":\"left\",\"text\":\"You fell: 3 lives left. You return at the rift's entrance when you log in again.\"}"));
            check(l.State == "left" && l.Boss == "alive" && l.Result == "left" && l.Lives == 3, "party rift HUD: a fallen member's 'left' end message keeps the guardian alive and the shared lives");
        }

        // LiveClient counts the extended opcode errors of its own connection (phase 24: the partner of the party rift has no per-opcode table).
        static void ExtErrorCount(Action<bool, string> check)
        {
            var world = new World(DatFile.Parse(Program.SyntheticDat()));
            var s = new GameSession(world, new GameSession.Options { Host = "127.0.0.1", Port = 1, Account = "a", Password = "b", Character = "c" });
            var c = new LiveClient(world, s, "hero");
            s.Ext.On(228, m => { if (m.Action == "boom") throw new InvalidOperationException("boom"); });
            s.Ext.Receive(228, ExtOpcodes.ToWire("{\"action\":\"start\",\"data\":{}}"));
            check(c.ExtErrors == 0, "ext errors: a good message counts nothing");
            s.Ext.Receive(228, ExtOpcodes.ToWire("not json"));
            s.Ext.Receive(228, ExtOpcodes.ToWire("{\"action\":\"boom\"}"));
            check(c.ExtErrors == 2, "ext errors: invalid JSON and a handler that threw are counted (" + c.ExtErrors + ")");
            s.Ext.Receive(228, ExtOpcodes.ToWire("{\"action\":\"start\"}"));
            check(c.ExtErrors == 2, "ext errors: the next good message goes through");
        }

        // ------------------------------------------------------------------------------------------------ phase 25
        // The five scenarios of phase 25 run after coffer and before the two death scenarios; the options and the scrub know the third account.
        static void Phase25ScenarioList(Action<bool, string> check)
        {
            var all = LiveRun.AllScenarios.ToList();
            string[] names = { "guardians", "partnerdeath", "lastlife", "party3", "trialwindows" };
            bool order = true;
            int last = all.IndexOf("coffer");
            foreach (string n in names) { int i = all.IndexOf(n); order &= i > last; last = i; }
            check(order && last < all.IndexOf("death"), "phase 25: guardians, partnerdeath, lastlife, party3 and trialwindows follow coffer in that order and run before the death scenarios");
            check(all.Count == all.Distinct().Count() && all[all.Count - 1] == "pvpdeath" && all[all.Count - 2] == "death", "phase 25: no name twice, the two death scenarios still last");
            var o = new LiveOptions();
            check(o.GuardianTier == 5 && o.TwinMods == "twin:70" && o.WrathMods == "wrath:20" && o.HitSize == 0 && o.ReflectProbe == "tier", "phase 25: the guardian, hit size and reflect probe defaults (Twin Guardians need tier 3, the Wrathful Guardian tier 4)");
            check(o.ArchivistNpc == "Archivist Odrenna" && !o.ArchivistAt.HasValue && o.Account3 == null && o.Password3 == null && o.Character3 == null, "phase 25: the Archivist default and no third account until the environment gives one");
            // the third account's names never reach a report
            string line = LiveRun.Scrub("Tester Xyzq joined the party of Tester Abcd (third-acct-77)", new[] { "Tester Xyzq", "Tester Abcd", "third-acct-77" });
            check(line == "<name> joined the party of <name> (<name>)", "phase 25: account and character names of all three connections are scrubbed (" + line + ")");
        }

        // The HUD of the two guardians (rift.lua hudData: the note 'Guardians left: N.' while a Twin Guardian lives) and of the last life: a member who falls with lives left gets
        // {result = "left"}; the next login starts the HUD again; the death that takes the last life ends the run for all with {result = "failed"} and 0 lives.
        static void LastLifeAndTwinHud(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            double now = 9000;
            var h = new RiftHud(ext) { Clock = () => now };
            Action<string> msg = json => ext.Receive(228, ExtOpcodes.ToWire(json));
            msg("{\"action\":\"update\",\"data\":{\"tier\":5,\"boss\":\"alive\",\"state\":\"running\",\"total\":300,\"killed\":240,\"bossAt\":230,\"bossName\":\"Crypt Dreadknight\",\"notes\":[\"Guardians left: 2.\"],\"lives\":4,\"livesMax\":4}}");
            check(h.Active && h.Notes.Count == 1 && h.Notes[0] == "Guardians left: 2." && h.Boss == "alive", "twin HUD: the note names two guardians left and the guardian stays alive");
            msg("{\"action\":\"update\",\"data\":{\"tier\":5,\"boss\":\"alive\",\"state\":\"running\",\"total\":300,\"killed\":240,\"bossAt\":230,\"bossName\":\"Crypt Dreadknight\",\"notes\":[\"Guardians left: 1.\"],\"lives\":4,\"livesMax\":4}}");
            check(h.Notes.Count == 1 && h.Notes[0] == "Guardians left: 1." && h.State == "running" && h.Result.Length == 0, "twin HUD: one twin down, the run goes on (no result, one note)");
            // the first death with lives left: the fallen member gets 'left', the survivors' update has one life less and the 'may still return' note
            msg("{\"action\":\"update\",\"data\":{\"tier\":1,\"boss\":\"waiting\",\"state\":\"running\",\"total\":264,\"killed\":0,\"bossAt\":198,\"notes\":[\"1 fallen player may still return.\"],\"lives\":1,\"livesMax\":4}}");
            check(h.Lives == 1 && h.LivesMax == 4 && h.LivesLine() == "Lives: 1 / 4" && h.Notes.Count == 1 && h.Notes[0].StartsWith("1 fallen player"), "last life HUD: one life left, 1 of 4, the note about the fallen player");
            msg("{\"action\":\"end\",\"data\":{\"result\":\"left\",\"text\":\"You fell: 1 life left. You return at the rift's entrance when you log in again.\"}}");
            check(h.State == "left" && h.Result == "left" && h.ResultText.IndexOf("1 life left", StringComparison.Ordinal) >= 0 && h.HideAt == now + 8000, "last life HUD: the fallen member's 'left' end text names the life left, hides after 8 s");
            // the login after the death: the server sends 'start' again, the old result goes
            msg("{\"action\":\"start\",\"data\":{\"tier\":1,\"boss\":\"waiting\",\"state\":\"running\",\"total\":264,\"killed\":3,\"bossAt\":198,\"lives\":1,\"livesMax\":4}}");
            check(h.Active && h.Result.Length == 0 && h.ResultText.Length == 0 && h.HideAt < 0 && h.State == "running" && h.Lives == 1, "last life HUD: the returning member's start clears the 'left' result");
            // the last life: the survivors' update with 0 lives, then the end message of the collapse
            msg("{\"action\":\"update\",\"data\":{\"tier\":1,\"boss\":\"waiting\",\"state\":\"failed\",\"total\":264,\"killed\":3,\"bossAt\":198,\"lives\":0,\"livesMax\":4}}");
            check(h.Lives == 0 && h.State == "failed" && h.LivesLine() == "Lives: 0 / 4", "last life HUD: 0 lives (not 'unknown') and the failed state in the update before the end");
            msg("{\"action\":\"end\",\"data\":{\"result\":\"failed\",\"text\":\"No lives are left! The rift collapses and the key is lost.\"}}");
            check(h.Result == "failed" && h.State == "failed" && h.Boss == "waiting" && h.ExitIn == 0 && h.HideAt == now + 8000 && h.ResultText.StartsWith("No lives are left!"), "last life HUD: the collapse ends the run as failed, no exit time, the boss never dead");
            // a member who was removed (dead) and never had a HUD: the end message alone shows the result
            var fresh = new RiftHud(ext) { Clock = () => now };
            fresh.Handle("end", Json.TryParse("{\"result\":\"failed\",\"text\":\"No lives are left! The rift collapses and the key is lost.\"}"));
            check(fresh.Active && fresh.State == "failed" && fresh.Result == "failed", "last life HUD: an end message without a start still shows the result");
        }

        // ------------------------------------------------------------------------------------------------ phase 26
        // riftsolodeath, omenparty and wrathnova follow trialwindows and run before the two death scenarios.
        static void Phase26ScenarioList(Action<bool, string> check)
        {
            var all = LiveRun.AllScenarios.ToList();
            string[] names = { "riftsolodeath", "omenparty", "wrathnova" };
            bool order = true;
            int last = all.IndexOf("trialwindows");
            foreach (string n in names) { int i = all.IndexOf(n); order &= i > last; last = i; }
            check(order && last < all.IndexOf("death"), "phase 26: riftsolodeath, omenparty and wrathnova follow trialwindows in that order and run before the death scenarios");
            check(all.Count == all.Distinct().Count() && all[all.Count - 1] == "pvpdeath", "phase 26: no name twice, pvpdeath still last");
        }

        // ------------------------------------------------------------------------------------------------ phase 27
        // newplayer, firstkill and firstquest open the list (a new character's first hour, in the order a player lives it), riftkilled follows riftsolodeath.
        static void Phase27ScenarioList(Action<bool, string> check)
        {
            var all = LiveRun.AllScenarios.ToList();
            check(all[0] == "newplayer" && all.IndexOf("firstkill") < all.IndexOf("firstquest") && all.IndexOf("firstquest") < all.IndexOf("tooltip"), "phase 27: newplayer opens the list, firstkill and firstquest follow in the order of a first hour, before the others");
            check(all.IndexOf("riftkilled") == all.IndexOf("riftsolodeath") + 1, "phase 27: riftkilled follows riftsolodeath");
            check(all.Count == all.Distinct().Count() && all[all.Count - 1] == "pvpdeath", "phase 27: no name twice, pvpdeath still last");
            check(LiveRun.FirstLoginWindowMs >= 40000, "phase 27: the first login window covers the Tale of Cinderhold introduction (30 s after the welcome)");
        }

        // The helpers of the first hour scenarios: a monster's name carries the level tag the server appends ("Rat [4]"), a wanted Rat takes a Cave Rat too (the first hunt and the tale
        // of the cellars count both), and the teleport items of items.xml (type = teleport, an id range too) are found through the otb ids.
        static void FirstHourHelpers(Action<bool, string> check)
        {
            check(LiveRun.BaseName("Rat [4]") == "Rat" && LiveRun.BaseName("Cave Rat [5]") == "Cave Rat" && LiveRun.BaseName("Dragon") == "Dragon" && LiveRun.BaseName("Name ]") == "Name ]", "monster names: the level tag is cut off, a name without one stays");
            check(LiveRun.NameIs("Rat [4]", "Rat") && LiveRun.NameIs("Cave Rat [5]", "Rat") && LiveRun.NameIs("Cave Rat", "cave rat") && !LiveRun.NameIs("Cave Rat [5]", "Spider") && !LiveRun.NameIs("Rat [4]", "Cave Rat"), "monster names: a wanted Rat takes a Cave Rat, nothing else");
            var o = new List<byte> { 0, 0, 0, 0 };
            o.Add(0xFE); o.Add(0);
            o.AddRange(new byte[] { 0, 0, 0, 0, 1, 4, 0, 1, 0, 0, 0 });
            Node(o, 0, 0, 28013, 25358); Node(o, 0, 0, 28014, 25359); Node(o, 0, 0, 28015, 25360);   // a range of Mystic Teleport pieces
            Node(o, 0, 0, 1387, 1949);                                                                  // a single teleport item
            Node(o, 0, 0, 2120, 3003);                                                                  // a rope
            o.Add(0xFF);
            string xml = "<items>\n<item fromid=\"28013\" toid=\"28015\" name=\"Mystic Teleport\">\n<attribute key=\"type\" value=\"teleport\" />\n</item>\n" +
                         "<item id=\"1387\" name=\"magic forcefield\">\n<attribute key=\"type\" value=\"teleport\" />\n</item>\n<item id=\"2120\" name=\"rope\">\n<attribute key=\"weight\" value=\"1800\" />\n</item>\n<item id=\"2121\" name=\"x\" />\n</items>";
            var tele = OtbDat.TeleportItems(xml, o.ToArray());
            check(tele.SetEquals(new[] { 25358, 25359, 25360, 1949 }), "teleport items: the id range and the single item of items.xml map to their client ids, the rope is not one (" + string.Join(",", tele.OrderBy(x => x)) + ")");
        }

        // ------------------------------------------------------------------------------------------------ phase 28
        // questlog and firstunlock join the first hour: newplayer, questlog (the new character's empty log), firstunlock, firstkill, firstquest, then the others.
        static void Phase28ScenarioList(Action<bool, string> check)
        {
            var all = LiveRun.AllScenarios.ToList();
            check(all.IndexOf("newplayer") == 0 && all.IndexOf("questlog") == 1 && all.IndexOf("firstunlock") == 2 && all.IndexOf("firstkill") == 3 && all.IndexOf("firstquest") == 4, "phase 28: newplayer, questlog, firstunlock, firstkill, firstquest open the list in that order");
            check(all.Count == all.Distinct().Count() && all[all.Count - 1] == "pvpdeath", "phase 28: no name twice, pvpdeath still last");
            check(LiveRun.FirstUnlockLimitMs == 170000, "phase 28: a first spell unlock gets three minutes at most (170 s of hunting after the walk starts)");
        }

        // The welcome toast of a new character carries openHelper and a hint (server newplayer.lua showWelcome: {action "newplayer", message, openHelper = true, hint}); the main client
        // opens the Helper on its Auto setup button (notifications.lua newplayer, onboarding.lua; its test: onboarding_test.lua, the same expectations here).
        static void WelcomeToastOpensHelper(Action<bool, string> check)
        {
            Loc.Set("en");
            var ext = new ExtOpcodes();
            var tc = new ToastCenter(ext) { Clock = () => 0 };
            Action<string> msg = json => ext.Receive(79, ExtOpcodes.ToWire(json));
            msg("{\"action\":\"newplayer\",\"message\":\"Welcome, a new adventurer.\"}");
            check(tc.Active.Count + tc.Queue.Count == 1 && !tc.HelperRequested && tc.HelperRequests == 0, "welcome toast: a plain newplayer toast shows and does not open the Helper");
            msg("{\"action\":\"newplayer\",\"message\":\"Your first steps.\",\"openHelper\":true,\"hint\":\"Press Auto setup\"}");
            check(tc.Active.Count + tc.Queue.Count == 2 && tc.HelperRequested && tc.HelperRequests == 1 && tc.HelperHint == "Press Auto setup", "welcome toast: openHelper shows the toast and asks for the Helper with the server's hint");
            check(tc.TakeHelperRequest(out string h1) && h1 == "Press Auto setup" && !tc.HelperRequested && !tc.TakeHelperRequest(out _), "welcome toast: the window takes the request once");
            msg("{\"action\":\"newplayer\",\"message\":\"x\",\"openHelper\":true}");
            check(tc.TakeHelperRequest(out string h2) && h2 == "Set up your helper in one click", "welcome toast: no hint, the client's own text");
            msg("{\"action\":\"newplayer\",\"openHelper\":true,\"hint\":\"\"}");
            check(tc.TakeHelperRequest(out string h3) && h3 == "Set up your helper in one click", "welcome toast: an empty hint is no hint, and no message still opens the Helper");
            msg("{\"action\":\"bounty\",\"message\":\"b\",\"openHelper\":true}");
            check(!tc.HelperRequested, "welcome toast: only a newplayer message opens the Helper");
            msg("{\"action\":\"newplayer\",\"message\":\"y\",\"openHelper\":false}");
            check(!tc.HelperRequested && tc.HelperRequests == 3, "welcome toast: openHelper false does nothing");
            Loc.Set("pt-BR");
            msg("{\"action\":\"newplayer\",\"openHelper\":true}");
            check(tc.TakeHelperRequest(out string hp) && hp == "Configure seu helper com um clique", "welcome toast: the fallback hint in pt-BR");
            Loc.Set("en");
            msg("{\"action\":\"newplayer\",\"openHelper\":true}");
            tc.Clear();
            check(!tc.HelperRequested, "welcome toast: a new session forgets an unanswered request");
            // onboarding.lua: O.plan and O.blinkFrames
            check(HelperOnboarding.NeedsToggle(false) && !HelperOnboarding.NeedsToggle(true), "helper onboarding: a hidden window is opened, an open one is not closed");
            check(HelperOnboarding.HintOf("Set up", "fb") == "Set up" && HelperOnboarding.HintOf("", "fb") == "fb" && HelperOnboarding.HintOf(null, "fb") == "fb", "helper onboarding: the server hint, else the fallback");
            var f = HelperOnboarding.Frames(12000, 400);
            check(f.Length == 30 && f[0] && !f[f.Length - 1], "helper onboarding: thirty frames, gold first, ending on the button's own colour");
            check(HelperOnboarding.Frames(1000, 400).Length % 2 == 0 && HelperOnboarding.Frames(0, 400).Length == 0, "helper onboarding: an even count, no blink for no time");
            check(HelperOnboarding.Gold(0) && !HelperOnboarding.Gold(450) && HelperOnboarding.Gold(850) && !HelperOnboarding.Gold(11999) && !HelperOnboarding.Gold(12000) && !HelperOnboarding.Gold(-1), "helper onboarding: gold at the even steps, off after the time");
            check(HelperOnboarding.Active(0) && HelperOnboarding.Active(11999) && !HelperOnboarding.Active(12000) && !HelperOnboarding.Active(-1), "helper onboarding: the hint and the blink end on their own");
        }

        // Opcode 115 'new' (server unlocks.lua announcement) is a system of the top menu by key, not a spell: the level up that opens one is read as an announcement with its title and its
        // two lines. A class spell is told by name elsewhere (the Helper's level up notice: Phase7XTests SpellUnlockNames).
        static void SystemUnlockAnnouncement(Action<bool, string> check)
        {
            var ux = new ExtOpcodes();
            var mu = new MenuUnlocks(ux) { Clock = () => 0 };
            ux.Receive(115, "{\"action\":\"new\",\"data\":{\"key\":\"passive\",\"level\":12,\"menu\":\"Passive Tree\",\"title\":\"Passive Tree\",\"why\":[\"Spend points.\",\"Open it.\"]}}");
            check(mu.Announcement != null && mu.Announcement.Key == "passive" && mu.Announcement.Title == "Passive Tree" && mu.Announcement.Line2 == "Open it." && mu.Unlocked.Contains("passive"), "system unlock: opcode 115 'new' is read as the announcement (key, title, two lines)");
        }

        // The base quest log, on the wire of the base server (protocolgame.cpp sendQuestLog / sendQuestLine): the client's requests 0xF0 and 0xF1 (quest id), the answers 0xF0 (u16 count,
        // per quest u16 id, string name, u8 completed) and 0xF1 (u16 quest id, u8 count, per mission string name, string description), read to the last byte.
        static void QuestLogWire(Action<bool, string> check)
        {
            Loc.Set("en");
            var p = NewParser();
            var sent = new List<byte[]>();
            p.Quests.Send = sent.Add;
            p.Quests.Request();
            p.Quests.Select(0x01A5);
            check(sent.Count == 2 && Hex(sent[0]) == "f0" && Hex(sent[1]) == "f1a501", "quest log wire: the requests are F0 and F1 with the quest id (little endian)");
            // 0xF0: a new character holds no started quest; a log of two with Latin-1 text; the packet followed by another one in the same message
            p.Parse(new ByteWriter().U8(0xF0).U16(0).ToArray());
            check(p.Quests.Loaded && p.Quests.Quests.Count == 0 && p.FailureCount == 0, "quest log wire: F0 with no quest is read");
            var log = new ByteWriter().U8(0xF0).U16(2).U16(7).Str("Pastry Decoration").U8(0).U16(300).Str("Café Quest").U8(1);
            p.Parse(log.ToArray());
            check(p.Quests.Quests.Count == 2 && p.Quests.Quests[0].Id == 7 && p.Quests.Quests[1].Completed && p.Quests.Quests[1].Name == "Café Quest" && p.FailureCount == 0, "quest log wire: F0 with two quests, ids names and flags");
            var next = new ByteWriter().U8(0xF0).U16(1).U16(9).Str("Mines").U8(0).U8(0xA2).U16(0x0105);
            p.Parse(next.ToArray());
            check(p.Quests.Quests.Count == 1 && p.Quests.Quests[0].Name == "Mines" && p.PlayerStates == 0x0105 && p.FailureCount == 0, "quest log wire: F0 followed by another packet reads both, the second at its right place (" + p.FailureCount + " failures)");
            // 0xF1: a quest that is not started has no missions (the base server lists the started ones), then missions
            p.Parse(new ByteWriter().U8(0xF1).U16(0x01A5).U8(0).ToArray());
            var none = p.Quests.Missions(0x01A5);
            check(none != null && none.Count == 0 && p.FailureCount == 0, "quest line wire: F1 with no mission is an empty list, not a missing one");
            p.Parse(new ByteWriter().U8(0xF1).U16(7).U8(2).Str("Find it").Str("Look in the cave.").Str("Café").Str("Back to the town.").ToArray());
            var ms = p.Quests.Missions(7);
            check(ms != null && ms.Count == 2 && ms[0].Name == "Find it" && ms[0].Description == "Look in the cave." && ms[1].Name == "Café" && p.FailureCount == 0, "quest line wire: F1 with two missions, names and descriptions");
            check(p.Quests.Summary() == "0 of 1 quests done" && p.Seen.ContainsKey(0xF0) && p.Seen.ContainsKey(0xF1), "quest log wire: the summary counts the log, both packet types were counted");
        }

        // A mortal who dies alone in a rift: the end message 'left' with the lives, the next login's start clears it, the last life ends it as failed; a fresh HUD (a new
        // session after the login at the temple) is not active; a damage number of message type 24 is read as typed or plain numbers by the feed.
        static void SoloDeathHudAndNova(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            double now = 5000;
            var h = new RiftHud(ext) { Clock = () => now };
            Action<string> msg = json => ext.Receive(228, ExtOpcodes.ToWire(json));
            msg("{\"action\":\"start\",\"data\":{\"tier\":1,\"boss\":\"waiting\",\"state\":\"running\",\"total\":216,\"killed\":0,\"bossAt\":162,\"lives\":3,\"livesMax\":3}}");
            msg("{\"action\":\"end\",\"data\":{\"result\":\"left\",\"text\":\"You fell: 2 lives left. You return at the rift's entrance when you log in again.\"}}");
            check(h.Result == "left" && h.State == "left" && h.ResultText.IndexOf("2 lives left", StringComparison.Ordinal) >= 0 && h.Lives == 3, "solo death HUD: 'left' with the lives left in the text");
            msg("{\"action\":\"start\",\"data\":{\"tier\":1,\"boss\":\"waiting\",\"state\":\"running\",\"total\":216,\"killed\":0,\"bossAt\":162,\"lives\":2,\"livesMax\":3}}");
            check(h.Active && h.Result.Length == 0 && h.Lives == 2 && h.LivesLine() == "Lives: 2 / 3", "solo death HUD: the login after the death starts the HUD again with 2 lives");
            msg("{\"action\":\"update\",\"data\":{\"tier\":1,\"boss\":\"waiting\",\"state\":\"failed\",\"total\":216,\"killed\":0,\"bossAt\":162,\"lives\":0,\"livesMax\":3}}");
            msg("{\"action\":\"end\",\"data\":{\"result\":\"failed\",\"text\":\"No lives are left! The rift collapses and the key is lost.\"}}");
            check(h.Result == "failed" && h.Lives == 0 && h.ExitIn == 0, "solo death HUD: the last life ends the run as failed with 0 lives");
            check(!new RiftHud(new ExtOpcodes()).Active, "solo death HUD: a new session after the last login has no rift HUD");
            // the tiles the client forgets take their creatures off the map (a partner who stayed behind is no ghost at its last tile)
            var w = new World(null) { PlayerId = 1 };
            var me = new Creature { Id = 1, Name = "Me" };
            var far = new Creature { Id = 2, Name = "Far" };
            w.Creatures[1] = me; w.Creatures[2] = far;
            w.Center = new Pos(1000, 1000, 7);
            w.AddThing(new Pos(1000, 1000, 7), new Thing { Creature = me });
            w.AddThing(new Pos(1002, 1000, 7), new Thing { Creature = far });
            w.ForgetOutside(w.Center);
            check(far.Position.X == 1002 && me.Position.X == 1000, "forget: creatures inside the window keep their tile");
            w.Center = new Pos(1100, 1000, 7);
            w.AddThing(w.Center, new Thing { Creature = me });
            w.ForgetOutside(w.Center);
            check(far.Position.X == 0 && w.Creatures.ContainsKey(2) && me.Position.X == 1100, "forget: a creature left behind is off the map (no ghost), still known; the player keeps its tile");
        }

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
