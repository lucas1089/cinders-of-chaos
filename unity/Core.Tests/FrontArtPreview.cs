// A small CPU preview of the front-art scene, to check the layout and the camera without the engine (env CHAOS_FA_DUMP=DIR writes
// front_art_preview.png and front_art_preview_close.png). Not the real look: no shadows, no post effects, one flat light model.
// It draws the Core meshes (terrain and boxes) with the generated textures, the characters as upright billboards from the committed
// pictures, and the flames as bright quads, with the same camera maths as Unity/FrontArtScene.cs.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;

namespace Chaos.Core.Tests
{
    static class FrontArtPreview
    {
        const int W = 1200, H = 880;

        static Vec3 Cross(Vec3 a, Vec3 b) { return new Vec3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X); }
        static Vec3 Norm(Vec3 a) { float l = a.Length; return new Vec3(a.X / l, a.Y / l, a.Z / l); }

        sealed class Pic { public int W, H; public byte[] Rgba; }

        static Pic LoadPng(string path)
        {
            var d = File.ReadAllBytes(path);
            int pos = 8, w = 0, h = 0;
            var idat = new MemoryStream();
            while (pos < d.Length)
            {
                int len = (d[pos] << 24) | (d[pos + 1] << 16) | (d[pos + 2] << 8) | d[pos + 3];
                string type = System.Text.Encoding.ASCII.GetString(d, pos + 4, 4);
                if (type == "IHDR") { w = (d[pos + 8] << 24) | (d[pos + 9] << 16) | (d[pos + 10] << 8) | d[pos + 11]; h = (d[pos + 12] << 24) | (d[pos + 13] << 16) | (d[pos + 14] << 8) | d[pos + 15]; }
                if (type == "IDAT") idat.Write(d, pos + 8, len);
                pos += 12 + len;
            }
            idat.Position = 0;
            var raw = new MemoryStream();
            using (var z = new ZLibStream(idat, CompressionMode.Decompress)) z.CopyTo(raw);
            var buf = raw.ToArray();
            int st = w * 4;
            var o = new byte[h * st];
            for (int y = 0; y < h; y++)
            {
                int f = buf[y * (st + 1)];
                for (int x = 0; x < st; x++)
                {
                    int a = x >= 4 ? o[y * st + x - 4] : 0, b = y > 0 ? o[(y - 1) * st + x] : 0, c = x >= 4 && y > 0 ? o[(y - 1) * st + x - 4] : 0;
                    int v = buf[y * (st + 1) + 1 + x], r;
                    if (f == 0) r = v; else if (f == 1) r = v + a; else if (f == 2) r = v + b; else if (f == 3) r = v + (a + b) / 2;
                    else { int p = a + b - c, pa = Math.Abs(p - a), pb = Math.Abs(p - b), pc = Math.Abs(p - c); r = v + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c); }
                    o[y * st + x] = (byte)r;
                }
            }
            return new Pic { W = w, H = h, Rgba = o };
        }

        public static void Render(string dir, string picsDir)
        {
            var L = FrontArtLayout.Build();
            var tex = new PixelTex[(int)FaTex.Count];
            for (int i = 0; i < tex.Length; i++) tex[i] = FrontArtTex.Make((FaTex)i, 1098);
            var buckets = new[] { FrontArtMesher.Terrain(L), FrontArtMesher.Boxes(L.Boxes) };
            Shot(L, tex, buckets, picsDir, Path.Combine(dir, "front_art_preview.png"), new Vec3(L.W / 2f, 1.0f, L.D / 2f - 1.7f), 32f);
            float cx = 0, cy = 0, cz = 0;
            foreach (var a in L.Actors) { cx += a.X; cy += a.Y + 0.95f; cz += a.Z; }
            Shot(L, tex, buckets, picsDir, Path.Combine(dir, "front_art_preview_close.png"), new Vec3(cx / 4, cy / 4, cz / 4), 11f);
        }

        static void Shot(FrontArtLayout L, PixelTex[] tex, FaBucket[][] buckets, string picsDir, string path, Vec3 target, float dist)
        {
            float yaw = 0f;
            var fwd = FrontArtCamera.Forward(yaw, FrontArtCamera.Pitch);
            var pos = FrontArtCamera.Position(target, dist, yaw, FrontArtCamera.Pitch);
            var right = Norm(Cross(new Vec3(0, 1, 0), fwd));
            var up = Cross(fwd, right);
            float tanH = (float)Math.Tan(FrontArtCamera.Fov * Math.PI / 360.0), aspect = W / (float)H;
            var px = new float[W * H * 3];
            var zb = new float[W * H];
            for (int i = 0; i < zb.Length; i++) { zb[i] = float.MaxValue; px[i * 3] = 0.07f; px[i * 3 + 1] = 0.07f; px[i * 3 + 2] = 0.13f; }
            var moon = FrontArtCamera.MoonForward();
            Func<Vec3, float[]> proj = p =>
            {
                var d = p - pos;
                float z = Vec3.Dot(d, fwd), x = Vec3.Dot(d, right), y = Vec3.Dot(d, up);
                return new[] { (x / (z * tanH * aspect) * 0.5f + 0.5f) * W, (1f - (y / (z * tanH) * 0.5f + 0.5f)) * H, z };
            };
            Func<float, float, float, float, float, float, float[]> light = (wx, wy, wz, nx, ny, nz) =>
            {
                float lr = 0.22f, lg = 0.24f, lb = 0.38f;
                float dm = Math.Max(0f, -(nx * moon.X + ny * moon.Y + nz * moon.Z));
                lr += 0.55f * 1.15f * dm; lg += 0.67f * 1.15f * dm; lb += 1.0f * 1.15f * dm;
                foreach (var l in L.Lights)
                {
                    float dx = l.X - wx, dy = l.Y - wy, dz = l.Z - wz;
                    float d2 = dx * dx + dy * dy + dz * dz, d = (float)Math.Sqrt(d2);
                    float nl = Math.Max(0f, (nx * dx + ny * dy + nz * dz) / Math.Max(0.001f, d));
                    float att = Math.Max(0f, 1f - d2 / (l.Range * l.Range)) / (1f + 25f * d2 / (l.Range * l.Range));
                    float k = nl * att * l.Intensity;
                    lr += l.R * k; lg += l.G * k; lb += l.B * k;
                }
                return new[] { lr, lg, lb };
            };
            for (int set = 0; set < buckets.Length; set++)
                for (int k = 0; k < buckets[set].Length; k++)
                {
                    var b = buckets[set][k];
                    var t = tex[k];
                    for (int tri = 0; tri < b.T.Count; tri += 3)
                    {
                        var v = new Vec3[3]; var sp = new float[3][]; var uv = new float[3][]; var col = new float[3][];
                        bool behind = false;
                        for (int c = 0; c < 3; c++)
                        {
                            int i = b.T[tri + c];
                            v[c] = new Vec3(b.V[i * 3], b.V[i * 3 + 1], b.V[i * 3 + 2]);
                            sp[c] = proj(v[c]);
                            if (sp[c][2] < 1f) behind = true;
                            uv[c] = new[] { b.UV[i * 2], b.UV[i * 2 + 1] };
                            col[c] = new[] { b.C[i * 4], b.C[i * 4 + 1], b.C[i * 4 + 2] };
                        }
                        if (behind) continue;
                        float nx = b.N[b.T[tri] * 3], ny = b.N[b.T[tri] * 3 + 1], nz = b.N[b.T[tri] * 3 + 2];
                        float area = (sp[1][0] - sp[0][0]) * (sp[2][1] - sp[0][1]) - (sp[2][0] - sp[0][0]) * (sp[1][1] - sp[0][1]);
                        if (Math.Abs(area) < 1e-6f) continue;
                        int minx = Math.Max(0, (int)Math.Floor(Math.Min(sp[0][0], Math.Min(sp[1][0], sp[2][0])))), maxx = Math.Min(W - 1, (int)Math.Ceiling(Math.Max(sp[0][0], Math.Max(sp[1][0], sp[2][0]))));
                        int miny = Math.Max(0, (int)Math.Floor(Math.Min(sp[0][1], Math.Min(sp[1][1], sp[2][1])))), maxy = Math.Min(H - 1, (int)Math.Ceiling(Math.Max(sp[0][1], Math.Max(sp[1][1], sp[2][1]))));
                        for (int y = miny; y <= maxy; y++)
                            for (int x = minx; x <= maxx; x++)
                            {
                                float fx = x + 0.5f, fy = y + 0.5f;
                                float w0 = ((sp[1][0] - fx) * (sp[2][1] - fy) - (sp[2][0] - fx) * (sp[1][1] - fy)) / area;
                                float w1 = ((sp[2][0] - fx) * (sp[0][1] - fy) - (sp[0][0] - fx) * (sp[2][1] - fy)) / area;
                                float w2 = 1f - w0 - w1;
                                if (w0 < 0 || w1 < 0 || w2 < 0) continue;
                                // perspective correct weights
                                float i0 = w0 / sp[0][2], i1 = w1 / sp[1][2], i2 = w2 / sp[2][2], s = i0 + i1 + i2;
                                float z = 1f / s;
                                int zi = y * W + x;
                                if (z >= zb[zi]) continue;
                                float p0 = i0 / s, p1 = i1 / s, p2 = i2 / s;
                                float u = uv[0][0] * p0 + uv[1][0] * p1 + uv[2][0] * p2, vv = uv[0][1] * p0 + uv[1][1] * p1 + uv[2][1] * p2;
                                int tx = ((int)Math.Floor(u * 64f) % 64 + 64) % 64, ty = ((int)Math.Floor(vv * 64f) % 64 + 64) % 64;
                                int ti = (ty * 64 + tx) * 4;
                                float wx = v[0].X * p0 + v[1].X * p1 + v[2].X * p2, wy = v[0].Y * p0 + v[1].Y * p1 + v[2].Y * p2, wz = v[0].Z * p0 + v[1].Z * p1 + v[2].Z * p2;
                                var lt = light(wx, wy, wz, nx, ny, nz);
                                float cr = col[0][0] * p0 + col[1][0] * p1 + col[2][0] * p2;
                                float cg = col[0][1] * p0 + col[1][1] * p1 + col[2][1] * p2;
                                float cb = col[0][2] * p0 + col[1][2] * p1 + col[2][2] * p2;
                                float em = k == (int)FaTex.Coal ? 1.7f : 0f;
                                zb[zi] = z;
                                px[zi * 3] = t.Rgba[ti] / 255f * cr * lt[0] + t.Rgba[ti] / 255f * em;
                                px[zi * 3 + 1] = t.Rgba[ti + 1] / 255f * cg * lt[1] + t.Rgba[ti + 1] / 255f * em;
                                px[zi * 3 + 2] = t.Rgba[ti + 2] / 255f * cb * lt[2] + t.Rgba[ti + 2] / 255f * em;
                            }
                    }
                }
            // characters and the pack monsters (when opened): upright quads of Units (1.5 by default) facing the camera
            foreach (var a in System.Linq.Enumerable.Concat(L.Actors, L.Extras))
            {
                string dirName = FrontArtFacing.Name(a.FaceX, a.FaceZ, yaw);
                string file = Path.Combine(picsDir, a.Folder, dirName + ".png");
                if (!File.Exists(file)) continue;
                var pic = LoadPng(file);
                var foot = new Vec3(a.X, a.Y, a.Z);
                var lt = light(a.X, a.Y + 1f, a.Z, 0f, 0.8f, -0.6f);
                float units = a.Units > 0f ? a.Units : 1.5f, texel = units / pic.W;
                for (int sy = 0; sy < pic.H * 2; sy++)
                    for (int sx = 0; sx < pic.W * 2; sx++)
                    {
                        int tx = sx / 2, ty = pic.H - 1 - sy / 2;
                        int ti = (ty * pic.W + tx) * 4;
                        if (pic.Rgba[ti + 3] < 128) continue;
                        var wp = foot + right * ((sx + 0.5f) * texel / 2f - units / 2f) + new Vec3(0, (sy + 0.5f) * texel / 2f, 0);
                        var s = proj(wp);
                        int x0 = (int)s[0], y0 = (int)s[1];
                        float size = W / (2f * s[2] * tanH * aspect) * texel / 2f + 1f;
                        for (int yy = 0; yy < size; yy++)
                            for (int xx = 0; xx < size; xx++)
                            {
                                int x = x0 + xx, y = y0 - yy;
                                if (x < 0 || y < 0 || x >= W || y >= H) continue;
                                int zi = y * W + x;
                                if (s[2] - 0.05f >= zb[zi]) continue;
                                zb[zi] = s[2] - 0.05f;
                                px[zi * 3] = pic.Rgba[ti] / 255f * Math.Min(1.4f, lt[0] + 0.15f);
                                px[zi * 3 + 1] = pic.Rgba[ti + 1] / 255f * Math.Min(1.4f, lt[1] + 0.15f);
                                px[zi * 3 + 2] = pic.Rgba[ti + 2] / 255f * Math.Min(1.4f, lt[2] + 0.15f);
                            }
                    }
            }
            // flames as bright quads
            foreach (var l in L.Lights)
            {
                if (!l.Flame) continue;
                for (int i = 0; i < 12; i++)
                {
                    var s = proj(new Vec3(l.FlameX, l.FlameY + i * 0.07f * l.FlameSize, l.FlameZ));
                    int rad = (int)Math.Max(1, 7f * l.FlameSize * (1f - i / 14f) * 32f / s[2]);
                    for (int yy = -rad; yy <= rad; yy++)
                        for (int xx = -rad / 2; xx <= rad / 2; xx++)
                        {
                            int x = (int)s[0] + xx, y = (int)s[1] - yy * 2;
                            if (x < 0 || y < 0 || x >= W || y >= H) continue;
                            int zi = y * W + x;
                            px[zi * 3] = 2.2f; px[zi * 3 + 1] = i < 5 ? 1.2f : 0.7f; px[zi * 3 + 2] = i < 5 ? 0.45f : 0.2f;
                        }
                }
            }
            var o = new byte[W * H * 4];
            for (int i = 0; i < W * H; i++)
                for (int c = 0; c < 3; c++)
                {
                    float v = px[i * 3 + c] * 1.2f;
                    v = v / (1f + v) * 1.6f;
                    o[i * 4 + c] = (byte)Math.Max(0, Math.Min(255, (int)(v * 255f)));
                    o[i * 4 + 3] = 255;
                }
            Png.Write(path, o, W, H);
        }
    }
}
