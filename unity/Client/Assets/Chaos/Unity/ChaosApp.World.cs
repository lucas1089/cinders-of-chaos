// What the world and map utilities draw (track O): tile overlays (field timers, server bars), quest marks over NPC heads, party arrows on the game view, the map overlay,
// the Hideout placing ghost, weather (rain, ambient specks, colour mood), name plates, the points of interest on the minimap, the Candlemarks counter and a small tooltip.
// Models: Core/WorldMarks.cs, WorldTiles.cs, WorldTravel.cs. Both map views work (classic and the live front-art view) through TileScreenPx (ChaosApp.Loot.cs).
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        string worldTip = "";
        GUIStyle worldStyle, worldTiny, plateStyle;

        /// <summary>A text box near the mouse for this frame (windows call it for the hovered cell).</summary>
        public void SetTip(string text) { worldTip = text ?? ""; }

        WorldUtils Utils => session?.Utils;

        static readonly Dictionary<string, string> MarkColors = new Dictionary<string, string>
        {
            { "temple", "#ffd84a" }, { "depot", "#5fa0ff" }, { "bank", "#e8c372" }, { "npc", "#8ee05a" }, { "shop", "#ff9d2e" }, { "travel", "#5fd0ff" }, { "bless", "#fff0a0" },
            { "craft", "#c0783a" }, { "guild", "#c8a0ff" }, { "portal", "#e070ff" }, { "dungeon", "#ff6464" }, { "boss", "#c03030" }, { "hunt", "#5fffc8" },
            { "quest", "#ffd84a" }, { "questgoal", "#fff070" },
            // the map overlay's kinds
            { "party", "#ff9d2e" }, { "entry", "#e070ff" }, { "guardian", "#ff6464" }, { "chest", "#ffd84a" }, { "coffer", "#e8c372" }, { "goblin", "#8ee05a" },
            { "worldboss", "#c03030" }, { "invasion", "#ff6464" },
        };

        static Color MarkColor(string kind) => MarkColors.TryGetValue(kind, out string h) ? HexColor(h) : Color.white;

        void WorldStyles()
        {
            if (worldStyle != null) return;
            worldStyle = new GUIStyle(GUI.skin.label) { fontSize = 12, alignment = TextAnchor.MiddleCenter, clipping = TextClipping.Overflow, fontStyle = FontStyle.Bold };
            worldTiny = new GUIStyle(GUI.skin.label) { fontSize = 11, alignment = TextAnchor.MiddleCenter, clipping = TextClipping.Overflow };
            plateStyle = new GUIStyle(GUI.skin.label) { fontSize = 11, alignment = TextAnchor.LowerCenter, clipping = TextClipping.Overflow };
        }

        /// <summary>Text with a black shadow.</summary>
        void ShadowText(Rect r, string text, GUIStyle st, Color c)
        {
            var old = st.normal.textColor;
            st.normal.textColor = Color.black;
            GUI.Label(new Rect(r.x + 1, r.y + 1, r.width, r.height), text, st);
            st.normal.textColor = c;
            GUI.Label(r, text, st);
            st.normal.textColor = old;
        }

        /// <summary>A tile centre in the map group's units, false when the view cannot say.</summary>
        bool TileInGroup(Pos p, Rect map, float scale, out Vector2 at)
        {
            at = default(Vector2);
            if (!TileScreenPx(p, out Vector3 px)) return false;
            at = new Vector2(px.x / scale - map.x, (UnityEngine.Screen.height - px.y) / scale - map.y);
            return true;
        }

        // ------------------------------------------------------------------------------------------------ the map group
        /// <summary>Called inside the map group (map is its rect in UI units) after the ground labels.</summary>
        void DrawWorldOverlays(Rect map, float scale)
        {
            var u = Utils;
            if (u == null || world?.Player == null) return;
            WorldStyles();
            double now = session.Now;
            float tile = map.height / ViewTilesH;
            var local = new Rect(0, 0, map.width, map.height);
            DrawMapOverlay(map, scale, u);
            DrawWeather(local, u, now);
            DrawTileOverlays(map, scale, tile, u, now);
            DrawNpcMarks(map, scale, tile, u);
            DrawPartyArrows(map, scale, tile, u);
            DrawHideoutGhost(map, scale, tile, u);
        }

        // ---- tile overlays
        void DrawTileOverlays(Rect map, float scale, float tile, WorldUtils u, double now)
        {
            if (Event.current.type != EventType.Repaint) return;
            float ts = tile / 64f;
            foreach (var rec in u.Tiles.Recs.Values)
            {
                if (!TileInGroup(rec.Pos, map, scale, out Vector2 at)) continue;
                if (at.x < -40 || at.x > map.width + 40 || at.y < -40 || at.y > map.height + 40) continue;
                ShadowText(new Rect(at.x - 30, at.y - 10, 60, 20), TileOverlays.FieldText(rec, now), worldStyle, HexColor(TileOverlays.FieldColor(rec, now)));
            }
            var done = new HashSet<Pos>();
            foreach (var bar in u.Tiles.Bars.Values)
            {
                if (!done.Add(bar.Pos)) continue;
                if (!TileInGroup(bar.Pos, map, scale, out Vector2 at)) continue;
                if (at.x < -80 || at.x > map.width + 80 || at.y < -60 || at.y > map.height + 60) continue;
                var stack = TileOverlays.Stack(u.Tiles.Bars, bar.Pos);
                for (int i = 0; i < stack.Count; i++)
                {
                    var b = stack[i];
                    string text = TileOverlays.BarText(b, now);
                    float tw = worldTiny.CalcSize(new GUIContent(text)).x;
                    float w = TileOverlays.BarWidth(tw) * ts, h = TileOverlays.BarH * ts;
                    float lift = TileOverlays.BarLift(tile / ts, i + 1) * ts;
                    var r = new Rect(at.x - w / 2, at.y - lift - h / 2, w, h);
                    Fill(new Rect(r.x - 1, r.y - 1, r.width + 2, r.height + 2), new Color(0f, 0f, 0f, 0.85f));
                    float fill = TileOverlays.FillWidth(TileOverlays.BarProgress(b, now), (int)(r.width - 2));
                    Fill(new Rect(r.x + 1, r.y + 1, fill, r.height - 2), HexColor(b.Color));
                    ShadowText(r, text, worldTiny, Color.white);
                }
            }
        }

        // ---- quest marks over NPC heads
        void DrawNpcMarks(Rect map, float scale, float tile, WorldUtils u)
        {
            if (!u.Marks.Settings.NpcMarks || u.Marks.Npc.Count == 0 || Event.current.type != EventType.Repaint) return;
            float barH = Mathf.Max(3f, Mathf.Round(tile / 14f));
            foreach (var (c, sp) in LabelPoints())
            {
                if (c.Type != 2) continue;
                string mark = u.Marks.Npc.MarkFor(c.Name);
                if (mark.Length == 0) continue;
                float x = sp.x / scale - map.x, y = (UnityEngine.Screen.height - sp.y) / scale - map.y;
                if (x < 0 || x > map.width || y < 0 || y > map.height + tile * 0.5f) continue;
                float ms = Mathf.Clamp(Mathf.Round(tile / 32f), 1f, 3f);
                if (ArtMark(MarkArt.NpcMark(mark), new Vector2(x, y - barH - 22 - 12 * ms), 16, 24, Color.white, ms)) continue;
                var st = new GUIStyle(worldStyle) { fontSize = Mathf.RoundToInt(Mathf.Clamp(tile * 0.55f, 14f, 30f)) };
                ShadowText(new Rect(x - 12, y - barH - 22 - st.fontSize - 2, 24, st.fontSize + 4), NpcMarks.Glyph(mark), st, HexColor(NpcMarks.GlyphColor(mark)));
            }
        }

        // ---- party arrows on the game view
        void DrawPartyArrows(Rect map, float scale, float tile, WorldUtils u)
        {
            var m = u.Marks;
            if (!m.Settings.Game || !m.Settings.Party || m.Party.Count == 0 || Event.current.type != EventType.Repaint) return;
            var me = world.Player.Position;
            int viewZ = world.Center.Z;
            double now = session.Now;
            foreach (var p in m.Party.Values)
            {
                int dx = p.X - me.X, dy = p.Y - me.Y, dz = p.Z - me.Z;
                bool inView = MapMarkMath.InView(dx, dy);
                if (inView && dz == 0) continue;
                m.Anim.TryGetValue(p.Id, out var anim);
                double gx = p.X, gy = p.Y;
                if (anim != null) MapMarkMath.Glide(anim, now, out gx, out gy, out _);
                if (!TileInGroup(new Pos((int)System.Math.Round(gx), (int)System.Math.Round(gy), viewZ), map, scale, out Vector2 at)) continue;
                bool inside = MapMarkMath.Edge(at.x, at.y, 0, 0, map.width, map.height, 20, out double ex, out double ey, out string dir);
                var col = HexColor(MapMarkMath.Color(m.SlotOf(p.Id)));
                var r = new Rect((float)ex - 5, (float)ey - 5, 10, 10);
                string arrowArt = inside ? MarkArt.PartyPin : MarkArt.PartyArrow(dir);
                if (!ArtMark(arrowArt, new Vector2((float)ex, (float)ey), MarkArt.ArrowPx, MarkArt.ArrowPx, col))
                {
                    Fill(new Rect(r.x - 1, r.y - 1, 12, 12), new Color(0f, 0f, 0f, 0.8f));
                    Fill(r, col);
                }
                string arrow = MapMarkMath.FloorArrow(p.Z, me.Z);
                string text = MapMarkMath.GameText(p.Name, System.Math.Max(System.Math.Abs(dx), System.Math.Abs(dy)), dz);
                if (arrow.Length > 0) text = (arrow == "up" ? "^ " : "v ") + text;
                if (!inside && MarkArt.PartyArrow(dir) == null) text = ArrowOf(dir) + " " + text;
                ShadowText(new Rect((float)ex - 90, (float)ey + 6, 180, 16), text, worldTiny, col);
            }
        }

        static string ArrowOf(string dir)
        {
            switch (dir) { case "e": return ">"; case "w": return "<"; case "n": return "^"; case "s": return "v"; case "ne": return "^>"; case "nw": return "<^"; case "se": return "v>"; case "sw": return "<v"; }
            return "";
        }

        // ---- weather
        static float Hash(int i, int salt)
        {
            unchecked
            {
                uint h = (uint)(i * 73856093) ^ (uint)(salt * 19349663);
                h ^= h >> 13; h *= 0x5bd1e995; h ^= h >> 15;
                return (h & 0xFFFF) / 65535f;
            }
        }

        void DrawWeather(Rect r, WorldUtils u, double now)
        {
            if (Event.current.type != EventType.Repaint) return;
            var w = u.Weather;
            w.OptionOn = Phase7Prefs.WeatherOn;   // Options > Visuals: Weather and ambient effects
            w.MoodTint(out float mr, out float mg, out float mb, out float ma);
            if (ma > 0.004f) Fill(r, new Color(mr, mg, mb, ma));
            // ambient specks: embers, motes, dust drift in the view
            foreach (var l in WeatherState.AmbientLayers)
            {
                double op = w.AmbientCur[l.Name];
                if (op <= WeatherState.MinOpacity) continue;
                if (TiledArt.AmbientImage.TryGetValue(l.Name, out string ambImg) && ArtRepeat(TiledArt.Path(ambImg)) is Texture2D ambTex)
                {
                    WeatherState.AmbientOffset(l, now, out double aox, out double aoy);
                    DrawTiled(ambTex, TiledArt.AmbientTile, r, aox, aoy, new Color(1f, 1f, 1f, (float)(op * WeatherState.AmbientPulse(l, now))));
                    continue;
                }
                bool near = l.Name.EndsWith("near");
                int count = Mathf.Max(6, (int)(r.width * r.height / (near ? 40000f : 22000f)));
                WeatherState.AmbientOffset(l, now, out double ox, out double oy);
                float pulse = (float)WeatherState.AmbientPulse(l, now);
                var col = l.Kind == "embers" ? HexColor("#ff8a3a") : l.Kind == "motes" ? HexColor("#cfe8ff") : HexColor("#c8b89a");
                col.a = (float)op * pulse * 0.8f;
                float sz = near ? 3f : 2f;
                for (int i = 0; i < count; i++)
                {
                    float x = Mathf.Repeat(Hash(i, l.Name.Length * 7 + (int)l.Phase) * r.width + (float)ox, r.width);
                    float y = Mathf.Repeat(Hash(i, 91 + (int)l.Phase) * r.height + (float)oy, r.height);
                    Fill(new Rect(r.x + x, r.y + y, sz, sz), col);
                }
            }
            // rain: slanted streaks falling down and to the right
            bool any = false;
            foreach (var l in WeatherState.RainLayers) if (w.Cur[l.Name] > WeatherState.MinOpacity) any = true;
            if (!any) return;
            var matrix = GUI.matrix;
            foreach (var l in WeatherState.RainLayers)
            {
                double op = w.Cur[l.Name];
                if (op <= WeatherState.MinOpacity) continue;
                if (TiledArt.RainImage.TryGetValue(l.Name, out string rainImg) && ArtRepeat(TiledArt.Path(rainImg)) is Texture2D rainTex)
                {
                    WeatherState.Offset(l, now, TiledArt.RainTile, out int rox, out int roy);
                    DrawTiled(rainTex, TiledArt.RainTile, r, rox, roy, new Color(1f, 1f, 1f, (float)op));
                    continue;
                }
                int count = Mathf.Max(20, (int)(r.width * r.height / (l.Name == "far" ? 4200f : l.Name == "mid" ? 5600f : 7500f)));
                float len = l.Name == "far" ? 9f : l.Name == "mid" ? 13f : 18f;
                var col = new Color(0.78f, 0.86f, 1f, (float)op * (l.Name == "far" ? 0.35f : 0.55f));
                WeatherState.Offset(l, now, 4096, out int ox, out int oy);
                for (int i = 0; i < count; i++)
                {
                    float x = Mathf.Repeat(Hash(i, 3 + (int)l.Phase) * r.width + ox * 0.3f, r.width);
                    float y = Mathf.Repeat(Hash(i, 17 + (int)l.Phase) * (r.height + len) + oy, r.height + len) - len;
                    var pivot = new Vector2(r.x + x, r.y + y);
                    GUIUtility.RotateAroundPivot(-16.7f, pivot);
                    Fill(new Rect(pivot.x, pivot.y, 1.2f, len), col);
                    GUI.matrix = matrix;
                }
            }
        }

        // ---- map overlay
        Texture2D overlayTex;
        Color32[] overlayBuf;
        int overlayVer = -1, overlayX, overlayY, overlayZ, overlayZoom = -1, overlayW, overlayH;
        Rect overlayStrip;
        Vector2 overlayDrag, overlayPanStart;
        bool overlayDragging;

        void DrawMapOverlay(Rect map, float scale, WorldUtils u)
        {
            var o = u.Overlay;
            if (!o.Shown) return;
            var s = o.Settings;
            var me = world.Player.Position;
            int ppt = MapOverlayState.PixelsPerTile(s.Zoom);
            Rect box = map;
            if (s.Corner)
            {
                MapOverlayState.CornerSize(map.width, map.height, out int cw, out int ch);
                box = new Rect(map.width - cw - 8, 8, cw, ch);
            }
            box.x = Mathf.Max(0, box.x - (s.Corner ? 0 : 0));
            var local = new Rect(s.Corner ? box.x : 0, s.Corner ? box.y : 0, box.width, box.height);
            int tw = Mathf.Max(8, (int)local.width), th = Mathf.Max(8, (int)local.height);
            int cx = me.X + Mathf.RoundToInt((float)o.PanX), cy = me.Y + Mathf.RoundToInt((float)o.PanY);
            int floor = me.Z;
            var mem = Minimap;
            if (overlayTex == null || overlayW != tw || overlayH != th) { if (overlayTex != null) Object.Destroy(overlayTex); overlayTex = new Texture2D(tw, th, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp }; overlayBuf = new Color32[tw * th]; overlayW = tw; overlayH = th; overlayVer = -1; }
            if (mem.Version != overlayVer || cx != overlayX || cy != overlayY || floor != overlayZ || s.Zoom != overlayZoom)
            {
                overlayVer = mem.Version; overlayX = cx; overlayY = cy; overlayZ = floor; overlayZoom = s.Zoom;
                int tilesW = tw / ppt + 1, tilesH = th / ppt + 1, halfW = tilesW / 2, halfH = tilesH / 2;
                for (int i = 0; i < overlayBuf.Length; i++) overlayBuf[i] = new Color32(0, 0, 0, 0);
                for (int ty = 0; ty < tilesH; ty++)
                    for (int tx = 0; tx < tilesW; tx++)
                    {
                        byte c = mem.Get(cx - halfW + tx, cy - halfH + ty, floor);
                        if (c == 0) continue;
                        MinimapMemory.Rgb(c, out byte rr, out byte gg, out byte bb);
                        var col = new Color32(rr, gg, bb, 255);
                        for (int dy = 0; dy < ppt; dy++)
                        {
                            int py = ty * ppt + dy;
                            if (py >= th) break;
                            int row = th - 1 - py;
                            for (int dx = 0; dx < ppt; dx++)
                            {
                                int px = tx * ppt + dx;
                                if (px < tw) overlayBuf[row * tw + px] = col;
                            }
                        }
                    }
                overlayTex.SetPixels32(overlayBuf);
                overlayTex.Apply(false);
            }
            var old = GUI.color;
            GUI.color = new Color(1f, 1f, 1f, (float)s.Opacity);
            if (Event.current.type == EventType.Repaint) GUI.DrawTexture(local, overlayTex, ScaleMode.StretchToFill, true);
            GUI.color = old;
            // marks: kinds of the 245 channel on the shown floor, then the player
            if (Event.current.type == EventType.Repaint)
            {
                int tilesW = tw / ppt + 1, tilesH = th / ppt + 1, halfW = tilesW / 2, halfH = tilesH / 2;
                foreach (var m in o.VisibleMarks(floor))
                {
                    float x = local.x + (m.X - (cx - halfW)) * ppt + ppt / 2f, y = local.y + (m.Y - (cy - halfH)) * ppt + ppt / 2f;
                    if (x < local.x || x > local.xMax || y < local.y || y > local.yMax) continue;
                    float sz = Mathf.Max(5f, ppt);
                    var r = new Rect(x - sz / 2, y - sz / 2, sz, sz);
                    if (ArtMark(MarkArt.Overlay(m.Kind), new Vector2(x, y), MarkArt.OverlayPx, MarkArt.OverlayPx, Color.white)) r = new Rect(x - 8, y - 8, 16, 16);
                    else
                    {
                        Fill(new Rect(x - sz / 2 - 1, y - sz / 2 - 1, sz + 2, sz + 2), new Color(0f, 0f, 0f, 0.8f));
                        Fill(new Rect(x - sz / 2, y - sz / 2, sz, sz), MarkColor(m.Kind));
                    }
                    if (m.Name.Length > 0 && r.Contains(Event.current.mousePosition)) SetTip(m.Name);
                }
                float px0 = local.x + (me.X - (cx - halfW)) * ppt + ppt / 2f, py0 = local.y + (me.Y - (cy - halfH)) * ppt + ppt / 2f;
                if (!ArtMark(MarkArt.Overlay("self"), new Vector2(px0, py0), MarkArt.OverlayPx, MarkArt.OverlayPx, Color.white)) { Fill(new Rect(px0 - 5, py0 - 1, 10, 2), Color.white); Fill(new Rect(px0 - 1, py0 - 5, 2, 10), Color.white); }
            }
            var e = Event.current;
            Vector2 mouse = e.mousePosition;   // map group units
            // the strip: the only part that takes the mouse
            if (s.Strip)
            {
                float bw = 34, bh = 22;
                overlayStrip = new Rect(local.xMax - bw * 6 - 4, local.yMax - bh - 4, bw * 6, bh);
                string[] labels = { "o-", "o+", "z-", "z+", Loc.T("Ctr"), "x" };
                for (int i = 0; i < 6; i++)
                {
                    if (!GUI.Button(new Rect(overlayStrip.x + i * bw, overlayStrip.y, bw - 2, bh), labels[i])) continue;
                    switch (i)
                    {
                        case 0: s.Opacity = MapOverlayState.StepOpacity(s.Opacity, -0.1); break;
                        case 1: s.Opacity = MapOverlayState.StepOpacity(s.Opacity, 0.1); break;
                        case 2: s.Zoom = MapOverlayState.ClampZoom(s.Zoom - 1); break;
                        case 3: s.Zoom = MapOverlayState.ClampZoom(s.Zoom + 1); break;
                        case 4: o.Centre(); break;
                        case 5: o.Show(false); break;
                    }
                    MapOverlayWindow.Save(s);
                }
                uiRects.Add(Scaled(new Rect(map.x + overlayStrip.x, map.y + overlayStrip.y, overlayStrip.width, overlayStrip.height), scale));
            }
            bool overStrip = s.Strip && overlayStrip.Contains(mouse);
            bool shift = e.shift, ctrl = e.control;
            if (e.type == EventType.ScrollWheel && local.Contains(mouse))
            {
                string act = MapOverlayState.WheelAction(ctrl, shift, overStrip);
                bool up = e.delta.y < 0;
                if (act == "opacity") { s.Opacity = MapOverlayState.StepOpacity(s.Opacity, up ? 0.1 : -0.1); MapOverlayWindow.Save(s); e.Use(); }
                else if (act == "zoom")
                {
                    int nz = MapOverlayState.ClampZoom(s.Zoom + (up ? 1 : -1));
                    double ox = mouse.x - (local.x + local.width / 2), oy = mouse.y - (local.y + local.height / 2);
                    if (overStrip) { ox = 0; oy = 0; }
                    MapOverlayState.ZoomToward(o.PanX, o.PanY, s.Zoom, nz, ox, oy, out double px, out double py);
                    if (o.PanX == 0 && o.PanY == 0) { px = 0; py = 0; }
                    o.PanX = px; o.PanY = py; s.Zoom = nz; MapOverlayWindow.Save(s); e.Use();
                }
            }
            if (e.type == EventType.MouseDown && e.button == 2 && MapOverlayState.StartsPan(true, shift, overStrip) && local.Contains(mouse))
            {
                overlayDragging = true; overlayDrag = mouse; overlayPanStart = new Vector2((float)o.PanX, (float)o.PanY); e.Use();
            }
            else if (e.type == EventType.MouseDrag && overlayDragging)
            {
                MapOverlayState.DragPan(overlayPanStart.x, overlayPanStart.y, mouse.x - overlayDrag.x, mouse.y - overlayDrag.y, s.Zoom, out double px, out double py);
                o.PanX = px; o.PanY = py; e.Use();
            }
            else if (e.type == EventType.MouseUp && e.button == 2) overlayDragging = false;
        }

        // ---- the Hideout placing mode
        HideoutRow placingRow;
        int placingRot = 1, placingMove;
        bool placing;
        string placingMsg = "";

        public bool HideoutPlacing => placing;

        public void StartHideoutPlacing(HideoutRow row, int rot, int moveId)
        {
            if (row == null) return;
            placing = true; placingRow = row; placingRot = Mathf.Max(1, rot); placingMove = moveId; placingMsg = "";
        }

        public void StopHideoutPlacing() { placing = false; placingRow = null; placingMove = 0; }

        void DrawHideoutGhost(Rect map, float scale, float tile, WorldUtils u)
        {
            if (!placing) return;
            var h = u.Hideout;
            if (!h.HasInside || !h.Inside.IsOwner) { StopHideoutPlacing(); return; }
            var row = h.RowOf(placingRow.Key);
            if (row == null) { StopHideoutPlacing(); return; }
            placingRow = row;
            uiRects.Add(Scaled(map, scale));   // clicks on the map are for the ghost, not for walking
            var e = Event.current;
            Vector2 mouse = e.mousePosition;
            int hx = -1, hy = -1;
            for (int gx = 0; gx <= h.Layout.W + 1 && hx < 0; gx++)
                for (int gy = 0; gy <= h.Layout.H + 1; gy++)
                {
                    if (!TileInGroup(new Pos(h.Inside.OriginX + gx, h.Inside.OriginY + gy, h.Inside.OriginZ), map, scale, out Vector2 at)) continue;
                    if (new Rect(at.x - tile / 2, at.y - tile / 2, tile, tile).Contains(mouse)) { hx = gx; hy = gy; break; }
                }
            bool fits = false; string why = "";
            if (hx >= 0)
            {
                fits = h.Check(row, hx, hy, placingRot, placingMove, out why);
                string side = row.Layer == "wall" ? HideoutState.WallSide(h.Layout, hx, hy) : "";
                foreach (var part in HideoutState.Parts(row, placingRot, side))
                {
                    if (!TileInGroup(new Pos(h.Inside.OriginX + hx + part.Dx, h.Inside.OriginY + hy + part.Dy, h.Inside.OriginZ), map, scale, out Vector2 at)) continue;
                    var r = new Rect(at.x - tile / 2, at.y - tile / 2, tile, tile);
                    if (e.type == EventType.Repaint)
                    {
                        if (part.Id > 0) DrawItem(r, (ushort)part.Id, 1);
                        Fill(r, fits ? new Color(0.2f, 0.8f, 0.2f, 0.35f) : new Color(0.9f, 0.2f, 0.15f, 0.4f));
                    }
                }
                placingMsg = fits ? "" : why;
            }
            if (e.type == EventType.MouseDown && e.button == 0 && hx >= 0 && fits)
            {
                if (placingMove > 0) { h.Move(placingMove, hx, hy, placingRot); StopHideoutPlacing(); }
                else h.Place(row.Key, hx, hy, placingRot);
                e.Use();
            }
            else if (e.type == EventType.MouseDown && e.button == 1) { StopHideoutPlacing(); e.Use(); }
            else if (e.type == EventType.ScrollWheel) { placingRot = HideoutState.NextRot(row, placingRot, e.delta.y < 0 ? 1 : -1); e.Use(); }
        }

        // ------------------------------------------------------------------------------------------------ name plates
        /// <summary>Behind the name of a player: the frame and the guild, and the title above (opcode 248). Called from the name loop with the name label's rect.</summary>
        void DrawNameplate(Creature c, float x, Rect nameRect)
        {
            var u = Utils;
            if (u == null || c.Type != 0 || Event.current.type != EventType.Repaint) return;
            WorldStyles();
            var plate = u.Plates.Shown(c.Id, session.Now);
            if (plate == null) return;
            float nw = nameStyle.CalcSize(new GUIContent(c.Name)).x + 14;
            string guild = NameplateState.GuildText(plate.Guild);
            float gw = guild.Length > 0 ? plateStyle.CalcSize(new GUIContent(guild)).x + 14 : 0;
            float w = Mathf.Max(nw, gw), gh = guild.Length > 0 ? 12f : 0f;
            var frame = new Rect(x - w / 2, nameRect.yMax - 17 - gh, w, 17 + gh);
            if (!DrawPlatePicture(plate.Frame, frame))   // the frame picture of game_nameplate cut in nine; the bordered box without it
            {
                Fill(frame, new Color(0.05f, 0.04f, 0.06f, 0.78f));
                Ui.Frame(frame, HexColor(NameplateState.FrameColor(plate.Frame)));
            }
            if (guild.Length > 0) ShadowText(new Rect(frame.x, frame.y - 1, frame.width, 14), guild, plateStyle, HexColor(NameplateState.GuildColorFor(c.Emblem)));
            if (plate.Title.Length > 0) ShadowText(new Rect(x - 100, frame.y - 15, 200, 14), plate.Title, plateStyle, HexColor(plate.Color));
        }

        // ------------------------------------------------------------------------------------------------ the minimap window
        /// <summary>Points of interest and party pins on the minimap window (map is the picture's rect, p the centre tile, ppt pixels per tile, size the picture's side).</summary>
        public void DrawMinimapMarks(Rect map, Pos p, int floor, int ppt, int size)
        {
            var u = Utils;
            if (u == null || Event.current.type != EventType.Repaint) return;
            int tiles = size / ppt, half = tiles / 2;
            var m = u.Marks;
            var mouse = Event.current.mousePosition;
            if (m.Settings.Poi)
            {
                foreach (var mk in MapMarkMath.Visible(m.Floors, floor, p.X - half, p.Y - half, p.X - half + tiles, p.Y - half + tiles, m.Settings, MapMarkMath.MaxPoi))
                {
                    float x = map.x + (mk.X - (p.X - half)) * ppt + ppt / 2f, y = map.y + (mk.Y - (p.Y - half)) * ppt + ppt / 2f;
                    var r = new Rect(x - 3, y - 3, 6, 6);
                    if (ArtMark(MarkArt.Poi(mk.Kind), new Vector2(x, y), MarkArt.PoiPx, MarkArt.PoiPx, Color.white)) r = new Rect(x - 7, y - 7, 14, 14);
                    else
                    {
                        Fill(new Rect(r.x - 1, r.y - 1, 8, 8), new Color(0f, 0f, 0f, 0.85f));
                        Fill(r, MarkColor(mk.Kind));
                    }
                    if (mk.Name.Length > 0 && r.Contains(mouse)) SetTip(mk.Name);
                }
            }
            // the safe exits and the shrine of the Scorched Marches while the zone is entered (game_pvpzone)
            var zone = session?.Endgame?.PvpZone;
            if (zone != null && zone.Marks.Count > 0)
            {
                foreach (var zm in PvpZoneFlags.Visible(zone.Marks, floor, p.X - half, p.Y - half, p.X - half + tiles, p.Y - half + tiles))
                {
                    float x = map.x + (zm.X - (p.X - half)) * ppt + ppt / 2f, y = map.y + (zm.Y - (p.Y - half)) * ppt + ppt / 2f;
                    var r = new Rect(x - 4, y - 4, 8, 8);
                    Fill(new Rect(r.x - 1, r.y - 1, 10, 10), new Color(0f, 0f, 0f, 0.9f));
                    Fill(r, HexColor(PvpZoneFlags.Color(zm.Kind)));
                    if (r.Contains(mouse)) SetTip(PvpZoneFlags.Tip(zm));
                }
            }
            if (!m.Settings.Party) return;
            double now = session.Now;
            foreach (var pm in m.Party.Values)
            {
                m.Anim.TryGetValue(pm.Id, out var anim);
                double gx = pm.X, gy = pm.Y;
                if (anim != null) MapMarkMath.Glide(anim, now, out gx, out gy, out _);
                float x = map.x + ((float)gx - (p.X - half)) * ppt + ppt / 2f, y = map.y + ((float)gy - (p.Y - half)) * ppt + ppt / 2f;
                bool inside = MapMarkMath.Edge(x, y, map.x, map.y, map.width, map.height, 7, out double ex, out double ey, out _);
                var col = HexColor(MapMarkMath.Color(m.SlotOf(pm.Id)));
                var r = new Rect((float)ex - 4, (float)ey - 4, 8, 8);
                if (ArtMark(MarkArt.PartyPin, new Vector2((float)ex, (float)ey), MarkArt.ArrowPx, MarkArt.ArrowPx, col)) r = new Rect((float)ex - 6, (float)ey - 6, 12, 12);
                else
                {
                    Fill(new Rect(r.x - 1, r.y - 1, 10, 10), new Color(0f, 0f, 0f, 0.9f));
                    Fill(r, col);
                }
                string arrow = MapMarkMath.FloorArrow(pm.Z, floor);
                if (arrow.Length > 0 && !ArtMark(MarkArt.Floor(arrow), new Vector2(r.xMax + 5, r.y + 4), MarkArt.FloorPx, MarkArt.FloorPx, Color.white)) GUI.Label(new Rect(r.x + 8, r.y - 4, 14, 14), arrow == "up" ? "^" : "v", worldTiny);
                if (r.Contains(mouse)) SetTip(MapMarkMath.MemberText(pm, world.Player.Position, true));
                if (!inside) { }
            }
        }

        // ------------------------------------------------------------------------------------------------ HUD pieces
        /// <summary>The Candlemarks counter, the Hideout placing bar and the tooltip (over the windows, like the HUD).</summary>
        void WorldGui(float w, float h, float scale)
        {
            var u = Utils;
            if (u == null) { worldTip = ""; return; }
            WorldStyles();
            if (u.Candles.Hud != null)
            {
                var r = new Rect(w - 104 - 76 * 7 - 216, 12, 210, 24);
                uiRects.Add(Scaled(r, scale));
                Fill(r, new Color(0.04f, 0.03f, 0.05f, 0.8f));
                GUI.Label(new Rect(r.x + 4, r.y + 2, r.width - 8, 20), u.Candles.CounterText(), worldTiny);
                if (GUI.Button(r, new GUIContent("", u.Candles.CounterTip()), GUIStyle.none)) u.Candles.Toggle();
                if (r.Contains(Event.current.mousePosition)) SetTip(u.Candles.CounterTip());
            }
            if (placing && placingRow != null)
            {
                var r = new Rect(w / 2 - 260, 8, 520, 44);
                uiRects.Add(Scaled(r, scale));
                Fill(r, new Color(0.04f, 0.03f, 0.05f, 0.9f));
                GUI.Label(new Rect(r.x + 6, r.y + 2, r.width - 150, 20), Loc.T("Placing {0}: left click places, the wheel turns it, right click ends.", placingRow.Name), worldTiny);
                Ui.Text(new Rect(r.x + 6, r.y + 22, r.width - 150, 18), placingMsg.Length > 0 ? placingMsg : u.Hideout.ResultText, worldTiny, placingMsg.Length > 0 ? "#e07060" : "#8cd08c");
                if (GUI.Button(new Rect(r.xMax - 140, r.y + 10, 64, 24), Loc.T("Rotate"))) placingRot = HideoutState.NextRot(placingRow, placingRot);
                if (GUI.Button(new Rect(r.xMax - 72, r.y + 10, 64, 24), Loc.T("Done"))) StopHideoutPlacing();
            }
            if (worldTip.Length > 0)
            {
                var m = Event.current.mousePosition;
                var gc = new GUIContent(worldTip);
                var st = Ui.Wrap(this, 12);
                float tw = Mathf.Min(300, worldStyle.CalcSize(gc).x + 12);
                float th = st.CalcHeight(gc, tw - 8) + 8;
                var r = new Rect(Mathf.Min(m.x + 14, w - tw - 4), Mathf.Min(m.y + 14, h - th - 4), tw, th);
                Fill(r, new Color(0.04f, 0.03f, 0.05f, 0.95f));
                Ui.Frame(r, new Color(0.6f, 0.45f, 0.2f, 1f));
                GUI.Label(new Rect(r.x + 4, r.y + 4, r.width - 8, r.height - 8), worldTip, st);
                if (Event.current.type == EventType.Repaint) worldTip = "";
            }
        }
    }
}
