// Phase 8, track A: the passive tree window's remaining gap list. Node icons with the frame of each node kind (and the painted option), curved links between the nodes
// of one orbit, the vocation Trials panel, the Auto build panel and the Paragon Mastery panel. The rules are Core/Phase8ATree.cs; the main client's versions are
// game_passivetree trials.lua, autobuild.lua, paragonmastery.lua and passivetree.lua.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class PassiveTreeWindow
    {
        static TreeIcons iconCache;
        readonly Dictionary<long, List<double[]>> arcs = new Dictionary<long, List<double[]>>();
        Vector2 trialsScroll, buildScroll, masteryScroll;
        bool masteryExchangeAsk;

        /// <summary>The icon clips of the nodes (Resources/PassiveTreeIcons.json), loaded once; null when the file is missing (the discs stay).</summary>
        static TreeIcons Icons()
        {
            if (iconCache == null)
            {
                using var _slow = SlowCalls.Scope("PassiveTreeIcons data", "load");
                var asset = Resources.Load<TextAsset>("PassiveTreeIcons");
                if (asset != null) { try { iconCache = TreeIcons.Parse(asset.text); } catch (System.Exception) { iconCache = null; } }
            }
            return iconCache;
        }

        // ------------------------------------------------------------------------------------ node icons
        /// <summary>Draws a node as its icon clip and the frame of its kind and state (the main client's CommonNode ... DivineNode); false when the sheets are missing or the node is too small to read.</summary>
        bool NodeArt(ChaosApp app, PassiveTree tree, TreeNode n, Vector2 p, bool lit, bool can, Color frameTint, float alpha)
        {
            if (zoom < TreeNodeArt.ArtMinZoom || n.IsStart) return false;
            var icons = Icons();
            if (icons == null) return false;
            var g = TreeNodeArt.Of(n.Type);
            float size = (float)g.Size * zoom;
            string key = TreeIcons.KeyFor(n, tree.Vocation);
            if (!icons.Resolve(key, VisualPrefs.Painted, out string path, out int cx, out int cy, out int cw, out int ch)) return false;
            var tex = app.ArtTexture(path, VisualPrefs.Painted);
            if (tex == null) return false;
            var old = GUI.color;
            var iconTint = n.IsMastery ? (lit ? new Color(1f, 0.85f, 0.54f) : new Color(0.9f, 0.76f, 0.48f)) : Color.white;
            iconTint.a = alpha * (lit ? 1f : 0.8f);
            GUI.color = iconTint;
            float u = cx / (float)tex.width, v = 1f - (cy + ch) / (float)tex.height;
            GUI.DrawTextureWithTexCoords(new Rect(p.x - size / 2f, p.y - size / 2f, size, size), tex, new Rect(u, v, cw / (float)tex.width, ch / (float)tex.height));
            var state = TreeNodeArt.StateOf(lit, can);
            var frame = app.ArtTexture(TreeNodeArt.FramePath(n.Type, state), true);
            if (frame != null)
            {
                float fw = (float)g.FrameW * zoom, fh = (float)g.FrameH * zoom;
                frameTint.a *= alpha;
                GUI.color = frameTint;
                GUI.DrawTexture(new Rect(p.x - fw / 2f, p.y - fh / 2f, fw, fh), frame, ScaleMode.StretchToFill, true);
            }
            GUI.color = old;
            return true;
        }

        // ------------------------------------------------------------------------------------ curved links
        /// <summary>The arcs of the links between nodes of one group and orbit, found once per link set.</summary>
        void BuildArcs(PassiveTree tree)
        {
            arcs.Clear();
            var data = tree.Data;
            foreach (var l in links)
            {
                var a = data.Nodes[l[0]]; var b = data.Nodes[l[1]];
                if (a.Group == 0 || a.Group != b.Group || !data.Groups.TryGetValue(a.Group, out var c)) continue;
                var pts = TreeArcs.Arc(a, b, c[0], c[1]);
                if (pts != null) arcs[ArcKey(l[0], l[1])] = pts;
            }
        }

        static long ArcKey(int a, int b) => (long)a * 100000L + b;

        /// <summary>Draws a link: the arc when there is one, else the straight line.</summary>
        void DrawLink(PassiveTree tree, int ia, int ib, Vector2 pa, Vector2 pb, Rect vp, float width, Color c)
        {
            if (arcs.TryGetValue(ArcKey(ia, ib), out var pts))
            {
                Vector2 prev = ToScreen((float)pts[0][0], (float)pts[0][1], vp);
                for (int i = 1; i < pts.Count; i++)
                {
                    var cur = ToScreen((float)pts[i][0], (float)pts[i][1], vp);
                    Line(prev, cur, width, c);
                    prev = cur;
                }
                return;
            }
            Line(pa, pb, width, c);
        }

        // ------------------------------------------------------------------------------------ trials
        void TrialsPanel(ChaosApp app, PassiveTree tree, Rect box, Rect inner)
        {
            var tr = tree.Trials;
            Head(box, Loc.T("Vocation Trials"));
            if (!tr.Known) { GUI.Label(new Rect(inner.x, inner.y, inner.width, 20), Loc.T("Asking the server..."), mid); }
            else if (!tr.Supported) { GUI.Label(new Rect(inner.x, inner.y, inner.width, 24), Loc.T("No trial for this vocation"), mid); }
            else
            {
                GUI.Label(new Rect(inner.x, inner.y, inner.width, 20), TreeTrials.Fit(tr.Trial, 40), tipTitle);
                GUI.Label(new Rect(inner.x, inner.y + 20, inner.width, 34), TreeTrials.Fit(tr.Story, 190), tip);
                var small = app.SmallStyle;
                GUI.Label(new Rect(inner.x, inner.y + 56, inner.width, 18), tr.TokensLine, small);
                float tw = (inner.width - 8) / 3f;
                for (int i = 0; i < tr.Tiers.Count && i < 3; i++)
                {
                    var b = tr.TierButton(i);
                    GUI.enabled = b.Enabled && !tr.Asking;
                    if (GUI.Button(new Rect(inner.x + i * (tw + 4), inner.y + 76, tw, 24), new GUIContent(b.Action, b.Tooltip))) { if (tr.Enter(i + 1)) { panel = Panel.None; Open = false; } }
                }
                GUI.enabled = true;
                float top = inner.y + 106;
                float rowH = 112;
                float listH = inner.height - (top - inner.y) - 34;
                trialsScroll = GUI.BeginScrollView(new Rect(inner.x, top, inner.width, listH), trialsScroll, new Rect(0, 0, inner.width - 18, rowH * tr.Pairs.Count));
                float cardW = (inner.width - 18 - 90 - 8) / 2f;
                for (int p = 0; p < tr.Pairs.Count; p++)
                {
                    var e = tr.Pairs[p];
                    float y = p * rowH;
                    var title = new GUIStyle(tipTitle) { fontSize = 11, wordWrap = true };
                    title.normal.textColor = e.Locked ? Hex(TreeTrials.Dim) : new Color(0.91f, 0.72f, 0.29f);
                    GUI.Label(new Rect(0, y, 84, 40), Loc.T("Pair {0}", e.Number) + "\n" + e.Tier + (e.Locked ? "\n" + Loc.T("(locked)") : ""), title);
                    GUI.enabled = tr.ClearCard(e).Enabled && !tr.Asking;
                    if (GUI.Button(new Rect(0, y + 60, 84, 22), new GUIContent(Loc.T("Clear"), tr.ClearCard(e).Tooltip))) tr.AskClear(e.Number);
                    GUI.enabled = true;
                    for (int side = 1; side <= 2; side++) TrialCardView(app, tr, e, side, new Rect(90 + (side - 1) * (cardW + 8), y, cardW, rowH - 4));
                }
                GUI.EndScrollView();
                if (!string.IsNullOrEmpty(GUI.tooltip)) { var ts = new GUIStyle(tip) { fontSize = 11 }; GUI.Label(new Rect(inner.x + 4, inner.yMax - 56, inner.width - 8, 26), GUI.tooltip, ts); }
                if (tr.Running && GUI.Button(new Rect(inner.x, inner.yMax - 28, 120, 24), Loc.T("Leave the trial"))) tr.Leave();
            }
            if (GUI.Button(new Rect(inner.xMax - 90, inner.yMax - 28, 90, 24), Loc.T("Close"))) { tree.Trials.Cancel(); panel = Panel.None; }
            if (tr.Asking) AskBox(box, tr.AskTitle, tr.AskText, () => tr.Confirm(), () => tr.Cancel());
        }

        static Color Hex(string hex) { Color c; return ColorUtility.TryParseHtmlString(hex, out c) ? c : Color.white; }

        void TrialCardView(ChaosApp app, TreeTrials tr, TrialPair e, int side, Rect r)
        {
            var node = e.Nodes[side - 1];
            var info = tr.Card(e, side);
            ChaosApp.Fill(r, new Color(1f, 1f, 1f, e.Held == side ? 0.1f : 0.05f));
            if (e.Held == side) ChaosApp.Fill(new Rect(r.x, r.y, 2, r.height), Hex(TreeTrials.Held));
            var nameStyle = new GUIStyle(tipTitle) { fontSize = 12 };
            nameStyle.normal.textColor = e.Locked ? Hex(TreeTrials.Dim) : e.Held == side ? Hex(TreeTrials.Held) : new Color(0.91f, 0.72f, 0.29f);
            GUI.Label(new Rect(r.x + 6, r.y + 1, r.width - 12, 18), TreeTrials.Fit(node.Name, 30), nameStyle);
            var ls = new GUIStyle(app.SmallStyle) { fontSize = 10 };
            for (int i = 0; i < TreeTrials.MaxLines; i++)
            {
                if (i >= node.Lines.Count) break;
                var line = node.Lines[i];
                if (e.Locked) { ls.normal.textColor = Hex(TreeTrials.Dim); GUI.Label(new Rect(r.x + 6, r.y + 18 + i * 12, r.width - 12, 13), "? " + new string('.', 14), ls); }
                else { ls.normal.textColor = Hex(line.Value ? TreeTrials.Good : TreeTrials.Bad); GUI.Label(new Rect(r.x + 6, r.y + 18 + i * 12, r.width - 12, 13), (line.Value ? "+ " : "- ") + TreeTrials.Fit(line.Key, 46), ls); }
            }
            ls.normal.textColor = Hex(TreeTrials.Dim);
            if (!e.Locked) GUI.Label(new Rect(r.x + 6, r.y + 18 + 5 * 12, r.width - 12, 13), TreeTrials.Fit(node.Lore, 52), ls);
            ls.normal.textColor = Hex(info.StatusColor.Length > 0 ? info.StatusColor : TreeTrials.Dim);
            GUI.Label(new Rect(r.x + 6, r.yMax - 22, r.width - 100, 18), TreeTrials.Fit(info.Status, 30), ls);
            GUI.enabled = info.Enabled && !tr.Asking;
            string tip2 = info.Tooltip + (node.NeedsSpellEvents && !e.Locked ? "\n" + Loc.T("Part of this node needs the server's spell events.") : "");
            if (GUI.Button(new Rect(r.xMax - 88, r.yMax - 24, 84, 20), new GUIContent(info.Action, tip2))) tr.AskChoose(e.Number, side);
            GUI.enabled = true;
        }

        /// <summary>A question over the panel with Ok and Cancel.</summary>
        void AskBox(Rect box, string title, string text, System.Action ok, System.Action cancel)
        {
            var ask = new Rect(box.x + 30, box.y + box.height / 2 - 90, box.width - 60, 180);
            ChaosApp.Fill(new Rect(ask.x - 2, ask.y - 2, ask.width + 4, ask.height + 4), new Color(0.5f, 0.4f, 0.2f));
            ChaosApp.Fill(ask, new Color(0.06f, 0.05f, 0.07f, 1f));
            GUI.Label(new Rect(ask.x + 8, ask.y + 4, ask.width - 16, 20), title, tipTitle);
            GUI.Label(new Rect(ask.x + 8, ask.y + 26, ask.width - 16, ask.height - 66), text, tip);
            if (GUI.Button(new Rect(ask.x + 10, ask.yMax - 32, 90, 24), Loc.T("Ok"))) ok();
            if (GUI.Button(new Rect(ask.xMax - 100, ask.yMax - 32, 90, 24), Loc.T("Cancel"))) cancel();
        }

        // ------------------------------------------------------------------------------------ auto build
        void AutoBuildPanel(ChaosApp app, PassiveTree tree, Rect box, Rect inner)
        {
            var ab = tree.Auto;
            Head(box, Loc.T("Auto build"));
            var rows = ab.Rows();
            float listH = Mathf.Min(150f, rows.Count * 22f + 4f);
            if (rows.Count == 0) GUI.Label(new Rect(inner.x, inner.y, inner.width, 22), Loc.T("Asking the server..."), mid);
            buildScroll = GUI.BeginScrollView(new Rect(inner.x, inner.y, inner.width, listH), buildScroll, new Rect(0, 0, inner.width - 18, rows.Count * 22f));
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                var rr = new Rect(0, i * 22f, inner.width - 18, 20);
                if (r.Heading) { var hs = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleCenter }; hs.normal.textColor = Hex(AutoBuild.Dim); GUI.Label(rr, r.Text, hs); continue; }
                bool on = r.Id == ab.Selected;
                if (GUI.Toggle(rr, on, r.Text, GUI.skin.button) && !on) ab.Pick(r.Id);
            }
            GUI.EndScrollView();
            string detail = ab.Detail(out string color);
            var ds = new GUIStyle(tip) { wordWrap = true };
            ds.normal.textColor = Hex(color);
            GUI.Label(new Rect(inner.x, inner.y + listH + 6, inner.width, inner.height - listH - 44), detail, ds);
            float by = inner.yMax - 28;
            GUI.enabled = ab.CanApply && ab.ConfirmTextShown.Length == 0;
            if (GUI.Button(new Rect(inner.x, by, 90, 24), Loc.T("Apply"))) ab.Apply();
            GUI.enabled = ab.CanReset && ab.ConfirmTextShown.Length == 0;
            if (GUI.Button(new Rect(inner.x + 94, by, 130, 24), Loc.T("Reset and apply"))) ab.AskReset();
            GUI.enabled = true;
            if (GUI.Button(new Rect(inner.xMax - 90, by, 90, 24), Loc.T("Close"))) { ab.Close(); panel = Panel.None; }
            if (ab.ConfirmTextShown.Length > 0) AskBox(box, Loc.T("Reset and apply"), ab.ConfirmTextShown, () => ab.ConfirmReset(), () => ab.CancelReset());
        }

        // ------------------------------------------------------------------------------------ Paragon masteries
        void ParagonMasteryPanel(ChaosApp app, PassiveTree tree, Rect box, Rect inner)
        {
            var pg = tree.Paragon;
            Head(box, Loc.T("Paragon Mastery"));
            if (!pg.Known || !pg.HasMastery) { GUI.Label(new Rect(inner.x, inner.y, inner.width, 20), Loc.T("Asking the server..."), mid); }
            else
            {
                GUI.Label(new Rect(inner.x, inner.y, inner.width, 20), Loc.T("Available: {0}     Total: {1}", pg.FreePoints, pg.Total), mid);
                float rowH = 30;
                float listH = inner.height - 112;
                masteryScroll = GUI.BeginScrollView(new Rect(inner.x, inner.y + 24, inner.width, listH), masteryScroll, new Rect(0, 0, inner.width - 18, Mathf.Max(listH, pg.MasteryRows.Count * rowH)));
                for (int i = 0; i < pg.MasteryRows.Count; i++)
                {
                    var row = pg.MasteryRows[i];
                    float y = i * rowH;
                    ChaosApp.Fill(new Rect(0, y, inner.width - 18, rowH - 2), new Color(1f, 1f, 1f, 0.05f));
                    GUI.Label(new Rect(6, y, 150, rowH), new GUIContent(row.Name, row.Desc.Length > 0 ? row.Desc : row.Name), app.SmallStyle);
                    var rs = new GUIStyle(app.SmallStyle) { alignment = TextAnchor.MiddleRight, fontSize = 11 };
                    GUI.Label(new Rect(150, y, 50, rowH), row.Ranks + "/" + pg.MasteryMaxRanks, rs);
                    GUI.Label(new Rect(200, y, 70, rowH), ParagonPanel.MasteryValueText(row), rs);
                    rs.normal.textColor = new Color(0.55f, 0.5f, 0.44f);
                    GUI.Label(new Rect(270, y, 90, rowH), Loc.T("{0} next rank", ParagonPanel.MasteryNextText(row)), rs);
                    int[] steps = { 1, 10, 100 };
                    for (int s = 0; s < 3; s++)
                    {
                        GUI.enabled = pg.MasteryBuy(row, steps[s]) >= steps[s];
                        if (GUI.Button(new Rect(inner.width - 18 - (3 - s) * 46, y + 2, 44, rowH - 6), "+" + steps[s])) pg.BuyMastery(row, steps[s]);
                    }
                    GUI.enabled = true;
                }
                GUI.EndScrollView();
                var es = new GUIStyle(tip) { fontSize = 11 };
                GUI.Label(new Rect(inner.x, inner.yMax - 84, inner.width, 36), pg.ExchangeLine, es);
                GUI.enabled = pg.Exchangeable > 0 && !masteryExchangeAsk;
                if (GUI.Button(new Rect(inner.x, inner.yMax - 28, 150, 24), Loc.T("Exchange tree points"))) masteryExchangeAsk = true;
                GUI.enabled = true;
            }
            if (GUI.Button(new Rect(inner.xMax - 90, inner.yMax - 28, 90, 24), Loc.T("Back"))) { panel = Panel.Paragon; masteryExchangeAsk = false; }
            if (masteryExchangeAsk) AskBox(box, Loc.T("Exchange tree points"), pg.ExchangeAsk, () => { pg.Exchange(); masteryExchangeAsk = false; }, () => masteryExchangeAsk = false);
        }
    }
}
