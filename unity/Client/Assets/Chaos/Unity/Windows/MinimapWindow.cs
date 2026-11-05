// Minimap (Ctrl+M): the remembered minimap round the player, one pixel block per tile, white cross on the player.
// The texture is rebuilt when the memory, the player's tile, the floor or the zoom changes, not every frame.
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class MinimapWindow : GameWindow
    {
        const int Size = 200;                                // texture side in pixels (and UI units)
        static readonly int[] Zooms = { 1, 2, 4, 5, 8 };     // pixels per tile; all divide Size
        static Color32[] palette;

        Texture2D tex;
        Color32[] buf;
        int zoom = 1;                                        // index into Zooms: 2 px per tile
        int floor, lastPlayerZ = -1;
        int builtVersion = -1, builtX, builtY, builtZ, builtZoom = -1;

        public override string Title => "Minimap";
        public override KeyCode Hotkey => KeyCode.M;
        protected override Rect Place(float w, float h) => new Rect(w - 216, 44, Size + 8, Size + 62);

        public override void Reset()
        {
            if (tex != null) UnityEngine.Object.Destroy(tex);
            tex = null;
            builtVersion = -1;
            builtZoom = -1;
            lastPlayerZ = -1;
        }

        static Color32 Colour(byte c)
        {
            if (palette == null)
            {
                palette = new Color32[256];
                for (int i = 0; i < 256; i++)
                {
                    MinimapMemory.Rgb((byte)i, out byte r, out byte g, out byte b);
                    palette[i] = new Color32(r, g, b, 255);
                }
            }
            return palette[c];
        }

        void Build(MinimapMemory mem, Pos p)
        {
            if (tex == null)
            {
                tex = new Texture2D(Size, Size, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
                buf = new Color32[Size * Size];
            }
            int ppt = Zooms[zoom], tiles = Size / ppt, half = tiles / 2;
            var unknown = new Color32(12, 10, 14, 255);
            for (int ty = 0; ty < tiles; ty++)
                for (int tx = 0; tx < tiles; tx++)
                {
                    byte c = mem.Get(p.X - half + tx, p.Y - half + ty, floor);
                    var col = c == 0 ? unknown : Colour(c);
                    // texture row 0 is the bottom; the map's north is the top
                    for (int dy = 0; dy < ppt; dy++)
                    {
                        int row = Size - 1 - (ty * ppt + dy);
                        for (int dx = 0; dx < ppt; dx++) buf[row * Size + tx * ppt + dx] = col;
                    }
                }
            if (floor == p.Z)
            {
                int cx = half * ppt + ppt / 2, cy = Size - 1 - (half * ppt + ppt / 2), arm = 4 + ppt;
                var white = new Color32(255, 255, 255, 255);
                for (int i = -arm; i <= arm; i++)
                {
                    int hx = cx + i, vy = cy + i;
                    if (hx >= 0 && hx < Size) buf[cy * Size + hx] = white;
                    if (vy >= 0 && vy < Size) buf[vy * Size + cx] = white;
                }
            }
            tex.SetPixels32(buf);
            tex.Apply(false);
            builtVersion = mem.Version;
            builtX = p.X; builtY = p.Y; builtZ = floor; builtZoom = zoom;
        }

        protected override void Body(ChaosApp app, Rect inner)
        {
            var me = app.World?.Player;
            if (me == null) return;
            Pos p = me.Position;
            if (p.Z != lastPlayerZ) { lastPlayerZ = p.Z; floor = p.Z; }
            var mem = app.Minimap;
            if (tex == null || mem.Version != builtVersion || p.X != builtX || p.Y != builtY || floor != builtZ || zoom != builtZoom)
                Build(mem, p);
            var map = new Rect(inner.x, inner.y, Size, Size);
            GUI.DrawTexture(map, tex, ScaleMode.StretchToFill, false);

            float y = map.yMax + 6;
            if (GUI.Button(new Rect(inner.x, y, 30, 24), "^") && floor > 0) floor--;
            if (GUI.Button(new Rect(inner.x + 32, y, 30, 24), "v") && floor < 15) floor++;
            if (GUI.Button(new Rect(inner.x + 64, y, 30, 24), "-") && zoom > 0) zoom--;
            if (GUI.Button(new Rect(inner.x + 96, y, 30, 24), "+") && zoom < Zooms.Length - 1) zoom++;
            GUI.Label(new Rect(inner.x + 130, y + 2, 70, 22), "Floor " + floor, app.SmallStyle);
        }
    }
}
