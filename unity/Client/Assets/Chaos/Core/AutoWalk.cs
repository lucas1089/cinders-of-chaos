// Auto-walk to a clicked tile (phase 6, track V): the client works out the path on the tiles it knows (A*), sends it in one
// 0x64 packet (the server walks it, one step per answer) and stops on Escape (0xBE) or on any manual step. Pure: no engine API.
// The direction bytes are the protocol's: 1 east, 2 north-east, 3 north, 4 north-west, 5 west, 6 south-west, 7 south, 8 south-east,
// in walking order (the first step first).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class WalkDirs
    {
        /// <summary>The byte of a direction in the auto-walk packet.</summary>
        public static byte Code(Dir d)
        {
            switch (d)
            {
                case Dir.East: return 1;
                case Dir.NorthEast: return 2;
                case Dir.North: return 3;
                case Dir.NorthWest: return 4;
                case Dir.West: return 5;
                case Dir.SouthWest: return 6;
                case Dir.South: return 7;
                default: return 8;
            }
        }

        public static void Delta(Dir d, out int dx, out int dy)
        {
            dx = 0; dy = 0;
            switch (d)
            {
                case Dir.North: dy = -1; break;
                case Dir.South: dy = 1; break;
                case Dir.East: dx = 1; break;
                case Dir.West: dx = -1; break;
                case Dir.NorthEast: dx = 1; dy = -1; break;
                case Dir.NorthWest: dx = -1; dy = -1; break;
                case Dir.SouthEast: dx = 1; dy = 1; break;
                case Dir.SouthWest: dx = -1; dy = 1; break;
            }
        }

        public static bool Diagonal(Dir d) => (int)d >= 4;

        public static Pos Step(Pos p, Dir d) { Delta(d, out int dx, out int dy); return p.Offset(dx, dy); }

        public static readonly Dir[] All = { Dir.North, Dir.East, Dir.South, Dir.West, Dir.NorthEast, Dir.SouthEast, Dir.SouthWest, Dir.NorthWest };
    }

    /// <summary>A* on one floor over the tiles the client knows. A diagonal step takes WalkTiming.DiagonalNum / DiagonalDen of a straight one (about 1.4), so it costs 14 against 10: the path
    /// cuts a corner where that is shorter and goes straight otherwise.</summary>
    public static class PathFinder
    {
        public const int Straight = 10, Diagonal = (int)(Straight * WalkTiming.DiagonalNum / WalkTiming.DiagonalDen);
        public const int MaxNodes = 6000, MaxRadius = 40;

        sealed class Node { public Pos P; public int G, F; public Node From; public Dir Via; public bool Closed; }

        sealed class Heap
        {
            readonly List<Node> a = new List<Node>();
            public int Count => a.Count;
            public void Push(Node n)
            {
                a.Add(n);
                int i = a.Count - 1;
                while (i > 0)
                {
                    int p = (i - 1) / 2;
                    if (Less(a[p], a[i])) break;
                    var t = a[p]; a[p] = a[i]; a[i] = t;
                    i = p;
                }
            }
            public Node Pop()
            {
                var top = a[0];
                var last = a[a.Count - 1];
                a.RemoveAt(a.Count - 1);
                if (a.Count > 0)
                {
                    a[0] = last;
                    int i = 0;
                    while (true)
                    {
                        int l = i * 2 + 1, r = l + 1, m = i;
                        if (l < a.Count && Less(a[l], a[m])) m = l;
                        if (r < a.Count && Less(a[r], a[m])) m = r;
                        if (m == i) break;
                        var t = a[m]; a[m] = a[i]; a[i] = t;
                        i = m;
                    }
                }
                return top;
            }
            static bool Less(Node x, Node y) => x.F < y.F || (x.F == y.F && x.G > y.G);
        }

        public static int Cheb(Pos a, Pos b) => Math.Max(Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));

        /// <summary>The steps from `from` to `to`, or to the nearest tile within `range` (Chebyshev) of `to` that is walkable and reachable. Null when there is no way, an empty list when
        /// `from` is already there. `walkable(p)` says whether a tile can be stepped on (the start tile is never asked). Another floor gives null.</summary>
        public static List<Dir> Find(Pos from, Pos to, Func<Pos, bool> walkable, int range = 0, int maxNodes = MaxNodes)
        {
            if (from.Z != to.Z || walkable == null) return null;
            range = Math.Max(0, range);
            if (Goal(from, to, range)) return new List<Dir>();
            var nodes = new Dictionary<Pos, Node>();
            var open = new Heap();
            var start = new Node { P = from, G = 0 };
            start.F = Heuristic(from, to, range);
            nodes[from] = start;
            open.Push(start);
            int expanded = 0;
            while (open.Count > 0 && expanded < maxNodes)
            {
                var cur = open.Pop();
                if (cur.Closed) continue;
                cur.Closed = true;
                expanded++;
                if (Goal(cur.P, to, range)) return Trace(cur);
                foreach (var d in WalkDirs.All)
                {
                    var np = WalkDirs.Step(cur.P, d);
                    if (Math.Abs(np.X - from.X) > MaxRadius || Math.Abs(np.Y - from.Y) > MaxRadius) continue;
                    if (nodes.TryGetValue(np, out var seen) && seen.Closed) continue;
                    if (!walkable(np)) continue;
                    int g = cur.G + (WalkDirs.Diagonal(d) ? Diagonal : Straight);
                    if (seen != null && seen.G <= g) continue;
                    var n = seen ?? new Node { P = np };
                    n.G = g; n.F = g + Heuristic(np, to, range); n.From = cur; n.Via = d;
                    nodes[np] = n;
                    open.Push(n);
                }
            }
            return null;
        }

        static bool Goal(Pos p, Pos to, int range) => range > 0 ? (Cheb(p, to) <= range && p != to) : p == to;

        static int Heuristic(Pos p, Pos to, int range) =>
            Straight * (Math.Max(0, Math.Abs(p.X - to.X) - range) + Math.Max(0, Math.Abs(p.Y - to.Y) - range));

        static List<Dir> Trace(Node end)
        {
            var path = new List<Dir>();
            for (var n = end; n.From != null; n = n.From) path.Add(n.Via);
            path.Reverse();
            return path;
        }

        /// <summary>The tiles a path visits, from the start (included).</summary>
        public static List<Pos> Tiles(Pos from, IList<Dir> path)
        {
            var o = new List<Pos> { from };
            var p = from;
            foreach (var d in path) { p = WalkDirs.Step(p, d); o.Add(p); }
            return o;
        }
    }

    public static class AutoWalkPackets
    {
        public const byte Walk = 0x64, Stop = 0xBE, MaxSteps = 100;

        /// <summary>0x64 with the path in walking order. Null for an empty path; a path over MaxSteps is cut (the walk can be asked again).</summary>
        public static byte[] WalkPacket(IList<Dir> path)
        {
            if (path == null || path.Count == 0) return null;
            int n = Math.Min(path.Count, (int)MaxSteps);
            var w = new ByteWriter().U8(Walk).U8((byte)n);
            for (int i = 0; i < n; i++) w.U8(WalkDirs.Code(path[i]));
            return w.ToArray();
        }

        /// <summary>0xBE: stops the walk (and the attack or follow, as the server's cancel does).</summary>
        public static byte[] StopPacket() => new byte[] { Stop };
    }

    /// <summary>What a tile says about walking: a tile the client knows, with a ground, nothing that blocks (not walkable, not pathable) and no creature
    /// standing there. The player's own tile is never asked.</summary>
    public static class WalkMap
    {
        /// <summary>A tile whose items stop a shot (BlockMissile): for the Auto Target line of sight.</summary>
        public static bool BlocksMissile(World w, Pos p)
        {
            if (w == null || !w.Tiles.TryGetValue(p, out var tile)) return false;
            foreach (var t in tile.Things) if (!t.IsCreature && t.Item?.Type != null && t.Item.Type.BlockMissile) return true;
            return false;
        }


        public static bool Walkable(World w, Pos p, uint selfId, bool ignoreCreatures = false)
        {
            if (w == null || !w.Tiles.TryGetValue(p, out var tile)) return false;
            bool ground = false;
            foreach (var t in tile.Things)
            {
                if (t.IsCreature)
                {
                    var c = t.Creature;
                    if (!ignoreCreatures && c != null && c.Id != selfId && !c.Walkthrough) return false;
                    continue;
                }
                var type = t.Item?.Type;
                if (type == null) continue;
                if (type.Ground) ground = true;
                if (type.NotWalkable || type.BlockPath) return false;
            }
            return ground;
        }
    }

    /// <summary>A walk in progress: the tiles the path crosses, the last time the player was seen moving, and why it ended.</summary>
    public sealed class AutoWalkState
    {
        public enum Result { None, Running, Arrived, Interrupted, Stalled }

        /// <summary>No progress for this long ends the walk (the server refused a step: 0xB5).</summary>
        public const double StallMs = 1800;

        public bool Active;
        public Pos Goal;
        public int Index;
        List<Pos> tiles = new List<Pos>();
        double lastProgress;

        public int Remaining => Active ? tiles.Count - 1 - Index : 0;

        public void Start(Pos from, IList<Dir> path, double now)
        {
            tiles = PathFinder.Tiles(from, path);
            Goal = tiles[tiles.Count - 1];
            Index = 0;
            lastProgress = now;
            Active = path.Count > 0;
        }

        /// <summary>Ends the walk at once (Escape, a manual step, the player was moved).</summary>
        public void Cancel() { Active = false; }

        /// <summary>Call every frame with the player's tile. Running while the player follows the path; Arrived at the goal; Interrupted when the player stands off the path (pushed, a manual step);
        /// Stalled when it stands still too long.</summary>
        public Result Update(Pos me, double now)
        {
            if (!Active) return Result.None;
            if (me == Goal) { Active = false; return Result.Arrived; }
            int at = -1;
            for (int i = Index; i < tiles.Count; i++) if (tiles[i] == me) { at = i; break; }
            if (at < 0) { Active = false; return Result.Interrupted; }
            if (at != Index) { Index = at; lastProgress = now; }
            if (now - lastProgress > StallMs) { Active = false; return Result.Stalled; }
            return Result.Running;
        }
    }
}
