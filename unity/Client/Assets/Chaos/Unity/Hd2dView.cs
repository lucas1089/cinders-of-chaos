// The HD-2D view (O432): the world's sprites placed in a 3D scene. The layout (what stands, what lies, where, which lights)
// is Core/Hd2d.cs; this file turns it into two dynamic meshes over the sprite atlas (flat floor quads that receive shadows,
// upright billboards that cast them), a tilted perspective camera that keeps the 15 x 11 tile view, Unity point lights
// (nearest first, capped) and a warm dusk ambient. Bloom, depth of field and fog are Hd2dPost. Built-in render pipeline.
// Only the player's floor is drawn. Quality: mobile and the "chaos.hd2d.low" pref turn shadows off and cap the lights.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace Chaos.Client
{
    public sealed class Hd2dView : MonoBehaviour
    {
        public World World;
        public SpriteAtlas Atlas;
        public Func<double> Clock;
        public Camera Cam;
        public float Pitch = Hd2dCamera.DefaultPitch, Fov = Hd2dCamera.DefaultFov;

        /// <summary>Where a creature is on screen: a name point above it and the corners of its sprite (world space).</summary>
        public struct Label { public Creature C; public Vector3 Head, BottomLeft, TopRight; }
        public readonly List<Label> Labels = new List<Label>();

        /// <summary>The sprites are drawn straight up (the synthetic demo art), not in the classic slant: no shear.</summary>
        public bool StraightArt;
        /// <summary>Pieces this returns true for are not drawn as sprites (a 3D model takes their place: Hd2dRuins3d). Lights still come from them.</summary>
        public Func<Hd2dPiece, bool> Skip;
        /// <summary>Creatures this returns true for are not drawn as sprites (a 3D character takes their place: Hd2dChars3d). Their name label stays.</summary>
        public Func<Creature, bool> SkipCreature;
        /// <summary>Phase 8 track C: the outfit shader, hit flash and outline of a creature (null: plain), and whether water and lava grounds shimmer (Hd2dSprite.shader fx modes).</summary>
        public Func<Creature, MapFxLook> CreatureFx;
        public bool LiquidFx = true;
        /// <summary>Phase 9 track D: the rarity outline of items on the map is drawn as a silhouette behind the sprite (Hd2dSprite.shader FX_ITEMGLOW) and a Divine item in metal
        /// (FX_METAL). ItemGlowReal says whether the shader is there: the ground ring of ChaosApp.DrawItemRings stands in when it is not.</summary>
        public bool ItemOutlines = true;
        public bool ItemGlowReal => ItemOutlines && fxShaderOk;
        /// <summary>The spell lights now (tiles to world positions relative to the origin tile): they go in front of the scene's own lights, within MaxLights.</summary>
        public Func<Pos, List<Hd2dLight>> SpellLights;
        int fxMode; float fxStrength = 1f;
        bool fxShaderOk;   // the material is Chaos/Hd2dSprite, which reads the fx modes
        Color32 fxTint = new Color32(255, 255, 255, 255);
        Vector3 fxOff;
        /// <summary>The draw size of a monster (phase 8 track A, game_monsterbar): its quads are scaled about its feet. Null: 1.</summary>
        public Func<Creature, float> CreatureScale;
        float curScale = 1f;
        Vector3 curPivot;
        public static bool LowQuality => Application.isMobilePlatform || PlayerPrefs.GetInt("chaos.hd2d.low", 0) == 1;
        public int MaxLights => LowQuality ? 4 : 8;
        public int MaxShadowLights => LowQuality ? 0 : 2;

        sealed class Batch
        {
            public readonly Mesh Mesh = new Mesh { name = "chaos-hd2d" };
            public readonly List<Vector3> V = new List<Vector3>(), N = new List<Vector3>();
            public readonly List<Vector2> UV = new List<Vector2>();
            public readonly List<Vector2> UV2 = new List<Vector2>();   // phase 8 track C: x the FxMode of the quad, y its strength (Hd2dSprite.shader uv2_MainTex)
            public readonly List<Color32> Col = new List<Color32>();   // the colour of an outline silhouette or of an outfit shader family
            public readonly List<int> T = new List<int>();
            public MeshRenderer Renderer;
            public void Clear() { V.Clear(); N.Clear(); UV.Clear(); UV2.Clear(); Col.Clear(); T.Clear(); }
            public void Upload()
            {
                Mesh.Clear();
                Mesh.SetVertices(V);
                Mesh.SetNormals(N);
                Mesh.SetUVs(0, UV);
                Mesh.SetUVs(1, UV2);
                Mesh.SetColors(Col);
                Mesh.SetTriangles(T, 0);
            }
        }

        Batch flat, upright;
        Hd2dGround ground;   // contact shadows and wall ambient occlusion (Hd2dGround.cs)
        Material material;
        readonly List<Light> lights = new List<Light>();
        readonly Vector3 upNormal = Vector3.up;
        Vector3 camNormal = new Vector3(0, 0.64f, -0.77f);
        bool saved;
        AmbientMode oldMode; Color oldAmbient; ShadowQuality oldShadows; int oldPixelLights; float oldShadowDistance;
        public Hd2dCameraPose LastPose;
        /// <summary>Dust, embers and flame halos (Hd2dParticles); null until the view is enabled.</summary>
        public Hd2dParticles Particles { get; private set; }

        Batch NewBatch(string name, bool casts)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            var b = new Batch();
            b.Mesh.indexFormat = IndexFormat.UInt32;
            b.Mesh.MarkDynamic();
            go.AddComponent<MeshFilter>().sharedMesh = b.Mesh;
            b.Renderer = go.AddComponent<MeshRenderer>();
            b.Renderer.sharedMaterial = material;
            b.Renderer.shadowCastingMode = casts ? ShadowCastingMode.TwoSided : ShadowCastingMode.Off;
            b.Renderer.receiveShadows = true;
            return b;
        }

        void Awake()
        {
            var shader = Resources.Load<Shader>("Hd2dSprite");
            if (shader == null) shader = Shader.Find("Legacy Shaders/Transparent/Cutout/Diffuse");
            if (shader == null) shader = Shader.Find("Sprites/Default");
            material = new Material(shader) { name = "chaos-hd2d" };
            fxShaderOk = shader != null && shader.name == Hd2dPost.SpriteShaderName;
            material.SetFloat("_Cutoff", 0.5f);
            flat = NewBatch("floor", false);
            upright = NewBatch("upright", true);
            ground = new Hd2dGround(transform);
        }

        void OnEnable()
        {
            if (!saved)
            {
                oldMode = RenderSettings.ambientMode; oldAmbient = RenderSettings.ambientLight;
                oldShadows = QualitySettings.shadows; oldPixelLights = QualitySettings.pixelLightCount; oldShadowDistance = QualitySettings.shadowDistance;
                saved = true;
            }
            QualitySettings.shadows = LowQuality ? ShadowQuality.Disable : ShadowQuality.All;
            QualitySettings.pixelLightCount = Math.Max(oldPixelLights, MaxLights);
            QualitySettings.shadowDistance = 60f;
            RenderSettings.ambientMode = AmbientMode.Flat;
            if (flat != null) { flat.Renderer.enabled = true; upright.Renderer.enabled = true; ground.Enabled = true; }
            if (Cam != null) Hd2dPost.Attach(Cam, LowQuality);
            if (Particles == null) { var pg = new GameObject("particles"); pg.transform.SetParent(transform, false); Particles = pg.AddComponent<Hd2dParticles>(); }
            Particles.Cam = Cam;
            Particles.enabled = true;
        }

        void OnDisable()
        {
            if (saved)
            {
                RenderSettings.ambientMode = oldMode; RenderSettings.ambientLight = oldAmbient;
                QualitySettings.shadows = oldShadows; QualitySettings.pixelLightCount = oldPixelLights; QualitySettings.shadowDistance = oldShadowDistance;
                saved = false;
            }
            if (flat != null) { flat.Renderer.enabled = false; upright.Renderer.enabled = false; ground.Enabled = false; }
            foreach (var l in lights) if (l != null) l.enabled = false;
            if (Cam != null) Hd2dPost.Detach(Cam);
            if (Particles != null) Particles.enabled = false;
        }

        // the measured lean profile of each thing's art (Hd2d.Lean), once per type
        readonly Dictionary<(ThingType, bool), float[]> leans = new Dictionary<(ThingType, bool), float[]>();

        float[] LeanOf(ThingType t, bool outfit)
        {
            if (leans.TryGetValue((t, outfit), out var v)) return v;
            v = Hd2d.Lean(t, outfit, id => id == 0 ? null : Atlas.Raw(id));
            leans[(t, outfit)] = v;
            return v;
        }

        double Now => Clock != null ? Clock() : Time.realtimeSinceStartupAsDouble * 1000;

        float[] Drawn(Creature c, out float progress)
        {
            WalkMath.Drawn(c, Now, out float x, out float y, out progress);   // Core/SmoothWalk.cs
            return new[] { x, y };
        }

        float[] DrawnPos(Creature c) { return Drawn(c, out float _); }

        /// <summary>The tile position a creature is drawn at now, fractional while it walks (x east, y south).</summary>
        public Vector2 DrawnTile(Creature c) { var d = DrawnPos(c); return new Vector2(d[0], d[1]); }

        void LateUpdate() { Refresh(); }

        /// <summary>Builds the mesh for the current world now (LateUpdate, or the screenshot mode without a frame).</summary>
        public void Refresh()
        {
            if (World == null || Atlas == null || Cam == null) return;
            int gen = Atlas.Generation;
            Build();
            if (Atlas.Generation != gen) Build();   // the atlas filled up and was cleared while building
            Atlas.Upload();
            material.mainTexture = Atlas.Texture;
        }

        void Build()
        {
            flat.Clear(); upright.Clear(); Labels.Clear();
            Pos origin = World.Center;
            var player = World.Player;
            float[] pd = player != null ? DrawnPos(player) : new float[] { origin.X, origin.Y };
            var pieces = Hd2d.Layout(World, origin, Pitch, DrawnPos, !StraightArt, LeanOf);
            double p = Pitch * Math.PI / 180.0;
            camNormal = new Vector3(0f, (float)Math.Sin(p), -(float)Math.Cos(p));
            foreach (var piece in pieces)
            {
                if (piece.Creature != null && SkipCreature != null && SkipCreature(piece.Creature)) { AddLabel(piece); continue; }
                if (Skip != null && Skip(piece)) continue;
                if (piece.Creature != null) AddCreature(piece);
                else AddItem(piece);
            }
            flat.Upload(); upright.Upload();
            ground.Build(pieces);

            var pose = Hd2dCamera.ForTile(pd[0], pd[1], origin, Cam.aspect, Pitch, Fov, ChaosApp.ViewTilesW, ChaosApp.ViewTilesH);
            LastPose = pose;
            Cam.orthographic = false;
            Cam.fieldOfView = Fov;
            Cam.nearClipPlane = 0.5f;
            Cam.farClipPlane = 260f;
            Cam.rect = new Rect(0f, 0f, 1f, 1f);
            Cam.transform.SetPositionAndRotation(new Vector3(pose.Position.X, pose.Position.Y, pose.Position.Z),
                                                 Quaternion.LookRotation(new Vector3(pose.Forward.X, pose.Forward.Y, pose.Forward.Z), Vector3.up));

            // world light: darker and cooler underground and at night; 255 is full daylight
            float day = Mathf.Clamp01(World.WorldLight / 255f);
            // never pitch black: the HD-2D look keeps a warm dusk under the torches
            RenderSettings.ambientLight = Color.Lerp(new Color(0.20f, 0.18f, 0.24f), new Color(0.50f, 0.48f, 0.52f), day);
            var lightList = Hd2d.Lights(pieces, pose.Target, MaxLights);
            var spell = SpellLights != null ? SpellLights(origin) : null;
            if (spell != null && spell.Count > 0)
            {
                lightList.InsertRange(0, spell);
                if (lightList.Count > MaxLights) lightList.RemoveRange(MaxLights, lightList.Count - MaxLights);
            }
            SetLights(lightList);
            if (Particles != null) Particles.SetLights(lightList, pose.Target);
            // light shafts toward the strongest lights (Hd2dPost)
            shaftPos.Clear(); shaftCol.Clear();
            foreach (var d in lightList) { shaftPos.Add(new Vector3(d.Position.X, d.Position.Y, d.Position.Z)); shaftCol.Add(new Color(d.R, d.G, d.B) * d.Intensity); }
            Hd2dEffect.SetLightsWorld(Cam, shaftPos, shaftCol);
        }

        readonly List<Vector3> shaftPos = new List<Vector3>();
        readonly List<Color> shaftCol = new List<Color>();

        void SetLights(List<Hd2dLight> list)
        {
            while (lights.Count < list.Count)
            {
                var go = new GameObject("light " + lights.Count);
                go.transform.SetParent(transform, false);
                var l = go.AddComponent<Light>();
                l.type = LightType.Point;
                lights.Add(l);
            }
            for (int i = 0; i < lights.Count; i++)
            {
                var l = lights[i];
                if (i >= list.Count) { l.enabled = false; continue; }
                var d = list[i];
                l.enabled = true;
                l.transform.position = new Vector3(d.Position.X, d.Position.Y, d.Position.Z);
                l.color = new Color(d.R, d.G, d.B);
                l.range = d.Range * 1.8f;
                l.intensity = d.Intensity * 2.0f;
                if (Hd2d.IsFlame(d))   // torch flicker (Hd2d.Flicker): intensity and a tiny position jitter
                {
                    float ft = (float)(Now / 1000.0);
                    l.intensity *= Hd2d.Flicker(ft, i + 1);
                    l.transform.position += new Vector3(Hd2d.Flicker(ft * 1.7f, i + 11) - 1f, Hd2d.Flicker(ft * 1.3f, i + 21) - 1f, Hd2d.Flicker(ft * 1.9f, i + 31) - 1f) * 0.25f;
                }
                l.shadows = i < MaxShadowLights ? LightShadows.Soft : LightShadows.None;
                l.shadowStrength = 0.85f;
                l.shadowBias = 0.03f;
                l.shadowNearPlane = 0.1f;
                l.renderMode = LightRenderMode.ForcePixel;
            }
        }

        // ---- sprite choice: the same rules as MapView.DrawItem / DrawCreature ---------------------------------------

        int Phase(FrameGroup g, long salt)
        {
            if (g.Phases <= 1) return 0;
            int d = g.MinDuration != null && g.MinDuration[0] > 0 ? g.MinDuration[0] : 300;
            return (int)(((long)Now / d + salt) % g.Phases);
        }

        static int Mod(int a, int n) { int m = a % n; return m < 0 ? m + n : m; }

        void AddItem(Hd2dPiece piece)
        {
            var it = piece.Item;
            var t = it.Type;
            var g = t.Idle;
            Pos pos = piece.Tile;
            int px, py, pz;
            if (t.Stackable && g.PatternX * g.PatternY >= 8) { int s = MapView.StackIndex(it.Count); px = s % 4; py = s / 4; pz = 0; }
            else if ((t.Fluid || t.Splash) && g.PatternX * g.PatternY > 1) { int s = it.Count % (g.PatternX * g.PatternY); px = s % g.PatternX; py = s / g.PatternX; pz = 0; }
            else { px = Mod(pos.X, g.PatternX); py = Mod(pos.Y, g.PatternY); pz = Mod(pos.Z, g.PatternZ); }
            int phase = Phase(g, 0);
            // phase 9, track D: the soft rarity outline behind the sprite and the Divine metal (upright sprites; a thing lying flat keeps the ground ring)
            var glow = ItemGlowReal && !piece.Flat ? ItemGlowFx.For(it) : null;
            if (glow != null)
            {
                float up = 1f / Mathf.Max(0.3f, Mathf.Cos(Pitch * Mathf.Deg2Rad));
                fxMode = FxMode.ItemGlow; fxStrength = ItemGlowFx.PulseParam(glow.PulseMs);
                foreach (var st in ItemGlowFx.Steps(ItemGlowFx.Width))
                {
                    float k = glow.A * st.Fall;
                    fxTint = new Color(glow.R * k, glow.G * k, glow.B * k, 1f);
                    fxOff = new Vector3(st.Dx / 32f, st.Dy / 32f * up, 0.004f);
                    for (int layer = 0; layer < g.Layers; layer++)
                        for (int hh = 0; hh < g.Height; hh++)
                            for (int ww = 0; ww < g.Width; ww++)
                                Quad(piece, ww, hh, Atlas.Sprite(g.Sprite(ww, hh, layer, px, py, pz, phase)), layer);
                }
                fxOff = Vector3.zero;
                fxMode = 0; fxStrength = 1f; fxTint = new Color32(255, 255, 255, 255);
                if (glow.Metal) { fxMode = FxMode.Metal; fxStrength = glow.MetalStrength; fxTint = new Color(glow.MetalR, glow.MetalG, glow.MetalB, 1f); }
            }
            else fxMode = fxShaderOk && LiquidFx && t.Ground ? LiquidGrounds.ModeOf(t.Id) : 0;
            for (int layer = 0; layer < g.Layers; layer++)
                for (int hh = 0; hh < g.Height; hh++)
                    for (int ww = 0; ww < g.Width; ww++)
                        Quad(piece, ww, hh, Atlas.Sprite(g.Sprite(ww, hh, layer, px, py, pz, phase)), layer);
            fxMode = 0; fxStrength = 1f; fxTint = new Color32(255, 255, 255, 255);
        }

        readonly List<(int slot, int ww, int hh, int addon)> fxCells = new List<(int, int, int, int)>();

        void AddCreature(Hd2dPiece piece)
        {
            var c = piece.Creature;
            curScale = SceneScale.For(c, CreatureScale);
            curPivot = new Vector3(piece.Right - 0.5f, piece.Y, piece.Z);
            try { AddCreatureScaled(piece, c); } finally { curScale = 1f; }
        }

        Vector3 Scaled(Vector3 v)
        {
            if (curScale == 1f) return v;
            SceneScale.About(ref v.x, ref v.y, ref v.z, curPivot.x, curPivot.y, curPivot.z, curScale);
            return v;
        }

        void AddCreatureScaled(Hd2dPiece piece, Creature c)
        {
            var o = c.Outfit;
            if (o.LookType == 0)
            {
                var g0 = piece.Type.Idle;
                for (int hh = 0; hh < g0.Height; hh++)
                    for (int ww = 0; ww < g0.Width; ww++)
                        Quad(piece, ww, hh, Atlas.Sprite(g0.Sprite(ww, hh, 0, 0, 0, 0, 0)), 0);
                AddLabel(piece);
                return;
            }
            var t = piece.Type;
            Drawn(c, out float progress);
            bool walking = progress < 1;
            var g = walking ? t.Moving : t.Idle;
            int dir = (int)c.Direction;
            if (dir > 3) dir = dir == 4 || dir == 5 ? 1 : 3;
            if (g.PatternX >= 8) dir = (int)c.Direction;
            int phase;
            if (walking && g.Phases > 1) phase = 1 + (int)(progress * (g.Phases - 1)) % (g.Phases - 1);
            else phase = g.Phases > 1 && !walking && t.Groups.Length > 1 ? Phase(g, c.Id) : 0;
            fxCells.Clear();
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
                        fxCells.Add((slot, ww, hh, addon));
                    }
            }
            var look = fxShaderOk && CreatureFx != null ? CreatureFx(c) : null;
            if (look != null && look.Outline != null && !piece.Flat)
            {
                // the silhouette ring behind the creature (game_visualfx target and follow, game_cosmeticfx), one colour, unlit
                var ol = look.Outline;
                float w = Math.Max(1f, ol.WidthPx) / 32f;
                float up = 1f / Mathf.Max(0.3f, Mathf.Cos(Pitch * Mathf.Deg2Rad));
                fxMode = FxMode.Solid;
                foreach (var d in OutlineFx.Ring)
                    foreach (var cell in fxCells)
                    {
                        OutlineFx.ColorAt(ol, (cell.hh + 0.5f) / Math.Max(1, g.Height), out float cr, out float cg, out float cb);
                        fxTint = new Color(cr, cg, cb, 1f);
                        fxOff = new Vector3(d[0] * w, d[1] * w * up, 0.004f);
                        Quad(piece, cell.ww, cell.hh, cell.slot, cell.addon);
                    }
                fxOff = Vector3.zero; fxMode = 0; fxTint = new Color32(255, 255, 255, 255);
            }
            if (look != null && look.Mode != FxMode.None) { fxMode = look.Mode; fxStrength = look.Strength; fxTint = look.Tint; }
            foreach (var cell in fxCells) Quad(piece, cell.ww, cell.hh, cell.slot, cell.addon);
            fxMode = 0; fxStrength = 1f; fxTint = new Color32(255, 255, 255, 255);
            AddLabel(piece);
        }

        void AddLabel(Hd2dPiece piece)
        {
            var bl = piece.Cell(piece.Width - 1, 0)[0];
            var tr = piece.Cell(0, piece.Height - 1)[2];
            Labels.Add(new Label
            {
                C = piece.Creature,
                Head = Scaled(new Vector3(tr.X - piece.Width / 2f, tr.Y + 0.1f, tr.Z)),
                BottomLeft = Scaled(new Vector3(bl.X, bl.Y, bl.Z)),
                TopRight = Scaled(new Vector3(tr.X, tr.Y, tr.Z)),
            });
        }

        /// <summary>One cell quad. `layer` pushes a later layer a hair towards the camera (no z-fighting).</summary>
        void Quad(Hd2dPiece piece, int ww, int hh, int slot, int layer)
        {
            if (slot == 0) return;
            var b = piece.Flat ? flat : upright;
            var normal = piece.Flat ? upNormal : camNormal;
            Vector3 bias = (piece.Flat ? new Vector3(0, 0.0004f * layer, 0) : new Vector3(0, 0, -0.0004f * layer)) + fxOff;
            var r = Atlas.Uv(slot);
            // an upright cell with a lean profile is drawn in strips, each moved by the profile (the art straightened)
            int n = !piece.Flat && piece.Lean != null ? Hd2d.Strips : 1;
            for (int k = 0; k < n; k++)
            {
                var c = n == 1 ? piece.Cell(ww, hh) : piece.Strip(ww, hh, k, n);
                float v0 = r.yMin + (r.yMax - r.yMin) * k / n, v1 = r.yMin + (r.yMax - r.yMin) * (k + 1) / n;
                int i = b.V.Count;
                for (int q = 0; q < 4; q++) { b.V.Add(Scaled(new Vector3(c[q].X, c[q].Y, c[q].Z)) + bias); b.N.Add(normal); b.UV2.Add(new Vector2(fxMode, fxStrength)); b.Col.Add(fxTint); }
                b.UV.Add(new Vector2(r.xMin, v0));
                b.UV.Add(new Vector2(r.xMax, v0));
                b.UV.Add(new Vector2(r.xMax, v1));
                b.UV.Add(new Vector2(r.xMin, v1));
                // corners: bottom-left, bottom-right, top-right, top-left as the camera sees them; these triangles face it
                b.T.Add(i); b.T.Add(i + 2); b.T.Add(i + 1);
                b.T.Add(i); b.T.Add(i + 3); b.T.Add(i + 2);
            }
        }
    }
}
