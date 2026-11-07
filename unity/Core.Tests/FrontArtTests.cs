// Checks of the front-art scene (Core/FrontArtTex.cs, Core/FrontArt.cs): the procedural textures (size, determinism, palette,
// hue shift), the normal map, the facing against the camera, the layout (what stands where) and the mesher (quads, windings).
// With the env CHAOS_FA_DUMP=DIR the textures are also written as PNG (a contact sheet, x4) to look at them.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class FrontArtTests
    {
        static int Distinct(PixelTex t)
        {
            var set = new HashSet<uint>();
            for (int y = 0; y < t.H; y++) for (int x = 0; x < t.W; x++) set.Add(t.Get(x, y));
            return set.Count;
        }

        static string FindPics()
        {
            string dir = AppContext.BaseDirectory;
            for (int i = 0; i < 10 && dir != null; i++, dir = Path.GetDirectoryName(dir))
            {
                foreach (var rel in new[] { "Client", "unity/Client" })
                {
                    string c = Path.Combine(dir, rel, "Assets", "Chaos", "Unity", "Resources", "FrontArt");
                    if (Directory.Exists(c)) return c;
                }
            }
            return null;
        }

        static bool Same(byte[] a, byte[] b) { return a.Length == b.Length && a.SequenceEqual(b); }

        static int R(uint c) { return (int)(c >> 16) & 255; }
        static int B(uint c) { return (int)c & 255; }

        public static void Run(Action<bool, string> check)
        {
            var kinds = new[] { FaTex.Flagstone, FaTex.Cobble, FaTex.Dirt, FaTex.MossDirt, FaTex.DeadGrass, FaTex.Brick, FaTex.Wood, FaTex.Coal };
            var texs = kinds.ToDictionary(k => k, k => FrontArtTex.Make(k, 1098));

            check(FrontArtTex.TexelsPerUnit == 16 && FrontArtTex.Size == 64 && Math.Abs(FrontArtTex.TileUnits - 4f) < 1e-6f, "front art: 16 texels per unit, 64 texel textures, 4 units a tile");
            check(kinds.All(k => texs[k].W == 64 && texs[k].H == 64 && texs[k].Rgba.Length == 64 * 64 * 4), "front art: every texture is 64 x 64 RGBA");
            check(kinds.All(k => { var t = texs[k]; for (int i = 3; i < t.Rgba.Length; i += 4) if (t.Rgba[i] != 255) return false; return true; }), "front art: textures are opaque");
            check(kinds.All(k => Same(FrontArtTex.Make(k, 1098).Rgba, texs[k].Rgba)), "front art: the same kind and seed give the same bytes");
            check(kinds.All(k => !Same(FrontArtTex.Make(k, 7).Rgba, texs[k].Rgba)), "front art: another seed gives another texture");
            check(kinds.All(k => { int n = Distinct(texs[k]); return n >= (k == FaTex.Coal ? 6 : 16) && n <= 120; }), "front art: a small hand-made palette per texture (16 to 120 colours): " + string.Join(",", kinds.Select(k => Distinct(texs[k]))));
            check(kinds.All(k => texs[k].Height.All(h => h >= 0f && h <= 1f)), "front art: heights are in 0..1");

            // hue shift: the darkest step leans blue-violet, the lightest warm (the coal ramp glows, it is exempt)
            foreach (var k in kinds.Where(k => k != FaTex.Coal))
            {
                var ramp = FrontArtTex.Ramp(k);
                check(B(ramp[0]) >= R(ramp[0]) && R(ramp[ramp.Length - 1]) > B(ramp[ramp.Length - 1]), "front art: " + k + " ramp is cool in the shadow, warm in the light");
                bool rising = true;
                for (int i = 1; i < ramp.Length; i++) rising &= (R(ramp[i]) + B(ramp[i])) > (R(ramp[i - 1]) + B(ramp[i - 1]));
                check(rising, "front art: " + k + " ramp gets lighter step by step");
            }

            // the stone textures have joints (height 0) and bevelled slabs; coal is bright (it is lit by itself)
            check(texs[FaTex.Flagstone].Height.Count(h => h == 0f) > 100 && texs[FaTex.Brick].Height.Count(h => h == 0f) > 150, "front art: flagstone and brick have joints");
            check(texs[FaTex.Cobble].Height.Count(h => h == 0f) > 100, "front art: cobble has joints between the stones");
            var coal = texs[FaTex.Coal];
            int bright = 0;
            for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++) if (R(coal.Get(x, y)) > 200) bright++;
            check(bright > 40, "front art: coal has glowing texels (" + bright + ")");

            // tileable: the seam between the right and the left edge is no harder than the inside
            foreach (var k in new[] { FaTex.Dirt, FaTex.DeadGrass, FaTex.Coal })
            {
                var t = texs[k];
                double seam = 0, inner = 0, seamV = 0, innerV = 0;
                for (int y = 0; y < 64; y++) seam += Math.Abs(R(t.Get(63, y)) - R(t.Get(0, y)));
                for (int x = 0; x < 63; x++) for (int y = 0; y < 64; y++) inner += Math.Abs(R(t.Get(x, y)) - R(t.Get(x + 1, y)));
                for (int x = 0; x < 64; x++) seamV += Math.Abs(R(t.Get(x, 63)) - R(t.Get(x, 0)));
                for (int y = 0; y < 63; y++) for (int x = 0; x < 64; x++) innerV += Math.Abs(R(t.Get(x, y)) - R(t.Get(x, y + 1)));
                inner /= 63; innerV /= 63;
                check(seam <= inner * 1.5 + 40 && seamV <= innerV * 1.5 + 40, "front art: " + k + " tiles without a seam (" + seam + " / " + seamV + " against " + inner.ToString("0") + " / " + innerV.ToString("0") + ")");
            }

            // normal map
            var flat = new PixelTex(8, 8);
            for (int y = 0; y < 8; y++) for (int x = 0; x < 8; x++) flat.Set(x, y, 0x808080, 0.5f);
            var nf = FrontArtTex.NormalMap(flat, 4f);
            check(nf[0] == 128 && nf[1] == 128 && nf[2] == 255 && nf[3] == 255, "front art: a flat height map gives the flat normal");
            var slope = new PixelTex(8, 8);
            for (int y = 0; y < 8; y++) for (int x = 0; x < 8; x++) slope.Set(x, y, 0x808080, x / 8f);
            var ns = FrontArtTex.NormalMap(slope, 4f);
            int mid = (3 * 8 + 3) * 4;
            check(ns[mid] < 128 && ns[mid + 2] > 128, "front art: a height rising to the right tilts the normal to the left");
            var nm = FrontArtTex.NormalMap(texs[FaTex.Brick], 3f);
            check(nm.Length == 64 * 64 * 4 && Enumerable.Range(0, 64 * 64).Any(i => nm[i * 4] != 128), "front art: the brick normal map has relief");

            // flame
            var fl = FrontArtTex.Flame(3);
            int lit = 0;
            for (int y = 0; y < fl.H; y++) for (int x = 0; x < fl.W; x++) if (R(fl.Get(x, y)) > 0) lit++;
            check(fl.W == 12 && fl.H == 20 && lit > 50 && lit < 200, "front art: the flame is a teardrop of " + lit + " texels");
            int topRow = 0, bottomRow = 0;
            for (int x = 0; x < fl.W; x++) { if (R(fl.Get(x, 0)) > 0) bottomRow++; if (R(fl.Get(x, fl.H - 1)) > 0) topRow++; }
            check(bottomRow <= 8 && topRow <= 3, "front art: the flame is narrow at the tip (top row " + topRow + ")");

            string dump = Environment.GetEnvironmentVariable("CHAOS_FA_DUMP");
            if (!string.IsNullOrEmpty(dump))
            {
                Directory.CreateDirectory(dump);
                const int sc = 4, cell = 64 * sc + 8;
                int cols = 4, rows = 2, w = cols * cell, h = rows * cell;
                var sheet = new byte[w * h * 4];
                for (int i = 0; i < sheet.Length; i += 4) { sheet[i] = 12; sheet[i + 1] = 10; sheet[i + 2] = 16; sheet[i + 3] = 255; }
                for (int n = 0; n < kinds.Length; n++)
                {
                    var t = texs[kinds[n]];
                    int ox = (n % cols) * cell + 4, oy = (n / cols) * cell + 4;
                    for (int y = 0; y < 64 * sc; y++)
                        for (int x = 0; x < 64 * sc; x++)
                        {
                            int sx = x / sc, sy = 63 - y / sc;   // the PNG writer wants the top row first
                            int si = (sy * 64 + sx) * 4, di = ((oy + y) * w + ox + x) * 4;
                            sheet[di] = t.Rgba[si]; sheet[di + 1] = t.Rgba[si + 1]; sheet[di + 2] = t.Rgba[si + 2]; sheet[di + 3] = 255;
                        }
                }
                Png.Write(Path.Combine(dump, "front_art_textures.png"), sheet, w, h);
                string pics = FindPics();
                if (pics != null) FrontArtPreview.Render(dump, pics);
            }

            // facing against the camera
            check(FrontArtFacing.Name(0, -1, 0) == "south" && FrontArtFacing.Name(0, 1, 0) == "north", "front art: facing the camera shows the south picture, away the north one");
            check(FrontArtFacing.Name(1, 0, 0) == "east" && FrontArtFacing.Name(-1, 0, 0) == "west", "front art: east is to the right of a camera that looks north");
            check(FrontArtFacing.Name(1, -1, 0) == "south-east" && FrontArtFacing.Name(-1, -1, 0) == "south-west" && FrontArtFacing.Name(1, 1, 0) == "north-east" && FrontArtFacing.Name(-1, 1, 0) == "north-west", "front art: the four diagonals");
            check(FrontArtFacing.Name(1, 0, 90) == "north" && FrontArtFacing.Name(-1, 0, 90) == "south", "front art: a camera that looks east sees the back of a character that faces east");
            check(FrontArtFacing.Name(0, 1, 90) == "west" && FrontArtFacing.Name(0, -1, 90) == "east", "front art: a turned camera turns the pictures");
            check(FrontArtFacing.Name(0, 0, 0) == "south", "front art: no facing shows the south picture");
            bool all8 = true;
            for (int i = 0; i < 8; i++)
            {
                double a = i * 45.0 * Math.PI / 180.0;
                all8 &= FrontArtFacing.Index((float)Math.Sin(a), (float)Math.Cos(a), 0) == i;
            }
            check(all8, "front art: every one of the 8 headings picks its own picture, clockwise from north");
            check(FrontArtFacing.Index(0.01f, -1f, 360f) == 4 && FrontArtFacing.Index(0.01f, -1f, -720f) == 4, "front art: a camera yaw outside 0..360 wraps");

            // layout
            var L = FrontArtLayout.Build();
            check(L.W == 20 && L.D == 16, "front art: the slab is 20 x 16 tiles");
            check(L.Actors.Count == 4 && string.Join(",", L.Actors.Select(a => a.Folder)) == "knight,mage,skeleton,ghoul", "front art: four characters");
            check(L.Actors.All(a => a.X > 0 && a.X < L.W && a.Z > 0 && a.Z < L.D && L.H[(int)a.X, (int)a.Z] <= 2 && !L.Masonry[(int)a.X, (int)a.Z]), "front art: the characters stand on open ground");
            check(L.Actors.All(a => Math.Abs(a.Y - L.GroundY(a.X, a.Z)) < 1e-4f), "front art: the characters stand on the ground");
            check(L.Actors.Where(a => !a.Monster).All(a => a.X < 10f) && L.Actors.Where(a => a.Monster).All(a => a.X > 10f), "front art: the heroes stand west of the brazier, the monsters east");
            var everyone = L.Actors.Concat(L.Extras).ToList();
            check(L.Extras.Count == 14 && L.Extras.All(a => a.Folder.StartsWith("pk_") && a.Units > 0.5f && a.Monster), "front art: fourteen pack monsters with their own picture size");
            check(L.Extras.All(a => a.X > 2.5f && a.X < 16.6f && a.Z > 2.5f && a.Z < 11.5f && L.H[(int)a.X, (int)a.Z] <= 0 && !L.Masonry[(int)a.X, (int)a.Z] && Math.Abs(a.Y - L.GroundY(a.X, a.Z)) < 1e-4f), "front art: the pack monsters stand on the open ground inside the ring");
            check(everyone.All(a => everyone.All(o => ReferenceEquals(a.Name, o.Name) || (a.X - o.X) * (a.X - o.X) + (a.Z - o.Z) * (a.Z - o.Z) > 0.8f * 0.8f)), "front art: no two figures stand closer than 0.8");
            check(L.Extras.All(a => !L.Boxes.Any(bx => bx.Tag != "rubble" && a.X > bx.X0 - 0.25f && a.X < bx.X1 + 0.25f && a.Z > bx.Z0 - 0.25f && a.Z < bx.Z1 + 0.25f)), "front art: no pack monster stands in a grave, pillar, brazier, crate or the sarcophagus");
            // patrols: open flat ground the whole way, nobody walks into anyone, the walk faces its way
            var walkers = L.Extras.Where(a => a.Walks).ToList();
            check(walkers.Count >= 10 && walkers.All(a => FrontArtWalk.Length(a) > 0.6f && FrontArtWalk.Length(a) < 2.0f), "front art: ten or more pack monsters patrol 0.6 to 2 units (" + walkers.Count + ")");
            bool pathOpen = true;
            string blocked = "";
            foreach (var a in walkers)
                for (int k = 0; k <= 20; k++)
                {
                    float x = a.X + (a.WalkX - a.X) * k / 20f, z = a.Z + (a.WalkZ - a.Z) * k / 20f;
                    bool ok = x > 2.5f && x < 16.6f && z > 2.5f && z < 11.5f && L.H[(int)x, (int)z] <= 0 && !L.Masonry[(int)x, (int)z]
                        && Math.Abs(L.GroundY(x, z) - a.Y) < 1e-4f
                        && !L.Boxes.Any(bx => bx.Tag != "rubble" && x > bx.X0 - 0.25f && x < bx.X1 + 0.25f && z > bx.Z0 - 0.25f && z < bx.Z1 + 0.25f);
                    if (!ok) { pathOpen = false; blocked = a.Name + " at " + x.ToString("0.00") + "," + z.ToString("0.00"); break; }
                }
            check(pathOpen, "front art: every patrol runs on flat open ground, no grave, pillar or crate in the way (" + blocked + ")");
            float closest = float.MaxValue;
            string pair = "";
            for (float t = 0f; t < 60f; t += 0.1f)
            {
                var at = new List<FrontArtWalk.Pose>();
                for (int i = 0; i < L.Extras.Count; i++) at.Add(FrontArtWalk.At(L.Extras[i], t, FrontArtWalk.Phase(i)));
                foreach (var b in L.Actors) at.Add(new FrontArtWalk.Pose { X = b.X, Z = b.Z });
                for (int i = 0; i < at.Count; i++)
                    for (int j = i + 1; j < at.Count; j++)
                    {
                        float d = (float)Math.Sqrt((at[i].X - at[j].X) * (at[i].X - at[j].X) + (at[i].Z - at[j].Z) * (at[i].Z - at[j].Z));
                        if (d < closest) { closest = d; pair = i + "/" + j + " at " + t.ToString("0.0"); }
                    }
            }
            check(closest > 0.7f, "front art: walking figures keep 0.7 apart (closest " + closest.ToString("0.00") + ", " + pair + ")");
            var w0 = walkers[0];
            var half = FrontArtWalk.At(w0, FrontArtWalk.Pause + 0.5f * FrontArtWalk.Length(w0) / FrontArtWalk.Speed, 0f);
            check(half.Walking && Math.Abs(half.X - (w0.X + w0.WalkX) / 2) < 1e-3f && Math.Abs(half.Z - (w0.Z + w0.WalkZ) / 2) < 1e-3f && half.FaceX * (w0.WalkX - w0.X) + half.FaceZ * (w0.WalkZ - w0.Z) > 0f, "front art walk: half way out, facing the far end");
            var home = FrontArtWalk.At(w0, 0.5f, 0f);
            check(!home.Walking && home.X == w0.X && home.FaceX == w0.FaceX, "front art walk: standing at home facing the scene");
            var far = FrontArtWalk.At(w0, FrontArtWalk.Pause + FrontArtWalk.Length(w0) / FrontArtWalk.Speed + 0.5f, 0f);
            check(!far.Walking && Math.Abs(far.X - w0.WalkX) < 1e-3f && far.FaceX * (w0.X - w0.WalkX) + far.FaceZ * (w0.Z - w0.WalkZ) > 0f, "front art walk: at the far end, looking back");
            var back = FrontArtWalk.At(w0, FrontArtWalk.Cycle(w0) - 0.01f, 0f);
            check(back.Walking && Math.Abs(back.X - w0.X) < 0.05f && Math.Abs(back.Z - w0.Z) < 0.05f, "front art walk: home again at the end of the cycle");
            var still = FrontArtWalk.At(L.Actors[0], 3f, 0f);
            check(!still.Walking && still.X == L.Actors[0].X, "front art walk: a figure without a patrol stands");
            var brazier = L.Lights.Where(l => l.Flame).ToList();
            check(brazier.Count >= 6 && brazier.All(l => l.R > l.B + 0.4f), "front art: warm flame lights at the braziers and torches (" + brazier.Count + ")");
            check(L.Lights.Any(l => !l.Flame && l.B > l.R), "front art: a cold light too");
            check(L.Lights.All(l => l.X > 0 && l.X < L.W && l.Z > 0 && l.Z < L.D && l.Y > 0 && l.Range > 2f), "front art: lights are inside the slab");
            var centre = L.Boxes.Where(b => b.Tag == "brazier").ToList();
            check(centre.Count >= 5 * 7 && L.Boxes.Count(b => b.Tag == "coal") >= 7, "front art: braziers have bowls and coals");
            check(L.Boxes.Count(b => b.Tag == "grave") >= 9 * 3 && L.Boxes.Count(b => b.Tag == "pillar") == 16 && L.Boxes.Any(b => b.Tag == "sarcophagus") && L.Boxes.Any(b => b.Tag == "gate" && b.Tex == FaTex.Wood), "front art: gravestones, four pillars, a sarcophagus and a gate");
            check(L.Boxes.All(b => b.X1 > b.X0 && b.Y1 > b.Y0 && b.Z1 > b.Z0), "front art: every box has a size");
            check(L.Boxes.All(b => b.Y0 > -0.01f && b.Y1 < 5f && b.X0 > 0f && b.X1 < L.W && b.Z0 > 0f && b.Z1 < L.D), "front art: every box is inside the slab");
            int maxH = 0;
            for (int z = 0; z < L.D; z++) for (int x = 0; x < L.W; x++) maxH = Math.Max(maxH, L.H[x, z]);
            check(maxH >= 6 && maxH <= 8, "front art: the temple wall is 3 to 4 units high (" + maxH + " levels)");
            check(Enumerable.Range(0, L.W).All(x => L.H[x, 0] == 0) && L.H[9, 0] == 0 && L.H[9, 2] == 0 && L.H[9, 11] == 2 && L.H[9, 10] == 1, "front art: the path is open to the gate, steps of 1 and 2 levels");
            check(L.H[9, 12] == 0 && L.H[9, 13] == 0 && L.H[7, 12] >= 6 && L.H[12, 12] >= 6, "front art: the gate passage is open between tall posts");
            int ring = 0;
            for (int z = 2; z <= 11; z++) { if (L.H[2, z] == 1 || L.H[2, z] == 2) ring++; if (L.H[17, z] == 1 || L.H[17, z] == 2) ring++; }
            check(ring >= 12 && ring < 20, "front art: a low wall ring with broken tiles (" + ring + " of 20)");
            var same = FrontArtLayout.Build();
            check(same.Boxes.Count == L.Boxes.Count && same.Boxes.Zip(L.Boxes, (a, b) => a.X0 == b.X0 && a.Y1 == b.Y1 && a.Tex == b.Tex).All(x => x), "front art: the layout is deterministic");
            var kinds2 = new HashSet<FaTex>();
            for (int z = 0; z < L.D; z++) for (int x = 0; x < L.W; x++) kinds2.Add(L.Top[x, z]);
            check(kinds2.Contains(FaTex.Flagstone) && kinds2.Contains(FaTex.Cobble) && kinds2.Contains(FaTex.MossDirt) && kinds2.Contains(FaTex.DeadGrass) && kinds2.Contains(FaTex.Dirt), "front art: the ground uses flagstone, cobble, dirt, mossy dirt and dead grass");
            check(L.Boxes.Select(b => b.Tex).Distinct().Count() >= 5, "front art: the props use five or more textures");

            // mesher
            var terrain = FrontArtMesher.Terrain(L);
            int tops = 0;
            for (int i = 0; i < terrain.Length; i++) tops += terrain[i].Quads;
            check(tops > L.W * L.D && terrain[(int)FaTex.Brick].Quads > 40, "front art: terrain quads: a top per tile plus sides (" + tops + ")");
            check(terrain.All(b => b.T.All(i => i >= 0 && i < b.Vertices) && b.T.Count % 6 == 0 && b.V.Count == b.N.Count && b.UV.Count / 2 == b.Vertices && b.C.Count / 4 == b.Vertices), "front art: terrain mesh arrays agree and indices are in range");
            check(WindingOk(terrain), "front art: every terrain triangle winds clockwise seen from its normal");
            // no side between equal heights: count the sides the grid needs
            int sides = 0;
            int[] dx = { -1, 1, 0, 0 }, dz = { 0, 0, -1, 1 };
            for (int z = 0; z < L.D; z++)
                for (int x = 0; x < L.W; x++)
                    for (int k = 0; k < 4; k++)
                    {
                        int nx = x + dx[k], nz = z + dz[k];
                        int nh = L.Inside(nx, nz) ? L.H[nx, nz] : FrontArtLayout.OuterLevels;
                        if (nh < L.H[x, z]) sides += L.Inside(nx, nz) ? 1 : (L.H[x, z] > 0 ? 2 : 1);
                    }
            check(tops == L.W * L.D + sides + 1, "front art: top quads, only the sides that show, and the outer ground (" + tops + " = " + (L.W * L.D) + " + " + sides + " + 1)");
            var boxes = FrontArtMesher.Boxes(L.Boxes);
            check(FrontArtMesher.TotalQuads(boxes) == L.Boxes.Count * 5, "front art: a box is five quads (the bottom is dropped)");
            check(WindingOk(boxes), "front art: every box triangle winds clockwise seen from its normal");
            check(boxes.All(b => b.N.Count == b.V.Count), "front art: box normals");
            bool unit = true;
            foreach (var b in boxes)
                for (int i = 0; i < b.N.Count; i += 3)
                {
                    float l = (float)Math.Sqrt(b.N[i] * b.N[i] + b.N[i + 1] * b.N[i + 1] + b.N[i + 2] * b.N[i + 2]);
                    unit &= Math.Abs(l - 1f) < 1e-4f;
                }
            check(unit, "front art: box normals are unit length, also on turned boxes");
        }

        // a triangle winds clockwise seen from its normal when (b - a) x (c - a) points along it (the engine is left-handed: the vertex order
        // a, d, c of a quad seen from the front has this cross product pointing at the viewer)
        static bool WindingOk(FaBucket[] buckets)
        {
            foreach (var b in buckets)
                for (int t = 0; t < b.T.Count; t += 3)
                {
                    int i0 = b.T[t] * 3, i1 = b.T[t + 1] * 3, i2 = b.T[t + 2] * 3;
                    float ux = b.V[i1] - b.V[i0], uy = b.V[i1 + 1] - b.V[i0 + 1], uz = b.V[i1 + 2] - b.V[i0 + 2];
                    float vx = b.V[i2] - b.V[i0], vy = b.V[i2 + 1] - b.V[i0 + 1], vz = b.V[i2 + 2] - b.V[i0 + 2];
                    float cx = uy * vz - uz * vy, cy = uz * vx - ux * vz, cz = ux * vy - uy * vx;
                    float d = cx * b.N[i0] + cy * b.N[i0 + 1] + cz * b.N[i0 + 2];
                    if (d <= 0f) return false;
                }
            return true;
        }
    }
}
