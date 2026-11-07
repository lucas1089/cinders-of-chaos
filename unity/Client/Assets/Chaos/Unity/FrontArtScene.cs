// The front-art scene: a test of a new look. Our 2D art is drawn at a slant, which looks wrong in 3D. The recipe here: a blocky 3D
// diorama with crisp pixel textures (made in code, Core/FrontArtTex.cs: 16 texels per unit, point filtered) and small FRONT-FACING
// pixel sprites standing upright as billboards (Resources/FrontArt/<name>/<direction>.png, 64 x 64, 8 directions picked by the
// facing against the camera yaw, Core/FrontArt.cs). Lit by one moon with soft shadows, a cool trilight ambient and warm flickering
// point lights at braziers and torches; narrow field of view, far away, tilt-shift depth of field and bloom (Hd2dPost.cs),
// ember particles (Hd2dParticles.cs) and fog. Built-in render pipeline. The layout and the meshing are Core (tested); this file turns
// them into Unity objects. Shaders: Resources/FrontArtBlock and Resources/FrontArtSprite (the blob shadow and the glow are the HD-2D ones).
//
// Sprites: an upright quad that turns with the camera's yaw (never tilts), alpha cutout, a bent normal and wrap light (the shader),
// a soft blob under the feet, and a shadow thrown by a second quad that faces the sun (shadow pass only) and sits a little behind the
// picture along the light, so the picture never shadows itself and the ground shadow is the same.
// Open it: F11 in the game (offline, no login), mouse wheel zooms between the wide view and the close view on the four characters.
// CI: Hd2dShot (-chaosHd2dShot DIR) builds it and writes front_art.png and front_art_close.png.
// The idea (not the code) follows the MIT-licensed Luminati engine, see docs/CREDITS.md.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace Chaos.Client
{
    public sealed class FrontArtScene : MonoBehaviour
    {
        public Camera Cam;
        public FrontArtLayout Layout;
        public bool LowQuality;
        /// <summary>The mouse wheel zooms and the scene animates itself (the game); the screenshot mode frames and ticks by hand.</summary>
        public bool Interactive;
        public float CamYaw = 0f;
        /// <summary>A sprite's picture covers 2 x 2 units: 64 texels at 32 per unit, a little finer than the 16 of the blocks.</summary>
        public const float SpriteUnits = 2f;
        public const string Folder = "FrontArt/";

        sealed class ActorView
        {
            public FaActor A;
            public readonly Texture2D[] Pics = new Texture2D[8];
            public readonly Texture2D[] Nrm = new Texture2D[8];   // the pictures' normal maps (<dir>_n.png), null when missing
            public Material Mat, ShadowMat;
            public readonly Material[] CastMat = new Material[2];
            public Transform Quad, Proxy;
            public readonly Mesh[] Cast = new Mesh[2];   // ground silhouettes: [0] away from the nearest flame, [1] away from the moon
            public int Dir = -1;
        }

        sealed class LightView { public Light L; public FaLight S; }

        readonly List<ActorView> actors = new List<ActorView>();
        readonly List<LightView> lights = new List<LightView>();
        readonly List<UnityEngine.Object> owned = new List<UnityEngine.Object>();
        Light moon;
        Mesh quadMesh, flameMesh;
        Material flameMat;
        Texture2D flameTex;
        Hd2dParticles particles;
        float zoom;       // 0 wide, 1 close
        float clock;

        // what the scene changes outside itself, to give back
        bool savedState;
        ShadowQuality oldShadows; int oldPixelLights, oldCascades; float oldShadowDistance; ShadowResolution oldShadowRes; ShadowProjection oldProjection;
        AmbientMode oldAmbientMode; Color oldSky, oldEquator, oldGround;

        public int ActorCount => actors.Count;
        public int LightCount => lights.Count;
        public Hd2dParticles Particles => particles;

        /// <summary>Builds the scene under a new object and attaches the look to cam.</summary>
        public static FrontArtScene Open(Camera cam, bool lowQuality, bool interactive)
        {
            var go = new GameObject("Front art");
            var s = go.AddComponent<FrontArtScene>();
            s.Interactive = interactive;
            s.Create(cam, lowQuality);
            return s;
        }

        public void Create(Camera cam, bool lowQuality)
        {
            Cam = cam;
            LowQuality = lowQuality;
            Layout = FrontArtLayout.Build();
            SaveState();
            var mats = MakeMaterials();
            BuildBlocks(mats);
            BuildActors();
            BuildLights();
            BuildFlames();
            BuildBlobs();
            BuildParticles();
            SetupLook();
            FrameWide();
            Tick(0.4f);
            Debug.Log("chaos front art: " + Layout.Boxes.Count + " boxes, " + actors.Count + " characters, " + lights.Count + " lights");
            if (actors.Count > 0)
            {
                var v0 = actors[0];
                var sh = v0.CastMat[0] != null ? v0.CastMat[0].shader : null;
                Debug.Log("chaos front art: cast mesh " + v0.Cast[0].vertexCount + " verts, bounds " + v0.Cast[0].bounds + ", shader " + (sh != null ? sh.name + " supported " + sh.isSupported : "none") + ", queue " + (v0.CastMat[0] != null ? v0.CastMat[0].renderQueue : -1) + ", feet y " + v0.A.Y);
            }
            Debug.Log("chaos front art: shadows " + QualitySettings.shadows + ", distance " + QualitySettings.shadowDistance + ", cascades " + QualitySettings.shadowCascades + ", moon " + (moon != null ? moon.shadows.ToString() : "none") + ", supported " + SystemInfo.supportsShadows + ", low " + LowQuality);
        }

        void SaveState()
        {
            if (savedState) return;
            savedState = true;
            oldShadows = QualitySettings.shadows; oldPixelLights = QualitySettings.pixelLightCount; oldCascades = QualitySettings.shadowCascades;
            oldShadowDistance = QualitySettings.shadowDistance; oldShadowRes = QualitySettings.shadowResolution; oldProjection = QualitySettings.shadowProjection;
            oldAmbientMode = RenderSettings.ambientMode; oldSky = RenderSettings.ambientSkyColor; oldEquator = RenderSettings.ambientEquatorColor; oldGround = RenderSettings.ambientGroundColor;
        }

        void OnDestroy()
        {
            if (Cam != null) Hd2dPost.Detach(Cam);
            if (savedState)
            {
                QualitySettings.shadows = oldShadows; QualitySettings.pixelLightCount = oldPixelLights; QualitySettings.shadowCascades = oldCascades;
                QualitySettings.shadowDistance = oldShadowDistance; QualitySettings.shadowResolution = oldShadowRes; QualitySettings.shadowProjection = oldProjection;
                RenderSettings.ambientMode = oldAmbientMode; RenderSettings.ambientSkyColor = oldSky; RenderSettings.ambientEquatorColor = oldEquator; RenderSettings.ambientGroundColor = oldGround;
                savedState = false;
            }
            foreach (var o in owned) if (o != null) Destroy(o);
            owned.Clear();
        }

        T Own<T>(T o) where T : UnityEngine.Object { owned.Add(o); return o; }

        static Shader FindShader(string name, string fallback)
        {
            var sh = Resources.Load<Shader>(name);
            if (sh == null) sh = Shader.Find("Chaos/" + name);
            if (sh == null) sh = Shader.Find(fallback);
            return sh;
        }

        // ---- blocks ----

        Material[] MakeMaterials()
        {
            var shader = FindShader("FrontArtBlock", "Legacy Shaders/Diffuse");
            var mats = new Material[(int)FaTex.Count];
            for (int i = 0; i < mats.Length; i++)
            {
                var kind = (FaTex)i;
                var pt = FrontArtTex.Make(kind, 1098);
                var tex = Own(new Texture2D(pt.W, pt.H, TextureFormat.RGBA32, false) { name = "front-art-" + kind, filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Repeat, anisoLevel = 0 });
                tex.LoadRawTextureData(pt.Rgba);
                tex.Apply(false, false);
                var bump = Own(new Texture2D(pt.W, pt.H, TextureFormat.RGBA32, false, true) { name = "front-art-relief-" + kind, filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Repeat, anisoLevel = 0 });
                bump.LoadRawTextureData(FrontArtTex.NormalMap(pt, kind == FaTex.Coal || kind == FaTex.DeadGrass ? 1.5f : 3.0f));
                bump.Apply(false, false);
                var m = Own(new Material(shader) { name = "front-art-" + kind });
                m.mainTexture = tex;
                if (m.HasProperty("_BumpTex")) m.SetTexture("_BumpTex", bump);
                if (m.HasProperty("_Emit")) m.SetFloat("_Emit", kind == FaTex.Coal ? 1.7f : 0f);
                mats[i] = m;
            }
            return mats;
        }

        Mesh ToMesh(FaBucket b, string name)
        {
            var mesh = Own(new Mesh { name = name, indexFormat = IndexFormat.UInt32 });
            int n = b.Vertices;
            var v = new List<Vector3>(n); var nr = new List<Vector3>(n); var uv = new List<Vector2>(n); var col = new List<Color>(n);
            for (int i = 0; i < n; i++)
            {
                v.Add(new Vector3(b.V[i * 3], b.V[i * 3 + 1], b.V[i * 3 + 2]));
                nr.Add(new Vector3(b.N[i * 3], b.N[i * 3 + 1], b.N[i * 3 + 2]));
                uv.Add(new Vector2(b.UV[i * 2], b.UV[i * 2 + 1]));
                col.Add(new Color(b.C[i * 4], b.C[i * 4 + 1], b.C[i * 4 + 2], b.C[i * 4 + 3]));
            }
            mesh.SetVertices(v); mesh.SetNormals(nr); mesh.SetUVs(0, uv); mesh.SetColors(col);
            mesh.SetTriangles(b.T, 0);
            mesh.RecalculateBounds();
            return mesh;
        }

        void BuildBlocks(Material[] mats)
        {
            var sets = new[] { FrontArtMesher.Terrain(Layout), FrontArtMesher.Boxes(Layout.Boxes) };
            string[] names = { "terrain ", "props " };
            var terrainMats = new Material[mats.Length];
            for (int s = 0; s < sets.Length; s++)
                for (int k = 0; k < sets[s].Length; k++)
                {
                    if (sets[s][k].Quads == 0) continue;
                    var go = new GameObject(names[s] + (FaTex)k);
                    go.transform.SetParent(transform, false);
                    go.AddComponent<MeshFilter>().sharedMesh = ToMesh(sets[s][k], names[s] + (FaTex)k);
                    var mr = go.AddComponent<MeshRenderer>();
                    // the terrain draws first (queue 1990), then the ground silhouettes (1995), then the props and the rest, so a
                    // silhouette is tested only against the floor and the walls; something else in the opaque pass hid them
                    if (terrainMats[k] == null)
                    {
                        terrainMats[k] = Own(new Material(mats[k]) { name = mats[k].name + "-terrain", renderQueue = 1990 });
                    }
                    mr.sharedMaterial = s == 0 ? terrainMats[k] : mats[k];
                    mr.shadowCastingMode = ShadowCastingMode.On;
                    mr.receiveShadows = true;
                    mr.lightProbeUsage = LightProbeUsage.Off;
                    mr.reflectionProbeUsage = ReflectionProbeUsage.Off;
                }
        }

        // ---- characters ----

        Mesh Quad()
        {
            if (quadMesh != null) return quadMesh;
            quadMesh = Own(new Mesh { name = "front-art-quad" });
            quadMesh.vertices = new[] { new Vector3(-0.5f, 0, 0), new Vector3(0.5f, 0, 0), new Vector3(0.5f, 1, 0), new Vector3(-0.5f, 1, 0) };
            quadMesh.normals = new[] { new Vector3(0, 0, -1), new Vector3(0, 0, -1), new Vector3(0, 0, -1), new Vector3(0, 0, -1) };
            quadMesh.uv = new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) };
            quadMesh.triangles = new[] { 0, 3, 2, 0, 2, 1 };
            quadMesh.bounds = new Bounds(new Vector3(0, 0.5f, 0), new Vector3(1.2f, 1.2f, 0.4f));
            return quadMesh;
        }

        void BuildActors()
        {
            var shader = FindShader("FrontArtSprite", "Unlit/Transparent Cutout");
            foreach (var a in Layout.Actors)
            {
                var v = new ActorView { A = a };
                int found = 0;
                for (int i = 0; i < 8; i++)
                {
                    var t = Resources.Load<Texture2D>(Folder + a.Folder + "/" + FrontArtFacing.Dirs[i]);
                    if (t != null)
                    {
                        t.filterMode = FilterMode.Point; t.wrapMode = TextureWrapMode.Clamp; t.anisoLevel = 0;
                        found++;
                    }
                    v.Pics[i] = t;
                    var nt = Resources.Load<Texture2D>(Folder + a.Folder + "/" + FrontArtFacing.Dirs[i] + "_n");
                    if (nt != null) { nt.filterMode = FilterMode.Point; nt.wrapMode = TextureWrapMode.Clamp; nt.anisoLevel = 0; }
                    v.Nrm[i] = nt;
                }
                if (found < 8) Debug.LogWarning("chaos front art: " + a.Folder + " has " + found + " of 8 pictures in Resources/" + Folder);
                v.Mat = Own(new Material(shader) { name = "front-art-sprite-" + a.Folder });
                v.ShadowMat = Own(new Material(shader) { name = "front-art-shadow-" + a.Folder });
                v.Quad = MakeSpriteObject("sprite " + a.Name, v.Mat, ShadowCastingMode.Off);
                v.Proxy = MakeSpriteObject("shadow " + a.Name, v.ShadowMat, ShadowCastingMode.ShadowsOnly);
                for (int k = 0; k < v.Cast.Length; k++)
                {
                    var cgo = new GameObject("cast " + k + " " + a.Name);
                    cgo.transform.SetParent(transform, false);
                    v.Cast[k] = Own(new Mesh { name = "front-art-cast" });
                    v.Cast[k].MarkDynamic();
                    cgo.AddComponent<MeshFilter>().sharedMesh = v.Cast[k];
                    var cmr = cgo.AddComponent<MeshRenderer>();
                    v.CastMat[k] = Own(new Material(FindShader("FrontArtCast", "Sprites/Default")) { name = "front-art-cast-" + k + "-" + a.Folder });
                    cmr.sharedMaterial = v.CastMat[k];
                    cmr.shadowCastingMode = ShadowCastingMode.Off;
                    cmr.receiveShadows = false;
                    cmr.lightProbeUsage = LightProbeUsage.Off;
                    cmr.reflectionProbeUsage = ReflectionProbeUsage.Off;
                }
                actors.Add(v);
            }
        }

        Transform MakeSpriteObject(string name, Material m, ShadowCastingMode mode)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            go.AddComponent<MeshFilter>().sharedMesh = Quad();
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = m;
            mr.shadowCastingMode = mode;
            mr.receiveShadows = mode != ShadowCastingMode.ShadowsOnly;
            mr.lightProbeUsage = LightProbeUsage.Off;
            mr.reflectionProbeUsage = ReflectionProbeUsage.Off;
            return go.transform;
        }

        static void SetPic(Material m, Texture2D t)
        {
            m.mainTexture = t;
            if (m.HasProperty("_Cutoff")) m.SetFloat("_Cutoff", 0.5f);
        }

        // ---- lights, flames, blobs, particles ----

        void BuildLights()
        {
            var mgo = new GameObject("moon");
            mgo.transform.SetParent(transform, false);
            var f = FrontArtCamera.MoonForward();
            mgo.transform.rotation = Quaternion.LookRotation(new Vector3(f.X, f.Y, f.Z));
            moon = mgo.AddComponent<Light>();
            moon.type = LightType.Directional;
            moon.color = new Color(0.55f, 0.67f, 1.0f);
            moon.intensity = 1.5f;
            moon.shadows = LowQuality ? LightShadows.Hard : LightShadows.Soft;
            moon.shadowStrength = 1f;
            moon.shadowBias = 0.02f;
            moon.shadowNormalBias = 0.25f;
            moon.shadowNearPlane = 0.5f;
            moon.shadowResolution = LightShadowResolution.FromQualitySettings;
            if (!LowQuality) moon.shadowCustomResolution = 2048;

            int pixel = 0;
            // the two flames nearest the figures also cast soft shadows: the figures' shadows then fall away from the fire, the way
            // the HD-2D view lights its rooms (Hd2dView.cs MaxShadowLights)
            var mid = Vector3.zero;
            foreach (var a in Layout.Actors) mid += new Vector3(a.X, a.Y, a.Z);
            mid /= Mathf.Max(1, Layout.Actors.Count);
            var casters = new List<FaLight>();
            if (!LowQuality)
            {
                var flames = new List<FaLight>();
                foreach (var s in Layout.Lights) if (s.Flame) flames.Add(s);
                flames.Sort((p, q) => (new Vector3(p.X, p.Y, p.Z) - mid).sqrMagnitude.CompareTo((new Vector3(q.X, q.Y, q.Z) - mid).sqrMagnitude));
                for (int i = 0; i < flames.Count && i < 2; i++) casters.Add(flames[i]);
            }
            foreach (var s in Layout.Lights)
            {
                var go = new GameObject("light " + lights.Count);
                go.transform.SetParent(transform, false);
                go.transform.position = new Vector3(s.X, s.Y, s.Z);
                var l = go.AddComponent<Light>();
                l.type = LightType.Point;
                l.color = new Color(s.R, s.G, s.B);
                l.range = s.Range;
                l.intensity = s.Intensity;
                l.shadows = casters.Contains(s) ? LightShadows.Soft : LightShadows.None;
                if (l.shadows != LightShadows.None) { l.shadowStrength = 0.85f; l.shadowBias = 0.02f; l.shadowNormalBias = 0.2f; l.shadowNearPlane = 0.2f; }
                l.renderMode = pixel++ < 8 ? LightRenderMode.ForcePixel : LightRenderMode.Auto;
                lights.Add(new LightView { L = l, S = s });
            }
        }

        void BuildFlames()
        {
            flameTex = Own(new Texture2D(12, 20, TextureFormat.RGBA32, false) { name = "front-art-flame", filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp });
            flameTex.LoadRawTextureData(FrontArtTex.Flame(3).Rgba);
            flameTex.Apply(false, false);
            var sh = FindShader("Hd2dGlow", "Legacy Shaders/Particles/Additive");
            flameMat = Own(new Material(sh) { name = "front-art-flame", mainTexture = flameTex });
            flameMesh = Own(new Mesh { name = "front-art-flames" });
            flameMesh.MarkDynamic();
            var go = new GameObject("flames");
            go.transform.SetParent(transform, false);
            go.AddComponent<MeshFilter>().sharedMesh = flameMesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = flameMat;
            mr.shadowCastingMode = ShadowCastingMode.Off;
            mr.receiveShadows = false;
            mr.lightProbeUsage = LightProbeUsage.Off;
            mr.reflectionProbeUsage = ReflectionProbeUsage.Off;
        }

        readonly List<Vector3> fv = new List<Vector3>();
        readonly List<Color> fc = new List<Color>();
        readonly List<Vector2> fuv = new List<Vector2>();
        readonly List<int> ft = new List<int>();

        void FlameQuad(Vector3 baseCentre, float w, float h, Color col, Vector3 right)
        {
            int i = fv.Count;
            fv.Add(baseCentre - right * (w / 2)); fv.Add(baseCentre + right * (w / 2));
            fv.Add(baseCentre + right * (w / 2) + Vector3.up * h); fv.Add(baseCentre - right * (w / 2) + Vector3.up * h);
            for (int k = 0; k < 4; k++) fc.Add(col);
            fuv.Add(new Vector2(0, 0)); fuv.Add(new Vector2(1, 0)); fuv.Add(new Vector2(1, 1)); fuv.Add(new Vector2(0, 1));
            ft.Add(i); ft.Add(i + 3); ft.Add(i + 2); ft.Add(i); ft.Add(i + 2); ft.Add(i + 1);
        }

        /// <summary>The flames: two upright quads each (a wide orange one and a narrow hot one), bright enough (HDR) to bloom, flickering.</summary>
        void BuildFlameMesh(float t)
        {
            fv.Clear(); fc.Clear(); fuv.Clear(); ft.Clear();
            Vector3 right = Cam != null ? Cam.transform.right : Vector3.right;
            right.y = 0f;
            if (right.sqrMagnitude < 1e-4f) right = Vector3.right;
            right.Normalize();
            foreach (var lv in lights)
            {
                var s = lv.S;
                if (!s.Flame) continue;
                float fl = Hd2d.Flicker(t, s.Seed);
                float sway = 0.06f * Mathf.Sin(t * 9f + s.Seed) * s.FlameSize;
                var b = new Vector3(s.FlameX + sway * 0.3f, s.FlameY, s.FlameZ);
                float size = s.FlameSize * (0.92f + 0.5f * (fl - 1f));
                FlameQuad(b + right * sway * 0.4f, 0.62f * size, 0.95f * size * (0.96f + 0.3f * (fl - 1f)), new Color(2.1f, 0.85f, 0.22f, 1f), right);
                FlameQuad(b, 0.38f * size, 0.60f * size * (1.02f + 0.3f * (1f - fl)), new Color(2.6f, 2.0f, 0.8f, 1f), right);
            }
            flameMesh.Clear();
            if (fv.Count == 0) return;
            flameMesh.SetVertices(fv); flameMesh.SetColors(fc); flameMesh.SetUVs(0, fuv); flameMesh.SetTriangles(ft, 0);
            flameMesh.bounds = new Bounds(new Vector3(Layout.W / 2f, 2f, Layout.D / 2f), new Vector3(Layout.W, 8f, Layout.D));
        }

        void BuildBlobs()
        {
            var sh = FindShader("Hd2dBlob", "Sprites/Default");
            var v = new List<Vector3>(); var uv = new List<Vector4>(); var t = new List<int>();
            Action<float, float, float, float, float, float> blob = (x, y, z, rx, rz, strength) =>
            {
                int i = v.Count;
                v.Add(new Vector3(x - rx, y + CastLift, z - rz)); v.Add(new Vector3(x + rx, y + CastLift, z - rz));
                v.Add(new Vector3(x + rx, y + CastLift, z + rz)); v.Add(new Vector3(x - rx, y + CastLift, z + rz));
                uv.Add(new Vector4(0, 0, 0, strength)); uv.Add(new Vector4(1, 0, 0, strength)); uv.Add(new Vector4(1, 1, 0, strength)); uv.Add(new Vector4(0, 1, 0, strength));
                t.Add(i); t.Add(i + 3); t.Add(i + 2); t.Add(i); t.Add(i + 2); t.Add(i + 1);
            };
            foreach (var a in Layout.Actors) blob(a.X, a.Y, a.Z, 0.62f, 0.36f, 0.9f);
            foreach (var b in Layout.Boxes)
            {
                if (b.Tag == null || b.Tag == "rubble" || b.Tag == "coal" || b.Tag == "torch" || b.Tag == "gate") continue;
                float cx = (b.X0 + b.X1) / 2f, cz = (b.Z0 + b.Z1) / 2f, gy = Layout.GroundY(cx, cz);
                if (b.Y0 - gy > 0.03f) continue;
                float r = Mathf.Max(b.X1 - b.X0, b.Z1 - b.Z0) * 0.5f;
                if (b.Tag == "brazier" && r < 0.3f) continue;
                if (b.Tag == "tree") { blob(cx, gy, cz, 0.55f, 0.35f, 0.5f); continue; }
                if (b.Tag == "brazier" || b.Tag == "pillar" || b.Tag == "sarcophagus" || b.Tag == "crate" || b.Tag == "grave")
                    blob(cx, gy, cz, r * 1.35f, r * 1.2f, 0.55f);
            }
            var mesh = Own(new Mesh { name = "front-art-blobs" });
            mesh.SetVertices(v); mesh.SetUVs(0, uv); mesh.SetTriangles(t, 0);
            mesh.RecalculateBounds();
            var go = new GameObject("blobs");
            go.transform.SetParent(transform, false);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = Own(new Material(sh) { name = "front-art-blob" });
            mr.shadowCastingMode = ShadowCastingMode.Off;
            mr.receiveShadows = false;
        }

        void BuildParticles()
        {
            var go = new GameObject("embers");
            go.transform.SetParent(transform, false);
            particles = go.AddComponent<Hd2dParticles>();
            particles.Cam = Cam;
            var list = new List<Hd2dLight>();
            foreach (var s in Layout.Lights)
                list.Add(new Hd2dLight { Position = new Vec3(s.FlameSize > 0f ? s.FlameX : s.X, s.FlameSize > 0f ? s.FlameY + 0.15f : s.Y, s.FlameSize > 0f ? s.FlameZ : s.Z), R = s.R, G = s.G, B = s.B, Range = Mathf.Min(s.Range, 4.5f), Intensity = Mathf.Min(1f, s.Intensity * 0.5f) });
            particles.SetLights(list, new Vec3(Layout.W / 2f, 1f, Layout.D / 2f - 1f));
            particles.Prewarm(4f);
        }

        // ---- the look ----

        void SetupLook()
        {
            QualitySettings.pixelLightCount = Mathf.Max(oldPixelLights, LowQuality ? 4 : 8);
            QualitySettings.shadows = LowQuality ? ShadowQuality.HardOnly : ShadowQuality.All;
            QualitySettings.shadowResolution = ShadowResolution.VeryHigh;
            QualitySettings.shadowCascades = 1;
            QualitySettings.shadowDistance = 70f;
            QualitySettings.shadowProjection = ShadowProjection.StableFit;
            if (Cam == null) return;
            Cam.orthographic = false;
            Cam.fieldOfView = FrontArtCamera.Fov;
            Cam.nearClipPlane = 1f;
            Cam.farClipPlane = 400f;
            var stale = Cam.GetComponent<Hd2dEffect>();
            if (stale != null) DestroyImmediate(stale);   // a pending Destroy of an earlier view would take the new effect too
            Hd2dPost.Attach(Cam, LowQuality);
            // cold moonlit air: a trilight ambient, thick fog that melts the far ground into the dark
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.30f, 0.36f, 0.58f);
            RenderSettings.ambientEquatorColor = new Color(0.20f, 0.21f, 0.34f);
            RenderSettings.ambientGroundColor = new Color(0.10f, 0.08f, 0.13f);
            var fog = new Color(0.07f, 0.07f, 0.13f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.ExponentialSquared;
            RenderSettings.fogDensity = 0.011f;
            RenderSettings.fogColor = fog;
            Cam.backgroundColor = fog;
            Tune(false);
        }

        /// <summary>The post look for the wide view (strong tilt-shift, a thin sharp band) or the close view (a thicker band around the figures).</summary>
        public void Tune(bool close)
        {
            if (Cam == null) return;
            var fx = Cam.GetComponent<Hd2dEffect>();
            if (fx == null) return;
            fx.focusHalf = close ? 0.20f : 0.13f;
            fx.focusFeather = close ? 0.26f : 0.30f;
            fx.bloomThreshold = 1.0f;
            fx.bloomKnee = 0.5f;
            fx.bloomIntensity = 0.9f;
            fx.exposure = LowQuality ? 1.25f : 1.0f;
            fx.vignette = 0.5f;
            fx.grain = 0.035f;
            fx.saturation = 1.1f;
            fx.contrast = 1.08f;
        }

        // ---- camera ----

        Vector3 WideTarget => new Vector3(Layout.W / 2f, 1.0f, Layout.D / 2f - 1.7f);

        Vector3 CloseTarget
        {
            get
            {
                var c = Vector3.zero;
                foreach (var a in Layout.Actors) c += new Vector3(a.X, a.Y + 0.95f, a.Z);
                return c / Mathf.Max(1, Layout.Actors.Count);
            }
        }

        void PlaceCamera(Vector3 target, float dist)
        {
            if (Cam == null) return;
            var p = FrontArtCamera.Position(new Vec3(target.x, target.y, target.z), dist, CamYaw, FrontArtCamera.Pitch);
            Cam.transform.SetPositionAndRotation(new Vector3(p.X, p.Y, p.Z), Quaternion.Euler(FrontArtCamera.Pitch, CamYaw, 0f));
        }

        /// <summary>The whole diorama: 32 units away, a narrow lens.</summary>
        public void FrameWide() { zoom = 0f; PlaceCamera(WideTarget, 32f); Tune(false); }

        /// <summary>The four characters across the brazier, 11 units away.</summary>
        public void FrameClose() { zoom = 1f; PlaceCamera(CloseTarget, 11f); Tune(true); }

        // ---- per frame ----

        void Update()
        {
            if (!Interactive) return;
            float wheel = Input.mouseScrollDelta.y;
            if (Mathf.Abs(wheel) > 0.01f) zoom = Mathf.Clamp01(zoom + wheel * 0.08f);
            PlaceCamera(Vector3.Lerp(WideTarget, CloseTarget, zoom), Mathf.Lerp(32f, 11f, zoom));
            Tune(zoom > 0.5f);
        }

        void LateUpdate()
        {
            if (Interactive) Tick(Time.time);
        }

        /// <summary>Turns the sprites to the camera, picks their pictures, flickers the lights and rebuilds the flames. t is the scene's clock in seconds.</summary>
        public void Tick(float t)
        {
            clock = t;
            if (Layout == null) return;
            float yaw = Cam != null ? Cam.transform.eulerAngles.y : CamYaw;
            var face = Quaternion.Euler(0f, yaw, 0f);
            Vector3 sun = moon != null ? moon.transform.forward : Vector3.down;
            float sunYaw = Mathf.Atan2(sun.x, sun.z) * Mathf.Rad2Deg;
            var sunFace = Quaternion.Euler(0f, sunYaw, 0f);
            for (int i = 0; i < actors.Count; i++)
            {
                var v = actors[i];
                int dir = FrontArtFacing.Index(v.A.FaceX, v.A.FaceZ, yaw);
                if (dir != v.Dir)
                {
                    v.Dir = dir;
                    SetPic(v.Mat, v.Pics[dir]);
                    if (v.Nrm[dir] != null) v.Mat.SetTexture("_BumpMap", v.Nrm[dir]);
                    v.Mat.SetFloat("_NormalAmount", v.Nrm[dir] != null ? 0.85f : 0f);
                    SetPic(v.ShadowMat, v.Pics[dir]);
                    SetPic(v.CastMat[0], v.Pics[dir]);
                    SetPic(v.CastMat[1], v.Pics[dir]);
                }
                float breath = 1f + 0.012f * Mathf.Sin(t * 2.1f + i * 1.7f);
                var pos = new Vector3(v.A.X, v.A.Y + 0.01f, v.A.Z);
                var scale = new Vector3(SpriteUnits, SpriteUnits * breath, 1f);
                v.Quad.SetPositionAndRotation(pos, face);
                v.Quad.localScale = scale;
                v.Proxy.SetPositionAndRotation(pos + sun * 0.18f, sunFace);
                v.Proxy.localScale = scale;
                CastShadows(v, pos, sun);
            }
            foreach (var lv in lights)
            {
                if (lv.S.Flame) lv.L.intensity = lv.S.Intensity * Hd2d.Flicker(t, lv.S.Seed);
            }
            if (flameMesh != null) BuildFlameMesh(t);
            if (particles != null) { particles.Cam = Cam; particles.BuildMesh(); }
        }

        /// <summary>The figure's ground silhouettes: one stretched away from the nearest flame (strong when close, longer the lower the
        /// flame), one away from the moon (faint, length from its height). They stand in for the shadow map, which the screenshot
        /// renderer does not give this scene.</summary>
        void CastShadows(ActorView v, Vector3 feet, Vector3 sun)
        {
            LightView near = null;
            float best = float.MaxValue;
            foreach (var lv in lights)
            {
                if (!lv.S.Flame) continue;
                float d = (lv.L.transform.position - feet).sqrMagnitude;
                if (d < best) { best = d; near = lv; }
            }
            if (near != null)
            {
                var lp = near.L.transform.position;
                var away = new Vector3(feet.x - lp.x, 0f, feet.z - lp.z);
                float dist = away.magnitude;
                float h = Mathf.Max(0.35f, lp.y - feet.y);
                float len = SpriteUnits * Mathf.Clamp(0.55f * dist / h + 0.35f, 0.5f, 1.4f);
                float strength = 0.62f * Mathf.Clamp01(1f - dist / Mathf.Max(0.1f, near.S.Range));
                SetCast(v.Cast[0], feet, dist > 0.01f ? away / dist : Vector3.forward, len);
                v.CastMat[0].SetFloat("_Strength", strength);
            }
            else v.Cast[0].Clear();
            var flat = new Vector3(sun.x, 0f, sun.z);
            float fl = flat.magnitude;
            float elev = Mathf.Atan2(-sun.y, Mathf.Max(0.01f, fl));
            SetCast(v.Cast[1], feet, fl > 0.01f ? flat / fl : Vector3.forward, SpriteUnits * Mathf.Clamp(0.8f / Mathf.Tan(Mathf.Max(0.2f, elev)), 0.4f, 1.3f));
            v.CastMat[1].SetFloat("_Strength", 0.3f);
        }

        static readonly Vector3[] castVerts = new Vector3[4];
        static readonly Vector2[] castUv = { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) };
        static readonly int[] castTris = { 0, 1, 2, 0, 2, 3 };

        /// <summary>How far the ground silhouettes and blobs float over the floor. Closer ones were hidden by the floor in the
        /// screenshot renderer (front_art_debug.png showed them drawn); from this camera the lift does not show.</summary>
        const float CastLift = 0.12f;

        static void SetCast(Mesh m, Vector3 feet, Vector3 dir, float len)
        {
            var side = Vector3.Cross(Vector3.up, dir) * (SpriteUnits * 0.5f);
            var f = feet + Vector3.up * CastLift;
            castVerts[0] = f + side; castVerts[1] = f - side;
            castVerts[2] = f - side + dir * len; castVerts[3] = f + side + dir * len;
            m.Clear();
            m.vertices = castVerts;
            m.uv = castUv;
            m.triangles = castTris;
            m.RecalculateBounds();
            // a flat mesh has a bounding box with no height; give it some so no culling step ever drops it
            var bb = m.bounds; bb.Expand(new Vector3(0f, 1f, 0f)); m.bounds = bb;
        }

        /// <summary>Screenshot-mode check: the ground silhouettes drawn over everything at full strength (front_art_debug.png), to tell a
        /// silhouette that is not drawn from one that is hidden under the floor.</summary>
        public void DebugCastsOnTop(bool always, float full)
        {
            foreach (var v in actors)
                foreach (var m in v.CastMat)
                    if (m != null)
                    {
                        Debug.Log("chaos front art: cast " + v.A.Name + " strength " + m.GetFloat("_Strength") + " ztest " + m.GetFloat("_ZTest") + " queue " + m.renderQueue);
                        m.SetFloat("_ZTest", (float)(always ? CompareFunction.Always : CompareFunction.LessEqual));
                        if (full >= 0f) m.SetFloat("_Strength", full);
                    }
        }

        /// <summary>The scene's clock, for the screenshot mode.</summary>
        public float Clock => clock;
    }
}
