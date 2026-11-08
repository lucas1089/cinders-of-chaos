// One live run: login, enter, parse, walk, extended opcode sweep, report. Single threaded: everything happens in Pump, which polls the session.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Threading;

namespace Chaos.Core.LiveCheck
{
    public sealed class LiveOptions
    {
        public string Host, Account, Password, Character, Report, OtbFile, PairDir;
        public int Port = 7171, Seconds = 45;
        public bool Chaos, SkipExt;
        /// <summary>Waits in ms: after the entry for the session's own hellos, for the answer to one request, and after it for late parts (tests shorten them).</summary>
        public int WarmMs = 4500, ReplyWaitMs = 1500, SettleMs = 120;
        public byte[] GuardKey = ClientGuard.DevKey;
        public string Rsa = Protocol.OpenRsaModulus;
        // ---- play scenarios (LiveScenarios.cs), phase 21
        /// <summary>The scenarios to run: tooltip, stairs, floorchange, npc, sell, market, modal, party, sharedkill, rift, riftboss, death, pvpdeath (empty: none).</summary>
        public readonly List<string> Scenarios = new List<string>();
        /// <summary>The second account of the party and death scenarios (environment CHAOS_LIVE_ACCOUNT2, CHAOS_LIVE_PASSWORD2, CHAOS_LIVE_CHARACTER2).</summary>
        public string Account2, Password2, Character2;
        /// <summary>items.xml of the server (floor changes of stairs and holes); by default the one beside items.otb.</summary>
        public string ItemsXml;
        /// <summary>The NPC the npc scenario talks to and trades with, and where to walk to find it when it is out of view.</summary>
        public string NpcName = "Tesenna";
        public Pos? NpcAt, StairsAt;
        /// <summary>The monster the partner summons to kill the primary character in the death scenario.</summary>
        public string Killer = "Demon";
        /// <summary>The weak monster the partner summons for the shared kill (sharedkill scenario).</summary>
        public string Weak = "Rat";
        /// <summary>Server item id of the Rift Key (rift_config.lua key.itemId) the rift scenario asks the staff command for.</summary>
        public int RiftKeyServerId = 10155;
        // ---- phase 23
        /// <summary>The NPC that sends a modal window (0xFA) for the modal scenario, the word that makes it send one, and where to walk to find it. The default is the Chaos
        /// Archivist Maelis, who answers "tales" with the list of tales (modal id 7170, tales.lua).</summary>
        public string ModalNpc = "Archivist Maelis", ModalWord = "tales";
        public Pos? ModalAt;
        /// <summary>The staff chat commands the riftboss scenario uses: one that kills every monster round the staff character (it hits the rift's packs, then the guardian), and one
        /// that moves the character next to the strongest monster in range (the guardian's arena is far from the entrance). The server has neither: a local-only revscript
        /// for the run (unity/README.md "Rift boss and modal windows (phase 23)"); without them the scenario is a skip.</summary>
        public string RiftKill = "/rkill", RiftNear = "/rnear";
        /// <summary>Server item ids of the rift reward chest (rift_config.lua chest.itemId and chest.fallbackId), whose client ids the scenario looks for on the map.</summary>
        public int RiftChestServerId = 32311, RiftChestFallbackServerId = 21584;
        // ---- phase 24
        /// <summary>The tier and the fixed modifiers ("name:value,name:value", as the staff command /rift key TIER MODS takes them; empty: random) of the rifttier and riftfail
        /// scenarios. Tier 2 is the first one above the tier 1 of the earlier scenarios; the staff key allows up to rift_config.lua maxTier (15).</summary>
        public int RiftTier = 2;
        public string RiftMods;
        /// <summary>Seconds the riftfail scenario leaves the rift (the local-only staff command /rtime sets the deadline: the server's own time-up rule then fails the run).</summary>
        public int RiftFailSeconds = 12;
        /// <summary>The staff command that sets the open rift's deadline in N seconds, and the one that moves the character next to the rift's chest or coffer (local-only, like --rift-kill).</summary>
        public string RiftTime = "/rtime", RiftGo = "/rgo", RiftKeys = "/rkeys";
        /// <summary>Server item ids of the Omen Key (rift_config.lua omen.key.id) and of the Sealed Coffer (coffer.itemId, coffer.fallbackId).</summary>
        public int OmenKeyServerId = 32072, CofferServerId = 32312, CofferFallbackServerId = 12664;
        /// <summary>The Keeper of Trials (the trial window) and the NPC beside him (the Ascendant Oracle's choice) for moremodals, and where to look for them.</summary>
        public string KeeperNpc = "Keeper of Trials", OracleNpc = "Ascendant Oracle";
        public Pos? KeeperAt;
        /// <summary>The aware range asked for after the login (Chaos identity only), 0 asks for nothing.</summary>
        public int AwareWidth, AwareHeight;
        /// <summary>Time limit of one scenario in ms (the death and rift ones take their own, longer, limits from it).</summary>
        public int ScenarioMs = 60000;
    }

    /// <summary>What happened on one extended opcode.</summary>
    public sealed class OpStat
    {
        public OpPlan Plan;
        public bool Handled;                 // a Core handler is registered for it
        public int Sent;                     // requests that went out (ours and the session's own)
        public string SentAction = "";
        public double SentAt = -1;
        public int Replies;                  // complete messages: all of them
        public int RepliesAfterSend;
        public double FirstReplyMs = -1;     // from the first request to the first reply
        public int RawReplies;               // packets on this opcode, parts of a chunked message included
        public int Json, Invalid, HandlerErrors;
        public readonly List<string> Actions = new List<string>();
        public readonly List<string> Errors = new List<string>();

        /// <summary>ok, no_reply, parse_error (requests); session_ok, session_no_reply (the session asked); push_seen, push_not_seen.</summary>
        public string Status()
        {
            bool bad = Invalid > 0 || HandlerErrors > 0;
            if (Plan.Kind == "request") return Sent == 0 ? "not_sent" : bad ? "parse_error" : RepliesAfterSend > 0 || (Plan.Text && RawReplies > 0) ? "ok" : "no_reply";
            if (Plan.Kind == "session") return bad ? "parse_error" : Replies > 0 || RawReplies > 0 ? "session_ok" : "session_no_reply";
            return bad ? "parse_error" : Replies > 0 || RawReplies > 0 ? "push_seen" : "push_not_seen";
        }
    }

    public sealed class WalkResult
    {
        public string Dir = "";
        public bool Sent, Confirmed, Cancelled, PositionOk;
        /// <summary>Not tried: the target tile holds a stair, ramp or hole, and a step onto it changes the floor (phase 22; the sweep checks the plain step on the same floor).</summary>
        public bool Skipped;
        public int Dx, Dy;               // what the player moved
        public int ExpectedDx, ExpectedDy;
        public double Ms = -1;
        /// <summary>Packet types the server sent while the step was out (a refused step shows 0xB5, a confirmed one 0x6D).</summary>
        public string Packets = "";
        public int WalksSent;
    }

    public sealed partial class LiveRun
    {
        readonly LiveOptions o;
        readonly DatFile dat;
        readonly string datSource;
        World world;
        GameSession s;
        LiveClient me, partner;
        readonly Dictionary<byte, OpStat> ops = new Dictionary<byte, OpStat>();
        readonly SortedDictionary<byte, OpStat> other = new SortedDictionary<byte, OpStat>();
        readonly List<OpPlan> plan = LiveOps.Plan();
        readonly List<WalkResult> walks = new List<WalkResult>();
        readonly List<string> thrown = new List<string>();     // exceptions out of Poll (not ProtocolException): the packet type is in parser.Failures
        readonly List<string> logged = new List<string>();     // "parse:" lines and extended opcode errors
        int cancels, characters, level, vocation, chunkedReplies;
        string loginError, closed;
        bool loginOk, enterOk;
        double enterMs = -1, loginMs;
        Pos enterPos;
        int tilesMax, creaturesMax;
        string[] features = new string[0];
        double startedAt;
        /// <summary>CHAOS_LIVE_DEBUG=1 prints the first bytes of the packets of opcodes outside the table to stderr (never into the report: they can hold names).</summary>
        readonly bool debug = Environment.GetEnvironmentVariable("CHAOS_LIVE_DEBUG") == "1";

        public LiveRun(LiveOptions options, DatFile d, string source)
        {
            o = options;
            dat = d;
            datSource = source;
            world = new World(d);
            foreach (var p in plan) ops[p.Op] = new OpStat { Plan = p };
        }

        // ------------------------------------------------------------------------------------ the run
        public int Execute()
        {
            var t0 = Environment.TickCount64;
            var res = LoginClient.Login(o.Host, o.Port, o.Account, o.Password, o.Rsa).GetAwaiter().GetResult();
            loginMs = Environment.TickCount64 - t0;
            if (res.Error != null) { loginError = res.Error; return 1; }
            loginOk = true;
            characters = res.Characters.Count;
            var ch = o.Character != null ? res.Characters.FirstOrDefault(x => x.Name == o.Character) : res.Characters.FirstOrDefault();
            if (ch == null) { loginError = "no such character in the list"; return 1; }
            level = ch.Level; vocation = ch.Vocation;

            s = new GameSession(world, new GameSession.Options
            {
                Host = ch.Host, Port = ch.Port, Account = o.Account, Password = o.Password, SessionKey = res.SessionKey, Character = ch.Name,
                GuardKey = o.GuardKey, RsaModulus = o.Rsa, Identity = o.Chaos ? ClientIdentity.Chaos(30) : ClientIdentity.Extended,
                AwareWidth = o.Chaos ? o.AwareWidth : 0, AwareHeight = o.Chaos ? o.AwareHeight : 0,
            });
            me = new LiveClient(world, s, ch.Name);
            Hook();
            s.Log += m =>
            {
                if (m.StartsWith("parse:", StringComparison.Ordinal) || m.StartsWith("extended opcode", StringComparison.Ordinal))
                    if (logged.Count < 200) logged.Add(m);
            };
            startedAt = s.Now;
            s.Start();

            // entering: the login packet 0x17, the first map
            Pump(15000, () => s.Parser.LoggedIn && world.Player != null && world.Tiles.Count > 0 || s.Closed != null);
            enterOk = s.Parser.LoggedIn && world.Player != null && world.Tiles.Count > 0;
            enterMs = s.Now - startedAt;
            if (world.Player != null) enterPos = world.Player.Position;
            double enteredAt = s.Now;
            if (!enterOk) { closed = s.Closed; return 1; }

            Pump(o.WarmMs, () => s.Closed != null);   // the session's own hellos and prefetches (spells at 3 s, progression at 1.8 s)
            if (o.OtbFile != null && floorChanges == null) PrepareScenarioData();   // the floor changes, so the walk does not step onto a stair
            if (s.Closed == null) WalkAll();
            if (s.Closed == null && !o.SkipExt) Sweep();
            if (s.Closed == null && o.Scenarios.Count > 0) RunScenarios();
            Pump(Math.Max(0, o.Seconds * 1000 - (int)(s.Now - enteredAt)), () => s.Closed != null);

            closed = s.Closed;
            if (partner != null)
            {
                partnerStats = "parse failures " + partner.S.Parser.FailureCount + ", exceptions " + partner.Thrown.Count + ", packets " + partner.S.Packets;
                partnerBad = partner.S.Parser.FailureCount > 0 || partner.Thrown.Count > 0;
                foreach (var f in partner.S.Parser.Failures.Take(5)) partnerStats += " [" + f + "]";
                partner.Close();
                partner = null;
            }
            features = s.Parser.Features.All.OrderBy(f => f).Select(f => f.ToString(CultureInfo.InvariantCulture)).ToArray();
            s.Logout();
            Pump(300, () => false);
            s.Dispose();
            var tried = walks.Where(w => !w.Skipped).ToList();
            bool walkOk = tried.Count > 0 && tried.All(w => w.Confirmed || w.Cancelled) && tried.Any(w => w.Confirmed && w.PositionOk);
            return enterOk && walkOk && s.Parser.FailureCount == 0 && thrown.Count == 0 && closed == null && !ScenariosFailed ? 0 : 1;
        }

        /// <summary>Counts what the session sends and receives on the extended opcodes, without changing either.</summary>
        void Hook()
        {
            var ext = s.Ext;
            foreach (var p in plan) ops[p.Op].Handled = ext.Handles(p.Op);
            var transmit = ext.Transmit;
            ext.Transmit = pkt =>
            {
                if (pkt.Length >= 4 && pkt[0] == 0x32)
                {
                    var st = Stat(pkt[1]);
                    st.Sent++;
                    if (st.SentAt < 0) st.SentAt = s.Now;
                    int len = pkt[2] | pkt[3] << 8;
                    string text = len > 0 && 4 + len <= pkt.Length ? Encoding.UTF8.GetString(pkt, 4, len) : "";
                    var root = Chaos.Core.Json.TryParse(text);
                    string action = root != null ? Chaos.Core.Json.Text(root, "action") : text.Length > 12 ? text.Substring(0, 12) : text;
                    if (st.SentAction.Length == 0) st.SentAction = action;
                }
                transmit(pkt);
            };
            var prevLog = ext.Log;
            ext.Log = m =>
            {
                const string prefix = "extended opcode ";
                if (m.StartsWith(prefix, StringComparison.Ordinal))
                {
                    int colon = m.IndexOf(':');
                    if (colon > prefix.Length && byte.TryParse(m.Substring(prefix.Length, colon - prefix.Length), out byte op))
                    {
                        var st = Stat(op);
                        if (m.EndsWith("invalid JSON", StringComparison.Ordinal)) st.Invalid++; else st.HandlerErrors++;
                        if (st.Errors.Count < 3) st.Errors.Add(m.Substring(colon + 1).Trim());
                    }
                }
                prevLog(m);
            };
            var prevExt = s.Parser.ExtendedOpcode;
            s.Parser.ExtendedOpcode = (op, data) =>
            {
                var st = Stat(op);
                st.RawReplies++;
                if (debug && !ops.ContainsKey(op)) Console.Error.WriteLine("raw " + op + ": " + (data.Length > 160 ? data.Substring(0, 160) : data).Replace("\n", " "));
                if (data.Length > 0 && (data[0] == 'S' || data[0] == 'P' || data[0] == 'E') && data.Length < 8200) chunkedReplies++;
                prevExt(op, data);
            };
            foreach (var p in plan)
            {
                byte op = p.Op;
                if (p.Text) continue;
                ext.On(op, m =>
                {
                    var st = Stat(op);
                    st.Replies++;
                    st.Json++;
                    if (st.SentAt >= 0) st.RepliesAfterSend++;
                    if (st.FirstReplyMs < 0 && st.SentAt >= 0) st.FirstReplyMs = s.Now - st.SentAt;
                    if (m.Action.Length > 0 && !st.Actions.Contains(m.Action) && st.Actions.Count < 12) st.Actions.Add(m.Action);
                });
            }
            var prevCancel = s.Parser.WalkCancelled;
            s.Parser.WalkCancelled = d => { cancels++; prevCancel(d); };
        }

        OpStat Stat(byte op)
        {
            if (ops.TryGetValue(op, out var st)) return st;
            if (!other.TryGetValue(op, out st)) other[op] = st = new OpStat { Plan = new OpPlan { Op = op, Name = "(not in the table)" } };
            return st;
        }

        /// <summary>Polls the session until the condition holds or the time (ms) is up. A parse error costs the packet, as in the client; the run goes on.</summary>
        void Pump(int ms, Func<bool> until)
        {
            long end = Environment.TickCount64 + ms;
            while (Environment.TickCount64 < end)
            {
                try { s.Poll(); }
                catch (Exception e) when (!(e is ProtocolException))
                {
                    if (thrown.Count < 50) thrown.Add(e.GetType().Name + ": " + e.Message);
                }
                partner?.Poll();
                tilesMax = Math.Max(tilesMax, world.Tiles.Count);
                creaturesMax = Math.Max(creaturesMax, world.Creatures.Count);
                if (until()) return;
                Thread.Sleep(4);
            }
        }

        // ------------------------------------------------------------------------------------ walking
        static readonly Dir[] WalkOrder =
        {
            Dir.North, Dir.South, Dir.East, Dir.West, Dir.NorthEast, Dir.SouthWest, Dir.SouthEast, Dir.NorthWest,
        };

        void WalkAll()
        {
            foreach (var d in WalkOrder)
            {
                var r = new WalkResult { Dir = d.ToString() };
                walks.Add(r);
                WalkDirs.Delta(d, out r.ExpectedDx, out r.ExpectedDy);
                Pump(3000, () => s.CanWalk || s.Closed != null);
                var me = world.Player;
                if (me == null || !s.CanWalk) continue;
                var before = me.Position;
                if (StepsOntoFloorChange(world, floorChanges, before, d)) { r.Skipped = true; continue; }
                int moves0 = s.Parser.PlayerMoves, cancel0 = cancels, sent0 = s.WalksSent;
                var seen0 = new Dictionary<byte, int>(s.Parser.Seen);
                double t = s.Now;
                s.Walk(d);
                r.Sent = true;
                Pump(2500, () => s.Parser.PlayerMoves > moves0 || cancels > cancel0 || s.Closed != null);
                r.Confirmed = s.Parser.PlayerMoves > moves0;
                r.Cancelled = cancels > cancel0;
                r.Ms = s.Now - t;
                Pump(250, () => false);   // the glide ends, a late cancel arrives
                r.WalksSent = s.WalksSent - sent0;
                r.Packets = string.Join(" ", s.Parser.Seen.Where(kv => kv.Key != 0x1D && (!seen0.TryGetValue(kv.Key, out int n0) || n0 != kv.Value)).OrderBy(kv => kv.Key).Select(kv => kv.Key.ToString("X2")));
                var after = world.Player.Position;
                r.Dx = after.X - before.X; r.Dy = after.Y - before.Y;
                r.PositionOk = r.Confirmed && after.Z == before.Z && r.Dx == r.ExpectedDx && r.Dy == r.ExpectedDy;
                Pump(150, () => false);
            }
        }

        /// <summary>True when the tile one step from `from` in direction `d` holds a floor change item (a stair, ramp or hole by client id): stepping there changes the floor.
        /// Without floor change data (no items.otb) nothing is known and the answer is false.</summary>
        public static bool StepsOntoFloorChange(World w, Dictionary<int, string> floorChanges, Pos from, Dir d)
        {
            if (floorChanges == null || floorChanges.Count == 0) return false;
            var t = w.Get(WalkDirs.Step(from, d));
            if (t == null) return false;
            foreach (var th in t.Things)
                if (!th.IsCreature && th.Item != null && floorChanges.ContainsKey(th.Item.Id)) return true;
            return false;
        }

        // ------------------------------------------------------------------------------------ the extended opcode requests
        void Sweep()
        {
            foreach (var p in plan)
            {
                if (p.Kind != "request" || s.Closed != null) continue;
                var st = ops[p.Op];
                s.Ext.Send(p.Op, p.Action, p.Data ?? new Dictionary<string, object>());
                if (LiveOps.More.TryGetValue(p.Op, out var more)) { Pump(250, () => false); s.Ext.Send(p.Op, more.Item1, more.Item2 ?? new Dictionary<string, object>()); }
                int before = st.RawReplies;
                Pump(o.ReplyWaitMs, () => st.RawReplies > before || s.Closed != null);
                Pump(o.SettleMs, () => false);   // late parts, the server's rate limit
            }
        }

        // ------------------------------------------------------------------------------------ the reports
        int Count(string status) => ops.Values.Count(x => x.Status() == status);

        public Dictionary<string, object> JsonReport()
        {
            var rows = new List<object>();
            foreach (var p in plan)
            {
                var st = ops[p.Op];
                rows.Add(new Dictionary<string, object>
                {
                    { "opcode", (int)p.Op }, { "name", p.Name }, { "kind", p.Kind }, { "status", st.Status() }, { "request", st.SentAction },
                    { "sent", st.Sent }, { "replies", st.Replies }, { "packets", st.RawReplies }, { "json", st.Json }, { "invalidJson", st.Invalid },
                    { "handlerErrors", st.HandlerErrors }, { "replyMs", Math.Round(st.FirstReplyMs) }, { "actions", st.Actions }, { "errors", st.Errors },
                    { "coreHandler", st.Handled }, { "note", LiveOps.Silent.TryGetValue(p.Op, out var why) ? why : "" },
                });
            }
            var otherRows = new List<object>();
            foreach (var kv in other)
                otherRows.Add(new Dictionary<string, object> { { "opcode", (int)kv.Key }, { "packets", kv.Value.RawReplies }, { "json", kv.Value.Json } });
            var seen = new Dictionary<string, object>();
            if (s == null) return new Dictionary<string, object>
            {
                { "tool", "Core.LiveCheck" }, { "identity", o.Chaos ? "chaos" : "extended" }, { "itemTypes", datSource },
                { "login", new Dictionary<string, object> { { "ok", loginOk }, { "ms", Math.Round(loginMs) }, { "characters", characters }, { "error", loginError ?? "" } } },
            };
            foreach (var kv in s.Parser.Seen.OrderBy(x => x.Key)) seen["0x" + kv.Key.ToString("X2")] = kv.Value;
            var errs = new List<object>();
            foreach (var f in s.Parser.Failures)
                errs.Add(new Dictionary<string, object> { { "packetType", "0x" + f.Op.ToString("X2") }, { "offset", f.Start }, { "stoppedAt", f.Stop }, { "unknownType", f.Unknown }, { "message", f.Message } });
            var unknown = new Dictionary<string, object>();
            foreach (var g in s.Parser.Failures.Where(f => f.Unknown).GroupBy(f => f.Op)) unknown["0x" + g.Key.ToString("X2")] = g.Count();
            var walkRows = walks.Select(w => (object)new Dictionary<string, object>
            {
                { "dir", w.Dir }, { "skipped", w.Skipped }, { "sent", w.Sent }, { "confirmed", w.Confirmed }, { "cancelled", w.Cancelled }, { "positionOk", w.PositionOk },
                { "moved", new[] { w.Dx, w.Dy } }, { "expected", new[] { w.ExpectedDx, w.ExpectedDy } }, { "ms", Math.Round(w.Ms) }, { "packets", w.Packets },
            }).ToList();
            return new Dictionary<string, object>
            {
                { "tool", "Core.LiveCheck" },
                { "identity", o.Chaos ? "chaos" : "extended" },
                { "itemTypes", datSource },
                { "login", new Dictionary<string, object> { { "ok", loginOk }, { "ms", Math.Round(loginMs) }, { "characters", characters }, { "error", loginError ?? "" } } },
                { "enter", new Dictionary<string, object>
                    { { "ok", enterOk }, { "ms", Math.Round(enterMs) }, { "guardAnswered", s != null && s.GuardAnswered }, { "level", level }, { "vocation", vocation },
                      { "features", features }, { "closed", closed ?? "" } } },
                { "session", new Dictionary<string, object>
                    { { "seconds", o.Seconds }, { "packets", s?.Packets ?? 0 }, { "bytes", s?.Bytes ?? 0 }, { "tilesMax", tilesMax }, { "creaturesMax", creaturesMax },
                      { "deflatedPackets", s?.Inflater.PacketsIn ?? 0 }, { "deflatedBytesIn", s?.Inflater.BytesIn ?? 0 }, { "deflatedBytesOut", s?.Inflater.BytesOut ?? 0 },
                      { "extReceived", s?.Ext.Received ?? 0 }, { "extSent", s?.Ext.Sent ?? 0 }, { "chunkedPackets", chunkedReplies } } },
                { "packetTypes", seen },
                { "scenarios", ScenarioRows() },
                { "partner", partnerStats ?? "" },
                { "parse", new Dictionary<string, object>
                    { { "errors", s?.Parser.FailureCount ?? 0 }, { "unknownPacketTypes", unknown }, { "thrown", thrown }, { "items", errs }, { "logged", logged } } },
                { "walk", new Dictionary<string, object>
                    { { "directions", walks.Count }, { "skipped", walks.Count(w => w.Skipped) }, { "confirmed", walks.Count(w => w.Confirmed) }, { "positionOk", walks.Count(w => w.PositionOk) },
                      { "cancelled", walks.Count(w => w.Cancelled) }, { "results", walkRows } } },
                { "extended", new Dictionary<string, object>
                    { { "table", plan.Count }, { "requestOk", Count("ok") }, { "requestNoReply", Count("no_reply") }, { "requestParseError", Count("parse_error") },
                      { "requestNotSent", Count("not_sent") },
                      { "sessionOk", Count("session_ok") }, { "sessionNoReply", Count("session_no_reply") },
                      { "pushSeen", Count("push_seen") }, { "pushNotSeen", Count("push_not_seen") },
                      { "repliedWithoutCoreHandler", ops.Values.Where(x => x.RawReplies > 0 && !x.Handled).Select(x => (object)(int)x.Plan.Op).ToList() },
                      { "rows", rows }, { "notInTable", otherRows } } },
            };
        }

        public string TextReport()
        {
            var sb = new StringBuilder();
            sb.AppendLine("Core.LiveCheck report (identity " + (o.Chaos ? "chaos" : "extended") + ", item types from " + datSource + ")");
            sb.AppendLine("login: " + (loginOk ? "ok, " + characters + " characters, " + Math.Round(loginMs) + " ms" : "FAILED: " + loginError));
            if (s != null)
            {
                sb.AppendLine("enter: " + (enterOk ? "ok" : "FAILED") + " after " + Math.Round(enterMs) + " ms, guard answered " + s.GuardAnswered + ", level " + level + ", vocation " + vocation + ", entered at " + enterPos.X + "," + enterPos.Y + "," + enterPos.Z +
                              (closed != null ? ", closed: " + closed : ""));
                sb.AppendLine("features: " + (features.Length > 0 ? string.Join(",", features) : "none announced"));
                sb.AppendLine("session: " + o.Seconds + " s, " + s.Packets + " packets, " + s.Bytes + " bytes, tiles " + tilesMax + ", creatures " + creaturesMax +
                              ", extended opcode messages in " + s.Ext.Received + " out " + s.Ext.Sent +
                              ", deflated packets " + s.Inflater.PacketsIn + " (" + s.Inflater.BytesIn + " bytes in, " + s.Inflater.BytesOut + " out)");
                sb.AppendLine("packet types parsed (" + s.Parser.Seen.Count + "): " + string.Join(" ", s.Parser.Seen.OrderBy(x => x.Key).Select(x => x.Key.ToString("X2") + "x" + x.Value)));
                sb.AppendLine("parse errors: " + s.Parser.FailureCount + ", unknown packet types: " + s.Parser.Failures.Count(f => f.Unknown) + ", exceptions out of Poll: " + thrown.Count);
                foreach (var f in s.Parser.Failures.Take(20)) sb.AppendLine("  " + f);
                foreach (var t in thrown.Take(10)) sb.AppendLine("  thrown " + t);
                sb.AppendLine("walk: " + walks.Count(w => w.Confirmed) + " of " + walks.Count(w => !w.Skipped) + " steps confirmed by the server, " + walks.Count(w => w.PositionOk) + " at the right tile, " +
                              walks.Count(w => w.Cancelled) + " refused" + (walks.Any(w => w.Skipped) ? ", " + walks.Count(w => w.Skipped) + " not tried (a stair, ramp or hole on that tile)" : ""));
                foreach (var w in walks)
                    sb.AppendLine("  " + w.Dir.PadRight(10) + (w.Skipped ? "not tried (floor change tile)" : w.Sent ? (w.Confirmed ? "confirmed" : w.Cancelled ? "refused" : "no answer") : "not sent") + ", moved " + w.Dx + "," + w.Dy +
                                  " expected " + w.ExpectedDx + "," + w.ExpectedDy + (w.Ms >= 0 ? ", " + Math.Round(w.Ms) + " ms" : "") + ", packets [" + w.Packets + "]");
                ScenarioText(sb);
                sb.AppendLine("extended opcodes (" + plan.Count + " in the table): requests ok " + Count("ok") + ", no reply " + Count("no_reply") + ", parse error " + Count("parse_error") +
                              ", not sent " + Count("not_sent") + "; session asked ok " + Count("session_ok") + " no reply " + Count("session_no_reply") +
                              "; pushes seen " + Count("push_seen") + " not seen " + Count("push_not_seen"));
                sb.AppendLine("answered by an opcode no Core handler registers (the Unity window or a text opcode reads it): " +
                              string.Join(" ", ops.Values.Where(x => x.RawReplies > 0 && !x.Handled).Select(x => x.Plan.Op.ToString())));
                foreach (var p in plan)
                {
                    var st = ops[p.Op];
                    sb.AppendLine("  " + p.Op.ToString().PadLeft(3) + " " + p.Name.PadRight(20) + st.Status().PadRight(16) + (st.SentAction.Length > 0 ? "req " + st.SentAction + " " : "") +
                                  (st.Replies > 0 ? "replies " + st.Replies + " [" + string.Join(",", st.Actions) + "]" : st.RawReplies > 0 ? "packets " + st.RawReplies : "") +
                                  (st.Errors.Count > 0 ? " ERR " + string.Join(" | ", st.Errors) : "") + (LiveOps.Silent.TryGetValue(p.Op, out var why) && st.Replies == 0 ? "  (" + why + ")" : ""));
                }
                foreach (var kv in other) sb.AppendLine("  " + kv.Key.ToString().PadLeft(3) + " (not in the table)     packets " + kv.Value.RawReplies);
            }
            return sb.ToString();
        }
    }
}
