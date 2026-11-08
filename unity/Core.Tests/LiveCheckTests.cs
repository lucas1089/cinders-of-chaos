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
