// The Rift Atlas (opcode 210) and the Waystone Atlas (159): the long-term node maps of the rifts and of waystone runs. One model, two opcodes, the same
// protocol (client game_riftatlas, riftatlasview.lua; server atlas.lua, waystone_atlas.lua):
//   client -> server  open {tree = true when the client has none} | alloc {id} | refund {id, pay = "gold"|"orb"} | reset {pay}
//   server -> client  tree {nodes, branches, start, keystoneMax, grid, max}   (once per login, on the first open; may come chunked)
//                     state {earned, spent, points, max, alloc, done, refund, reset, orb, totals, msg}
//                     credit {cells = [names], points}
// The graph rules (what can be allocated or refunded, status of a node, the world and pan maths) are the main client's.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    public sealed class AtlasNode
    {
        public int I, C;
        public string K = "small", N = "?", G = "density";
        public int B;
        public string BranchKey = "";
        public double X, Y;
        public List<int> L = new List<int>();
        public List<string> T = new List<string>();
    }

    public sealed class AtlasBranch { public string K = "", Th = "", C = "#d6c9ae"; }

    public sealed class AtlasIndex
    {
        public readonly Dictionary<int, AtlasNode> ById = new Dictionary<int, AtlasNode>();
        public readonly Dictionary<int, HashSet<int>> Adj = new Dictionary<int, HashSet<int>>();
        public readonly List<AtlasNode> List = new List<AtlasNode>();
        public readonly List<int[]> Pairs = new List<int[]>();
        public readonly Dictionary<string, string> SetOf = new Dictionary<string, string>();
        public readonly Dictionary<string, AtlasBranch> BranchByTheme = new Dictionary<string, AtlasBranch>();
        public readonly Dictionary<string, AtlasBranch> BranchByKey = new Dictionary<string, AtlasBranch>();
        public int Start;
    }

    public sealed class AtlasTree
    {
        public List<AtlasNode> Nodes = new List<AtlasNode>();
        public List<AtlasBranch> Branches = new List<AtlasBranch>();
        public int Start, KeystoneMax = 1;
        public object Grid;
    }

    public sealed class AtlasCell { public string Key = "", Tip = "", Name = ""; public bool Done; public int Col; public string Color; }
    public sealed class AtlasRow { public string Label = "", Color = "#d6c9ae", Kind = "cell"; public List<AtlasCell> Cells = new List<AtlasCell>(); }
    public struct AtlasWorld { public double Cx, Cy, W, H; }

    public static class AtlasView
    {
        public const double Margin = 140;
        public static readonly double[] Zooms = { 0.3, 0.4, 0.5, 0.65, 0.8, 1.0 };
        public const int DefaultZoom = 2;   // 1-based index into Zooms, as the main client
        public static readonly Dictionary<string, int> Sizes = new Dictionary<string, int> { { "start", 100 }, { "small", 27 }, { "notable", 38 }, { "keystone", 60 } };

        public static AtlasTree ParseTree(object d)
        {
            var t = new AtlasTree { Start = Json.Int(d, "start"), KeystoneMax = Json.Get(d, "keystoneMax") is double km ? (int)km : 1, Grid = Json.Get(d, "grid") };
            foreach (object b in Json.List(d, "branches"))
                if (b is Dictionary<string, object>) t.Branches.Add(new AtlasBranch { K = Json.Text(b, "k"), Th = Json.Text(b, "th"), C = Json.Text(b, "c", "#d6c9ae") });
            foreach (object n in Json.List(d, "nodes"))
            {
                if (!(n is Dictionary<string, object>)) continue;
                var node = new AtlasNode
                {
                    I = Json.Int(n, "i"), K = Json.Text(n, "k", "small"), C = Json.Int(n, "c"), N = Json.Text(n, "n", "?"), G = Json.Text(n, "g", "density"),
                    BranchKey = Json.Get(n, "b") is string bs ? bs : "", X = Json.Number(n, "x"), Y = Json.Number(n, "y"),
                };
                foreach (object l in Json.List(n, "l")) if (l is double ld) node.L.Add((int)ld);
                node.T = Eg.Strings(n, "t");
                t.Nodes.Add(node);
            }
            return t;
        }

        public static AtlasIndex Index(AtlasTree tree)
        {
            var ix = new AtlasIndex();
            if (tree == null) return ix;
            ix.Start = tree.Start;
            foreach (var b in tree.Branches) { ix.SetOf[b.Th] = b.K; ix.BranchByTheme[b.Th] = b; ix.BranchByKey[b.K] = b; }
            foreach (var n in tree.Nodes)
            {
                ix.ById[n.I] = n;
                if (!ix.Adj.ContainsKey(n.I)) ix.Adj[n.I] = new HashSet<int>();
                ix.List.Add(n);
            }
            var seen = new HashSet<string>();
            foreach (var n in ix.List)
                foreach (int l in n.L)
                {
                    if (!ix.ById.ContainsKey(l) || l == n.I) continue;
                    ix.Adj[n.I].Add(l);
                    ix.Adj[l].Add(n.I);
                    int a = Math.Min(n.I, l), b = Math.Max(n.I, l);
                    if (seen.Add(a + "-" + b)) ix.Pairs.Add(new[] { a, b });
                }
            return ix;
        }

        public static HashSet<int> AllocSet(object state)
        {
            var s = new HashSet<int>();
            foreach (object id in Json.List(state, "alloc")) if (id is double d) s.Add((int)d);
            return s;
        }

        public static HashSet<string> DoneSet(object state)
        {
            var s = new HashSet<string>();
            foreach (object k in Json.List(state, "done"))
                s.Add(k is double d ? d.ToString("0.#", CultureInfo.InvariantCulture) : k as string ?? "");
            return s;
        }

        static bool Held(AtlasIndex ix, HashSet<int> alloc, int id) => id == ix.Start || alloc.Contains(id);

        static int Keystones(AtlasIndex ix, HashSet<int> alloc)
        {
            int n = 0;
            foreach (int id in alloc) if (ix.ById.TryGetValue(id, out var node) && node.K == "keystone") n++;
            return n;
        }

        public static bool Connected(AtlasIndex ix, HashSet<int> alloc)
        {
            var seen = new HashSet<int> { ix.Start };
            var queue = new List<int> { ix.Start };
            for (int i = 0; i < queue.Count; i++)
                if (ix.Adj.TryGetValue(queue[i], out var adj))
                    foreach (int o in adj)
                        if (alloc.Contains(o) && seen.Add(o)) queue.Add(o);
            foreach (int id in alloc) if (id != ix.Start && !seen.Contains(id)) return false;
            return true;
        }

        public static bool CanAllocate(AtlasIndex ix, HashSet<int> alloc, int id, double points, int keystoneMax, out string why)
        {
            why = "";
            if (!ix.ById.TryGetValue(id, out var node) || node.K == "start") { why = "unknown"; return false; }
            if (alloc.Contains(id)) { why = "held"; return false; }
            if (node.C > points) { why = "points"; return false; }
            if (node.K == "keystone" && Keystones(ix, alloc) >= keystoneMax) { why = "keystone"; return false; }
            if (ix.Adj.TryGetValue(id, out var adj)) foreach (int o in adj) if (Held(ix, alloc, o)) return true;
            why = "path";
            return false;
        }

        public static bool CanRefund(AtlasIndex ix, HashSet<int> alloc, int id, out string why)
        {
            why = "";
            if (!alloc.Contains(id)) { why = "not held"; return false; }
            alloc.Remove(id);
            bool ok = Connected(ix, alloc);
            alloc.Add(id);
            if (!ok) { why = "path"; return false; }
            return true;
        }

        public static string Status(AtlasIndex ix, HashSet<int> alloc, int id, double points, int keystoneMax)
        {
            if (!ix.ById.TryGetValue(id, out var node)) return "locked";
            if (node.K == "start") return "start";
            if (alloc.Contains(id)) return "alloc";
            if (CanAllocate(ix, alloc, id, points, keystoneMax, out string why)) return "avail";
            if ((why == "points" || why == "keystone") && ix.Adj.TryGetValue(id, out var adj))
                foreach (int o in adj) if (Held(ix, alloc, o)) return "reach";
            return "locked";
        }

        /// <summary>"Active" (both ends held), "Intermediate" (one), "Normal".</summary>
        public static string LinkState(AtlasIndex ix, HashSet<int> alloc, int a, int b)
        {
            bool ha = Held(ix, alloc, a), hb = Held(ix, alloc, b);
            return ha && hb ? "Active" : ha || hb ? "Intermediate" : "Normal";
        }

        /// <summary>The icon set of a node: node.b names a theme and the branch of that theme gives the set (core when none).</summary>
        public static string IconSet(AtlasIndex ix, AtlasNode n) => n != null && ix.SetOf.TryGetValue(n.BranchKey, out var k) ? k : "core";

        public static string Glyph(AtlasIndex ix, AtlasNode n)
        {
            string g = n != null ? n.G : "density";
            return g == "theme" ? "theme_" + IconSet(ix, n) : g;
        }

        public static int NodeSize(string kind, double zoom)
        {
            int s = Sizes.TryGetValue(kind ?? "", out var v) ? v : Sizes["small"];
            return Math.Max(8, (int)Math.Floor(s * (0.45 + 0.55 * zoom) + 0.5));
        }

        public static void Bounds(AtlasIndex ix, out double minX, out double maxX, out double minY, out double maxY)
        {
            minX = maxX = minY = maxY = 0;
            foreach (var n in ix.List) { minX = Math.Min(minX, n.X); maxX = Math.Max(maxX, n.X); minY = Math.Min(minY, n.Y); maxY = Math.Max(maxY, n.Y); }
            minX -= Margin; minY -= Margin; maxX += Margin; maxY += Margin;
        }

        public static AtlasWorld World(AtlasIndex ix)
        {
            Bounds(ix, out double a, out double b, out double c, out double d);
            return new AtlasWorld { Cx = (a + b) / 2, Cy = (c + d) / 2, W = b - a, H = d - c };
        }

        public static void ClampPan(double px, double py, double zoom, AtlasWorld w, double viewW, double viewH, out double ox, out double oy)
        {
            double hw = Math.Max(0, w.W * zoom / 2 - viewW / 2), hh = Math.Max(0, w.H * zoom / 2 - viewH / 2);
            ox = Math.Max(-hw, Math.Min(hw, px)); oy = Math.Max(-hh, Math.Min(hh, py));
        }

        public static int ZoomStep(int i, int dir) => Math.Max(1, Math.Min(Zooms.Length, i + (dir > 0 ? 1 : -1)));

        /// <summary>The place of a node on the canvas (pixels from the world's centre).</summary>
        public static void Place(AtlasWorld w, AtlasNode n, double zoom, out int x, out int y)
        {
            x = (int)Math.Floor((n.X - w.Cx) * zoom + 0.5); y = (int)Math.Floor((n.Y - w.Cy) * zoom + 0.5);
        }

        public static void PanTo(AtlasWorld w, AtlasNode n, double zoom, out int px, out int py)
        {
            Place(w, n, zoom, out int x, out int y);
            px = -x; py = -y;
        }

        static string Kind(string k) => k == "start" ? "Start" : k == "notable" ? "Notable" : k == "keystone" ? "Keystone" : "Node";

        public static string ReasonText(string why)
        {
            switch (why)
            {
                case "unknown": return Loc.T("Unknown node.");
                case "held": return Loc.T("Allocated.");
                case "points": return Loc.T("Not enough points: seal new rifts to earn more.");
                case "keystone": return Loc.T("You hold a keystone already: refund it first.");
                case "path": return Loc.T("Not connected to your atlas yet.");
                case "not held": return Loc.T("Not allocated.");
                default: return why ?? "";
            }
        }

        public static string KindLine(AtlasNode n)
        {
            if (n == null) return "";
            if (n.K == "start") return Loc.T("Start of the atlas");
            return Loc.T(n.C == 1 ? "{0}, {1} point" : "{0}, {1} points", Loc.T(Kind(n.K)), n.C);
        }

        public static string Tooltip(AtlasNode n, string status)
        {
            if (n == null) return "";
            var lines = new List<string> { n.N, KindLine(n) };
            lines.AddRange(n.T);
            if (status == "alloc") lines.Add(Loc.T("Allocated."));
            else if (status == "avail") lines.Add(Loc.T("Click, then Allocate."));
            return string.Join("\n", lines);
        }

        public static string Short(double n)
        {
            if (n >= 1000000) return (Math.Round(n / 1000000 * 10) / 10).ToString("0.#", CultureInfo.InvariantCulture) + "M";
            if (n >= 1000) return (Math.Round(n / 1000 * 10) / 10).ToString("0.#", CultureInfo.InvariantCulture) + "k";
            return ((long)Math.Floor(n)).ToString(CultureInfo.InvariantCulture);
        }

        public static string PointsLine(object state) => state is Dictionary<string, object> ? Json.Int(state, "points").ToString(CultureInfo.InvariantCulture) : "";
        public static string EarnedLine(object state) => !(state is Dictionary<string, object>) ? "" : Loc.T("Earned {0} / {1}, spent {2}", Json.Int(state, "earned"), Json.Int(state, "max"), Json.Int(state, "spent"));

        public static void RefundLabels(object state, out string gold, out string orbs)
        {
            var r = Json.Get(state, "refund");
            gold = Loc.T("Refund {0}", Short(Json.Number(r, "gold")));
            int o = Json.Int(r, "orbs");
            orbs = Loc.T(o == 1 ? "Refund {0} orb" : "Refund {0} orbs", o);
        }

        public static int SwiftSeconds(object grid, int tier)
        {
            var tiers = Json.Get(grid, "swiftTiers") as List<object>;
            double per = tiers != null && tier >= 1 && tier <= tiers.Count && tiers[tier - 1] is double d ? d : Json.Number(grid, "swift");
            return (int)Math.Max(0, Math.Floor(per));
        }

        static readonly Dictionary<string, string> Short4 = new Dictionary<string, string>
        {
            { "Abyssal Rift", "Abyss" }, { "Obsidian Hall", "Hall" }, { "Ashen Crypt", "Crypt" }, { "Forsaken Sanctum", "Sanctum" },
        };

        /// <summary>The grid of first completions: a row per theme, Flawless, Swift and Omens (rift mode), or the server's own rows (waystone mode).</summary>
        public static List<AtlasRow> GridRows(AtlasTree tree, AtlasIndex ix, HashSet<string> done)
        {
            var rows = new List<AtlasRow>();
            if (tree == null || !(tree.Grid is Dictionary<string, object> g)) return rows;
            if (Json.Get(g, "rows") is List<object> lr) return ListRows(lr, done);
            var P = Json.Get(g, "points");
            int tiers = Json.Int(g, "tiers");
            var themes = Eg.Strings(g, "themes");
            for (int ti = 1; ti <= themes.Count; ti++)
            {
                string name = themes[ti - 1];
                ix.BranchByTheme.TryGetValue(name, out var b);
                var row = new AtlasRow { Label = Short4.TryGetValue(name, out var sh) ? sh : name, Color = b != null ? b.C : "#d6c9ae" };
                for (int t = 1; t <= tiers; t++)
                {
                    string key = "c" + ti + "." + t;
                    bool d = done.Contains(key);
                    row.Cells.Add(new AtlasCell { Key = key, Done = d, Tip = Loc.T("{0} tier {1}: {2} (+{3})", name, t, d ? "sealed" : Loc.T("not yet"), Json.Int(P, "cell")) });
                }
                rows.Add(row);
            }
            var flaw = new AtlasRow { Label = Loc.T("Flawless"), Color = "#9fd89f", Kind = "flawless" };
            var swift = new AtlasRow { Label = Loc.T("Swift"), Color = "#7fb8e8", Kind = "swift" };
            for (int t = 1; t <= tiers; t++)
            {
                bool fd = done.Contains("f" + t), sd = done.Contains("s" + t);
                flaw.Cells.Add(new AtlasCell { Key = "f" + t, Done = fd, Tip = Loc.T("Flawless tier {0} (no death): {1} (+{2})", t, fd ? Loc.T("done") : Loc.T("not yet"), Json.Int(P, "flawless")) });
                int secs = SwiftSeconds(g, t);
                swift.Cells.Add(new AtlasCell { Key = "s" + t, Done = sd, Tip = Loc.T("Swift tier {0} (sealed within {1}:{2}): {3} (+{4})", t, secs / 60, (secs % 60).ToString("00", CultureInfo.InvariantCulture), sd ? Loc.T("done") : Loc.T("not yet"), Json.Int(P, "swift")) });
            }
            rows.Add(flaw);
            rows.Add(swift);
            var omen = new AtlasRow { Label = "Omens", Color = "#e05a3a", Kind = "omen" };
            foreach (object o in Json.List(g, "omens"))
            {
                string key = "o" + (Json.Get(o, "k") is string ks ? ks : Json.Get(o, "k") is double kd ? kd.ToString("0.#", CultureInfo.InvariantCulture) : "");
                bool d = done.Contains(key);
                string nm = Json.Text(o, "n");
                omen.Cells.Add(new AtlasCell { Key = key, Done = d, Name = nm, Tip = (Json.Get(o, "b") is string bb ? bb : nm) + ": " + (d ? "slain" : "not yet") + " (+" + Json.Int(P, "omen") + ")" });
            }
            rows.Add(omen);
            return rows;
        }

        public static List<AtlasRow> ListRows(List<object> list, HashSet<string> done)
        {
            var rows = new List<AtlasRow>();
            foreach (object r in list)
            {
                var row = new AtlasRow { Label = Json.Text(r, "label"), Color = Json.Text(r, "color", "#d6c9ae") };
                foreach (object c in Json.List(r, "cells"))
                {
                    string key = Json.Get(c, "k") is string ks ? ks : Json.Get(c, "k") is double kd ? kd.ToString("0.#", CultureInfo.InvariantCulture) : "";
                    bool d = done.Contains(key);
                    row.Cells.Add(new AtlasCell
                    {
                        Key = key, Done = d, Col = Json.Int(c, "c"), Color = Json.Get(c, "co") as string,
                        Tip = Json.Text(c, "n", key) + ": " + (d ? Loc.T("done") : Loc.T("not yet")) + " (+" + Json.Int(c, "p") + ")",
                    });
                }
                rows.Add(row);
            }
            return rows;
        }

        public static void GridCount(List<AtlasRow> rows, out int done, out int total)
        {
            done = total = 0;
            foreach (var r in rows) foreach (var c in r.Cells) { total++; if (c.Done) done++; }
        }
    }

    public sealed class AtlasState : EgModule
    {
        public const byte RiftOpcode = 210, WaystoneOpcode = 159;
        readonly byte opcode;
        protected override byte Op => opcode;
        public bool IsWaystone => opcode == WaystoneOpcode;

        public bool Visible;
        public AtlasTree Tree;
        public AtlasIndex Ix = new AtlasIndex();
        public AtlasWorld World;
        public object State;
        public HashSet<int> Alloc = new HashSet<int>();
        public HashSet<string> Done = new HashSet<string>();
        public int Selected;
        public int ZoomIndex = AtlasView.DefaultZoom;
        public double PanX, PanY;
        public string StatusText = "", StatusColor = "#f6cf72";
        public bool PanDirty;

        public AtlasState(ExtOpcodes e, byte op) : base(e) { opcode = op; ext.On(op, m => Handle(m.Action, Eg.DataOf(m))); }

        public double Zoom => AtlasView.Zooms[ZoomIndex - 1];
        public double Points => State != null ? Json.Number(State, "points") : 0;
        public int KeystoneMax => Tree != null ? Tree.KeystoneMax : 1;
        public List<AtlasRow> Grid() => AtlasView.GridRows(Tree, Ix, Done);

        public string Title => IsWaystone ? "Waystone Atlas" : "Rift Atlas";

        /// <summary>Shows the window and asks for the state (and the tree, when this client has none yet).</summary>
        public void Open()
        {
            Visible = true;
            Send("open", D("tree", Tree == null));
            Changed();
        }

        public void Hide() { Visible = false; Selected = 0; }
        public void Toggle() { if (Visible) Hide(); else Open(); }

        public void Handle(string action, object d)
        {
            if (!(d is Dictionary<string, object>) || d == null) return;
            if (action == "tree")
            {
                Tree = AtlasView.ParseTree(d);
                Ix = AtlasView.Index(Tree);
                World = AtlasView.World(Ix);
                Center();
            }
            else if (action == "state")
            {
                State = d;
                Alloc = AtlasView.AllocSet(d);
                Done = AtlasView.DoneSet(d);
                string msg = Json.Text(d, "msg");
                if (msg.Length > 0) { StatusText = msg; StatusColor = "#f6cf72"; }
            }
            else if (action == "credit")
            {
                StatusText = Loc.T("Completed: {0} (+{1})", string.Join(", ", Eg.Strings(d, "cells")), Json.Int(d, "points"));
                StatusColor = "#7fd07f";
            }
            Changed();
        }

        public void Center()
        {
            if (Tree == null || !Ix.ById.TryGetValue(Ix.Start, out var start)) { PanX = PanY = 0; return; }
            AtlasView.PanTo(World, start, Zoom, out int x, out int y);
            PanX = x; PanY = y;
        }

        public void ZoomBy(int dir)
        {
            int next = AtlasView.ZoomStep(ZoomIndex, dir);
            if (next == ZoomIndex) return;
            double ratio = AtlasView.Zooms[next - 1] / Zoom;
            ZoomIndex = next;
            PanX *= ratio; PanY *= ratio;
            Changed();
        }

        public void Pick(int id) { if (Ix.ById.ContainsKey(id)) { Selected = id; Changed(); } }

        public AtlasNode SelectedNode => Selected != 0 && Ix.ById.TryGetValue(Selected, out var n) ? n : null;
        public string StatusOf(int id) => AtlasView.Status(Ix, Alloc, id, Points, KeystoneMax);
        public bool CanAllocate(int id, out string why) => AtlasView.CanAllocate(Ix, Alloc, id, Points, KeystoneMax, out why);
        public bool CanRefund(int id, out string why) => AtlasView.CanRefund(Ix, Alloc, id, out why);

        /// <summary>Allocates the selected node when the rules allow it.</summary>
        public bool AllocateSelected()
        {
            if (Selected == 0 || !CanAllocate(Selected, out _)) return false;
            return Send("alloc", D("id", Selected));
        }

        public bool RefundSelected(string pay)
        {
            if (Selected == 0 || !CanRefund(Selected, out _)) return false;
            return Send("refund", D("id", Selected, "pay", pay == "orb" ? "orb" : "gold"));
        }

        public bool Reset(string pay) { if (Alloc.Count == 0) return false; return Send("reset", D("pay", pay == "orb" ? "orb" : "gold")); }

        public void Clear()
        {
            Visible = false; Tree = null; Ix = new AtlasIndex(); State = null; Alloc = new HashSet<int>(); Done = new HashSet<string>(); Selected = 0;
            ZoomIndex = AtlasView.DefaultZoom; PanX = PanY = 0; StatusText = "";
        }
    }
}
