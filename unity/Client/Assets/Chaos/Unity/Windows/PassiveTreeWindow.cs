// Passive tree (Ctrl+T), the main client's game_passivetree on the same opcode (65). The layout comes from Resources/PassiveTree.json
// (unity/tools/gen_tree_data.lua), the allocation from the server. A pannable, zoomable node graph: drag to pan, the wheel zooms
// round the pointer, hover for the tooltip. A left click plans the path to a node (green), a click on a planned node takes it out,
// Apply sends the plan (planApply), a right click on a saved node refunds it for the server's price. Masteries ask for their effect.
// The search box frames matches in orange, Prev / Next step through them. Build Code exports, previews and applies a code.
// Core: Core/PassiveTree.cs, Core/BuildCode.cs.
using System;
using System.Collections.Generic;
using System.Globalization;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class PassiveTreeWindow : GameWindow
    {
        enum Panel { None, Mastery, Refund, Reset, Box, Build, Totals, Paragon }

        static TreeData cache;
        static Texture2D disc, ring;
        Vector2 center;
        float zoom = 0.2f;
        bool fitted, wasOpen, dragging;
        Vector2 dragStart, dragOrigin;
        float dragMoved;
        Panel panel = Panel.None;
        int panelNode;
        bool panelSaved;
        string search = "", code = "";
        List<int> matches = new List<int>();
        int matchIndex;
        int builtVersion = -1;
        string builtSearch = null;
        HashSet<int> reachable = new HashSet<int>();
        List<int[]> links = new List<int[]>();
        int hover;
        GUIStyle tip, tipTitle, label, mid;
        string lastBox = "";
        float lastTotals;
        Rect lastView = new Rect(0, 0, 800, 480);

        public override string Title => Loc.T("Passive Tree");
        public override KeyCode Hotkey => KeyCode.N;
        protected override Rect Place(float w, float h) => new Rect(Mathf.Max(8, (w - 860) / 2), 44, Mathf.Min(860, w - 16), Mathf.Min(580, h - 60));

        public override void Reset()
        {
            fitted = false; wasOpen = false; panel = Panel.None; search = ""; code = ""; matches.Clear(); matchIndex = 0; builtVersion = -1; builtSearch = null;
            hover = 0; lastBox = "";
        }

        public override void Tick(ChaosApp app)
        {
            var tree = app.Session?.Progress?.Tree;
            if (tree == null) return;
            if (Open && !wasOpen)
            {
                EnsureData(tree);
                tree.Open();
            }
            wasOpen = Open;
            if (Open && tree.TotalsStale && Time.unscaledTime - lastTotals > 0.6f) { lastTotals = Time.unscaledTime; tree.RequestTotals(); }
            // a message from the server (an error, a refusal) shows in a box over the tree
            if (Open && tree.BoxText.Length > 0 && tree.BoxText != lastBox) { lastBox = tree.BoxText; panel = Panel.Box; }
        }

        static void EnsureData(PassiveTree tree)
        {
            if (tree.Ready) return;
            if (cache == null)
            {
                var asset = Resources.Load<TextAsset>("PassiveTree");
                if (asset != null) { try { cache = TreeData.Parse(asset.text); } catch (Exception) { cache = null; } }
            }
            if (cache != null) tree.SetData(cache);
        }

        static Texture2D Disc(bool filled)
        {
            if (filled && disc != null) return disc;
            if (!filled && ring != null) return ring;
            const int n = 64;
            var t = new Texture2D(n, n, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            var px = new Color32[n * n];
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                {
                    float d = Mathf.Sqrt((x - n / 2 + 0.5f) * (x - n / 2 + 0.5f) + (y - n / 2 + 0.5f) * (y - n / 2 + 0.5f)) / (n / 2f);
                    float a = filled ? Mathf.Clamp01((1f - d) * 24f) : Mathf.Clamp01((1f - d) * 24f) * Mathf.Clamp01((d - 0.78f) * 24f);
                    px[y * n + x] = new Color32(255, 255, 255, (byte)(a * 255));
                }
            t.SetPixels32(px);
            t.Apply();
            if (filled) disc = t; else ring = t;
            return t;
        }

        // the radius of a node in tree units
        static float Radius(TreeNode n)
        {
            switch (n.Type)
            {
                case 's': return 36;
                case 'M': return 24;
                case 'd': return 28;
                case 'm': return 17;
                case 'v': return 20;
                case 'r': return 16;
                case 'u': return 13;
                default: return 10;
            }
        }

        static Color TypeColor(TreeNode n)
        {
            switch (n.Type)
            {
                case 's': return new Color(0.85f, 0.7f, 0.3f);
                case 'M': return new Color(0.3f, 0.75f, 0.75f);
                case 'd': return n.Name.EndsWith("Keystone", StringComparison.Ordinal) || n.Classes.Length > 0 ? new Color(0.95f, 0.45f, 0.25f) : new Color(0.95f, 0.8f, 0.4f);
                case 'm': return new Color(0.7f, 0.5f, 0.9f);
                case 'v': return new Color(0.9f, 0.55f, 0.85f);
                case 'r': return new Color(0.4f, 0.6f, 0.95f);
                case 'u': return new Color(0.45f, 0.8f, 0.5f);
                default: return new Color(0.62f, 0.6f, 0.58f);
            }
        }

        void Styles(ChaosApp app)
        {
            if (tip != null) return;
            tip = new GUIStyle(app.SmallStyle) { fontSize = 12, wordWrap = true, richText = false };
            tipTitle = new GUIStyle(tip) { fontStyle = FontStyle.Bold, fontSize = 13 };
            label = new GUIStyle(app.SmallStyle) { fontSize = 11, alignment = TextAnchor.UpperCenter };
            mid = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleCenter, wordWrap = true };
        }

        Vector2 ToScreen(float x, float y, Rect vp) => new Vector2(vp.width / 2 + (x - center.x) * zoom, vp.height / 2 + (y - center.y) * zoom);

        void Fit(PassiveTree tree, Rect vp)
        {
            var d = tree.Data;
            float w = d.MaxX - d.MinX + 200, h = d.MaxY - d.MinY + 200;
            zoom = Mathf.Clamp(Mathf.Min(vp.width / w, vp.height / h), 0.04f, 1.5f);
            center = new Vector2((d.MinX + d.MaxX) / 2, (d.MinY + d.MaxY) / 2);
        }

        void Focus(TreeNode n)
        {
            center = new Vector2(n.X, n.Y);
            zoom = Mathf.Max(zoom, 0.35f);
        }

        // ------------------------------------------------------------------------------------ derived sets
        void Rebuild(PassiveTree tree)
        {
            if (builtVersion == tree.Version && builtSearch == search) return;
            builtVersion = tree.Version;
            reachable.Clear();
            if (tree.Ready)
            {
                var adj = tree.Graph();
                var owned = tree.Owned();
                foreach (int id in tree.PlanSet) owned.Add(id);
                foreach (int id in owned)
                    if (adj.TryGetValue(id, out var nbs))
                        foreach (int o in nbs)
                            if (!owned.Contains(o) && tree.Data.Nodes.TryGetValue(o, out var n) && tree.Shown(n) && tree.Allowed(n) && !n.IsStart) reachable.Add(o);
                // each link once, shown nodes only; the root's own links are not drawn (its nodes sit on its ring)
                links.Clear();
                foreach (var kv in adj)
                    foreach (int o in kv.Value)
                        if (kv.Key < o && tree.Data.Nodes.TryGetValue(kv.Key, out var a) && tree.Data.Nodes.TryGetValue(o, out var b) && tree.Shown(a) && tree.Shown(b)
                            && !((a.IsStart && a.Line.Length == 0) || (b.IsStart && b.Line.Length == 0)))
                            links.Add(new[] { kv.Key, o });
            }
            if (builtSearch != search)
            {
                builtSearch = search;
                matches = tree.Search(search);
                matchIndex = 0;
            }
        }

        // ------------------------------------------------------------------------------------ body
        protected override void Body(ChaosApp app, Rect inner)
        {
            var session = app.Session;
            var tree = session?.Progress?.Tree;
            if (tree == null) return;
            Styles(app);
            EnsureData(tree);
            tree.Level = session.Parser.Level;
            if (!tree.Ready)
            {
                GUI.Label(inner, Loc.T("The passive tree data is missing from this build."), mid);
                return;
            }
            Rebuild(tree);
            var e = Event.current;
            float y = inner.y;
            Toolbar(app, tree, new Rect(inner.x, y, inner.width, 52));
            var vp = new Rect(inner.x, inner.y + 54, inner.width, inner.height - 54);
            lastView = vp;
            if (!fitted && vp.width > 50) { Fit(tree, vp); fitted = true; }
            GraphView(app, tree, vp, e);
            if (panel != Panel.None) DrawPanel(app, tree, vp);
        }

        void Toolbar(ChaosApp app, PassiveTree tree, Rect r)
        {
            // row 1: points, boss points, class, plan text
            string head = Loc.T("{0} points", Fmt.Short(tree.Free));
            if (tree.BossTotal > 0) head += "   " + Loc.T("Boss points {0}/{1}", tree.BossGot, tree.BossTotal);
            if (tree.Cls.Length > 0) head += "   " + char.ToUpperInvariant(tree.Cls[0]) + tree.Cls.Substring(1);
            GUI.Label(new Rect(r.x + 4, r.y, 330, 20), head, app.SmallStyle);
            // phase 7 track Y: another character's tree on show (read-only), and the Paragon panel
            bool viewing = tree.Viewing != null;
            if (viewing)
            {
                var vs = new GUIStyle(app.SmallStyle);
                vs.normal.textColor = new Color(0.96f, 0.81f, 0.45f);
                GUI.Label(new Rect(r.x + 336, r.y, r.width - 336 - 124, 20), tree.Viewing.Banner, vs);
                if (GUI.Button(new Rect(r.xMax - 120, r.y, 118, 22), Loc.T("Back to my tree"))) { tree.CloseOther(); fitted = false; }
            }
            else if (GUI.Button(new Rect(r.xMax - 72, r.y, 70, 22), Loc.T("Paragon"))) { panel = Panel.Paragon; tree.Paragon.Request(); }
            bool fits = true;
            string plan = viewing ? "" : tree.CostText(out fits);
            if (tree.PlanMessage.Length > 0 && tree.PlanList.Count == 0) { plan = tree.PlanMessage; fits = tree.PlanOk; }
            var ps = new GUIStyle(app.SmallStyle);
            ps.normal.textColor = fits ? new Color(0.85f, 0.81f, 0.75f) : new Color(0.9f, 0.4f, 0.35f);
            if (!viewing) GUI.Label(new Rect(r.x + 336, r.y, r.width - 340 - 76, 20), plan, ps);
            // row 2: buttons and search
            float x = r.x + 2, by = r.y + 24;
            GUI.enabled = !viewing && tree.PlanList.Count > 0 && tree.PreviewNodes == null;
            if (GUI.Button(new Rect(x, by, 58, 24), Loc.T("Apply"))) tree.Apply();
            GUI.enabled = !viewing && tree.UndoCount > 0;
            if (GUI.Button(new Rect(x + 62, by, 26, 24), "<")) tree.Undo();
            GUI.enabled = !viewing && tree.RedoCount > 0;
            if (GUI.Button(new Rect(x + 90, by, 26, 24), ">")) tree.Redo();
            GUI.enabled = !viewing && tree.PlanList.Count > 0;
            if (GUI.Button(new Rect(x + 118, by, 52, 24), Loc.T("Clear"))) tree.ClearPlan();
            GUI.enabled = !viewing;
            if (GUI.Button(new Rect(x + 174, by, 52, 24), Loc.T("Reset"))) { panel = Panel.Reset; if (tree.Respec == null) tree.Open(); }
            if (GUI.Button(new Rect(x + 230, by, 82, 24), Loc.T("Build Code"))) { panel = Panel.Build; }
            GUI.enabled = true;
            if (GUI.Button(new Rect(x + 316, by, 56, 24), Loc.T("Totals"))) { panel = Panel.Totals; tree.RequestTotals(); }
            x += 60;
            if (GUI.Button(new Rect(x + 316, by, 24, 24), "+")) zoom = Mathf.Min(1.5f, zoom * 1.25f);
            if (GUI.Button(new Rect(x + 342, by, 24, 24), "-")) zoom = Mathf.Max(0.04f, zoom / 1.25f);
            if (GUI.Button(new Rect(x + 368, by, 40, 24), Loc.T("Fit"))) Fit(tree, lastView);
            // search
            float sx = x + 414;
            GUI.SetNextControlName("treeSearch");
            string typed = GUI.TextField(new Rect(sx, by + 1, Mathf.Max(80, r.width - sx - 134), 22), search, 40);
            if (GUI.GetNameOfFocusedControl() == "treeSearch") app.MarkTextEditing();
            search = typed;
            var e = Event.current;
            if (search.Length == 0 && e.type == EventType.Repaint && GUI.GetNameOfFocusedControl() != "treeSearch")
                GUI.Label(new Rect(sx + 3, by + 1, 120, 22), Loc.T("Search..."), app.SmallStyle);
            float nx = r.xMax - 128;
            GUI.enabled = matches.Count > 0;
            if (GUI.Button(new Rect(nx, by, 24, 24), "<")) StepMatch(tree, -1);
            if (GUI.Button(new Rect(nx + 26, by, 24, 24), ">")) StepMatch(tree, 1);
            GUI.enabled = true;
            string count = search.Trim().Length == 0 ? "" : matches.Count == 0 ? Loc.T("No match") : matchIndex + " / " + matches.Count;
            GUI.Label(new Rect(nx + 54, by + 2, 74, 20), count, app.SmallStyle);
            bool enter = e.type == EventType.KeyDown && (e.keyCode == KeyCode.Return || e.keyCode == KeyCode.KeypadEnter) && GUI.GetNameOfFocusedControl() == "treeSearch";
            if (enter) { StepMatch(tree, e.shift ? -1 : 1); e.Use(); }
        }

        void StepMatch(PassiveTree tree, int dir)
        {
            matchIndex = PassiveTree.Step(matchIndex, matches.Count, dir);
            if (matchIndex > 0 && tree.Data.Nodes.TryGetValue(matches[matchIndex - 1], out var n)) Focus(n);
        }

        // ------------------------------------------------------------------------------------ the graph
        void GraphView(ChaosApp app, PassiveTree tree, Rect vp, Event e)
        {
            ChaosApp.Fill(vp, new Color(0.02f, 0.015f, 0.03f, 1f));
            GUI.BeginClip(vp);
            var local = new Rect(0, 0, vp.width, vp.height);
            var data = tree.Data;
            var pre = tree.PreviewNodes;
            int cur = matchIndex > 0 && matchIndex <= matches.Count ? matches[matchIndex - 1] : 0;
            var matchSet = matches.Count > 0 ? new HashSet<int>(matches) : null;

            // input first: it only moves the view and clicks, the drawing below uses the result
            bool inView = panel == Panel.None && e.mousePosition.x >= 0 && e.mousePosition.y >= 0 && e.mousePosition.x < vp.width && e.mousePosition.y < vp.height;
            if (inView && e.type == EventType.ScrollWheel)
            {
                float f = e.delta.y < 0 ? 1.15f : 1f / 1.15f;
                var before = new Vector2((e.mousePosition.x - vp.width / 2) / zoom + center.x, (e.mousePosition.y - vp.height / 2) / zoom + center.y);
                zoom = Mathf.Clamp(zoom * f, 0.04f, 1.5f);
                center = before - new Vector2((e.mousePosition.x - vp.width / 2) / zoom, (e.mousePosition.y - vp.height / 2) / zoom);
                e.Use();
            }
            if (inView && e.type == EventType.MouseDown && (e.button == 0 || e.button == 1 || e.button == 2))
            {
                dragging = true; dragStart = e.mousePosition; dragOrigin = center; dragMoved = 0;
            }
            if (dragging && e.type == EventType.MouseDrag)
            {
                dragMoved = Mathf.Max(dragMoved, (e.mousePosition - dragStart).magnitude);
                if (dragMoved > 4) center = dragOrigin - (e.mousePosition - dragStart) / zoom;
                e.Use();
            }

            // hover: the node nearest the pointer within its radius
            hover = 0;
            if (inView || (dragging && e.type == EventType.MouseUp))
            {
                float best = float.MaxValue;
                foreach (var n in data.Ordered)
                {
                    if (!tree.Shown(n)) continue;
                    var p = ToScreen(n.X, n.Y, vp);
                    float rad = Mathf.Max(7f, Radius(n) * zoom) + 3f;
                    float d2 = (p - e.mousePosition).sqrMagnitude;
                    if (d2 <= rad * rad && d2 < best) { best = d2; hover = n.Id; }
                }
            }
            if (dragging && e.type == EventType.MouseUp)
            {
                dragging = false;
                if (dragMoved <= 4 && hover != 0 && panel == Panel.None) NodeClick(tree, hover, e.button);
                e.Use();
            }

            if (e.type == EventType.Repaint)
            {
                // links
                foreach (var l in links)
                {
                    var a = data.Nodes[l[0]]; var b = data.Nodes[l[1]];
                    var pa = ToScreen(a.X, a.Y, vp); var pb = ToScreen(b.X, b.Y, vp);
                    if ((pa.x < -20 && pb.x < -20) || (pa.x > vp.width + 20 && pb.x > vp.width + 20) || (pa.y < -20 && pb.y < -20) || (pa.y > vp.height + 20 && pb.y > vp.height + 20)) continue;
                    bool oa = tree.Allocated.Contains(l[0]) || a.IsStart, ob = tree.Allocated.Contains(l[1]) || b.IsStart;
                    bool pla = oa || tree.PlanSet.Contains(l[0]), plb = ob || tree.PlanSet.Contains(l[1]);
                    Color c = oa && ob ? new Color(0.9f, 0.72f, 0.3f, 0.95f) : pla && plb ? new Color(0.35f, 0.85f, 0.4f, 0.95f)
                        : pre != null && (pre.Contains(l[0]) || a.IsStart) && (pre.Contains(l[1]) || b.IsStart) ? new Color(0.3f, 0.8f, 0.9f, 0.9f)
                        : oa || ob ? new Color(0.55f, 0.45f, 0.25f, 0.8f) : new Color(0.3f, 0.28f, 0.3f, 0.7f);
                    Line(pa, pb, Mathf.Max(1.2f, 4f * zoom), c);
                }
                // nodes
                foreach (var n in data.Ordered)
                {
                    if (!tree.Shown(n)) continue;
                    var p = ToScreen(n.X, n.Y, vp);
                    float rad = Mathf.Max(3.5f, Radius(n) * zoom);
                    if (p.x < -rad || p.y < -rad || p.x > vp.width + rad || p.y > vp.height + rad) continue;
                    bool saved = tree.Allocated.Contains(n.Id) || n.IsStart;
                    bool planned = tree.PlanSet.Contains(n.Id);
                    bool shownByPreview = pre != null && pre.Contains(n.Id);
                    bool locked = !tree.Allowed(n);
                    Color baseColor = TypeColor(n);
                    Color fill = saved ? Color.Lerp(baseColor, new Color(1f, 0.85f, 0.35f), 0.7f) : planned ? new Color(0.35f, 0.9f, 0.4f) : shownByPreview ? new Color(0.35f, 0.85f, 0.95f) : baseColor * 0.55f;
                    fill.a = locked && !saved ? 0.35f : 1f;
                    var r = new Rect(p.x - rad, p.y - rad, rad * 2, rad * 2);
                    var old = GUI.color;
                    GUI.color = new Color(0f, 0f, 0f, fill.a);
                    GUI.DrawTexture(new Rect(r.x - 1.5f, r.y - 1.5f, r.width + 3, r.height + 3), Disc(true));
                    GUI.color = fill;
                    GUI.DrawTexture(r, Disc(true));
                    if (reachable.Contains(n.Id) && tree.PreviewNodes == null)
                    {
                        GUI.color = new Color(1f, 1f, 1f, 0.75f);
                        GUI.DrawTexture(new Rect(r.x - 2.5f, r.y - 2.5f, r.width + 5, r.height + 5), Disc(false));
                    }
                    if (matchSet != null && matchSet.Contains(n.Id))
                    {
                        GUI.color = n.Id == cur ? new Color(1f, 0.45f, 0.1f) : new Color(0.95f, 0.78f, 0.35f);
                        float g = n.Id == cur ? 6f : 4f;
                        GUI.DrawTexture(new Rect(r.x - g, r.y - g, r.width + 2 * g, r.height + 2 * g), Disc(false));
                    }
                    if (n.Id == hover)
                    {
                        GUI.color = Color.white;
                        GUI.DrawTexture(new Rect(r.x - 3, r.y - 3, r.width + 6, r.height + 6), Disc(false));
                    }
                    GUI.color = old;
                    // a name under the notable nodes once the view is close enough
                    if (zoom >= 0.3f && n.Type != 'c' && n.Type != 'u' && n.Type != 's')
                    {
                        var v = tree.View(n);
                        label.normal.textColor = new Color(0.82f, 0.78f, 0.7f, locked ? 0.4f : 0.9f);
                        GUI.Label(new Rect(p.x - 70, p.y + rad + 1, 140, 16), v.Name, label);
                    }
                }
            }

            if (hover != 0 && panel == Panel.None) Tooltip(app, tree, data.Nodes[hover], e.mousePosition, local);
            GUI.EndClip();
        }

        static void Line(Vector2 a, Vector2 b, float width, Color c)
        {
            var d = b - a;
            float len = d.magnitude;
            if (len < 0.5f) return;
            var old = GUI.matrix;
            var oldc = GUI.color;
            GUI.color = c;
            GUIUtility.RotateAroundPivot(Mathf.Atan2(d.y, d.x) * Mathf.Rad2Deg, a);
            GUI.DrawTexture(new Rect(a.x, a.y - width / 2, len, width), Texture2D.whiteTexture);
            GUI.matrix = old;
            GUI.color = oldc;
        }

        void NodeClick(PassiveTree tree, int id, int button)
        {
            var n = tree.Data.Nodes[id];
            if (button == 1)
            {
                // right click: refund a saved node (priced by the server)
                if (tree.Viewing == null && tree.Allocated.Contains(id) && !n.IsStart && tree.PreviewNodes == null) { panel = Panel.Refund; panelNode = id; if (tree.Respec == null) tree.Open(); }
                return;
            }
            if (button != 0) return;
            var result = tree.ClickNode(id);
            switch (result)
            {
                case PassiveTree.Click.ChangeSavedMastery: panel = Panel.Mastery; panelNode = id; panelSaved = true; break;
                case PassiveTree.Click.ChooseMastery: panel = Panel.Mastery; panelNode = id; panelSaved = false; break;
                case PassiveTree.Click.Planned:
                {
                    var missing = tree.MissingMasteries();
                    if (missing.Count > 0) { panel = Panel.Mastery; panelNode = missing[0]; panelSaved = false; }
                    break;
                }
            }
        }

        // ------------------------------------------------------------------------------------ tooltip
        void Tooltip(ChaosApp app, PassiveTree tree, TreeNode n, Vector2 mouse, Rect bounds)
        {
            var v = tree.View(n);
            const float W = 290f;
            var lines = new List<KeyValuePair<string, Color>>();
            Color text = new Color(0.86f, 0.82f, 0.75f);
            foreach (string s in v.Stats) lines.Add(new KeyValuePair<string, Color>(s, text));
            if (v.Desc.Length > 0) lines.Add(new KeyValuePair<string, Color>(v.Desc, new Color(0.75f, 0.72f, 0.68f)));
            if (n.IsMastery)
            {
                int chosen = tree.Masteries.TryGetValue(n.Id, out int sc) ? sc : tree.PlanMasteries.TryGetValue(n.Id, out int pc) ? pc : 0;
                for (int i = 0; i < n.Effects.Length; i++)
                    lines.Add(new KeyValuePair<string, Color>((i + 1) + ". " + n.Effects[i].Name + (chosen == i + 1 ? Loc.T(" (chosen)") : "") + ": " + string.Join(" ", n.Effects[i].Stats),
                        chosen == i + 1 ? new Color(0.95f, 0.85f, 0.45f) : text));
            }
            if (!tree.Allowed(n))
            {
                var names = new List<string>();
                foreach (string c in n.Classes) names.Add(ClassName(c));
                lines.Add(new KeyValuePair<string, Color>(Loc.T("Requires: {0}.", string.Join(", ", names)), new Color(0.9f, 0.45f, 0.4f)));
            }
            string state = n.IsStart ? "" : tree.Allocated.Contains(n.Id) ? Loc.T("Saved. Right-click to refund.") :
                tree.PlanSet.Contains(n.Id) ? Loc.T("Planned. Click to take it out.") : "";
            if (state.Length == 0 && !n.IsStart && tree.Allowed(n))
            {
                var path = PassiveTree.FindPath(tree.Graph(), OwnedPlus(tree), n.Id, id => tree.Data.Nodes.TryGetValue(id, out var x) && tree.Shown(x) && tree.Allowed(x) && !x.IsStart);
                state = path == null ? Loc.T("No path from your tree.") : path.Count == 1 ? Loc.T("Click to plan it (1 point).") : Loc.T("Click to plan the path ({0} points).", path.Count);
            }
            if (state.Length > 0) lines.Add(new KeyValuePair<string, Color>(state, new Color(0.6f, 0.8f, 0.95f)));

            float h = 8 + tipTitle.CalcHeight(new GUIContent(v.Name.Length > 0 ? v.Name : "-"), W - 12) + 4;
            foreach (var l in lines) h += tip.CalcHeight(new GUIContent(l.Key), W - 12) + 2;
            h += 6;
            float x = mouse.x + 16, y = mouse.y + 12;
            if (x + W > bounds.width) x = mouse.x - W - 12;
            if (y + h > bounds.height) y = Mathf.Max(0, bounds.height - h);
            if (x < 0) x = 0;
            ChaosApp.Fill(new Rect(x, y, W, h), new Color(0.05f, 0.04f, 0.06f, 0.97f));
            ChaosApp.Fill(new Rect(x, y, W, 1), new Color(0.6f, 0.5f, 0.3f));
            ChaosApp.Fill(new Rect(x, y + h - 1, W, 1), new Color(0.6f, 0.5f, 0.3f));
            tipTitle.normal.textColor = TypeColor(n) * 1.3f;
            float ty = y + 6;
            string title = v.Name.Length > 0 ? v.Name : Loc.T("Start");
            float th = tipTitle.CalcHeight(new GUIContent(title), W - 12);
            GUI.Label(new Rect(x + 6, ty, W - 12, th), title, tipTitle);
            ty += th + 4;
            foreach (var l in lines)
            {
                tip.normal.textColor = l.Value;
                float lh = tip.CalcHeight(new GUIContent(l.Key), W - 12);
                GUI.Label(new Rect(x + 6, ty, W - 12, lh), l.Key, tip);
                ty += lh + 2;
            }
        }

        static HashSet<int> OwnedPlus(PassiveTree tree)
        {
            var set = tree.Owned();
            foreach (int id in tree.PlanSet) set.Add(id);
            return set;
        }

        static string ClassName(string key)
        {
            foreach (var c in BuildCode.Classes) if (c[0] == key) return c[2];
            return key;
        }

        // ------------------------------------------------------------------------------------ panels over the graph
        void DrawPanel(ChaosApp app, PassiveTree tree, Rect vp)
        {
            ChaosApp.Fill(vp, new Color(0f, 0f, 0f, 0.55f));
            float w = Mathf.Min(panel == Panel.Totals ? 640 : panel == Panel.Paragon ? 560 : 460, vp.width - 24);
            float h = panel == Panel.Paragon ? vp.height - 12 : panel == Panel.Totals ? Mathf.Min(vp.height - 12, 90 + 20 * (tree.Totals?.Lines.Count ?? 1)) : panel == Panel.Build ? 330 : panel == Panel.Mastery ? 130 + 52 * (tree.Data.Nodes.TryGetValue(panelNode, out var mn) ? mn.Effects.Length : 0) : 170;
            h = Mathf.Min(h, vp.height - 12);
            var box = new Rect(vp.x + (vp.width - w) / 2, vp.y + (vp.height - h) / 2, w, h);
            ChaosApp.Fill(box, new Color(0.07f, 0.05f, 0.08f, 0.99f));
            ChaosApp.Fill(new Rect(box.x, box.y, box.width, 22), new Color(0.2f, 0.12f, 0.08f));
            var inner = new Rect(box.x + 10, box.y + 28, box.width - 20, box.height - 36);
            switch (panel)
            {
                case Panel.Box: BoxPanel(app, tree, box, inner); break;
                case Panel.Reset: ResetPanel(app, tree, box, inner); break;
                case Panel.Refund: RefundPanel(app, tree, box, inner); break;
                case Panel.Mastery: MasteryPanel(app, tree, box, inner); break;
                case Panel.Build: BuildPanel(app, tree, box, inner); break;
                case Panel.Totals: TotalsPanel(app, tree, box, inner); break;
                case Panel.Paragon: ParagonPanelView(app, tree, box, inner); break;
            }
        }

        Vector2 paragonScroll;
        bool paragonReset;

        // the Paragon panel (paragon.lua): points per stat with + and - (Shift: five), Apply sends the allocation, Reset refunds all for the server's price
        void ParagonPanelView(ChaosApp app, PassiveTree tree, Rect box, Rect inner)
        {
            var pg = tree.Paragon;
            Head(box, Loc.T("Paragon"));
            if (!pg.Known) { GUI.Label(new Rect(inner.x, inner.y, inner.width, 20), Loc.T("Asking the server..."), mid); }
            else if (!pg.Unlocked)
            {
                GUI.Label(new Rect(inner.x, inner.y, inner.width, 20), pg.Summary(), mid);
                GUI.Label(new Rect(inner.x, inner.y + 30, inner.width, 24), pg.LockedTitle, tipTitle);
                GUI.Label(new Rect(inner.x, inner.y + 58, inner.width, 60), pg.LockedText, tip);
            }
            else
            {
                GUI.Label(new Rect(inner.x, inner.y, inner.width, 20), pg.Summary(), mid);
                float listH = inner.height - 66;
                float rowH = 24;
                float total = 0;
                foreach (var c in pg.Categories) total += 22 + c.Stats.Count * rowH;
                paragonScroll = GUI.BeginScrollView(new Rect(inner.x, inner.y + 24, inner.width, listH), paragonScroll, new Rect(0, 0, inner.width - 18, Mathf.Max(listH, total)));
                float y = 0;
                bool shift = Event.current.shift;
                foreach (var c in pg.Categories)
                {
                    GUI.Label(new Rect(0, y, inner.width - 18, 20), c.Name, tipTitle);
                    y += 22;
                    foreach (var st in c.Stats)
                    {
                        int pts = pg.PointsOf(st);
                        bool pend = pg.CanRemove(st);
                        var rr = new Rect(0, y, inner.width - 18, rowH - 2);
                        ChaosApp.Fill(rr, new Color(1f, 1f, 1f, 0.05f));
                        GUI.Label(new Rect(6, y, 200, rowH), new GUIContent(st.Name, ParagonPanel.Tip(st)), app.SmallStyle);
                        var ps = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleRight };
                        ps.normal.textColor = pend ? new Color(0.96f, 0.81f, 0.45f) : new Color(0.84f, 0.79f, 0.68f);
                        GUI.Label(new Rect(208, y, 60, rowH), pts + "/" + st.MaxPoints, ps);
                        ps.normal.textColor = pts >= st.MaxPoints ? new Color(0.91f, 0.72f, 0.29f) : pend ? new Color(0.96f, 0.81f, 0.45f) : new Color(0.84f, 0.79f, 0.68f);
                        GUI.Label(new Rect(272, y, 120, rowH), ParagonPanel.ValueText(st, pts), ps);
                        GUI.enabled = pg.CanRemove(st);
                        if (GUI.Button(new Rect(inner.width - 18 - 62, y, 28, rowH - 2), "-")) pg.Remove(st, shift ? 5 : 1);
                        GUI.enabled = pg.CanAdd(st);
                        if (GUI.Button(new Rect(inner.width - 18 - 32, y, 28, rowH - 2), "+")) pg.Add(st, shift ? 5 : 1);
                        GUI.enabled = true;
                        y += rowH;
                    }
                }
                GUI.EndScrollView();
                float by = inner.yMax - 28;
                GUI.enabled = pg.PendingSum() > 0;
                if (GUI.Button(new Rect(inner.x, by, 90, 24), Loc.T("Apply"))) pg.Apply();
                GUI.enabled = pg.Spent > 0;
                if (GUI.Button(new Rect(inner.x + 94, by, 90, 24), new GUIContent(Loc.T("Reset"), pg.ResetTip))) paragonReset = true;
                GUI.enabled = true;
                if (!string.IsNullOrEmpty(GUI.tooltip)) { var ts = new GUIStyle(tip); GUI.Label(new Rect(inner.x + 190, by - 2, inner.width - 290, 28), GUI.tooltip, ts); }
            }
            if (GUI.Button(new Rect(inner.xMax - 90, inner.yMax - 28, 90, 24), Loc.T("Close"))) { panel = Panel.None; paragonReset = false; }
            if (paragonReset)
            {
                var ask = new Rect(box.x + 40, box.y + box.height / 2 - 50, box.width - 80, 100);
                ChaosApp.Fill(new Rect(ask.x - 2, ask.y - 2, ask.width + 4, ask.height + 4), new Color(0.5f, 0.4f, 0.2f));
                ChaosApp.Fill(ask, new Color(0.06f, 0.05f, 0.07f, 1f));
                GUI.Label(new Rect(ask.x + 8, ask.y + 8, ask.width - 16, 50), pg.ResetAsk, mid);
                if (GUI.Button(new Rect(ask.x + 10, ask.yMax - 32, 80, 24), Loc.T("Ok"))) { pg.Reset(); paragonReset = false; }
                if (GUI.Button(new Rect(ask.xMax - 90, ask.yMax - 32, 80, 24), Loc.T("Cancel"))) paragonReset = false;
            }
        }

        void TotalsPanel(ChaosApp app, PassiveTree tree, Rect box, Rect inner)
        {
            Head(box, Loc.T("Totals"));
            var lines = tree.Totals?.Lines;
            float y = inner.y;
            if (lines == null || lines.Count == 0) GUI.Label(new Rect(inner.x, y, inner.width, 20), Loc.T("Asking the server..."), mid);
            else
                foreach (var l in lines)
                {
                    var st = new GUIStyle(app.SmallStyle) { wordWrap = true };
                    st.normal.textColor = l.Kind == 'o' ? new Color(0.96f, 0.81f, 0.45f) : l.Kind == 'h' ? new Color(0.91f, 0.78f, 0.38f) : new Color(0.85f, 0.81f, 0.75f);
                    GUI.Label(new Rect(inner.x, y, inner.width, 20), l.Text, st);
                    y += 20;
                }
            if (GUI.Button(new Rect(inner.center.x - 40, inner.yMax - 26, 80, 24), Loc.T("Ok"))) panel = Panel.None;
        }

        void Head(Rect box, string title) { GUI.Label(new Rect(box.x + 8, box.y + 2, box.width - 16, 20), title, tipTitle); }

        void BoxPanel(ChaosApp app, PassiveTree tree, Rect box, Rect inner)
        {
            Head(box, tree.BoxTitle.Length > 0 ? tree.BoxTitle : Loc.T("Passive tree"));
            GUI.Label(new Rect(inner.x, inner.y, inner.width, inner.height - 30), tree.BoxText, mid);
            if (GUI.Button(new Rect(inner.center.x - 40, inner.yMax - 26, 80, 24), Loc.T("Ok"))) { panel = Panel.None; tree.BoxText = ""; lastBox = ""; }
        }

        string PriceText(PassiveTree tree, long cost)
        {
            var r = tree.Respec;
            if (r == null) return Loc.T("asked from the server");
            if (cost <= 0)
            {
                string free = r.Free == "level" ? Loc.T(" (free below level {0})", r.FreeBelowLevel) : r.Free == "vocation" ? Loc.T(" (free once after your class changed)") : "";
                return Loc.T("free") + free;
            }
            return Loc.T("{0} gold coins", Fmt.Exact(cost));
        }

        void ResetPanel(ChaosApp app, PassiveTree tree, Rect box, Rect inner)
        {
            Head(box, Loc.T("Reset Warning"));
            GUI.Label(new Rect(inner.x, inner.y, inner.width, inner.height - 30),
                Loc.T("Reset your whole passive tree for {0}? Every point becomes free to spend again.", tree.Respec == null ? Loc.T("asked from the server") : PriceText(tree, tree.Respec.Full)), mid);
            if (GUI.Button(new Rect(inner.center.x - 90, inner.yMax - 26, 80, 24), Loc.T("Ok"))) { tree.ResetTree(); panel = Panel.None; }
            if (GUI.Button(new Rect(inner.center.x + 10, inner.yMax - 26, 80, 24), Loc.T("Cancel"))) panel = Panel.None;
        }

        void RefundPanel(ChaosApp app, PassiveTree tree, Rect box, Rect inner)
        {
            Head(box, Loc.T("Refund node"));
            GUI.Label(new Rect(inner.x, inner.y, inner.width, inner.height - 30),
                Loc.T("Refund {0}? The point becomes free to spend again.", tree.NameOf(panelNode)) + "\n" + Loc.T("Price: {0}.", PriceText(tree, tree.Respec?.Node ?? 0)), mid);
            if (GUI.Button(new Rect(inner.center.x - 90, inner.yMax - 26, 80, 24), Loc.T("Refund"))) { tree.RefundNode(panelNode); panel = Panel.None; }
            if (GUI.Button(new Rect(inner.center.x + 10, inner.yMax - 26, 80, 24), Loc.T("Cancel"))) panel = Panel.None;
        }

        void MasteryPanel(ChaosApp app, PassiveTree tree, Rect box, Rect inner)
        {
            if (!tree.Data.Nodes.TryGetValue(panelNode, out var n)) { panel = Panel.None; return; }
            Head(box, tree.View(n).Name);
            GUI.Label(new Rect(inner.x, inner.y, inner.width, 34), panelSaved ? Loc.T("Pick another effect. A change costs the single-node refund price.") : Loc.T("Pick one effect. You can change it for free until you apply the plan."), tip);
            int current = panelSaved ? (tree.Masteries.TryGetValue(n.Id, out int sc) ? sc : 0) : (tree.PlanMasteries.TryGetValue(n.Id, out int pc) ? pc : 0);
            float y = inner.y + 38;
            for (int i = 0; i < n.Effects.Length; i++)
            {
                var r = new Rect(inner.x, y, inner.width, 48);
                bool on = current == i + 1;
                var old = GUI.backgroundColor;
                if (on) GUI.backgroundColor = new Color(0.9f, 0.75f, 0.3f);
                string t = n.Effects[i].Name + (on ? Loc.T("  (chosen)") : "") + "\n" + string.Join(" ", n.Effects[i].Stats);
                if (GUI.Button(r, t))
                {
                    if (panelSaved) { if (!on) tree.ChangeSavedMastery(n.Id, i + 1); panel = Panel.None; }
                    else
                    {
                        tree.SetPlanMastery(n.Id, i + 1);
                        var missing = tree.MissingMasteries();
                        if (missing.Count > 0) panelNode = missing[0]; else panel = Panel.None;
                    }
                }
                GUI.backgroundColor = old;
                y += 52;
            }
            if (!panelSaved && GUI.Button(new Rect(inner.x, inner.yMax - 26, 120, 24), Loc.T("Take it out"))) { tree.RemovePlanned(n.Id); panel = Panel.None; }
            if (GUI.Button(new Rect(inner.xMax - 90, inner.yMax - 26, 90, 24), Loc.T("Close"))) panel = Panel.None;
        }

        void BuildPanel(ChaosApp app, PassiveTree tree, Rect box, Rect inner)
        {
            Head(box, Loc.T("Build Code"));
            GUI.Label(new Rect(inner.x, inner.y, inner.width, 34), Loc.T("Export your tree as a code to share, or paste a code to preview it on the tree. The server decides what a build may take."), tip);
            float y = inner.y + 38;
            GUI.SetNextControlName("treeCode");
            code = GUI.TextField(new Rect(inner.x, y, inner.width, 24), code, 1000);
            if (GUI.GetNameOfFocusedControl() == "treeCode") app.MarkTextEditing();
            // an export from the server fills the box
            if (tree.BuildCodeText.Length > 0) { code = tree.BuildCodeText; tree.BuildCodeText = ""; }
            y += 30;
            float bw = (inner.width - 12) / 4;
            if (GUI.Button(new Rect(inner.x, y, bw, 24), Loc.T("Export"))) tree.ExportBuild(false);
            if (GUI.Button(new Rect(inner.x + bw + 4, y, bw, 24), Loc.T("Full Build"))) tree.ExportBuild(true);
            if (GUI.Button(new Rect(inner.x + 2 * (bw + 4), y, bw, 24), Loc.T("Copy"))) GUIUtility.systemCopyBuffer = code;
            if (GUI.Button(new Rect(inner.x + 3 * (bw + 4), y, bw, 24), Loc.T("Paste"))) code = (GUIUtility.systemCopyBuffer ?? "").Trim();
            y += 30;
            GUI.enabled = code.Trim().Length > 0;
            if (GUI.Button(new Rect(inner.x, y, bw * 2 + 4, 24), Loc.T("Preview"))) tree.PreviewBuild(code);
            GUI.enabled = tree.PreviewNodes != null;
            if (GUI.Button(new Rect(inner.x + 2 * (bw + 4), y, bw, 24), Loc.T("Apply Build"))) tree.ApplyBuild();
            if (GUI.Button(new Rect(inner.x + 3 * (bw + 4), y, bw, 24), Loc.T("Cancel Preview"))) tree.CancelPreview();
            GUI.enabled = true;
            y += 30;
            var st = new GUIStyle(tip);
            st.normal.textColor = tree.BuildError ? new Color(0.9f, 0.45f, 0.4f) : new Color(0.8f, 0.78f, 0.7f);
            string msg = tree.BuildMessage + (tree.PreviewSummary.Length > 0 ? "\n" + tree.PreviewSummary : "");
            GUI.Label(new Rect(inner.x, y, inner.width, inner.yMax - y - 28), msg, st);
            if (GUI.Button(new Rect(inner.xMax - 90, inner.yMax - 26, 90, 24), Loc.T("Close"))) panel = Panel.None;
        }
    }
}
