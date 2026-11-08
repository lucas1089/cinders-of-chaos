// Loot labels over the ground items, drawn in the map group of GameGui (classic view and the live front-art view; the HD-2D scene draws none yet).
// The rules, the scan and the server questions are Core/GroundLabels.cs; LootWindow scans once per frame. One block of labels per tile, laid out
// so that none overlaps another (GroundLabelRules.Layout); the rarity colour, the loot filter and the settings decide what gets a label.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        GUIStyle groundStyle;
        readonly Dictionary<string, Vector2> groundSizes = new Dictionary<string, Vector2>();

        /// <summary>The middle of a tile in screen pixels (y up), false when the view cannot say (the HD-2D scene).</summary>
        bool TileScreenPx(Pos p, out Vector3 px)
        {
            px = default(Vector3);
            if (world == null) return false;
            if (LiveOn)
            {
                px = cam.WorldToScreenPoint(frontLive.TileToWorld(p.X, p.Y, p.Z));
                return true;
            }
            if (hd2d || view == null) return false;
            Vector2 c = view.CamTiles;
            int off = p.Z - world.Center.Z;   // a lower floor is drawn shifted right and down by its depth
            float tx = p.X + off - c.x, ty = -(p.Y + off - c.y);
            px = cam.WorldToScreenPoint(new Vector3(tx + 0.5f, ty - 0.5f, 0f));
            return true;
        }

        /// <summary>Draws the labels inside the map group (map is its rect in UI units). A click on a corpse label opens the corpse.</summary>
        void DrawGroundLabels(Rect map, float scale)
        {
            var loot = FindWindow<LootWindow>();
            if (loot == null || loot.Ground == null || loot.Filter == null || session == null || world?.Player == null) return;
            var settings = loot.Ground.Settings;
            if (!settings.Enabled) return;
            var e = Event.current;
            if (e.type != EventType.Repaint && e.type != EventType.MouseDown) return;
            bool alt = Input.GetKey(KeyCode.LeftAlt) || Input.GetKey(KeyCode.RightAlt);
            var labels = loot.Ground.Labels(world.Player.Position, loot.Filter.Settings, alt);
            if (labels.Count == 0) return;
            if (groundStyle == null) groundStyle = new GUIStyle(GUI.skin.label) { alignment = TextAnchor.MiddleLeft, clipping = TextClipping.Overflow, wordWrap = false, padding = new RectOffset(0, 0, 0, 0) };
            int size = settings.Size == "small" ? 10 : settings.Size == "large" ? 14 : 12;
            groundStyle.fontSize = size;
            float pad = settings.Size == "small" ? 3 : settings.Size == "large" ? 5 : 4;
            float tile = map.height / ViewTilesH;

            // one block per tile: its labels top to bottom in priority order
            var byTile = new Dictionary<Pos, List<GroundLabel>>();
            var order = new List<Pos>();
            foreach (var l in labels)
            {
                List<GroundLabel> list;
                if (!byTile.TryGetValue(l.Tile, out list)) { list = new List<GroundLabel>(); byTile[l.Tile] = list; order.Add(l.Tile); }
                list.Add(l);
            }
            var blocks = new List<GroundLabelRules.LayoutBlock>();
            var anchors = new List<Pos>();
            var rowSizes = new Dictionary<GroundLabel, Vector2>();
            for (int i = 0; i < order.Count; i++)
            {
                Vector3 px;
                if (!TileScreenPx(order[i], out px)) continue;
                float ax = px.x / scale - map.x, ay = (UnityEngine.Screen.height - px.y) / scale - map.y;
                if (ax < -80 || ax > map.width + 80 || ay < -40 || ay > map.height + 40) continue;
                float bw = 0, bh = 0;
                foreach (var l in byTile[order[i]])
                {
                    var sz = groundStyle.CalcSize(new GUIContent(l.Timer ? System.Text.RegularExpressions.Regex.Replace(l.Text, "\\d", "0") : l.Text));
                    sz = new Vector2(sz.x + pad * 2, sz.y + 2);
                    rowSizes[l] = sz;
                    bw = Mathf.Max(bw, sz.x);
                    bh += sz.y + (bh > 0 ? 1 : 0);
                }
                blocks.Add(new GroundLabelRules.LayoutBlock { Key = anchors.Count, Ax = ax, Ay = ay, W = bw, H = bh });
                anchors.Add(order[i]);
            }
            var boxes = GroundLabelRules.Layout(blocks, 2f, Mathf.Floor(tile * 0.18f), tile * 3f);
            foreach (var b in blocks)
            {
                var box = boxes[b.Key];
                float y = b.Ay + box.Y;
                foreach (var l in byTile[anchors[b.Key]])
                {
                    var sz = rowSizes[l];
                    var r = new Rect(b.Ax + box.X, y, b.W, sz.y);
                    y += sz.y + 1;
                    bool over = r.Contains(e.mousePosition);
                    var bg = HexColor(l.Background); var border = HexColor(l.Border); var text = HexColor(l.Color);
                    if (over && !OverUi(Input.mousePosition)) bg = new Color(0.23f, 0.16f, 0.11f, 0.94f);
                    Fill(r, bg);
                    Fill(new Rect(r.x, r.y, r.width, 1), border); Fill(new Rect(r.x, r.yMax - 1, r.width, 1), border);
                    Fill(new Rect(r.x, r.y, 1, r.height), border); Fill(new Rect(r.xMax - 1, r.y, 1, r.height), border);
                    if (l.Decision.Dim) text.a = 0.7f;
                    var tint = GUI.contentColor;
                    GUI.contentColor = text;
                    GUI.Label(new Rect(r.x + pad, r.y, r.width, r.height), l.Text, groundStyle);
                    GUI.contentColor = tint;
                    if (over && l.Row.Corpse && e.type == EventType.MouseDown && e.button == 0 && !OverUi(Input.mousePosition))
                    {
                        byte free = 0;
                        for (byte c = 0; c < 16; c++) if (!session.Parser.Containers.ContainsKey(c)) { free = c; break; }
                        session.UseItem(l.Tile, (ushort)l.Row.Info.Id, (byte)l.Row.Info.S, free);
                        e.Use();
                    }
                }
            }
        }

        static Color HexColor(string hex)
        {
            Color c;
            return ColorUtility.TryParseHtmlString(hex ?? "", out c) ? c : Color.white;
        }
    }
}
