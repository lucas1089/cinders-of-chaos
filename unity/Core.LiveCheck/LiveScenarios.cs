// Play scenarios of the live check (O433 phase 21): the situations a quiet login does not reach. Each one is opt-in (--scenario stairs,npc,party,death,rift,tooltip
// or all), has a time limit, cleans up after itself and ends as pass, fail or skip with the reason. A skip says what the server or the account lacks, never
// "not tried". The scenarios drive the same Core objects the Unity client uses (GameSession, GameParser, the models) and look at what the server sends.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace Chaos.Core.LiveCheck
{
    public sealed class ScenarioResult
    {
        public string Name = "";
        /// <summary>pass, fail or skip.</summary>
        public string Status = "skip";
        public string Reason = "not run";
        public double Ms;
        public readonly List<string> Notes = new List<string>();
        public void Pass(string why) { Status = "pass"; Reason = why; }
        public void Fail(string why) { Status = "fail"; Reason = why; }
        public void Skip(string why) { Status = "skip"; Reason = why; }
        public void Note(string line) { if (Notes.Count < 60) Notes.Add(line); }
    }

    public sealed partial class LiveRun
    {
        public static readonly string[] AllScenarios = { "tooltip", "stairs", "npc", "party", "rift", "death" };

        readonly List<ScenarioResult> scenarios = new List<ScenarioResult>();
        Dictionary<int, string> floorChanges;
        Dictionary<int, int> serverToClient;
        bool ScenariosFailed => partnerBad || scenarios.Any(x => x.Status == "fail");
        static long Tick => Environment.TickCount64;

        void RunScenarios()
        {
            PrepareScenarioData();
            var want = o.Scenarios.Contains("all") ? AllScenarios.ToList() : AllScenarios.Where(n => o.Scenarios.Contains(n)).ToList();
            foreach (string name in want)
            {
                var r = new ScenarioResult { Name = name };
                scenarios.Add(r);
                if (s.Closed != null) { r.Skip("the connection was closed before it: " + s.Closed); continue; }
                long t0 = Tick;
                try
                {
                    switch (name)
                    {
                        case "tooltip": ScTooltip(r); break;
                        case "stairs": ScStairs(r); break;
                        case "npc": ScNpc(r); break;
                        case "party": ScParty(r); break;
                        case "rift": ScRift(r); break;
                        case "death": ScDeath(r); break;
                    }
                }
                catch (Exception e) { r.Fail("exception " + e.GetType().Name + ": " + e.Message); }
                r.Ms = Tick - t0;
                Pump(400, () => false);
            }
        }

        void PrepareScenarioData()
        {
            string xml = o.ItemsXml;
            if (xml == null && o.OtbFile != null)
            {
                string beside = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(o.OtbFile) ?? ".", "items.xml");
                if (System.IO.File.Exists(beside)) xml = beside;
            }
            if (o.OtbFile != null)
            {
                byte[] otb = System.IO.File.ReadAllBytes(o.OtbFile);
                serverToClient = new Dictionary<int, int>();
                foreach (var n in OtbDat.ReadNodes(otb)) serverToClient[n.Server] = n.Client;
                if (xml != null) floorChanges = OtbDat.FloorChanges(System.IO.File.ReadAllText(xml, Encoding.GetEncoding("ISO-8859-1")), otb);
            }
        }

        // ------------------------------------------------------------------------------------ helpers
        bool WaitFor(int ms, Func<bool> cond)
        {
            Pump(ms, cond);
            return cond();
        }

        static string P(Pos p) => p.X + "," + p.Y + "," + p.Z;

        static bool Arrived(Pos at, Pos goal, int range) => range > 0 ? PathFinder.Cheb(at, goal) <= range && at.Z == goal.Z : at.Equals(goal);

        /// <summary>Walks the client to the goal tile, or within `range` tiles of it, over the tiles it sees. A goal out of view is approached by the known tile nearest to it,
        /// re-planned after every step. With stopOnFloor a change of floor ends the walk as success (the way onto a stair tile). The reason is set when it fails.</summary>
        bool WalkTo(LiveClient a, Pos goal, int range, int timeoutMs, bool stopOnFloor, out string why)
        {
            why = "";
            long end = Tick + timeoutMs;
            int refused = 0, stuck = 0;
            int z0 = a.Pos.Z;
            while (Tick < end)
            {
                if (a.S.Closed != null) { why = "connection closed: " + a.S.Closed; return false; }
                var meC = a.World.Player;
                if (meC == null) { why = "no player"; return false; }
                var pos = meC.Position;
                if (stopOnFloor && pos.Z != z0) return true;
                if (Arrived(pos, goal, range)) return true;
                if (pos.Z != goal.Z && !stopOnFloor) { why = "the goal is on floor " + goal.Z + ", we are on " + pos.Z; return false; }
                var world = a.World;
                uint id = world.PlayerId;
                Func<Pos, bool> walkable = p => Passable(world, p, id);
                var path = PathFinder.Find(pos, goal, walkable, range);
                if (path == null)
                {
                    // out of view or behind a wall: the reachable known tile nearest to the goal (a flood fill over the tiles in view)
                    var best = pos;
                    int bd = PathFinder.Cheb(pos, goal);
                    var seenT = new HashSet<Pos> { pos };
                    var queue = new Queue<Pos>();
                    queue.Enqueue(pos);
                    while (queue.Count > 0)
                    {
                        var cur = queue.Dequeue();
                        int d = PathFinder.Cheb(cur, goal);
                        if (d < bd) { bd = d; best = cur; }
                        foreach (var dir in WalkDirs.All)
                        {
                            var np = WalkDirs.Step(cur, dir);
                            if (seenT.Contains(np) || !walkable(np)) continue;
                            seenT.Add(np);
                            queue.Enqueue(np);
                        }
                    }
                    if (best.Equals(pos))
                    {
                        // what walls the reachable area in: the item ids of the blocked tiles next to it (a closed door shows here)
                        var wall = new SortedDictionary<string, int>();
                        foreach (var rt in seenT)
                            foreach (var dir in WalkDirs.All)
                            {
                                var np = WalkDirs.Step(rt, dir);
                                if (seenT.Contains(np)) continue;
                                var nt = world.Get(np);
                                if (nt == null) { wall["void"] = wall.TryGetValue("void", out int v0) ? v0 + 1 : 1; continue; }
                                string key = string.Join("/", nt.Things.Where(th => !th.IsCreature).Select(th => th.Item.Id.ToString(CultureInfo.InvariantCulture) + (th.Item.Type != null && (th.Item.Type.NotWalkable || th.Item.Type.BlockPath) ? "!" : "")));
                                if (nt.Things.Any(th => th.IsCreature && th.Creature.Id != id)) key += "+creature";
                                wall[key] = wall.TryGetValue(key, out int v1) ? v1 + 1 : 1;
                            }
                        why = "no way towards " + P(goal) + " over the tiles in view (at " + P(pos) + ", " + seenT.Count + " reachable tiles, edge: " + string.Join(" ", wall.Take(12).Select(kv => kv.Key + "x" + kv.Value)) + "; creatures near: " + string.Join(" ", world.Creatures.Values.Where(c => c.Id != id && PathFinder.Cheb(c.Position, pos) <= 8).Take(10).Select(c => "type" + c.Type + "@" + P(c.Position) + (c.Walkthrough ? "w" : ""))) + ")";
                        return false;
                    }
                    path = PathFinder.Find(pos, best, walkable, 0);
                    if (path == null || path.Count == 0) { why = "no path to the nearest known tile " + P(best) + "; neighbours " + Neighbours(a); return false; }
                }
                if (path.Count == 0) return true;
                if (!WaitFor(3000, () => a.S.CanWalk || a.S.Closed != null)) { why = "the walk never became ready (an unanswered step)"; return false; }
                if (a.S.Closed != null) continue;
                var before = a.Pos;
                int cancels0 = a.Cancels;
                a.S.Walk(path[0]);
                Pump(2500, () => !a.Pos.Equals(before) || a.Cancels > cancels0 || a.S.Closed != null);
                if (a.Cancels > cancels0) { if (++refused >= 4) { why = "the server refused " + refused + " steps near " + P(a.Pos); return false; } Pump(300, () => false); }
                else if (a.Pos.Equals(before)) { if (++stuck >= 3) { why = "no answer to steps near " + P(a.Pos); return false; } }
                else { refused = 0; stuck = 0; }
            }
            why = "time limit near " + P(a.Pos);
            return false;
        }

        static string Neighbours(LiveClient a)
        {
            var sb = new StringBuilder();
            foreach (var d in WalkDirs.All)
            {
                var t = WalkDirs.Step(a.Pos, d);
                var tile = a.World.Get(t);
                sb.Append(d + ":" + (tile == null ? "none" : string.Join("/", tile.Things.Select(th => th.IsCreature ? "c" : th.Item.Id + (th.Item.Type == null ? "?" : (th.Item.Type.Ground ? "g" : "") + (th.Item.Type.NotWalkable ? "S" : "") + (th.Item.Type.BlockPath ? "P" : ""))))) + " ");
            }
            return sb.ToString();
        }

        /// <summary>WalkMap.Walkable, and a stair, ramp or hole tile whose floor change item is not the ground in the item types built from items.otb.</summary>
        bool Passable(World w, Pos p, uint selfId)
        {
            if (WalkMap.Walkable(w, p, selfId)) return true;
            var t = w.Get(p);
            if (t == null || FloorChangeOf(t) == null) return false;
            foreach (var th in t.Things)
            {
                if (th.IsCreature) { if (th.Creature.Id != selfId && !th.Creature.Walkthrough) return false; continue; }
                var ty = th.Item?.Type;
                if (ty != null && ty.NotWalkable) return false;   // a stair blocks the server's own path finding (otb flag), a step onto it works
            }
            return true;
        }

        string FloorChangeOf(Tile t)
        {
            if (floorChanges == null || t == null) return null;
            foreach (var th in t.Things)
                if (!th.IsCreature && th.Item != null && floorChanges.TryGetValue(th.Item.Id, out string v)) return v;
            return null;
        }

        static int FloorDelta(string kind) => kind == "down" ? 1 : -1;

        /// <summary>The parser failures and the unmatched moves, to see whether a scenario step added any.</summary>
        sealed class Mark
        {
            public int Failures, Unmatched, Thrown;
            public static Mark Of(LiveClient c) => new Mark { Failures = c.S.Parser.FailureCount, Unmatched = c.S.Parser.MoveUnmatched, Thrown = c.Thrown.Count };
            public string Diff(LiveClient c, string who)
            {
                var sb = new StringBuilder();
                if (c.S.Parser.FailureCount > Failures) sb.Append(who + ": " + (c.S.Parser.FailureCount - Failures) + " parse failure(s) (" + string.Join("; ", c.S.Parser.Failures.Skip(Failures).Take(3).Select(f => f.ToString())) + "); ");
                if (c.S.Parser.MoveUnmatched > Unmatched) sb.Append(who + ": " + (c.S.Parser.MoveUnmatched - Unmatched) + " move(s) of a creature not where the message said; ");
                if (c.Thrown.Count > Thrown) sb.Append(who + ": exception " + c.Thrown[Thrown] + "; ");
                return sb.ToString();
            }
        }

        // ------------------------------------------------------------------------------------ tooltip
        void ScTooltip(ScenarioResult r)
        {
            var p = s.Parser;
            var mark = Mark.Of(me);
            int answered = 0, asked = 0;
            var problems = new StringBuilder();
            int slot = -1;
            for (int i = 1; i < p.Inventory.Length; i++) if (p.Inventory[i] != null && p.Inventory[i].Id > 0) { slot = i; break; }
            if (slot > 0)
            {
                var it = p.Inventory[slot];
                int n0 = p.TooltipCount;
                asked++;
                s.RequestTooltip(GameSession.InventoryPos(slot), (ushort)it.Id, 1);
                if (WaitFor(3000, () => p.TooltipCount > n0))
                {
                    answered++;
                    var list = p.LastTooltip;
                    r.Note("worn item slot " + slot + ": " + list.Count + " entries, name '" + BaseTooltip.Name(list) + "', ids " + string.Join(",", list.Select(e => e.Id.ToString(CultureInfo.InvariantCulture))));
                    if (BaseTooltip.Name(list).Length == 0) problems.Append("the worn item's tooltip has no name; ");
                }
                else problems.Append("no tooltip for the worn item in slot " + slot + "; ");
            }
            else r.Note("no worn item to ask about");
            // an item known only by its sprite id: the ground under the player
            ushort sprite = 0;
            var tile = world.Get(me.Pos);
            if (tile != null) foreach (var th in tile.Things) if (!th.IsCreature && th.Item != null && th.Item.Id > 100) { sprite = (ushort)th.Item.Id; break; }
            if (sprite == 0 && slot > 0) sprite = (ushort)p.Inventory[slot].Id;
            if (sprite != 0)
            {
                int n0 = p.TooltipCount;
                asked++;
                s.RequestTooltip(null, sprite, 1);
                if (WaitFor(3000, () => p.TooltipCount > n0))
                {
                    answered++;
                    var list = p.LastTooltip;
                    r.Note("virtual item (sprite " + sprite + "): " + list.Count + " entries, name '" + BaseTooltip.Name(list) + "'");
                    if (BaseTooltip.Name(list).Length == 0) problems.Append("the virtual item's tooltip has no name; ");
                }
                else problems.Append("no tooltip for the sprite id " + sprite + "; ");
            }
            problems.Append(mark.Diff(me, "primary"));
            if (asked == 0) r.Skip("no item to ask about (no worn item, no ground item under the player)");
            else if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass(answered + " of " + asked + " tooltip requests answered with 0x9E, parsed, no failure");
        }

        // ------------------------------------------------------------------------------------ stairs
        /// <summary>The nearest stair, ramp or hole tile in view that the player can walk to, with its kind. Null when there is none.</summary>
        (Pos tile, string kind)? FindFloorChange(LiveClient a, int wantDelta)
        {
            if (floorChanges == null) return null;
            var here = a.Pos;
            var world = a.World;
            uint id = world.PlayerId;
            var cands = new List<(Pos, string, int)>();
            foreach (var kv in world.Tiles)
            {
                if (kv.Key.Z != here.Z) continue;
                string kind = FloorChangeOf(kv.Value);
                if (kind == null) continue;
                if (wantDelta != 0 && FloorDelta(kind) != wantDelta) continue;
                cands.Add((kv.Key, kind, PathFinder.Cheb(here, kv.Key)));
            }
            foreach (var c in cands.OrderBy(x => x.Item3).Take(12))
            {
                var path = PathFinder.Find(here, c.Item1, pp => Passable(world, pp, id), 0);
                if (path != null && path.Count > 0) return (c.Item1, c.Item2);
            }
            return null;
        }

        /// <summary>Walks onto a stair tile and checks what the server did: the floor, the landing, the view's centre, the next step.</summary>
        bool TakeStairs(LiveClient a, Pos tile, string kind, ScenarioResult r, string label, StringBuilder problems)
        {
            var from = a.Pos;
            var mark = Mark.Of(a);
            var seen0 = new Dictionary<byte, int>(a.S.Parser.Seen);
            if (!WalkTo(a, tile, 0, 30000, true, out string why)) { problems.Append(label + ": " + why + "; "); return false; }
            Pump(1200, () => false);   // the floor change packets and the map slices that follow the step
            var to = a.Pos;
            int dz = FloorDelta(kind);
            r.Note(label + ": " + kind + " stair at " + P(tile) + ", " + P(from) + " to " + P(to));
            if (to.Z != from.Z + dz) { problems.Append(label + ": expected floor " + (from.Z + dz) + ", the player is on " + to.Z + "; "); return false; }
            if (Math.Abs(to.X - tile.X) > 2 || Math.Abs(to.Y - tile.Y) > 2) problems.Append(label + ": landed " + P(to) + ", " + PathFinder.Cheb(to, tile) + " tiles from the stair; ");
            var packets = string.Join(" ", a.S.Parser.Seen.Where(kv => kv.Key != 0x1D && (!seen0.TryGetValue(kv.Key, out int n0) || n0 != kv.Value)).OrderBy(kv => kv.Key).Select(kv => kv.Key.ToString("X2", CultureInfo.InvariantCulture)));
            r.Note(label + ": packet types in the change [" + packets + "]");
            if (!a.World.Center.Equals(to)) problems.Append(label + ": the view is centred on " + P(a.World.Center) + ", the player stands on " + P(to) + "; ");
            var t = a.World.Get(to);
            if (t == null || !t.Things.Any(th => th.IsCreature && th.Creature.Id == a.World.PlayerId)) problems.Append(label + ": the player's tile on the new floor has no player on it; ");
            int around = 0, total = 0;
            for (int dx = -3; dx <= 3; dx++) for (int dy = -3; dy <= 3; dy++) { total++; if (a.World.Tiles.ContainsKey(new Pos(to.X + dx, to.Y + dy, to.Z))) around++; }
            r.Note(label + ": " + around + " of " + total + " tiles round the landing are known");
            if (around < total / 3) problems.Append(label + ": only " + around + " of " + total + " tiles round the landing came with the change; ");
            problems.Append(mark.Diff(a, "primary"));
            return true;
        }

        void ScStairs(ScenarioResult r)
        {
            if (floorChanges == null) { r.Skip("no items.xml: the floor changes of stairs and holes come from it (--items-xml, or the file beside items.otb)"); return; }
            var start = me.Pos;
            var found = FindFloorChange(me, 0);
            if (found == null && o.StairsAt.HasValue)
            {
                var hint = o.StairsAt.Value;
                if (hint.Z != start.Z) { r.Skip("no stair in view and the --stairs-at hint is on floor " + hint.Z + ", the player on " + start.Z); return; }
                WalkTo(me, hint, 3, o.ScenarioMs, false, out string approach);
                r.Note("approach to the hint " + P(hint) + ": " + (approach.Length == 0 ? "arrived" : approach));
                found = FindFloorChange(me, 0);
            }
            if (found == null && o.StairsAt.HasValue)
            {
                var ht = world.Get(o.StairsAt.Value);
                r.Note("floor changes known " + floorChanges.Count + " (414: " + (floorChanges.TryGetValue(414, out string k414) ? k414 : "no") + ", 8282 maps to " + (serverToClient.TryGetValue(8282, out int c8282) ? c8282.ToString(CultureInfo.InvariantCulture) : "nothing") + "); the hint tile holds " + (ht == null ? "nothing (not in view)" : string.Join(",", ht.Things.Where(th => !th.IsCreature).Select(th => th.Item.Id.ToString(CultureInfo.InvariantCulture)))));
            }
            if (found == null) { r.Skip("no stair, ramp or hole in view of " + P(me.Pos) + " (give --stairs-at X,Y,Z or start the character beside one)"); return; }
            var problems = new StringBuilder();
            var (tile, kind) = found.Value;
            var origin = me.Pos;
            int firstZ = origin.Z;
            if (!TakeStairs(me, tile, kind, r, "first change", problems)) { r.Fail(problems.ToString().Trim()); return; }
            // the way back: a stair of the other direction in the new view
            var back = FindFloorChange(me, -FloorDelta(kind));
            if (back == null)
            {
                r.Note("no way back in view on the new floor");
                if (problems.Length > 0) r.Fail(problems.ToString().Trim());
                else r.Pass("one change of floor read, landing right, view centred; no stair back in view (the character stays on floor " + me.Pos.Z + ")");
                return;
            }
            var (bt, bk) = back.Value;
            bool returned = TakeStairs(me, bt, bk, r, "way back", problems);
            if (returned)
            {
                if (me.Pos.Z != firstZ) problems.Append("back on floor " + me.Pos.Z + ", started on " + firstZ + "; ");
                else if (PathFinder.Cheb(me.Pos, origin) > 3) r.Note("back at " + P(me.Pos) + ", " + PathFinder.Cheb(me.Pos, origin) + " tiles from where we started");
                // one plain step after the changes: the server's 0x6D must name the tile the client believes
                var mk = Mark.Of(me);
                int moves0 = s.Parser.PlayerMoves;
                bool stepped = false;
                foreach (var d in new[] { Dir.South, Dir.North, Dir.East, Dir.West })
                {
                    var to = WalkDirs.Step(me.Pos, d);
                    if (!Passable(world, to, world.PlayerId) || FloorChangeOf(world.Get(to)) != null) continue;
                    if (!WaitFor(3000, () => s.CanWalk)) break;
                    s.Walk(d);
                    stepped = WaitFor(2500, () => s.Parser.PlayerMoves > moves0);
                    break;
                }
                Pump(400, () => false);
                if (!stepped) r.Note("the plain step after the floor changes did not confirm (no free neighbour, or no answer)");
                problems.Append(mk.Diff(me, "primary"));
            }
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass(kind + " stair and way back: floors " + firstZ + (kind == "down" ? " down to " : " up to ") + (firstZ + FloorDelta(kind)) + " and back, landings right, view centred, no parse failure");
        }

        // ------------------------------------------------------------------------------------ npc
        Creature FindNpc(string name)
        {
            Creature best = null;
            int bd = int.MaxValue;
            foreach (var c in world.Creatures.Values)
            {
                if (c.Type != 2 || c.Position.Z != me.Pos.Z) continue;
                if (name != null && !string.Equals(c.Name, name, StringComparison.OrdinalIgnoreCase)) continue;
                int d = PathFinder.Cheb(c.Position, me.Pos);
                if (d < bd) { bd = d; best = c; }
            }
            return best;
        }

        int Seen(byte op) => s.Parser.Seen.TryGetValue(op, out int n) ? n : 0;

        void ScNpc(ScenarioResult r)
        {
            var p = s.Parser;
            var npc = FindNpc(o.NpcName);
            if (npc == null && o.NpcAt.HasValue)
            {
                var hint = o.NpcAt.Value;
                if (hint.Z != me.Pos.Z) { r.Skip("no NPC '" + o.NpcName + "' in view and the --npc-at hint is on floor " + hint.Z + ", the player on " + me.Pos.Z); return; }
                WalkTo(me, hint, 2, o.ScenarioMs, false, out string approach);
                r.Note("approach to the hint " + P(hint) + ": " + (approach.Length == 0 ? "arrived" : approach));
                npc = FindNpc(o.NpcName);
            }
            if (npc == null) { r.Skip("NPC '" + o.NpcName + "' is not in view of " + P(me.Pos) + " (--npc NAME, --npc-at X,Y,Z)"); return; }
            if (!WalkTo(me, npc.Position, 2, o.ScenarioMs, false, out string why)) { r.Fail("could not walk to " + o.NpcName + ": " + why); return; }
            Pump(500, () => false);
            var mark = Mark.Of(me);
            var problems = new StringBuilder();
            int lines0 = p.NpcTalk.Lines.Count;
            s.SayToNpc("hi");
            if (!WaitFor(6000, () => p.NpcTalk.Lines.Skip(lines0).Any(l => l.FromNpc)))
            {
                r.Fail("the NPC did not answer 'hi' (distance " + PathFinder.Cheb(npc.Position, me.Pos) + ")");
                return;
            }
            r.Note("NPC greeting: " + p.NpcTalk.Lines.Skip(lines0).Count(l => l.FromNpc) + " line(s), focused " + p.NpcTalk.Focused(s.Now));
            int shops0 = Seen(0x7A);
            s.SayToNpc("trade");
            if (!WaitFor(6000, () => p.Trade.Open && p.Trade.Items.Count > 0 && Seen(0x7B) > 0 && Seen(0x7A) > shops0))
            {
                r.Fail("no trade window after 'trade' (0x7A seen " + (Seen(0x7A) - shops0) + " time(s), 0x7B " + Seen(0x7B) + ")");
                return;
            }
            Pump(300, () => false);
            r.Note("trade window: " + p.Trade.Items.Count + " goods, " + p.Trade.Items.Count(i => i.Buyable) + " buyable, money " + p.Trade.Money + ", " + p.Trade.Goods.Count + " sellable kinds");
            var pick = p.Trade.Items.Where(i => i.Buyable && i.Buy > 0 && i.Buy <= p.Trade.Balance).OrderBy(i => i.Buy).FirstOrDefault();
            if (pick == null)
            {
                s.NpcClose();
                r.Fail("the trade window opened (" + p.Trade.Items.Count + " goods) but nothing is buyable with " + p.Trade.Balance + " gold");
                return;
            }
            // open the backpack to watch the item arrive
            ushort bagId = 0;
            if (p.Inventory.Length > 3 && p.Inventory[3] != null) bagId = (ushort)p.Inventory[3].Id;
            int bagItems0 = -1;
            if (bagId != 0 && p.Containers.Count == 0)
            {
                s.UseItem(GameSession.InventoryPos(3), bagId, 0);
                WaitFor(2500, () => p.Containers.Count > 0);
            }
            if (p.Containers.Count > 0) bagItems0 = p.Containers.Values.Sum(c => c.Items.Count);
            ulong money0 = p.Trade.Money;
            uint cap0 = p.FreeCap;
            int cont0 = Seen(0x70) + Seen(0x71) + Seen(0x72) + Seen(0x78) + Seen(0x79);
            int goods0 = Seen(0x7B);
            bool ignoreCap = false;
            if (!s.NpcBuy(pick, 1, false)) { ignoreCap = true; r.Note("the buy rules block it by capacity; asking with 'ignore capacity'"); if (!s.NpcBuy(pick, 1, true)) { s.NpcClose(); r.Fail("the buy rules forbid buying '" + pick.Name + "' for " + pick.Buy + " (balance " + p.Trade.Balance + ")"); return; } }
            r.Note("bought 1 x " + pick.Name + " for " + pick.Buy + (ignoreCap ? " (capacity ignored)" : ""));
            bool updated = WaitFor(5000, () => Seen(0x7B) > goods0 || p.Trade.Money != money0);
            Pump(800, () => false);
            int cont1 = Seen(0x70) + Seen(0x71) + Seen(0x72) + Seen(0x78) + Seen(0x79);
            int bagItems1 = p.Containers.Count > 0 ? p.Containers.Values.Sum(c => c.Items.Count) : -1;
            var texts = me.ServerTexts(0).TakeLast(3).ToList();
            r.Note("after the buy: money " + money0 + " to " + p.Trade.Money + ", free capacity " + cap0 + " to " + p.FreeCap + ", container/slot packets +" + (cont1 - cont0) +
                   (bagItems0 >= 0 ? ", open containers hold " + bagItems0 + " to " + bagItems1 + " items" : ", no container open") + ", 0x7B again " + (Seen(0x7B) - goods0) + " time(s)");
            if (!updated) problems.Append("no goods update (0x7B) after the buy; ");
            if (p.Trade.Money >= money0) problems.Append("the money did not fall (" + money0 + " to " + p.Trade.Money + "); ");
            else if (money0 - p.Trade.Money != pick.Buy) problems.Append("the money fell by " + (money0 - p.Trade.Money) + ", the price is " + pick.Buy + "; ");
            bool inventoryMoved = cont1 > cont0 || p.FreeCap != cap0 || (bagItems0 >= 0 && bagItems1 != bagItems0);
            if (!inventoryMoved) problems.Append("nothing in the inventory changed after the buy (no container or slot packet, capacity and open bag unchanged); texts: " + string.Join(" | ", texts) + "; ");
            // close and leave
            s.NpcClose();
            s.SayToNpc("bye");
            Pump(600, () => false);
            if (p.Trade.Open) problems.Append("the trade window state stayed open after closing; ");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("greeting answered, trade window read (0x7A, 0x7B), bought 1 x " + pick.Name + ", money and inventory updated");
        }

        // ------------------------------------------------------------------------------------ party
        /// <summary>Connects the partner (second account) and waits for its entry. Null on success, else why not.</summary>
        string EnsurePartner()
        {
            if (partner != null && partner.S.Closed == null && partner.Entered) return null;
            if (string.IsNullOrEmpty(o.Account2) || string.IsNullOrEmpty(o.Password2)) return "no second account (environment CHAOS_LIVE_ACCOUNT2 and CHAOS_LIVE_PASSWORD2)";
            var c = LiveClient.Connect(o, dat, o.Account2, o.Password2, o.Character2, out string err);
            if (c == null) return "the partner could not log in: " + err;
            partner = c;
            if (!WaitFor(15000, () => partner.Entered || partner.S.Closed != null)) return "the partner did not enter the game";
            if (partner.S.Closed != null) return "the partner's connection closed: " + partner.S.Closed;
            Pump(2500, () => false);   // its hellos
            return null;
        }

        Creature Seeing(LiveClient who, string name)
        {
            foreach (var c in who.World.Creatures.Values) if (c.Type == 0 && string.Equals(c.Name, name, StringComparison.OrdinalIgnoreCase)) return c;
            return null;
        }

        /// <summary>Gets both characters within sight of each other: the partner walks to the primary.</summary>
        string MeetPartner()
        {
            if (Seeing(me, partner.Character) != null && Seeing(partner, me.Character) != null) return null;
            if (partner.Pos.Z != me.Pos.Z) return "the partner is on floor " + partner.Pos.Z + ", the primary on " + me.Pos.Z;
            if (!WalkTo(partner, me.Pos, 3, o.ScenarioMs, false, out string why)) return "the partner could not walk to the primary: " + why;
            Pump(800, () => false);
            if (Seeing(me, partner.Character) == null || Seeing(partner, me.Character) == null) return "the characters do not see each other after the walk";
            return null;
        }

        void ScParty(ScenarioResult r)
        {
            string err = EnsurePartner();
            if (err != null) { r.Skip(err); return; }
            err = MeetPartner();
            if (err != null) { r.Skip("the two characters cannot be brought together: " + err); return; }
            var markA = Mark.Of(me);
            var markB = Mark.Of(partner);
            var problems = new StringBuilder();
            var pCreature = Seeing(me, partner.Character);
            var mCreature = Seeing(partner, me.Character);
            r.Note("both characters in view, " + PathFinder.Cheb(me.Pos, partner.Pos) + " tiles apart");
            // a party left over from an earlier run is dissolved first
            if (me.S.Party.InParty) me.S.Party.Do(PartyAction.Leave, 0);
            if (partner.S.Party.InParty) partner.S.Party.Do(PartyAction.Leave, 0);
            Pump(800, () => false);
            int shield0 = Seen(0x91);
            me.S.Party.Do(PartyAction.Invite, pCreature.Id);
            bool invited = WaitFor(5000, () => partner.S.Party.InvitedBy.Length > 0 && PartyShield.InvitedYou(mCreature.Shield) && PartyShield.InvitedByYou(pCreature.Shield));
            r.Note("invite: partner's text '" + (partner.S.Party.InvitedBy.Length > 0 ? "invited by the leader" : "none") + "', shields seen by the partner " + mCreature.Shield + ", by the leader " + pCreature.Shield);
            if (!invited) { problems.Append("the invitation did not show (invited-by '" + partner.S.Party.InvitedBy + "', the leader sees the partner with shield " + pCreature.Shield + " (server: white and blue, 2), the partner sees the leader with " + mCreature.Shield + " (server: white and yellow, 1)); "); }
            else
            {
                partner.S.Party.Do(PartyAction.Join, mCreature.Id);
                bool joined = WaitFor(6000, () => PartyShield.IsLeader(mCreature.Shield) && PartyShield.IsMember(pCreature.Shield) && me.S.Party.InParty && partner.S.Party.InParty);
                r.Note("joined: shields " + mCreature.Shield + " (leader seen by the partner) and " + pCreature.Shield + " (member seen by the leader); party frames " +
                       me.S.Party.Members.Count + " / " + partner.S.Party.Members.Count + " members, states " + me.S.Party.States + " / " + partner.S.Party.States);
                if (!joined) problems.Append("joining did not complete (shields " + mCreature.Shield + "/" + pCreature.Shield + ", frames " + me.S.Party.Members.Count + "/" + partner.S.Party.Members.Count + "); ");
                else
                {
                    if (me.S.Party.Members.Count != 2 || partner.S.Party.Members.Count != 2) problems.Append("the party frames hold " + me.S.Party.Members.Count + " and " + partner.S.Party.Members.Count + " members, expected 2; ");
                    if (!me.S.Party.ViewerIsLeader) problems.Append("the inviter is not the leader in its frames; ");
                    // the shared experience switch round trip (0xA8) must not break the parse
                    me.S.Party.Do(PartyAction.ShareOn, 0);
                    Pump(1200, () => false);
                    r.Note("shared experience asked: xp state " + me.S.Party.XpOn + " / " + partner.S.Party.XpOn + ", text '" + me.S.Party.XpText() + "'");
                }
                // leave: the member goes, the party falls apart, the shields clear
                partner.S.Party.Do(PartyAction.Leave, 0);
                bool left = WaitFor(5000, () => !partner.S.Party.InParty && mCreature.Shield == PartyShield.None && pCreature.Shield == PartyShield.None);
                if (!left)
                {
                    me.S.Party.Do(PartyAction.Leave, 0);
                    left = WaitFor(4000, () => !me.S.Party.InParty && !partner.S.Party.InParty);
                    r.Note("the party outlived the member's leave; the leader left too");
                }
                if (!left) problems.Append("the party did not end (frames " + me.S.Party.Members.Count + "/" + partner.S.Party.Members.Count + ", shields " + mCreature.Shield + "/" + pCreature.Shield + "); ");
            }
            r.Note("0x91 shield packets seen by the primary: " + (Seen(0x91) - shield0));
            problems.Append(markA.Diff(me, "primary"));
            problems.Append(markB.Diff(partner, "partner"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("invite, join, party frames on both sides, shields, shared experience switch and leave all parsed, no failure");
        }

        // ------------------------------------------------------------------------------------ rift
        void ScRift(ScenarioResult r)
        {
            if (serverToClient == null || !serverToClient.TryGetValue(o.RiftKeyServerId, out int keyClient)) { r.Skip("no items.otb node for the Rift Key (server id " + o.RiftKeyServerId + ")"); return; }
            var p = s.Parser;
            var mark = Mark.Of(me);
            int say0 = me.Said.Count;
            // a key from the staff command; only an administrator gets one
            s.Say("/rift key 1");
            Pump(1500, () => false);
            ushort bagId = p.Inventory.Length > 3 && p.Inventory[3] != null ? (ushort)p.Inventory[3].Id : (ushort)0;
            if (bagId == 0) { r.Skip("no backpack on the character to hold a key"); return; }
            foreach (var cid in p.Containers.Keys.ToList()) s.CloseContainer(cid);
            Pump(400, () => false);
            s.UseItem(GameSession.InventoryPos(3), bagId, 0);
            WaitFor(2500, () => p.Containers.Count > 0);
            int slot = -1;
            byte contId = 0;
            foreach (var c in p.Containers.Values)
            {
                int i = c.Items.FindIndex(it => it != null && it.Id == keyClient);
                if (i >= 0) { slot = i + c.FirstIndex; contId = c.Id; break; }
            }
            if (slot < 0)
            {
                var texts = me.ServerTexts(say0).Take(3).ToList();
                r.Skip("the staff command gave no Rift Key (the character needs the administrator rights: group and account type God on the local server)" + (texts.Count > 0 ? "; server said: " + string.Join(" | ", texts) : ""));
                return;
            }
            r.Note("a Rift Key (client id " + keyClient + ") is in the backpack");
            var before = me.Pos;
            int rift0 = ops[228].Replies;
            int say1 = me.Said.Count;
            s.UseItem(GameSession.ContainerPos(contId, slot), (ushort)keyClient, (byte)slot);
            bool entered = WaitFor(Math.Max(30000, o.ScenarioMs), () => s.Progress.Rift.Active || ops[228].Replies > rift0 || s.Closed != null);
            if (!entered)
            {
                var texts = me.ServerTexts(say1).Take(3).ToList();
                r.Skip("the rift did not open within the time limit" + (texts.Count > 0 ? "; server said: " + string.Join(" | ", texts) : " (no slot ready on this server, or the key was refused)"));
                return;
            }
            Pump(2500, () => false);
            var st = ops[228];
            r.Note("rift opened: 228 messages " + (st.Replies - rift0) + " [" + string.Join(",", st.Actions) + "], HUD active " + s.Progress.Rift.Active + ", tier " + s.Progress.Rift.Tier + ", total " + s.Progress.Rift.Total +
                   ", position " + P(before) + " to " + P(me.Pos));
            // ask again inside the rift: the query answers only here
            int q0 = st.Replies;
            s.Progress.Rift.Query();
            bool answered = WaitFor(4000, () => st.Replies > q0);
            r.Note("rift query inside the rift: " + (answered ? "answered" : "no answer"));
            var problems = new StringBuilder();
            if (!s.Progress.Rift.Active) problems.Append("the rift HUD state is not active; ");
            if (!answered) problems.Append("opcode 228 did not answer the query inside the rift; ");
            // leave: the staff command closes it; the exit takes a few seconds
            s.Say("/rift fail");
            bool out1 = WaitFor(25000, () => s.Progress.Rift.Result.Length > 0 || s.Closed != null);
            Pump(1500, () => false);
            r.Note("closed by the staff command: result '" + s.Progress.Rift.Result + "', exit in " + s.Progress.Rift.ExitIn + " s" + (out1 ? "" : " (no end message seen)"));
            WaitFor(Math.Max(12000, (int)(s.Progress.Rift.ExitIn * 1000) + 6000), () => !PathFarFromRift(before) || s.Closed != null);
            r.Note("position after the exit " + P(me.Pos) + " (before the rift " + P(before) + ")");
            problems.Append(mark.Diff(me, "primary"));
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("a rift opened with a staff key, opcode 228 start and query answered, closed again, no parse failure");
        }

        bool PathFarFromRift(Pos before) => PathFinder.Cheb(me.Pos, before) > 30 || me.Pos.Z != before.Z;

        // ------------------------------------------------------------------------------------ death
        void ScDeath(ScenarioResult r)
        {
            string err = EnsurePartner();
            if (err != null) { r.Skip(err); return; }
            var p = s.Parser;
            var markA = Mark.Of(me);
            var problems = new StringBuilder();
            string victimName = me.Character;
            // outside the protection zone: a monster does not attack in one (bit 16384 of the player states)
            if ((p.PlayerStates & 16384) != 0)
            {
                var found = FindFloorChange(me, 0);
                if (found == null && o.StairsAt.HasValue) { WalkTo(me, o.StairsAt.Value, 3, o.ScenarioMs, false, out _); found = FindFloorChange(me, 0); }
                if (found != null)
                {
                    var down = FindFloorChange(me, 1) ?? found;
                    var tmp = new StringBuilder();
                    if (!TakeStairs(me, down.Value.tile, down.Value.kind, r, "to unprotected ground", tmp)) { r.Fail("could not leave the protection zone: " + tmp); return; }
                    if (tmp.Length > 0) r.Note("stairs: " + tmp);
                }
                Pump(800, () => false);
            }
            if ((p.PlayerStates & 16384) != 0) { r.Skip("the character stands in a protection zone and no way out was found (start it outside one, or give --stairs-at)"); return; }
            // the partner (staff) comes to the victim and summons the killer
            int pSay = partner.Said.Count;
            partner.S.Say("/goto " + victimName);
            bool near = WaitFor(8000, () => partner.Pos.Z == me.Pos.Z && PathFinder.Cheb(partner.Pos, me.Pos) <= 2);
            if (!near)
            {
                var texts = partner.ServerTexts(pSay).Take(3).ToList();
                r.Skip("the partner is not staff (/goto did not bring it to the character)" + (texts.Count > 0 ? "; server said: " + string.Join(" | ", texts) : ""));
                return;
            }
            var seenMonsters = new HashSet<uint>(world.Creatures.Values.Where(c => c.Type == 1).Select(c => c.Id));
            partner.S.Say("/m " + o.Killer);
            bool summoned = WaitFor(6000, () => world.Creatures.Values.Any(c => c.Type == 1 && !seenMonsters.Contains(c.Id)));
            if (!summoned)
            {
                var texts = partner.ServerTexts(pSay).Skip(0).Take(4).ToList();
                r.Skip("no monster appeared after '/m " + o.Killer + "' (the partner needs the administrator rights, and the name must be a monster)" + (texts.Count > 0 ? "; server said: " + string.Join(" | ", texts) : ""));
                return;
            }
            var killer = world.Creatures.Values.First(c => c.Type == 1 && !seenMonsters.Contains(c.Id));
            r.Note("summoned a monster " + PathFinder.Cheb(killer.Position, me.Pos) + " tiles from the character; health " + p.Health + "/" + p.MaxHealth);
            int deaths0 = Seen(0x28);
            int deathLimit = Math.Max(120000, o.ScenarioMs * 2);
            bool died = WaitFor(deathLimit, () => p.Dead || s.Closed != null);
            if (!died || !p.Dead)
            {
                r.Fail("the character did not die within " + deathLimit / 1000 + " s (health " + p.Health + "/" + p.MaxHealth + "): " + (s.Closed ?? "still alive"));
                return;
            }
            Pump(1500, () => false);
            r.Note("death packet 0x28 seen " + (Seen(0x28) - deaths0) + " time(s): type " + p.DeathType + ", penalty " + p.DeathPenalty + "%");
            if (Seen(0x28) - deaths0 != 1) problems.Append("0x28 seen " + (Seen(0x28) - deaths0) + " times; ");
            if (p.DeathType != 0 && p.DeathType != 1) problems.Append("death type " + p.DeathType + "; ");
            if (p.DeathPenalty < 0 || p.DeathPenalty > 100) problems.Append("death penalty " + p.DeathPenalty + "; ");
            problems.Append(markA.Diff(me, "primary"));
            // the partner leaves the scene (best effort), the dead character logs out and in again
            partner.S.Say("/t");
            me.Close();
            string name = me.Character;
            var again = LiveClient.Connect(o, dat, o.Account, o.Password, name, out string lerr);
            if (again == null) { r.Fail("login after the death failed: " + lerr + (problems.Length > 0 ? "; " + problems : "")); return; }
            // from here the run goes on with the new connection
            s = again.S; world = again.World; me = again;
            Hook();
            bool back = WaitFor(15000, () => again.Entered || again.S.Closed != null);
            Pump(3000, () => false);
            if (!back || again.S.Closed != null) { r.Fail("the character did not enter again after the death" + (again.S.Closed != null ? ": " + again.S.Closed : "")); return; }
            var np = again.S.Parser;
            r.Note("login after the death: entered at " + P(again.Pos) + ", health " + np.Health + "/" + np.MaxHealth + ", level " + np.Level + ", dead flag " + np.Dead);
            if (np.Dead) problems.Append("the new session starts dead; ");
            if (np.Health <= 0) problems.Append("the character comes back with " + np.Health + " health; ");
            if (np.FailureCount > 0) problems.Append("login after the death: " + np.FailureCount + " parse failure(s) (" + string.Join("; ", np.Failures.Take(3).Select(f => f.ToString())) + "); ");
            // it must walk: a stuck character is the failure this scenario guards against
            bool moved = false;
            foreach (var d in new[] { Dir.South, Dir.North, Dir.East, Dir.West })
            {
                var to = WalkDirs.Step(again.Pos, d);
                if (!Passable(again.World, to, again.World.PlayerId) || FloorChangeOf(again.World.Get(to)) != null) continue;
                if (!WaitFor(3000, () => again.S.CanWalk)) break;
                int m0 = np.PlayerMoves;
                again.S.Walk(d);
                moved = WaitFor(2500, () => np.PlayerMoves > m0);
                break;
            }
            r.Note("a step after the death: " + (moved ? "confirmed" : "not confirmed"));
            if (!moved) problems.Append("the character could not take a step after coming back; ");
            if (problems.Length > 0) r.Fail(problems.ToString().Trim());
            else r.Pass("killed by a summoned monster, 0x28 parsed (type " + p.DeathType + ", penalty " + p.DeathPenalty + "%), logged out and in again, alive and walking");
        }

        // ------------------------------------------------------------------------------------ reports
        public List<object> ScenarioRows() =>
            scenarios.Select(x => (object)new Dictionary<string, object>
            {
                { "name", x.Name }, { "status", x.Status }, { "reason", x.Reason }, { "ms", Math.Round(x.Ms) }, { "notes", x.Notes },
            }).ToList();

        void ScenarioText(StringBuilder sb)
        {
            if (scenarios.Count == 0) return;
            sb.AppendLine("scenarios: " + scenarios.Count(x => x.Status == "pass") + " pass, " + scenarios.Count(x => x.Status == "fail") + " fail, " + scenarios.Count(x => x.Status == "skip") + " skip");
            foreach (var x in scenarios)
            {
                sb.AppendLine("  " + x.Name.PadRight(8) + x.Status.ToUpperInvariant().PadRight(6) + Math.Round(x.Ms / 1000, 1).ToString("0.0", CultureInfo.InvariantCulture) + " s  " + x.Reason);
                foreach (var n in x.Notes) sb.AppendLine("      " + n);
            }
            if (partnerStats != null) sb.AppendLine("partner connection: " + partnerStats);
        }

        string partnerStats;
        bool partnerBad;
    }
}
