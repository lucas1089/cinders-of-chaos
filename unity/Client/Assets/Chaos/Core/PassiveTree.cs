// Passive tree (extended opcode 65, client game_passivetree, server passivetree.lua). The server sends only the allocation, so
// the shape of the tree comes from Resources/PassiveTree.json (unity/tools/gen_tree_data.lua, from the main client's tree data).
//
//   client -> server  requestPoints | requestNodesUnlocked | planApply {nodes, masteries [{id, choice}]} | masteryChoose {id, choice}
//                     | refundNode {id} | resetPreset <preset number> | respecInfo | refund (resync)
//                     | buildExport {full?} | buildPreview {code} | buildApply {code, cost}
//   server -> client  sendPoints <free> | sendNodes {preset, presetsTable [{name}], nodes [id], masteries [{id, choice}], vocation, cls, line}
//                     | planResult {ok, message} | sendMessage {title, message} | respecInfo {level, full, paragon, node, free, freeBelowLevel}
//                     | bossPoints {got, total, label, bosses} | buildCode {code, nodes, paragon, full, gear} | buildPreview {...}
//                     | buildError {message} | buildApplied {message}
//
// The planner works like the main client's (treeplan.lua): a click on a node plans the shortest path from what you own, a click on a
// planned node takes it (and what hangs on it) out, Apply sends the whole plan in one planApply. Saved nodes are refunded with a
// right-click (priced by the server). A mastery node needs its effect chosen. The server checks everything again.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    /// <summary>What a class sees of a node: name, stat lines, description.</summary>
    public sealed class TreeView
    {
        public string Name = "";
        public string[] Stats = new string[0];
        public string Desc = "";
    }

    public sealed class TreeEffect
    {
        public string Name = "";
        public string[] Stats = new string[0];
    }

    public sealed class TreeNode
    {
        public int Id;
        public float X, Y;
        /// <summary>s start, c common, u uncommon, r rare, v very rare, m mythic, d divine or keystone, M mastery.</summary>
        public char Type = 'c';
        public string Name = "";
        public string[] Stats = new string[0];
        public string Desc = "";
        /// <summary>The class line that sees this node ("" every line).</summary>
        public string Line = "";
        /// <summary>The classes that may take it (empty: all).</summary>
        public string[] Classes = new string[0];
        public bool Hidden;
        public int[] Links = new int[0];
        public TreeEffect[] Effects = new TreeEffect[0];
        public Dictionary<string, TreeView> Variants = new Dictionary<string, TreeView>();

        public bool IsStart => Type == 's';
        public bool IsMastery => Type == 'M';

        /// <summary>The node as the class variant (the "vocation" of sendNodes) shows it.</summary>
        public TreeView For(string variant)
        {
            if (variant != null && Variants.TryGetValue(variant, out var v))
                return new TreeView { Name = v.Name.Length > 0 ? v.Name : Name, Stats = v.Stats, Desc = v.Desc };
            return new TreeView { Name = Name, Stats = Stats, Desc = Desc };
        }
    }

    public sealed class TreeData
    {
        public readonly Dictionary<int, TreeNode> Nodes = new Dictionary<int, TreeNode>();
        public readonly List<TreeNode> Ordered = new List<TreeNode>();
        public float MinX, MinY, MaxX, MaxY;

        public static TreeData Parse(string json)
        {
            var data = new TreeData();
            object root = Json.Parse(json);
            bool first = true;
            foreach (object o in Json.List(root, "nodes"))
            {
                var n = new TreeNode
                {
                    Id = Json.Int(o, "i"), X = (float)Json.Number(o, "x"), Y = (float)Json.Number(o, "y"),
                    Name = Json.Text(o, "n"), Desc = Json.Text(o, "d"), Line = Json.Text(o, "l"), Hidden = Json.Int(o, "h") == 1
                };
                string t = Json.Text(o, "t", "c");
                if (t.Length > 0) n.Type = t[0];
                n.Stats = Strings(Json.List(o, "s"));
                n.Classes = Strings(Json.List(o, "c"));
                var links = new List<int>();
                foreach (object l in Json.List(o, "o")) if (l is double d) links.Add((int)d);
                n.Links = links.ToArray();
                var effects = new List<TreeEffect>();
                foreach (object e in Json.List(o, "a")) effects.Add(new TreeEffect { Name = Json.Text(e, "n"), Stats = Strings(Json.List(e, "s")) });
                n.Effects = effects.ToArray();
                if (Json.Get(o, "v") is Dictionary<string, object> vs)
                    foreach (var kv in vs)
                        n.Variants[kv.Key] = new TreeView { Name = Json.Text(kv.Value, "n"), Stats = Strings(Json.List(kv.Value, "s")), Desc = Json.Text(kv.Value, "d") };
                data.Nodes[n.Id] = n;
                data.Ordered.Add(n);
                if (!n.Hidden)
                {
                    if (first) { data.MinX = data.MaxX = n.X; data.MinY = data.MaxY = n.Y; first = false; }
                    data.MinX = Math.Min(data.MinX, n.X); data.MaxX = Math.Max(data.MaxX, n.X);
                    data.MinY = Math.Min(data.MinY, n.Y); data.MaxY = Math.Max(data.MaxY, n.Y);
                }
            }
            return data;
        }

        static string[] Strings(List<object> list)
        {
            var r = new List<string>();
            foreach (object o in list) if (o is string s) r.Add(s);
            return r.ToArray();
        }
    }

    /// <summary>The respec prices of the server (respecInfo).</summary>
    public sealed class RespecInfo
    {
        public int Level;
        public long Full, Paragon, Node;
        public string Free = "";
        public int FreeBelowLevel;
    }

    public sealed class PassiveTree
    {
        public const byte Opcode = 65;
        public const int Root = 1;
        public const int History = 100;

        readonly ExtOpcodes ext;
        public TreeData Data;
        public int Free;
        public readonly HashSet<int> Allocated = new HashSet<int>();
        public readonly Dictionary<int, int> Masteries = new Dictionary<int, int>();
        public int Preset;
        public readonly List<string> PresetNames = new List<string>();
        public string Cls = "", Line = "", Vocation = "";
        public RespecInfo Respec;
        public int BossGot, BossTotal;
        public string BossLabel = "";
        public bool Synced;

        // the plan
        public readonly List<int> PlanList = new List<int>();
        public readonly HashSet<int> PlanSet = new HashSet<int>();
        public readonly Dictionary<int, int> PlanMasteries = new Dictionary<int, int>();
        readonly List<Snapshot> undo = new List<Snapshot>(), redo = new List<Snapshot>();
        public int UndoCount => undo.Count;
        public int RedoCount => redo.Count;

        // messages
        public string BoxTitle = "", BoxText = "";
        public string PlanMessage = "";
        public bool PlanOk;
        public string BuildMessage = "", BuildCodeText = "";
        public bool BuildError;
        /// <summary>The build code preview (buildPreview): the nodes it would give, null when none is shown.</summary>
        public HashSet<int> PreviewNodes;
        public string PreviewCode = "";
        public long PreviewCost;
        public string PreviewSummary = "";
        public Action Changed = delegate { };
        /// <summary>Counts every change, so a window can cache what it derives (reachable nodes, search matches).</summary>
        public int Version;
        void Touch() { Version++; Changed(); }

        sealed class Snapshot { public List<int> List; public Dictionary<int, int> Masteries; }

        Dictionary<int, List<int>> adjacency;

        public PassiveTree(ExtOpcodes e)
        {
            ext = e;
            ext.On(Opcode, OnMessage);
        }

        public void Load(string json) { SetData(TreeData.Parse(json)); }

        /// <summary>Uses a parsed layout (the window keeps one for every login).</summary>
        public void SetData(TreeData data)
        {
            Data = data;
            adjacency = null;
            Touch();
        }

        public bool Ready => Data != null;

        // ------------------------------------------------------------------------------------ requests
        public void Open()
        {
            ext.Send(Opcode, "requestPoints");
            ext.Send(Opcode, "requestNodesUnlocked");
            ext.Send(Opcode, "respecInfo");
        }

        public void Resync() { ext.Send(Opcode, "refund"); }

        public void Apply()
        {
            if (PlanList.Count == 0) { Say(Loc.T("Apply plan"), Loc.T("Nothing is planned. Click a node to plan the path to it.")); return; }
            var missing = MissingMasteries();
            if (missing.Count > 0) { Say(Loc.T("Apply plan"), Loc.T("Choose the effect of {0} first.", NameOf(missing[0]))); return; }
            if (PlanList.Count > Free)
            {
                Say(Loc.T("Apply plan"), Loc.T("The plan needs {0} points; you have {1} free. Undo or take nodes out first.", PlanList.Count, Free));
                return;
            }
            ext.Send(Opcode, "planApply", Request());
            PlanMessage = Loc.T("Applying...");
            PlanOk = true;
            Touch();
        }

        /// <summary>The planApply data: {nodes, masteries}.</summary>
        public Dictionary<string, object> Request()
        {
            var nodes = new List<object>();
            var masteries = new List<object>();
            foreach (int id in PlanList) nodes.Add(id);
            foreach (int id in PlanList)
                if (PlanMasteries.TryGetValue(id, out int c)) masteries.Add(new Dictionary<string, object> { { "id", id }, { "choice", c } });
            return new Dictionary<string, object> { { "nodes", nodes }, { "masteries", masteries } };
        }

        public void RefundNode(int id) { ext.Send(Opcode, "refundNode", new Dictionary<string, object> { { "id", id } }); }

        public void ResetTree()
        {
            ext.Send(Opcode, "resetPreset", Preset > 0 ? Preset : 1);
            ext.Send(Opcode, "requestPoints");
        }

        public void ChangeSavedMastery(int id, int choice)
        {
            ext.Send(Opcode, "masteryChoose", new Dictionary<string, object> { { "id", id }, { "choice", choice } });
        }

        public void ExportBuild(bool full) { ext.Send(Opcode, "buildExport", full ? new Dictionary<string, object> { { "full", true } } : null); }

        public void PreviewBuild(string code)
        {
            code = (code ?? "").Trim();
            string tree = code;
            if (code.StartsWith("CC", StringComparison.Ordinal))
            {
                var card = BuildCode.Decode(code, out string err);
                if (card == null) { BuildMessage = Loc.T("The build code is not valid ({0}).", err); BuildError = true; Touch(); return; }
                if (card.Tree == null) { BuildMessage = Loc.T("This build code holds no passive tree."); BuildError = true; Touch(); return; }
                tree = card.Tree;
            }
            if (tree.Length == 0) { BuildMessage = Loc.T("Paste a build code first."); BuildError = true; Touch(); return; }
            if (!tree.StartsWith(BuildCode.TreePrefix, StringComparison.Ordinal)) { BuildMessage = Loc.T("The build code is not valid ({0}).", "format"); BuildError = true; Touch(); return; }
            ext.Send(Opcode, "buildPreview", new Dictionary<string, object> { { "code", tree } });
        }

        public void ApplyBuild()
        {
            if (PreviewNodes == null || PreviewCode.Length == 0) return;
            ext.Send(Opcode, "buildApply", new Dictionary<string, object> { { "code", PreviewCode }, { "cost", PreviewCost } });
        }

        public void CancelPreview() { PreviewNodes = null; PreviewCode = ""; PreviewSummary = ""; Touch(); }

        void Say(string title, string text) { BoxTitle = title; BoxText = text; Touch(); }

        // ------------------------------------------------------------------------------------ messages
        void OnMessage(ExtMessage m) { Handle(m.Action, m.Data); }

        public void Handle(string action, object data)
        {
            switch (action)
            {
                case "sendPoints":
                    if (data is double d) Free = (int)d;
                    break;
                case "sendNodes": ApplyNodes(data); return;
                case "planResult":
                    PlanOk = Json.Bool(data, "ok");
                    PlanMessage = Json.Text(data, "message", PlanOk ? Loc.T("Applied.") : Loc.T("The plan was not applied."));
                    if (PlanOk) ResetPlan();
                    else Say(Loc.T("Passive tree"), PlanMessage);
                    break;
                case "sendMessage": Say(Json.Text(data, "title"), Json.Text(data, "message")); return;
                case "respecInfo":
                    Respec = new RespecInfo
                    {
                        Level = Json.Int(data, "level"), Full = (long)Json.Number(data, "full"), Paragon = (long)Json.Number(data, "paragon"),
                        Node = (long)Json.Number(data, "node"), Free = Json.Get(data, "free") as string ?? "", FreeBelowLevel = Json.Int(data, "freeBelowLevel", 50)
                    };
                    break;
                case "statTotals": Totals = TreeTotals.Parse(data); break;
                case "bossPoints":
                    BossGot = Json.Int(data, "got"); BossTotal = Json.Int(data, "total"); BossLabel = Json.Text(data, "label");
                    break;
                case "buildCode":
                    BuildCodeText = Json.Text(data, "code");
                    BuildError = false;
                    if (Json.Bool(data, "full")) BuildCodeText = FullCode(BuildCodeText, data);
                    BuildMessage = Loc.T("Your build code ({0} nodes) is ready. Copy it and share it.", Json.List(data, "nodes").Count);
                    break;
                case "buildPreview":
                    PreviewNodes = new HashSet<int>();
                    foreach (object o in Json.List(data, "nodes")) if (o is double n) PreviewNodes.Add((int)n);
                    PreviewCode = Json.Text(data, "code");
                    PreviewCost = (long)Json.Number(data, "cost");
                    PreviewSummary = Json.Text(data, "summary") + (Json.Get(data, "change") is bool ch && ch
                        ? "\n" + Loc.T("The tree shows the build now. Apply Build to take it, Cancel Preview to go back.") : "");
                    BuildError = false;
                    BuildMessage = Loc.T("Points: the build needs {0}, you own {1}.", Json.Int(data, "wanted"), Json.Int(data, "points"));
                    break;
                case "buildError":
                    BuildMessage = Json.Text(data, "message", Loc.T("The build could not be imported."));
                    BuildError = true;
                    break;
                case "buildApplied":
                    PreviewNodes = null; PreviewCode = "";
                    BuildMessage = Json.Text(data, "message", Loc.T("Build imported."));
                    BuildError = false;
                    break;
                default: return;
            }
            Touch();
        }

        /// <summary>Class index, level and the worn gear of the server's full export go into one CC1 code (spells stay out: the rotation
        /// lives in the main client's Auto setup).</summary>
        string FullCode(string tree, object data)
        {
            var gear = new List<KeyValuePair<int, int>>();
            foreach (object g in Json.List(data, "gear")) gear.Add(new KeyValuePair<int, int>(Json.Int(g, "slot"), Json.Int(g, "id")));
            string cls = Cls;
            var card = new BuildCard { Class = cls.Length > 0 ? cls : null, Level = Level > 0 ? Level : (int?)null, Tree = tree, Gear = gear };
            string code = BuildCode.Encode(card, out _);
            return code ?? tree;
        }

        /// <summary>The character level (for the full export); set by the window.</summary>
        public int Level;

        /// <summary>Raw against effective stat totals (statTotals, passivetree_totals.lua); null until the server answered.</summary>
        public TreeTotals Totals;
        /// <summary>True when the allocation changed after the last statTotals request; the window asks again while open.</summary>
        public bool TotalsStale = true;
        public void RequestTotals() { TotalsStale = false; ext.Send(Opcode, "statTotals"); }

        void ApplyNodes(object data)
        {
            Allocated.Clear();
            foreach (object o in Json.List(data, "nodes"))
            {
                if (o is double d) Allocated.Add((int)d);
                else if (o is string s && int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out int id)) Allocated.Add(id);
            }
            Masteries.Clear();
            foreach (object o in Json.List(data, "masteries")) Masteries[Json.Int(o, "id")] = Json.Int(o, "choice");
            if (Json.Get(data, "vocation") is string v) Vocation = v;
            if (Json.Get(data, "cls") is string c) Cls = c;
            if (Json.Get(data, "line") is string l) Line = l;
            Preset = Json.Int(data, "preset");
            TotalsStale = true;
            PresetNames.Clear();
            foreach (object p in Json.List(data, "presetsTable")) PresetNames.Add(Json.Text(p, "name"));
            PreviewNodes = null;
            Synced = true;
            // ids the server saved leave the plan (the main client's TreePlan.prune)
            bool pruned = false;
            for (int i = PlanList.Count - 1; i >= 0; i--)
                if (Allocated.Contains(PlanList[i])) { PlanSet.Remove(PlanList[i]); PlanMasteries.Remove(PlanList[i]); PlanList.RemoveAt(i); pruned = true; }
            if (pruned) { }
            Touch();
        }

        // ------------------------------------------------------------------------------------ what the player may do
        public bool Shown(TreeNode n) => !n.Hidden && (n.Line.Length == 0 || n.Line == Line);

        /// <summary>The node's classes include the player's (a node without a list is for everyone).</summary>
        public bool Allowed(TreeNode n)
        {
            if (n.Classes.Length == 0) return true;
            foreach (string c in n.Classes) if (c == Cls) return true;
            return false;
        }

        public TreeView View(TreeNode n) => n.For(Vocation.Length > 0 ? Vocation : null);

        public string NameOf(int id) => Data != null && Data.Nodes.TryGetValue(id, out var n) ? View(n).Name : "#" + id;

        /// <summary>Start nodes that are always owned: the root and the start of the player's class section.</summary>
        public IEnumerable<int> Starts()
        {
            if (Data == null) yield break;
            foreach (var n in Data.Ordered)
                if (n.IsStart && (n.Line.Length == 0 || n.Line == Line)) yield return n.Id;
        }

        public Dictionary<int, List<int>> Graph()
        {
            if (adjacency != null || Data == null) return adjacency ?? new Dictionary<int, List<int>>();
            var adj = new Dictionary<int, List<int>>();
            foreach (var n in Data.Ordered)
            {
                if (n.Hidden) continue;
                foreach (int o in n.Links)
                {
                    if (!Data.Nodes.TryGetValue(o, out var other) || other.Hidden || o == n.Id) continue;
                    Add(adj, n.Id, o);
                    Add(adj, o, n.Id);
                }
            }
            foreach (var list in adj.Values) list.Sort();
            adjacency = adj;
            return adj;
        }

        static void Add(Dictionary<int, List<int>> adj, int a, int b)
        {
            if (!adj.TryGetValue(a, out var l)) adj[a] = l = new List<int>();
            if (!l.Contains(b)) l.Add(b);
        }

        public HashSet<int> Owned()
        {
            var set = new HashSet<int>(Allocated);
            foreach (int s in Starts()) set.Add(s);
            return set;
        }

        HashSet<int> OwnedPlus() { var set = Owned(); foreach (int id in PlanSet) set.Add(id); return set; }

        bool Passable(int id)
        {
            if (!Data.Nodes.TryGetValue(id, out var n)) return false;
            return Shown(n) && Allowed(n) && !n.IsStart;
        }

        /// <summary>Shortest path from the owned set to target over nodes the class can take: the new ids, target last. Empty when owned,
        /// null when there is no path. Ties go to the lower ids, so the same click plans the same path.</summary>
        public static List<int> FindPath(Dictionary<int, List<int>> adj, HashSet<int> owned, int target, Func<int, bool> passable)
        {
            if (owned.Contains(target)) return new List<int>();
            if (!passable(target)) return null;
            var sources = new List<int>(owned);
            sources.Sort();
            var parent = new Dictionary<int, int>();
            var queue = new List<int>();
            foreach (int s in sources) { parent[s] = -1; queue.Add(s); }
            for (int head = 0; head < queue.Count; head++)
            {
                int id = queue[head];
                if (!adj.TryGetValue(id, out var nbs)) continue;
                foreach (int o in nbs)
                {
                    if (parent.ContainsKey(o) || !passable(o)) continue;
                    parent[o] = id;
                    if (o == target)
                    {
                        var path = new List<int>();
                        int at = o;
                        while (at != -1 && !owned.Contains(at)) { path.Insert(0, at); at = parent[at]; }
                        return path;
                    }
                    queue.Add(o);
                }
            }
            return null;
        }

        // ------------------------------------------------------------------------------------ the plan
        public enum Click { None, Planned, Unplanned, ChooseMastery, ChangeSavedMastery, Locked, NoPath, Saved, Preview }

        /// <summary>A left click on a node, as the main client's plannerClick.</summary>
        public Click ClickNode(int id)
        {
            if (Data == null || !Data.Nodes.TryGetValue(id, out var n) || !Shown(n) || n.IsStart) return Click.None;
            if (PreviewNodes != null)
            {
                Say(Loc.T("Planner"), Loc.T("A build code preview is shown. Cancel the preview (Build Code) to plan again."));
                return Click.Preview;
            }
            if (Allocated.Contains(id)) return n.IsMastery ? Click.ChangeSavedMastery : Click.Saved;
            if (PlanSet.Contains(id))
            {
                if (n.IsMastery) return Click.ChooseMastery;
                RemovePlanned(id);
                return Click.Unplanned;
            }
            if (!Allowed(n)) { Say(Loc.T("Planner"), Loc.T("This node belongs to another class.")); return Click.Locked; }
            var path = FindPath(Graph(), OwnedPlus(), id, Passable);
            if (path == null) { Say(Loc.T("Planner"), Loc.T("No path leads there over nodes your class can take.")); return Click.NoPath; }
            AddPath(path);
            return Click.Planned;
        }

        /// <summary>The first planned mastery without a chosen effect, or 0.</summary>
        public List<int> MissingMasteries()
        {
            var list = new List<int>();
            foreach (int id in PlanList)
                if (Data.Nodes.TryGetValue(id, out var n) && n.IsMastery && !PlanMasteries.ContainsKey(id)) list.Add(id);
            return list;
        }

        public void AddPath(List<int> path)
        {
            var fresh = new List<int>();
            foreach (int id in path) if (!PlanSet.Contains(id)) fresh.Add(id);
            if (fresh.Count == 0) return;
            Record();
            foreach (int id in fresh) { PlanList.Add(id); PlanSet.Add(id); }
            PlanMessage = "";
            Touch();
        }

        /// <summary>Takes a planned id out with every planned id that no longer connects to what is owned.</summary>
        public List<int> RemovePlanned(int id)
        {
            var removed = new List<int>();
            if (!PlanSet.Contains(id)) return removed;
            Record();
            var keep = new HashSet<int>(PlanList);
            keep.Remove(id);
            var adj = Graph();
            var reached = new HashSet<int>(Owned());
            var queue = new List<int>(reached);
            queue.Sort();
            for (int head = 0; head < queue.Count; head++)
            {
                if (!adj.TryGetValue(queue[head], out var nbs)) continue;
                foreach (int nb in nbs) if (keep.Contains(nb) && reached.Add(nb)) queue.Add(nb);
            }
            var list = new List<int>();
            foreach (int o in PlanList)
            {
                if (o != id && reached.Contains(o)) list.Add(o);
                else { removed.Add(o); PlanSet.Remove(o); PlanMasteries.Remove(o); }
            }
            PlanList.Clear();
            PlanList.AddRange(list);
            PlanMessage = "";
            Touch();
            return removed;
        }

        public bool SetPlanMastery(int id, int choice)
        {
            if (!PlanSet.Contains(id) || (PlanMasteries.TryGetValue(id, out int c) && c == choice)) return false;
            Record();
            PlanMasteries[id] = choice;
            Touch();
            return true;
        }

        public void ClearPlan()
        {
            if (PlanList.Count == 0) return;
            Record();
            PlanList.Clear(); PlanSet.Clear(); PlanMasteries.Clear();
            Touch();
        }

        public void ResetPlan()
        {
            PlanList.Clear(); PlanSet.Clear(); PlanMasteries.Clear(); undo.Clear(); redo.Clear();
        }

        Snapshot Take() => new Snapshot { List = new List<int>(PlanList), Masteries = new Dictionary<int, int>(PlanMasteries) };

        void Restore(Snapshot s)
        {
            PlanList.Clear(); PlanSet.Clear(); PlanMasteries.Clear();
            foreach (int id in s.List) { PlanList.Add(id); PlanSet.Add(id); }
            foreach (var kv in s.Masteries) PlanMasteries[kv.Key] = kv.Value;
        }

        void Record()
        {
            undo.Add(Take());
            if (undo.Count > History) undo.RemoveAt(0);
            redo.Clear();
        }

        public bool Undo()
        {
            if (undo.Count == 0) return false;
            var s = undo[undo.Count - 1];
            undo.RemoveAt(undo.Count - 1);
            redo.Add(Take());
            Restore(s);
            Touch();
            return true;
        }

        public bool Redo()
        {
            if (redo.Count == 0) return false;
            var s = redo[redo.Count - 1];
            redo.RemoveAt(redo.Count - 1);
            undo.Add(Take());
            Restore(s);
            Touch();
            return true;
        }

        /// <summary>"Plan: 5 / 12 points (3 short)" and whether it fits.</summary>
        public string CostText(out bool fits)
        {
            int cost = PlanList.Count, free = Math.Max(0, Free);
            fits = cost <= free;
            if (cost == 0) return Loc.T("No plan: click a node to plan the path to it.");
            string text = Loc.T("Plan: {0} / {1} points", cost, free);
            return fits ? text : text + Loc.T(" ({0} short)", cost - free);
        }

        // ------------------------------------------------------------------------------------ search
        /// <summary>The searchable text of a node: its name, stat lines and effects as the class sees them.</summary>
        public string SearchText(TreeNode n)
        {
            var v = View(n);
            var sb = new StringBuilder(v.Name);
            foreach (string s in v.Stats) sb.Append(' ').Append(s);
            sb.Append(' ').Append(v.Desc);
            foreach (var e in n.Effects) { sb.Append(' ').Append(e.Name); foreach (string s in e.Stats) sb.Append(' ').Append(s); }
            return Normalize(sb.ToString());
        }

        public static string Normalize(string text)
        {
            var sb = new StringBuilder();
            bool space = true;
            foreach (char c in (text ?? "").ToLowerInvariant())
            {
                if (char.IsWhiteSpace(c)) { if (!space) sb.Append(' '); space = true; }
                else { sb.Append(c); space = false; }
            }
            return sb.ToString().TrimEnd();
        }

        /// <summary>Ids of the shown nodes (not starts) whose text holds every word of the query, in id order.</summary>
        public List<int> Search(string query)
        {
            var found = new List<int>();
            if (Data == null) return found;
            var words = Normalize(query).Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (words.Length == 0) return found;
            foreach (var n in Data.Ordered)
            {
                if (n.IsStart || !Shown(n)) continue;
                string text = SearchText(n);
                bool all = true;
                foreach (string w in words) if (text.IndexOf(w, StringComparison.Ordinal) < 0) { all = false; break; }
                if (all) found.Add(n.Id);
            }
            found.Sort();
            return found;
        }

        /// <summary>The next index in 1..count going dir (+1 or -1), wrapping; 0 when count is 0.</summary>
        public static int Step(int index, int count, int dir)
        {
            if (count <= 0) return 0;
            if (index < 1 || index > count) return dir < 0 ? count : 1;
            return ((index - 1 + (dir < 0 ? -1 : 1)) % count + count) % count + 1;
        }

        /// <summary>The summed stat lines of a set of nodes are not computed here (the server has the totals); this counts the nodes.</summary>
        public int OwnedCount()
        {
            int n = 0;
            foreach (int id in Allocated) if (Data != null && Data.Nodes.TryGetValue(id, out var node) && !node.IsStart) n++;
            return n;
        }
    }

    /// <summary>One line of the totals section: text and whether it is an overflow or a head line.</summary>
    public struct TotalsLine { public string Text; public char Kind; }

    /// <summary>statTotals: attributes and damage rows {k, n, raw, eff, cap}, crit chance and damage, attack speed (totalsview.lua).</summary>
    public sealed class TreeTotals
    {
        public readonly List<TotalsLine> Lines = new List<TotalsLine>();

        public static string Num(double v)
        {
            string s = v.ToString("0.0", CultureInfo.InvariantCulture);
            return s.EndsWith(".0", StringComparison.Ordinal) ? s.Substring(0, s.Length - 2) : s;
        }

        public static TreeTotals Parse(object data)
        {
            var t = new TreeTotals();
            if (data == null) return t;
            foreach (object row in Json.List(data, "attributes"))
            {
                string n = RowName(row);
                double raw = Json.Number(row, "raw"), eff = Json.Number(row, "eff"), cap = Json.Number(row, "cap");
                if (raw > cap) t.Add(Loc.T("{0}: {1} points -> {2} effective (full value up to {3})", n, Num(raw), Num(eff), Num(cap)), 'o');
                else t.Add(Loc.T("{0}: {1} points (full value up to {2})", n, Num(raw), Num(cap)), 't');
            }
            foreach (object row in Json.List(data, "damage"))
            {
                string n = RowName(row);
                double raw = Json.Number(row, "raw"), eff = Json.Number(row, "eff"), cap = Json.Number(row, "cap");
                if (raw > cap) t.Add(Loc.T("{0}: +{1}% -> +{2}% effective (full value up to +{3}%)", n, Num(raw), Num(eff), Num(cap)), 'o');
                else t.Add(Loc.T("{0}: +{1}% (full value up to +{2}%)", n, Num(raw), Num(cap)), 't');
            }
            object crit = Json.Get(data, "crit");
            object ch = Json.Get(crit, "chance"), am = Json.Get(crit, "amount");
            if (ch != null && am != null)
            {
                t.Add(Loc.T("Critical chance: {0}% (tree {1}%, gear and other {2}%)", Num(Json.Number(ch, "total")), Num(Json.Number(ch, "tree")), Num(Json.Number(ch, "other"))), 'h');
                t.Add(Loc.T("Critical damage: +{0}% (tree {1}%, Paragon {2}%, gear and other {3}%)", Num(Json.Number(am, "total")), Num(Json.Number(am, "tree")),
                    Num(Json.Number(am, "paragon")), Num(Json.Number(am, "other"))), 'h');
            }
            object a = Json.Get(data, "attackSpeed");
            if (a != null && Json.Get(a, "total") != null)
                t.Add(Loc.T("Attack speed: +{0}% (tree {1}%, gear {2}%; at most 1 attack per second)", Num(Json.Number(a, "total")), Num(Json.Number(a, "tree")), Num(Json.Number(a, "gear"))), 'h');
            return t;
        }

        static string RowName(object row) { string n = Json.Text(row, "n"); return n.Length > 0 ? n : Json.Text(row, "k"); }
        void Add(string text, char kind) { Lines.Add(new TotalsLine { Text = text, Kind = kind }); }
    }
}
