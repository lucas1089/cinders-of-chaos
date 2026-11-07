// Front-art scene (test of a new look): procedural pixel textures, 16 texels per world unit, drawn in code.
// The recipe is the one of small lit dioramas: crisp point-filtered texels, a hue-shifted palette (cool violet shadows,
// warm highlights), hand-placed looking detail (bevelled stones, chips, cracks, moss, pebbles, blades), and a height map
// per texture that gives a normal map. Every texture is 64 x 64 texels = 4 x 4 world units and tiles in both directions.
// Pure C#, no Unity types: the same file builds in Unity and in Core.Tests. Deterministic: same kind and seed, same bytes.
// The idea (not the code) follows the MIT-licensed Luminati engine, see docs/CREDITS.md.
using System;

namespace Chaos.Core
{
    /// <summary>A block texture kind.</summary>
    public enum FaTex { Flagstone, Cobble, Dirt, MossDirt, DeadGrass, Brick, Wood, Coal, Grass, Sand, Snow, Water, Lava, Count }

    /// <summary>RGBA texels (row 0 is the bottom row, like Unity) and a height per texel in 0..1.</summary>
    public sealed class PixelTex
    {
        public readonly int W, H;
        public readonly byte[] Rgba;
        public readonly float[] Height;
        public PixelTex(int w, int h) { W = w; H = h; Rgba = new byte[w * h * 4]; Height = new float[w * h]; }

        static int Mod(int a, int n) { int r = a % n; return r < 0 ? r + n : r; }

        /// <summary>Sets a texel (coordinates wrap, y grows downwards while a texture is built).</summary>
        public void Set(int x, int y, uint rgb, float height)
        {
            int i = Mod(y, H) * W + Mod(x, W);
            Rgba[i * 4] = (byte)(rgb >> 16); Rgba[i * 4 + 1] = (byte)(rgb >> 8); Rgba[i * 4 + 2] = (byte)rgb; Rgba[i * 4 + 3] = 255;
            Height[i] = height < 0f ? 0f : height > 1f ? 1f : height;
        }

        public uint Get(int x, int y)
        {
            int i = (Mod(y, H) * W + Mod(x, W)) * 4;
            return ((uint)Rgba[i] << 16) | ((uint)Rgba[i + 1] << 8) | Rgba[i + 2];
        }

        public float HeightAt(int x, int y) { return Height[Mod(y, H) * W + Mod(x, W)]; }

        /// <summary>Turns the picture upside down (built top-down, Unity wants the bottom row first).</summary>
        public void FlipY()
        {
            var row = new byte[W * 4];
            var hrow = new float[W];
            for (int y = 0; y < H / 2; y++)
            {
                int a = y * W, b = (H - 1 - y) * W;
                Buffer.BlockCopy(Rgba, a * 4, row, 0, W * 4);
                Buffer.BlockCopy(Rgba, b * 4, Rgba, a * 4, W * 4);
                Buffer.BlockCopy(row, 0, Rgba, b * 4, W * 4);
                Array.Copy(Height, a, hrow, 0, W);
                Array.Copy(Height, b, Height, a, W);
                Array.Copy(hrow, 0, Height, b, W);
            }
        }
    }

    public static class FrontArtTex
    {
        public const int TexelsPerUnit = 16, Size = 64;
        /// <summary>World size of one texture tile in units.</summary>
        public const float TileUnits = Size / (float)TexelsPerUnit;

        // palettes, dark to light: shadows lean blue-violet, lights lean warm
        static readonly uint[] StoneRamp = { 0x201e2e, 0x302d40, 0x433f53, 0x585364, 0x6f6870, 0x887f7c };
        static readonly uint[] CobbleRamp = { 0x221f2d, 0x332d3a, 0x483f48, 0x5f5256, 0x78675f, 0x938070 };
        static readonly uint[] DirtRamp = { 0x20192a, 0x30232c, 0x452f2d, 0x5b4034, 0x735340, 0x8c6a4c };
        static readonly uint[] MossRamp = { 0x182430, 0x23362e, 0x31482d, 0x445d33, 0x5e763b, 0x7e9345 };
        static readonly uint[] BrickRamp = { 0x241c30, 0x372836, 0x4d343c, 0x634545, 0x7d5951, 0x997462 };
        static readonly uint[] WoodRamp = { 0x1d1626, 0x2f2022, 0x432d29, 0x593c30, 0x735238, 0x8d6c43 };
        static readonly uint[] GrassRamp = { 0x252336, 0x39342b, 0x4d4a2c, 0x6a5f32, 0x877943, 0xa59155 };
        static readonly uint[] CoalRamp = { 0x2a0e18, 0x5a1612, 0x9a2c10, 0xd9570f, 0xff8a1c, 0xffc650 };
        // the live view's ground kinds (Core/FrontLive.cs): living grass, sand, snow, water
        static readonly uint[] GreenRamp = { 0x1b2a33, 0x27402f, 0x365730, 0x497033, 0x628b3c, 0x86a94b };
        static readonly uint[] SandRamp = { 0x2a2434, 0x4a3f45, 0x6e5f55, 0x927f69, 0xb59d7c, 0xd6bf94 };
        static readonly uint[] SnowRamp = { 0x2c3050, 0x4a5076, 0x7078a0, 0x9ea6c6, 0xcdd2e6, 0xf6f0ea };
        static readonly uint[] WaterRamp = { 0x10152e, 0x16254a, 0x1f3a66, 0x2d5586, 0x4a7aa6, 0x86b0c8 };
        const uint Mortar = 0x15121e;

        /// <summary>The colour ramp of a kind, dark to light (6 steps). Shadows are cool, lights warm.</summary>
        public static uint[] Ramp(FaTex kind)
        {
            switch (kind)
            {
                case FaTex.Flagstone: return StoneRamp;
                case FaTex.Cobble: return CobbleRamp;
                case FaTex.Dirt: return DirtRamp;
                case FaTex.MossDirt: return DirtRamp;
                case FaTex.DeadGrass: return GrassRamp;
                case FaTex.Brick: return BrickRamp;
                case FaTex.Wood: return WoodRamp;
                case FaTex.Coal: return CoalRamp;
                case FaTex.Grass: return GreenRamp;
                case FaTex.Sand: return SandRamp;
                case FaTex.Snow: return SnowRamp;
                case FaTex.Water: return WaterRamp;
                case FaTex.Lava: return CoalRamp;
                default: return StoneRamp;
            }
        }

        // ---- noise ----

        static uint Hash(int x, int y, uint seed)
        {
            unchecked
            {
                uint h = (uint)x * 374761393u + (uint)y * 668265263u + seed * 2246822519u + 0x9E3779B9u;
                h = (h ^ (h >> 13)) * 1274126177u;
                return h ^ (h >> 16);
            }
        }

        static float F(uint h) { return (h & 0xFFFFFF) / 16777216f; }

        static int Mod(int a, int n) { int r = a % n; return r < 0 ? r + n : r; }

        /// <summary>Deterministic float in 0..1 from two integers and a seed.</summary>
        public static float Rand(int x, int y, uint seed) { return F(Hash(x, y, seed)); }

        /// <summary>Tileable value noise: u, v in 0..1 (wraps), cx, cy lattice cells.</summary>
        static float VN(float u, float v, int cx, int cy, uint seed)
        {
            float x = u * cx, y = v * cy;
            int x0 = (int)Math.Floor(x), y0 = (int)Math.Floor(y);
            float fx = x - x0, fy = y - y0;
            fx = fx * fx * (3f - 2f * fx); fy = fy * fy * (3f - 2f * fy);
            float a = F(Hash(Mod(x0, cx), Mod(y0, cy), seed)), b = F(Hash(Mod(x0 + 1, cx), Mod(y0, cy), seed));
            float c = F(Hash(Mod(x0, cx), Mod(y0 + 1, cy), seed)), d = F(Hash(Mod(x0 + 1, cx), Mod(y0 + 1, cy), seed));
            return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy;
        }

        sealed class Rng
        {
            uint s;
            public Rng(uint seed) { s = seed * 2654435761u + 12345u; }
            public uint Next() { unchecked { s ^= s << 13; s ^= s >> 17; s ^= s << 5; } return s; }
            public int Int(int n) { return (int)(Next() % (uint)n); }
            public float Float() { return (Next() & 0xFFFFFF) / 16777216f; }
        }

        static uint Pick(uint[] ramp, int level) { return ramp[level < 0 ? 0 : level >= ramp.Length ? ramp.Length - 1 : level]; }

        // four hue variants (neutral, cooler, warmer, greener): every stone, plank and patch leans a little its own way
        static readonly int[,] Lean = { { 0, 0, 0 }, { -7, -1, 9 }, { 9, 3, -7 }, { -5, 7, -1 } };

        static uint Pick(uint[] ramp, int level, int variant)
        {
            uint c = Pick(ramp, level);
            int v = variant & 3;
            int r = Math.Max(0, Math.Min(255, (int)((c >> 16) & 255) + Lean[v, 0]));
            int g = Math.Max(0, Math.Min(255, (int)((c >> 8) & 255) + Lean[v, 1]));
            int b = Math.Max(0, Math.Min(255, (int)(c & 255) + Lean[v, 2]));
            return (uint)((r << 16) | (g << 8) | b);
        }

        // ---- public entry ----

        /// <summary>Builds the texture of a kind. Same kind and seed give the same bytes.</summary>
        public static PixelTex Make(FaTex kind, uint seed)
        {
            PixelTex t;
            switch (kind)
            {
                case FaTex.Flagstone: t = Flagstone(seed); break;
                case FaTex.Cobble: t = Cobble(seed); break;
                case FaTex.Dirt: t = Dirt(seed, false); break;
                case FaTex.MossDirt: t = Dirt(seed, true); break;
                case FaTex.DeadGrass: t = DeadGrass(seed); break;
                case FaTex.Brick: t = Brick(seed); break;
                case FaTex.Wood: t = Wood(seed); break;
                case FaTex.Coal: t = Coal(seed); break;
                case FaTex.Grass: t = GreenGrass(seed); break;
                case FaTex.Sand: t = Sand(seed); break;
                case FaTex.Snow: t = Snow(seed); break;
                case FaTex.Water: t = Water(seed); break;
                case FaTex.Lava: t = Lava(seed); break;
                default: throw new ArgumentOutOfRangeException("kind");
            }
            t.FlipY();
            return t;
        }

        /// <summary>How much a kind glows by itself (the block shader's _Emit): coal and lava.</summary>
        public static float Emit(FaTex kind) { return kind == FaTex.Coal ? 1.7f : kind == FaTex.Lava ? 1.3f : 0f; }

        /// <summary>The relief strength of a kind's normal map: soft ground (grass, sand, snow, water) and coal a gentle one, stone a hard one.</summary>
        public static float ReliefStrength(FaTex kind)
        {
            return kind == FaTex.Coal || kind == FaTex.DeadGrass || kind == FaTex.Grass || kind == FaTex.Sand || kind == FaTex.Snow || kind == FaTex.Water || kind == FaTex.Lava ? 1.5f : 3.0f;
        }

        /// <summary>A tangent-space normal map (RGBA, 128/128/255 is flat) from the height map; strength scales the slope.</summary>
        public static byte[] NormalMap(PixelTex t, float strength)
        {
            var o = new byte[t.W * t.H * 4];
            for (int y = 0; y < t.H; y++)
                for (int x = 0; x < t.W; x++)
                {
                    float dx = (t.HeightAt(x + 1, y) - t.HeightAt(x - 1, y)) * strength;
                    float dy = (t.HeightAt(x, y + 1) - t.HeightAt(x, y - 1)) * strength;   // y grows up after FlipY
                    float len = (float)Math.Sqrt(dx * dx + dy * dy + 1f);
                    int i = (y * t.W + x) * 4;
                    o[i] = (byte)Math.Round((-dx / len * 0.5f + 0.5f) * 255f);
                    o[i + 1] = (byte)Math.Round((-dy / len * 0.5f + 0.5f) * 255f);
                    o[i + 2] = (byte)Math.Round((1f / len * 0.5f + 0.5f) * 255f);
                    o[i + 3] = 255;
                }
            return o;
        }

        // ---- flagstone: slabs in running rows, bevelled, chipped, cracked, with moss in the joints ----

        static PixelTex Flagstone(uint seed)
        {
            var t = new PixelTex(Size, Size);
            var rnd = new Rng(seed);
            int[] rows = { 16, 12, 20, 16 };
            for (int i = 3; i > 0; i--) { int j = rnd.Int(i + 1); int tmp = rows[i]; rows[i] = rows[j]; rows[j] = tmp; }
            int[] opts = { 16, 20, 24, 28 };
            int y0 = 0;
            for (int r = 0; r < rows.Length; r++)
            {
                int h = rows[r], x = rnd.Int(16), rem = Size;
                while (rem > 0)
                {
                    int w = opts[rnd.Int(opts.Length)];
                    if (w > rem) w = rem;
                    if (rem - w > 0 && rem - w < 12) w = rem;
                    Slab(t, x, y0, w, h, rnd, seed);
                    x += w; rem -= w;
                }
                y0 += h;
            }
            return t;
        }

        static void Slab(PixelTex t, int x, int y0, int w, int h, Rng rnd, uint seed)
        {
            int baseLevel = 1 + rnd.Int(3), variant = rnd.Int(4);
            for (int ly = 0; ly < h; ly++)
                for (int lx = 0; lx < w; lx++)
                {
                    int px = x + lx, py = y0 + ly;
                    if (lx == w - 1 || ly == h - 1) { t.Set(px, py, Mortar, 0f); continue; }
                    int b = baseLevel;
                    if (ly == 0 || lx == 0) b++;
                    else if (ly == h - 2 || lx == w - 2) b--;
                    float nu = Mod(px, Size) / (float)Size, nv = Mod(py, Size) / (float)Size;
                    float n = VN(nu, nv, 4, 4, seed + 7);
                    if (n > 0.62f) b++; else if (n < 0.30f) b--;
                    float sp = F(Hash(px, py, seed + 3));
                    if (sp < 0.07f) b--; else if (sp > 0.94f) b++;
                    bool edge = ly == 0 || lx == 0 || ly == h - 2 || lx == w - 2;
                    if (lx <= 1 && ly <= 1 && F(Hash(x, y0, seed + 11)) < 0.3f) { t.Set(px, py, Mortar, 0.1f); continue; }
                    t.Set(px, py, Pick(StoneRamp, b, variant), (edge ? 0.5f : 0.62f) + 0.07f * b);
                }
            if (rnd.Float() < 0.35f)
            {
                int cx = 1 + rnd.Int(Math.Max(1, w - 4)), cy = 0;
                int len = 8 + rnd.Int(10);
                for (int i = 0; i < len && cy < h - 2; i++)
                {
                    t.Set(x + cx, y0 + cy, StoneRamp[0], 0.2f);
                    if (cx + 1 < w - 1) t.Set(x + cx + 1, y0 + cy, StoneRamp[4], 0.7f);
                    int step = rnd.Int(4); cx += step == 0 ? -1 : step == 1 ? 1 : 0; cy++;
                    if (cx < 1) cx = 1; if (cx > w - 3) cx = w - 3;
                }
            }
            if (rnd.Float() < 0.45f)
            {
                for (int lx = 0; lx < w - 1; lx++)
                {
                    int corner = (lx < 3 || lx > w - 5) ? 2 : 0;
                    int depth = 1 + (int)(3f * VN(lx / (float)w, 0.5f, 5, 2, seed + (uint)(x * 7 + y0))) + corner;
                    for (int d = 0; d < depth; d++)
                    {
                        int ly = h - 2 - d;
                        if (ly < 1) break;
                        int mlevel = 1 + (int)(F(Hash(x + lx, y0 + ly, seed + 5)) * 4f);
                        if (d == depth - 1 && depth > 1) mlevel = Math.Min(mlevel, 2);
                        t.Set(x + lx, y0 + ly, Pick(MossRamp, mlevel), 0.78f + 0.03f * mlevel);
                    }
                }
            }
        }

        // ---- cobble: tileable voronoi cells, domed, dark joints ----

        static PixelTex Cobble(uint seed)
        {
            var t = new PixelTex(Size, Size);
            const int cell = 8, n = Size / cell;
            var px = new float[n, n]; var py = new float[n, n];
            for (int cy = 0; cy < n; cy++)
                for (int cx = 0; cx < n; cx++)
                {
                    px[cx, cy] = cx * cell + 1.5f + F(Hash(cx, cy, seed)) * (cell - 3f);
                    py[cx, cy] = cy * cell + 1.5f + F(Hash(cx, cy, seed + 1)) * (cell - 3f);
                }
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                {
                    float d1 = 1e9f, d2 = 1e9f; int id = 0; float ox = 0, oy = 0;
                    int gx = x / cell, gy = y / cell;
                    for (int j = -1; j <= 1; j++)
                        for (int i = -1; i <= 1; i++)
                        {
                            int cx = gx + i, cy = gy + j;
                            int wx = Mod(cx, n), wy = Mod(cy, n);
                            float fx = px[wx, wy] + (cx < 0 ? -Size : cx >= n ? Size : 0);
                            float fy = py[wx, wy] + (cy < 0 ? -Size : cy >= n ? Size : 0);
                            float dx = x + 0.5f - fx, dy = y + 0.5f - fy;
                            float d = (float)Math.Sqrt(dx * dx + dy * dy);
                            if (d < d1) { d2 = d1; d1 = d; id = wy * n + wx; ox = dx; oy = dy; }
                            else if (d < d2) d2 = d;
                        }
                    float e = d2 - d1;
                    if (e < 1.1f) { t.Set(x, y, Mortar, 0f); continue; }
                    int b = 2 + (int)(F(Hash(id, 5, seed + 2)) * 3f) - 1;
                    float light = ox + oy;   // negative: the upper left half of the dome
                    if (light < -1.5f) b++; else if (light > 2.5f) b--;
                    if (e < 2.2f) b--;
                    float sp = F(Hash(x, y, seed + 3));
                    if (sp < 0.08f) b--; else if (sp > 0.93f) b++;
                    float nd = Math.Min(1f, d1 / 4.6f);
                    float dome = (1f - nd * nd) * Math.Min(1f, e / 3f);
                    t.Set(x, y, Pick(CobbleRamp, b, (int)(Hash(id, 9, seed + 4) >> 8)), 0.25f + 0.7f * dome);
                }
            return t;
        }

        // ---- dirt: layered noise, pebbles, twigs, optional moss ----

        static PixelTex Dirt(uint seed, bool mossy)
        {
            var t = new PixelTex(Size, Size);
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                {
                    float u = x / (float)Size, v = y / (float)Size;
                    float n = 0.6f * VN(u, v, 4, 4, seed) + 0.4f * VN(u, v, 16, 16, seed + 1);
                    int level = (int)(n * 5f);
                    float sp = F(Hash(x, y, seed + 2));
                    if (sp < 0.08f) level--; else if (sp > 0.95f) level++;
                    float h = 0.3f + 0.1f * level;
                    uint col = Pick(DirtRamp, level, (int)(VN(u, v, 3, 3, seed + 12) * 4f));
                    float m = 0.65f * VN(u, v, 3, 3, seed + 5) + 0.35f * VN(u, v, 12, 12, seed + 6);
                    float thr = mossy ? 0.5f : 0.74f;
                    if (m > thr)
                    {
                        int ml = (int)((m - thr) / (1f - thr) * 4.5f) + 1 + (sp > 0.9f ? 1 : 0) - (sp < 0.1f ? 1 : 0);
                        col = Pick(MossRamp, ml); h += 0.08f;
                    }
                    t.Set(x, y, col, h);
                }
            var rnd = new Rng(seed + 9);
            for (int i = 0; i < 16; i++)
            {
                int cx = rnd.Int(Size), cy = rnd.Int(Size), pw = 2 + rnd.Int(2), ph = 2;
                for (int j = 0; j < ph; j++)
                    for (int k = 0; k < pw; k++)
                    {
                        int lvl = 3 + (k == 0 && j == 0 ? 2 : 0) + (j == ph - 1 && k == pw - 1 ? -1 : 0);
                        t.Set(cx + k, cy + j, Pick(StoneRamp, lvl), 0.85f);
                    }
                t.Set(cx + pw, cy + ph, DirtRamp[0], 0.2f);
                t.Set(cx + 1, cy + ph, DirtRamp[0], 0.2f);
            }
            for (int i = 0; i < 4; i++)
            {
                int cx = rnd.Int(Size), cy = rnd.Int(Size), len = 5 + rnd.Int(3), dir = rnd.Int(2) == 0 ? 1 : -1;
                for (int k = 0; k < len; k++)
                    t.Set(cx + k, cy + (k * dir) / 3, k == len - 1 ? DirtRamp[4] : WoodRamp[2], 0.7f);
            }
            return t;
        }

        // ---- dead grass: dark dirt with straw, olive and dry blades ----

        static PixelTex DeadGrass(uint seed)
        {
            var t = new PixelTex(Size, Size);
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                {
                    float u = x / (float)Size, v = y / (float)Size;
                    float n = 0.55f * VN(u, v, 5, 5, seed) + 0.45f * VN(u, v, 18, 18, seed + 1);
                    int level = (int)(n * 3.2f);
                    t.Set(x, y, Pick(GrassRamp, level, (int)(VN(u, v, 3, 3, seed + 12) * 4f)), 0.15f + 0.05f * level);
                }
            var rnd = new Rng(seed + 4);
            for (int i = 0; i < 230; i++)
            {
                int bx = rnd.Int(Size), by = rnd.Int(Size), len = 3 + rnd.Int(3), bend = rnd.Int(3) - 1;
                int kind = rnd.Int(10);
                for (int k = 0; k < len; k++)
                {
                    int level = kind < 5 ? 3 + (k > len / 2 ? 1 : 0) : kind < 8 ? 2 : 1;
                    int xx = bx + (k > 1 ? bend * (k - 1) / 2 : 0);
                    t.Set(xx, by - k, Pick(GrassRamp, level, kind), 0.4f + 0.1f * k);
                }
                t.Set(bx, by + 1, GrassRamp[0], 0.1f);
            }
            for (int i = 0; i < 14; i++)
                t.Set(rnd.Int(Size), rnd.Int(Size), 0x7a4a34, 0.35f);
            return t;
        }

        // ---- brick: courses of blocks with mortar, chips, cracks, moss ----

        static PixelTex Brick(uint seed)
        {
            var t = new PixelTex(Size, Size);
            var rnd = new Rng(seed);
            const int bw = 16, bh = 8;
            for (int c = 0; c < Size / bh; c++)
                for (int b = 0; b < Size / bw; b++)
                {
                    int x0 = b * bw + (c % 2) * (bw / 2), y0 = c * bh;
                    Block(t, x0, y0, bw, bh, rnd, seed);
                }
            return t;
        }

        static void Block(PixelTex t, int x, int y0, int w, int h, Rng rnd, uint seed)
        {
            int baseLevel = 2 + rnd.Int(3) - (rnd.Int(4) == 0 ? 1 : 0), variant = rnd.Int(4);
            bool chip = rnd.Int(100) < 12;
            for (int ly = 0; ly < h; ly++)
                for (int lx = 0; lx < w; lx++)
                {
                    int px = x + lx, py = y0 + ly;
                    float nu = Mod(px, Size) / (float)Size, nv = Mod(py, Size) / (float)Size;
                    float mossN = VN(nu, nv, 3, 3, seed + 21);
                    if (lx == w - 1 || ly == h - 1)
                    {
                        t.Set(px, py, mossN > 0.72f ? MossRamp[0] : Mortar, 0f);
                        continue;
                    }
                    if (chip && lx >= w - 3 && ly <= 1 && lx - (w - 3) >= ly) { t.Set(px, py, Mortar, 0.1f); continue; }
                    int b = baseLevel;
                    if (ly == 0) b++;
                    else if (ly == h - 2) b--;
                    if (lx == 0) b++;
                    float n = VN(nu, nv, 5, 5, seed + 7);
                    if (n > 0.64f) b++; else if (n < 0.28f) b--;
                    float sp = F(Hash(px, py, seed + 3));
                    if (sp < 0.08f) b--; else if (sp > 0.94f) b++;
                    uint col = Pick(BrickRamp, b, variant);
                    float hh = (ly == 0 || lx == 0 ? 0.55f : 0.7f) + 0.05f * b;
                    if (mossN > 0.66f && ly >= h - 3)
                    {
                        col = Pick(MossRamp, 1 + (int)(sp * 4f)); hh += 0.05f;
                    }
                    t.Set(px, py, col, hh);
                }
            if (rnd.Int(100) < 22)
            {
                int cx = 2 + rnd.Int(Math.Max(1, w - 5)), cy = 0;
                for (int i = 0; i < h - 2; i++)
                {
                    t.Set(x + cx, y0 + cy, BrickRamp[0], 0.2f);
                    cx += rnd.Int(3) - 1; cy++;
                    if (cx < 1) cx = 1; if (cx > w - 3) cx = w - 3;
                }
            }
        }

        // ---- wood: horizontal planks with grain, nails, knots ----

        static PixelTex Wood(uint seed)
        {
            var t = new PixelTex(Size, Size);
            var rnd = new Rng(seed);
            const int ph = 8, pl = 32;
            for (int r = 0; r < Size / ph; r++)
            {
                int y0 = r * ph, off = rnd.Int(pl);
                for (int p = 0; p < 2; p++)
                {
                    int x0 = off + p * pl, baseLevel = 1 + rnd.Int(3), variant = rnd.Int(4);
                    for (int ly = 0; ly < ph; ly++)
                        for (int lx = 0; lx < pl; lx++)
                        {
                            int px = x0 + lx, py = y0 + ly;
                            if (ly == ph - 1 || lx == pl - 1) { t.Set(px, py, WoodRamp[0], 0f); continue; }
                            int b = baseLevel + (ly == 0 ? 1 : 0);
                            float g = VN(Mod(px, Size) / (float)Size, Mod(py, Size) / (float)Size, 3, 24, seed + 2);
                            if (g > 0.66f) b++; else if (g < 0.3f) b--;
                            float sp = F(Hash(px, py, seed + 3));
                            if (sp < 0.05f) b--;
                            t.Set(px, py, Pick(WoodRamp, b, variant), 0.5f + 0.06f * b);
                        }
                    t.Set(x0 + 2, y0 + 3, WoodRamp[0], 0.3f); t.Set(x0 + 1, y0 + 2, StoneRamp[4], 0.7f);
                    t.Set(x0 + pl - 4, y0 + 3, WoodRamp[0], 0.3f); t.Set(x0 + pl - 5, y0 + 2, StoneRamp[4], 0.7f);
                }
            }
            for (int i = 0; i < 2; i++)
            {
                int kx = 8 + rnd.Int(Size - 16), ky = 8 * rnd.Int(Size / 8) + 3;
                t.Set(kx, ky, WoodRamp[0], 0.3f); t.Set(kx + 1, ky, WoodRamp[0], 0.3f); t.Set(kx, ky + 1, WoodRamp[1], 0.4f); t.Set(kx + 1, ky + 1, WoodRamp[2], 0.5f);
            }
            return t;
        }

        // ---- coal: glowing embers in a dark crust (the shader makes it emissive) ----

        static PixelTex Coal(uint seed)
        {
            var t = new PixelTex(Size, Size);
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                {
                    float u = x / (float)Size, v = y / (float)Size;
                    float n = 0.5f * VN(u, v, 6, 6, seed) + 0.5f * VN(u, v, 14, 14, seed + 1);
                    int level = (int)(n * n * 7f);
                    t.Set(x, y, Pick(CoalRamp, level), 0.3f + 0.1f * level);
                }
            return t;
        }

        // ---- grass: dark soil under green blades, tufts and a few flowers ----

        static PixelTex GreenGrass(uint seed)
        {
            var t = new PixelTex(Size, Size);
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                {
                    float u = x / (float)Size, v = y / (float)Size;
                    float n = 0.55f * VN(u, v, 5, 5, seed) + 0.45f * VN(u, v, 18, 18, seed + 1);
                    int level = (int)(n * 3.4f);
                    t.Set(x, y, Pick(GreenRamp, level, (int)(VN(u, v, 3, 3, seed + 12) * 4f)), 0.15f + 0.05f * level);
                }
            var rnd = new Rng(seed + 4);
            for (int i = 0; i < 260; i++)
            {
                int bx = rnd.Int(Size), by = rnd.Int(Size), len = 3 + rnd.Int(3), bend = rnd.Int(3) - 1;
                int kind = rnd.Int(10);
                for (int k = 0; k < len; k++)
                {
                    int level = kind < 5 ? 3 + (k > len / 2 ? 1 : 0) : kind < 8 ? 2 : 4;
                    int xx = bx + (k > 1 ? bend * (k - 1) / 2 : 0);
                    t.Set(xx, by - k, Pick(GreenRamp, level, kind), 0.4f + 0.1f * k);
                }
                t.Set(bx, by + 1, GreenRamp[0], 0.1f);
            }
            uint[] flower = { 0xd2c25a, 0xc0628f, 0xd9d6c8 };
            for (int i = 0; i < 7; i++) t.Set(rnd.Int(Size), rnd.Int(Size), flower[i % 3], 0.6f);
            return t;
        }

        // ---- sand: ripples in the dune, pebbles and dark grains ----

        static PixelTex Sand(uint seed)
        {
            var t = new PixelTex(Size, Size);
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                {
                    float u = x / (float)Size, v = y / (float)Size;
                    float n = 0.6f * VN(u, v, 4, 4, seed) + 0.4f * VN(u, v, 16, 16, seed + 1);
                    float ripple = (float)Math.Sin((v * 8f + VN(u, v, 3, 3, seed + 3) * 1.1f) * 2.0 * Math.PI);
                    int level = (int)(n * 4.4f) + (ripple > 0.55f ? 1 : ripple < -0.7f ? -1 : 0);
                    float sp = F(Hash(x, y, seed + 2));
                    if (sp < 0.04f) level--; else if (sp > 0.97f) level++;
                    t.Set(x, y, Pick(SandRamp, level + 1, (int)(VN(u, v, 3, 3, seed + 12) * 4f)), 0.3f + 0.08f * level + (ripple > 0.55f ? 0.1f : 0f));
                }
            var rnd = new Rng(seed + 9);
            for (int i = 0; i < 12; i++)
            {
                int cx = rnd.Int(Size), cy = rnd.Int(Size);
                t.Set(cx, cy, Pick(StoneRamp, 4), 0.8f); t.Set(cx + 1, cy, Pick(StoneRamp, 3), 0.7f); t.Set(cx + 1, cy + 1, SandRamp[1], 0.2f);
            }
            return t;
        }

        // ---- snow: soft drifts, a blue shade in the hollows, sparkles ----

        static PixelTex Snow(uint seed)
        {
            var t = new PixelTex(Size, Size);
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                {
                    float u = x / (float)Size, v = y / (float)Size;
                    float n = 0.7f * VN(u, v, 3, 3, seed) + 0.3f * VN(u, v, 12, 12, seed + 1);
                    int level = 2 + (int)(n * 3.4f);
                    float sp = F(Hash(x, y, seed + 2));
                    if (sp > 0.985f) level = 5; else if (sp < 0.03f) level--;
                    t.Set(x, y, Pick(SnowRamp, level, (int)(VN(u, v, 2, 2, seed + 12) * 4f)), 0.4f + 0.07f * level);
                }
            var rnd = new Rng(seed + 5);
            for (int i = 0; i < 10; i++) t.Set(rnd.Int(Size), rnd.Int(Size), SnowRamp[1], 0.2f);
            return t;
        }

        // ---- water: dark blue with wave bands and short bright glints ----

        static PixelTex Water(uint seed)
        {
            var t = new PixelTex(Size, Size);
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                {
                    float u = x / (float)Size, v = y / (float)Size;
                    float warp = VN(u, v, 4, 4, seed) * 0.9f;
                    float w1 = (float)Math.Sin((v * 6f + warp) * 2.0 * Math.PI);
                    float w2 = (float)Math.Sin((u * 4f + v * 3f + VN(u, v, 5, 5, seed + 1) * 0.8f) * 2.0 * Math.PI);
                    float w = 0.65f * w1 + 0.35f * w2;
                    int level = 2 + (int)Math.Round(w * 1.4f);
                    t.Set(x, y, Pick(WaterRamp, level, (int)(VN(u, v, 3, 3, seed + 12) * 4f)), 0.3f + 0.1f * level);
                }
            var rnd = new Rng(seed + 7);
            for (int i = 0; i < 26; i++)
            {
                int cx = rnd.Int(Size), cy = rnd.Int(Size), len = 2 + rnd.Int(4);
                for (int k = 0; k < len; k++) t.Set(cx + k, cy, Pick(WaterRamp, k == 0 || k == len - 1 ? 4 : 5), 0.9f);
            }
            return t;
        }

        // ---- lava: a dark crust cracked by glowing veins (the shader makes it emissive) ----

        static PixelTex Lava(uint seed)
        {
            var t = new PixelTex(Size, Size);
            for (int y = 0; y < Size; y++)
                for (int x = 0; x < Size; x++)
                {
                    float u = x / (float)Size, v = y / (float)Size;
                    float n = 0.65f * VN(u, v, 4, 4, seed) + 0.35f * VN(u, v, 10, 10, seed + 1);
                    float d = Math.Abs(n - 0.5f) * 2f;
                    int level = d < 0.03f ? 5 : d < 0.07f ? 4 : d < 0.12f ? 3 : d < 0.3f ? 2 : 1;
                    float sp = F(Hash(x, y, seed + 2));
                    if (sp > 0.93f && level < 5) level++; else if (sp < 0.07f && level > 0) level--;
                    t.Set(x, y, Pick(CoalRamp, level), level >= 4 ? 0.15f : 0.4f + 0.1f * level);
                }
            return t;
        }

        // ---- a pixel flame: intensity in R, G and B, 12 x 20, top down ----

        /// <summary>A flame teardrop (12 x 20 texels, 4 intensity steps, intensity in the colour, alpha 255).</summary>
        public static PixelTex Flame(uint seed)
        {
            const int w = 12, h = 20;
            var t = new PixelTex(w, h);
            for (int y = 0; y < h; y++)
            {
                float u = y / (float)(h - 1);   // 0 top, 1 bottom
                float half = 5.4f * (float)Math.Pow(Math.Sin(Math.PI * Math.Pow(u, 1.6)), 0.9);
                float centre = 5.5f + 1.6f * (float)Math.Sin(u * 5.0 + seed) * (1f - u);
                for (int x = 0; x < w; x++)
                {
                    float d = Math.Abs(x + 0.5f - centre) / Math.Max(0.01f, half);
                    float v = 0f;
                    if (d < 1f)
                    {
                        v = 1f - d * 0.7f - (1f - u) * 0.25f;
                        v += (F(Hash(x, y, seed)) - 0.5f) * 0.18f;
                    }
                    int step = v <= 0.15f ? 0 : (int)Math.Min(4f, Math.Ceiling(v * 4f));
                    uint c = (uint)(step * 255 / 4);
                    t.Set(x, y, (c << 16) | (c << 8) | c, step / 4f);
                }
            }
            t.FlipY();
            return t;
        }
    }
}
