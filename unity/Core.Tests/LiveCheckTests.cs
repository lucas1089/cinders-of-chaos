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
