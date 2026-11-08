// Draws the world as one mesh of 32 x 32 quads over the sprite atlas, rebuilt every frame, in the stock draw order:
// floors bottom to top, tiles by diagonal, in a tile ground / borders / bottom items, common items (newest last),
// creatures, top items. One unit = one tile; the player's tile is at the origin.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class MapView : MonoBehaviour
    {
        public World World;
        public SpriteAtlas Atlas;
        public Func<double> Clock;   // ms, the session's clock (walk animation)
        /// <summary>Phase 7 track Y: the draw size of a creature (monster bar: bosses bigger, oversized monsters smaller; 1 when null) and the rarity outline of items on the map.</summary>
        public Func<Creature, float> CreatureScale;
        public bool ItemOutlines = true;
        Color32 tint = new Color32(255, 255, 255, 255);
        float quadScale = 1f, pivotX, pivotY;

        Mesh mesh;
        readonly List<Vector3> verts = new List<Vector3>();
        readonly List<Vector2> uvs = new List<Vector2>();
        readonly List<Color32> cols = new List<Color32>();
        readonly List<int> tris = new List<int>();
        public readonly List<(Creature c, Vector2 at)> Labels = new List<(Creature, Vector2)>();
        Vector2 cam;   // the player's drawn position in tiles (walk offset included)
        /// <summary>The player's drawn position in tiles (the loot labels place themselves with it).</summary>
        public Vector2 CamTiles => cam;

        void Awake()
        {
            mesh = new Mesh { name = "chaos-map" };
            mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
            mesh.MarkDynamic();
            gameObject.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = gameObject.AddComponent<MeshRenderer>();
            mr.sharedMaterial = new Material(Shader.Find("Sprites/Default"));
        }

        /// <summary>Off while the HD-2D view draws the world (F9): no mesh is built, nothing is drawn.</summary>
        public void SetVisible(bool on)
        {
            enabled = on;
            var mr = GetComponent<MeshRenderer>();
            if (mr != null) mr.enabled = on;
        }

        void LateUpdate() { Refresh(); }

        /// <summary>Builds the mesh for the current world now (LateUpdate, or the screenshot mode without a frame).</summary>
        public void Refresh()
        {
            if (World == null || Atlas == null) return;
            int gen = Atlas.Generation;
            Build();
            if (Atlas.Generation != gen) Build();   // the atlas filled up and was cleared while building
            Atlas.Upload();
            GetComponent<MeshRenderer>().sharedMaterial.mainTexture = Atlas.Texture;
        }

        double Now => Clock != null ? Clock() : Time.realtimeSinceStartupAsDouble * 1000;

        /// <summary>A creature's drawn position in world tiles (between its last two tiles while it walks).</summary>
        Vector2 Drawn(Creature c, out float progress)
        {
            progress = 1;
            var p = new Vector2(c.Position.X, c.Position.Y);
            if (c.WalkStart >= 0 && c.WalkMs > 0)
            {
                progress = (float)Math.Min(1.0, (Now - c.WalkStart) / c.WalkMs);
                if (progress < 1)
                {
                    var from = new Vector2(c.WalkFrom.X, c.WalkFrom.Y);
                    return Vector2.Lerp(from, p, progress);
                }
            }
            return p;
        }

        int FirstVisibleFloor(Pos c)
        {
            // underground the view holds two floors up at most, never the surface
            return FloorAbove(c, c.Z > 7 ? Math.Max(8, c.Z - 2) : 0);
        }

        int FloorAbove(Pos c, int top)
        {
            for (int k = 1; c.Z - k >= top; k++)
            {
                if (Covers(World.Get(new Pos(c.X + k, c.Y + k, c.Z - k))) || Covers(World.Get(new Pos(c.X, c.Y, c.Z - k))))
                    return c.Z - k + 1;
            }
            return top;
        }

        static bool Covers(Tile t)
        {
            if (t == null) return false;
            foreach (var th in t.Things)
                if (!th.IsCreature && th.Item.Type != null && (th.Item.Type.Ground || th.Item.Type.OnBottom && th.Item.Type.BlockPath && !th.Item.Type.DontHide))
                    return true;
            return false;
        }

        void Build()
        {
            verts.Clear(); uvs.Clear(); cols.Clear(); tris.Clear(); Labels.Clear();
            var player = World.Player;
            Pos center = World.Center;
            float t0;
            cam = player != null ? Drawn(player, out t0) : new Vector2(center.X, center.Y);
            int first = FirstVisibleFloor(center);
            int last = center.Z > 7 ? Math.Min(center.Z + 2, 15) : 7;
            int w = World.ViewW + 4, h = World.ViewH + 4;
            for (int z = last; z >= first; z--)
            {
                int off = z - center.Z;   // a lower floor is drawn shifted right and down by its depth
                for (int diag = 0; diag < w + h - 1; diag++)
                    for (int sx = Math.Max(0, diag - h + 1); sx <= Math.Min(diag, w - 1); sx++)
                    {
                        int sy = diag - sx;
                        int wx = center.X - World.RangeLeft - 1 + sx - off, wy = center.Y - World.RangeTop - 1 + sy - off;
                        var tile = World.Get(new Pos(wx, wy, z));
                        if (tile != null) DrawTile(tile, off);
                    }
            }
            mesh.Clear();
            mesh.SetVertices(verts);
            mesh.SetUVs(0, uvs);
            mesh.SetColors(cols);
            mesh.SetTriangles(tris, 0);
        }

        void DrawTile(Tile tile, int off)
        {
            Pos p = tile.Pos;
            // the tile's top-left corner on screen, in tiles, y up
            float tx = p.X + off - cam.x, ty = -(p.Y + off - cam.y);
            int elevation = 0;
            var things = tile.Things;
            foreach (var th in things)
            {
                if (th.IsCreature) continue;
                int prio = World.StackPriority(th);
                if (prio > 2) continue;
                DrawItem(th.Item, p, tx, ty, ref elevation);
            }
            for (int i = things.Count - 1; i >= 0; i--)
            {
                var th = things[i];
                if (!th.IsCreature && World.StackPriority(th) == 5) DrawItem(th.Item, p, tx, ty, ref elevation);
            }
            foreach (var th in things)
            {
                if (!th.IsCreature) continue;
                var c = th.Creature;
                var at = Drawn(c, out float progress);
                float cx = at.x + off - cam.x, cy = -(at.y + off - cam.y);
                DrawCreature(c, cx, cy, elevation, progress);
                Labels.Add((c, new Vector2(cx, cy)));
            }
            foreach (var th in things)
            {
                if (th.IsCreature || World.StackPriority(th) != 3) continue;
                int none = 0;
                DrawItem(th.Item, p, tx, ty, ref none);
            }
        }

        internal static int StackIndex(int count)
        {
            if (count <= 1) return 0;
            if (count < 5) return count - 1;
            if (count < 10) return 4;
            if (count < 25) return 5;
            if (count < 50) return 6;
            return 7;
        }

        int Phase(FrameGroup g, long salt)
        {
            if (g.Phases <= 1) return 0;
            int d = g.MinDuration != null && g.MinDuration[0] > 0 ? g.MinDuration[0] : 300;
            return (int)(((long)Now / d + salt) % g.Phases);
        }

        void DrawItem(Item it, Pos p, float tx, float ty, ref int elevation)
        {
            var t = it.Type;
            if (t == null) return;
            var g = t.Idle;
            int px, py, pz;
            if (t.Stackable && g.PatternX * g.PatternY >= 8)
            {
                int s = StackIndex(it.Count);
                px = s % 4; py = s / 4; pz = 0;
            }
            else if ((t.Fluid || t.Splash) && g.PatternX * g.PatternY > 1)
            {
                int s = it.Count % (g.PatternX * g.PatternY);
                px = s % g.PatternX; py = s / g.PatternX; pz = 0;
            }
            else
            {
                px = Mod(p.X, g.PatternX); py = Mod(p.Y, g.PatternY); pz = Mod(p.Z, g.PatternZ);
            }
            int phase = Phase(g, 0);
            float ox = tx - (elevation + t.DisplacementX) / 32f, oy = ty + (elevation + t.DisplacementY) / 32f;
            // the rarity outline: the sprite again, tinted with the rarity colour, one pixel to each side, behind itself (game_itemrarity, world shader)
            string outline = ItemOutlines ? MapItemOutline.Color(it) : null;
            if (outline != null && ColorUtility.TryParseHtmlString(outline, out Color oc))
            {
                oc.a = MapItemOutline.Alpha(it, Now);
                tint = oc;
                foreach (var d in MapItemOutline.Offsets)
                    for (int layer = 0; layer < g.Layers; layer++)
                        for (int hh = 0; hh < g.Height; hh++)
                            for (int ww = 0; ww < g.Width; ww++)
                                Quad(Atlas.Sprite(g.Sprite(ww, hh, layer, px, py, pz, phase)), ox - ww + d[0] / MapItemOutline.PixelsPerTile, oy + hh + d[1] / MapItemOutline.PixelsPerTile);
                tint = new Color32(255, 255, 255, 255);
            }
            for (int layer = 0; layer < g.Layers; layer++)
                for (int hh = 0; hh < g.Height; hh++)
                    for (int ww = 0; ww < g.Width; ww++)
                        Quad(Atlas.Sprite(g.Sprite(ww, hh, layer, px, py, pz, phase)), ox - ww, oy + hh);
            if (t.Elevation > 0) elevation = Math.Min(24, elevation + t.Elevation);
        }

        static int Mod(int a, int n) { int m = a % n; return m < 0 ? m + n : m; }

        void DrawCreature(Creature c, float x, float y, int elevation, float progress)
        {
            var o = c.Outfit;
            if (o.LookType == 0)
            {
                if (o.LookTypeEx != 0)
                {
                    var it = World.MakeItem(o.LookTypeEx, 1);
                    int e = elevation;
                    DrawItem(it, c.Position, x, y, ref e);
                }
                return;
            }
            var t = World.Dat.Outfit(o.LookType);
            if (t == null) return;
            bool walking = progress < 1;
            var g = walking ? t.Moving : t.Idle;
            int dir = (int)c.Direction;
            if (dir > 3) dir = dir == 4 || dir == 5 ? 1 : 3;   // a diagonal faces east or west, as the stock client draws it
            if (g.PatternX >= 8) dir = (int)c.Direction;   // a look with eight facings (src-patch 0077)
            int phase;
            if (walking && g.Phases > 1) phase = 1 + (int)(progress * (g.Phases - 1)) % (g.Phases - 1);
            else phase = g.Phases > 1 && !walking && (t.Groups.Length > 1 || BossAnimate.Animates(o.LookType)) ? Phase(g, c.Id) : 0;   // game_bossanimate: a look with walk frames only still beats its wings
            float scale = CreatureScale != null && c.Type == 1 ? CreatureScale(c) : 1f;
            if (scale != 1f) { quadScale = scale; pivotX = x + 0.5f; pivotY = y - 1f; }   // monster bar: drawn bigger or smaller round the middle of its feet
            BossAnimate.Shift(o.LookType, out int bsx, out int bsy);   // and a boss whose art sits off its tile is moved down and right
            float ox = x - (elevation + t.DisplacementX + bsx) / 32f, oy = y + (elevation + t.DisplacementY + bsy) / 32f;
            for (int addon = 0; addon < g.PatternY; addon++)
            {
                if (addon > 0 && (o.Addons & (1 << (addon - 1))) == 0) continue;
                for (int hh = 0; hh < g.Height; hh++)
                    for (int ww = 0; ww < g.Width; ww++)
                    {
                        uint baseId = g.Sprite(ww, hh, 0, dir, addon, 0, phase);
                        uint maskId = g.Layers > 1 ? g.Sprite(ww, hh, 1, dir, addon, 0, phase) : 0;
                        int slot;
                        if (maskId == 0) slot = Atlas.Sprite(baseId);
                        else
                        {
                            ulong key = (ulong)baseId << 28 ^ (ulong)(o.Head & 127) << 21 ^ (ulong)(o.Body & 127) << 14 ^ (ulong)(o.Legs & 127) << 7 ^ (ulong)(o.Feet & 127);
                            slot = Atlas.Composed(key, () =>
                            {
                                var rgba = Atlas.Raw(baseId);
                                var mask = Atlas.Raw(maskId);
                                if (rgba != null && mask != null) OutfitColors.Apply(rgba, mask, o);
                                return rgba;
                            });
                        }
                        Quad(slot, ox - ww, oy + hh);
                    }
            }
            quadScale = 1f;
        }

        Vector3 Piv(float px, float py) => new Vector3(pivotX + (px - pivotX) * quadScale, pivotY + (py - pivotY) * quadScale, 0);

        /// <summary>One 1 x 1 quad with its top-left corner at (x, y).</summary>
        void Quad(int slot, float x, float y)
        {
            if (slot == 0) return;
            var r = Atlas.Uv(slot);
            int i = verts.Count;
            if (quadScale != 1f)
            {
                verts.Add(Piv(x, y - 1)); verts.Add(Piv(x + 1, y - 1)); verts.Add(Piv(x + 1, y)); verts.Add(Piv(x, y));
            }
            else
            {
                verts.Add(new Vector3(x, y - 1, 0));
                verts.Add(new Vector3(x + 1, y - 1, 0));
                verts.Add(new Vector3(x + 1, y, 0));
                verts.Add(new Vector3(x, y, 0));
            }
            uvs.Add(new Vector2(r.xMin, r.yMin));
            uvs.Add(new Vector2(r.xMax, r.yMin));
            uvs.Add(new Vector2(r.xMax, r.yMax));
            uvs.Add(new Vector2(r.xMin, r.yMax));
            for (int k = 0; k < 4; k++) cols.Add(tint);
            tris.Add(i); tris.Add(i + 2); tris.Add(i + 1);
            tris.Add(i); tris.Add(i + 3); tris.Add(i + 2);
        }
    }
}
