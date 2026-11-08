// The front-art live view (F8): the real map around the player drawn in the look of the front-art scene (FrontArtScene.cs): a blocky
// diorama of pixel-textured tile blocks (walls tall, water low), upright front-facing sprites of the real art for the things standing
// on it, a moon and warm flickering point lights, tilt-shift depth of field and bloom (Hd2dPost.cs), fog and embers. Built-in pipeline.
// What stands where is Core/FrontLive.cs (tested); this file turns it into meshes, lights and a camera that follows the player.
//
// It draws no creatures and no effects. Other components do, and find their way here:
//   - FrontLiveCreatures and FrontLiveFx (Chaos.Client, written separately) are added to this object by reflection in Init when the types exist.
//   - Contract for them: Cam, World, Atlas, TileToWorld, GroundY, DrawnTile / DrawnPoint, Ticked (every frame after the world update, with the
//     clock in seconds), Labels (the creatures fill it for the name labels and clicks: ChaosApp reads it while this view is on), Layout.
//   - Terrain materials sit in render queue 1990 and the sprite batches in the alpha test queue, like the front-art scene, so ground
//     silhouettes (FrontArtCast, queue 1995) draw between the floor and the rest.
// World units: one tile is one unit, +x east, +z north, +y up; tile (x, y) is x - Anchor.X, Anchor.Y - y. The anchor is set at the first
// build and moves only after a walk of 192 tiles (a rebuild then; everything asks TileToWorld each frame).
// Rebuild: only when FrontLive.ViewHash changes (the player walked a tile, an item changed): the terrain and prop meshes are refilled in place
// (13 meshes each, pooled), the sprite meshes too; a layout with animated sprites refreshes the sprite meshes five times a second.
// Camera: FrontArtCamera (FOV 28, pitch 33) at the distance where the classic 15 x 11 tiles fit the screen (Hd2dCamera.ForTile) times Zoom,
// following the player's drawn position with a short smoothing; the mouse wheel zooms (not over a window).
// CI: Hd2dShot writes front_live.png and front_live_close.png (Refresh, Frame, Tick by hand, no frame waits).
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace Chaos.Client
{
    public sealed class FrontLiveView : MonoBehaviour
    {
        public World World;
        public SpriteAtlas Atlas;
        public Func<double> Clock;
        public Camera Cam;
        /// <summary>The wheel zooms and the view ticks itself (the game); the screenshot mode drives it by hand.</summary>
        public bool Interactive = true;
        /// <summary>True while the pointer is over a window: the wheel then does not zoom.</summary>
        public Func<bool> BlockInput;
        /// <summary>Called every frame after the view has updated: the clock in seconds. Creatures and effects hook here.</summary>
        public event Action<float> Ticked;
        /// <summary>The creatures' name points and sprite corners (world space), filled by FrontLiveCreatures; ChaosApp draws names from it.</summary>
        public readonly List<Hd2dView.Label> Labels = new List<Hd2dView.Label>();

        public float Zoom = 1f;
        /// <summary>The tilt-shift band: half the height that stays sharp, and its soft edge (the scene's own values are 0.13 and 0.30, too thin to play in).</summary>
        public float FocusHalf = 0.26f, FocusFeather = 0.30f;
        public const float MinZoom = 0.45f, MaxZoom = 1.8f;
        public const string Plugins = "Chaos.Client.FrontLiveCreatures,Chaos.Client.FrontLiveFx";

        public FrontLiveLayout Layout { get; private set; }
        /// <summary>Where the world coordinates are anchored (a tile).</summary>
        public Pos Anchor { get; private set; }
        public int Rebuilds { get; private set; }
        public float LastBuildMs { get; private set; }
        public Hd2dParticles Particles { get; private set; }
        public bool LowQuality => Hd2dView.LowQuality;
        public int MaxLights => LowQuality ? 4 : 8;

        readonly FrontLiveOptions options = new FrontLiveOptions();
        SpriteClassifier classifier;
        bool anchored, ready;
        float clock;

        // blocks: one pooled mesh per texture kind, for the terrain and for the props
        sealed class Pool
        {
            public readonly GameObject[] Go = new GameObject[(int)FaTex.Count];
            public readonly Mesh[] Mesh = new Mesh[(int)FaTex.Count];
            public readonly MeshRenderer[] Renderer = new MeshRenderer[(int)FaTex.Count];
        }

        Pool terrain = new Pool(), props = new Pool();
        Material[] terrainMats, propMats;
        readonly List<UnityEngine.Object> owned = new List<UnityEngine.Object>();

        // sprites over the atlas
        sealed class Batch
        {
            public Mesh Mesh;
            public MeshRenderer Renderer;
            public readonly List<Vector3> V = new List<Vector3>(), N = new List<Vector3>();
            public readonly List<Vector2> UV = new List<Vector2>();
            public readonly List<Vector2> UV2 = new List<Vector2>();   // phase 9 track D: x the FxMode of the quad, y its strength (Hd2dSprite.shader uv2_MainTex); one entry per vertex
            public readonly List<Color32> Col = new List<Color32>();   // the colour of an outline silhouette or of the metal look; one entry per vertex
            public readonly List<int> T = new List<int>();
        }

        Batch upright, flat;
        Material spriteMat;
        // phase 9 track D: the rarity outline of items (silhouette behind the sprite) and the Divine metal; the material must be Chaos/Hd2dSprite
        bool fxShaderOk, glowBuilt = true;
        int fxMode; float fxStrength = 1f;
        Color32 fxTint = new Color32(255, 255, 255, 255);
        Vector3 fxOff;
        /// <summary>The rarity outline of items on the map is wanted (Options > Visual).</summary>
        public bool ItemOutlines = true;
        /// <summary>The sprite shader draws the outline; when false the ground ring of ChaosApp.DrawItemRings stands in.</summary>
        public bool ItemGlowReal => ItemOutlines && fxShaderOk;
        /// <summary>The spell lights of this moment, added to the frame's lights before the nearest layout lights are picked.</summary>
        public Action<List<FaLight>> FrameLights;
        Vector3 camNormal;
        int atlasGen;
        float spriteNext;

        // light, post and the state to give back
        Light moon;
        readonly List<Light> pool = new List<Light>();
        readonly List<FaLight> extra = new List<FaLight>();   // creatures' lights this frame
        readonly List<FaLight> picked = new List<FaLight>();
        readonly List<Vector3> shaftPos = new List<Vector3>();
        readonly List<Color> shaftCol = new List<Color>();
        float particlesNext;
        bool[] usedBuf = new bool[128];
        bool savedState;
        ShadowQuality oldShadows; int oldPixelLights, oldCascades; float oldShadowDistance; ShadowResolution oldShadowRes; ShadowProjection oldProjection;
        AmbientMode oldAmbientMode; Color oldSky, oldEquator, oldGround;
        float daylight = -1f;

        // camera
        Vector3 camTarget, camVel;
        bool camSnap = true;
        float fitDist = 18f, fitAspect = -1f, fitRows = -1f;

        // ---- setup ----

        /// <summary>Gives the view its world and art and makes what it needs once. Call before the object is active; the plug-in components
        /// (FrontLiveCreatures, FrontLiveFx) are added here when their types exist.</summary>
        public void Init(World world, SpriteAtlas atlas, Camera cam, Func<double> clock)
        {
            World = world; Atlas = atlas; Cam = cam; Clock = clock;
            classifier = new SpriteClassifier(id => id == 0 || Atlas == null ? null : Atlas.Raw(id));
            MakeMaterials();
            MakeBatches();
            MakeLights();
            double p = FrontArtCamera.Pitch * Math.PI / 180.0;
            camNormal = new Vector3(0f, (float)Math.Sin(p), -(float)Math.Cos(p));
            var pg = new GameObject("embers");
            pg.transform.SetParent(transform, false);
            Particles = pg.AddComponent<Hd2dParticles>();
            Particles.Cam = Cam;
            AddPlugins();
            ready = true;
            if (isActiveAndEnabled) ApplyLook();   // made on an active object: OnEnable ran before there was anything to show
        }

        /// <summary>The creatures and effects components, by reflection: they are written apart from this file and may not be in the build.</summary>
        void AddPlugins()
        {
            foreach (var name in Plugins.Split(','))
            {
                var t = Type.GetType(name);
                if (t != null && GetComponent(t) == null) gameObject.AddComponent(t);
            }
        }

        T Own<T>(T o) where T : UnityEngine.Object { owned.Add(o); return o; }

        static Shader FindShader(string name, string fallback)
        {
            var sh = Resources.Load<Shader>(name);
            if (sh == null) sh = Shader.Find("Chaos/" + name);
            if (sh == null) sh = Shader.Find(fallback);
            return sh;
        }

        void MakeMaterials()
        {
            var shader = FindShader("FrontArtBlock", "Legacy Shaders/Diffuse");
            terrainMats = new Material[(int)FaTex.Count];
            propMats = new Material[(int)FaTex.Count];
            for (int i = 0; i < terrainMats.Length; i++)
            {
                var kind = (FaTex)i;
                var pt = FrontArtTex.Make(kind, 1098);
                var tex = Own(new Texture2D(pt.W, pt.H, TextureFormat.RGBA32, false) { name = "front-live-" + kind, filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Repeat, anisoLevel = 0 });
                tex.LoadRawTextureData(pt.Rgba);
                tex.Apply(false, false);
                var bump = Own(new Texture2D(pt.W, pt.H, TextureFormat.RGBA32, false, true) { name = "front-live-relief-" + kind, filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Repeat, anisoLevel = 0 });
                bump.LoadRawTextureData(FrontArtTex.NormalMap(pt, FrontArtTex.ReliefStrength(kind)));
                bump.Apply(false, false);
                var m = Own(new Material(shader) { name = "front-live-" + kind });
                m.mainTexture = tex;
                if (m.HasProperty("_BumpTex")) m.SetTexture("_BumpTex", bump);
                if (m.HasProperty("_Emit")) m.SetFloat("_Emit", FrontArtTex.Emit(kind));
                propMats[i] = m;
                // the terrain draws first (queue 1990), then the ground silhouettes (1995), then the props and the rest
                terrainMats[i] = Own(new Material(m) { name = "front-live-" + kind + "-terrain", renderQueue = 1990 });
            }
        }

        void MakeBatches()
        {
            var sh = Hd2dPost.SpriteMaterial(Atlas != null ? Atlas.Texture : null);
            spriteMat = Own(sh);
            fxShaderOk = sh != null && sh.shader != null && sh.shader.name == Hd2dPost.SpriteShaderName;
            upright = NewBatch("sprites", ShadowCastingMode.TwoSided);
            flat = NewBatch("flat sprites", ShadowCastingMode.Off);
        }

        Batch NewBatch(string name, ShadowCastingMode shadows)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            var b = new Batch { Mesh = Own(new Mesh { name = "front-live-" + name, indexFormat = IndexFormat.UInt32 }) };
            b.Mesh.MarkDynamic();
            go.AddComponent<MeshFilter>().sharedMesh = b.Mesh;
            b.Renderer = go.AddComponent<MeshRenderer>();
            b.Renderer.sharedMaterial = spriteMat;
            b.Renderer.shadowCastingMode = shadows;
            b.Renderer.receiveShadows = true;
            b.Renderer.lightProbeUsage = LightProbeUsage.Off;
            b.Renderer.reflectionProbeUsage = ReflectionProbeUsage.Off;
            return b;
        }

        void MakeLights()
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
        }

        // ---- the look, on while the object is active ----

        void OnEnable() { if (ready) ApplyLook(); }

        void ApplyLook()
        {
            SaveState();
            QualitySettings.pixelLightCount = Mathf.Max(oldPixelLights, MaxLights);
            QualitySettings.shadows = LowQuality ? ShadowQuality.HardOnly : ShadowQuality.All;
            QualitySettings.shadowResolution = ShadowResolution.VeryHigh;
            QualitySettings.shadowCascades = 1;
            QualitySettings.shadowDistance = 70f;
            QualitySettings.shadowProjection = ShadowProjection.StableFit;
            if (Cam != null)
            {
                Cam.orthographic = false;
                Cam.fieldOfView = FrontArtCamera.Fov;
                Cam.nearClipPlane = 1f;
                Cam.farClipPlane = 400f;
                Cam.rect = new Rect(0f, 0f, 1f, 1f);
                var stale = Cam.GetComponent<Hd2dEffect>();
                if (stale != null) DestroyImmediate(stale);   // a pending Destroy of another view would take the new effect too
                Hd2dPost.Attach(Cam, LowQuality);
                RenderSettings.ambientMode = AmbientMode.Trilight;
                RenderSettings.fog = true;
                RenderSettings.fogMode = FogMode.ExponentialSquared;
                RenderSettings.fogDensity = 0.011f;
                daylight = -1f;
                ApplyDaylight(DayFactor());
                Tune();
            }
            if (Particles != null) { Particles.Cam = Cam; Particles.enabled = true; }
            camSnap = true;
            upright.Renderer.enabled = true; flat.Renderer.enabled = true;   // the block meshes are enabled as they are filled
            if (moon != null) moon.enabled = true;
            Layout = null;   // the world may have changed while the view was off
        }

        void OnDisable()
        {
            foreach (var l in pool) if (l != null) l.enabled = false;
            if (moon != null) moon.enabled = false;
            foreach (var r in Renderers()) if (r != null) r.enabled = false;
            if (Particles != null) Particles.enabled = false;
            if (Cam != null) Hd2dPost.Detach(Cam);
            if (savedState)
            {
                QualitySettings.shadows = oldShadows; QualitySettings.pixelLightCount = oldPixelLights; QualitySettings.shadowCascades = oldCascades;
                QualitySettings.shadowDistance = oldShadowDistance; QualitySettings.shadowResolution = oldShadowRes; QualitySettings.shadowProjection = oldProjection;
                RenderSettings.ambientMode = oldAmbientMode; RenderSettings.ambientSkyColor = oldSky; RenderSettings.ambientEquatorColor = oldEquator; RenderSettings.ambientGroundColor = oldGround;
                savedState = false;
            }
        }

        void OnDestroy()
        {
            foreach (var o in owned) if (o != null) Destroy(o);
            owned.Clear();
        }

        IEnumerable<Renderer> Renderers()
        {
            foreach (var p in new[] { terrain, props })
                foreach (var r in p.Renderer) yield return r;
            if (upright != null) yield return upright.Renderer;
            if (flat != null) yield return flat.Renderer;
        }

        void SaveState()
        {
            if (savedState) return;
            savedState = true;
            oldShadows = QualitySettings.shadows; oldPixelLights = QualitySettings.pixelLightCount; oldCascades = QualitySettings.shadowCascades;
            oldShadowDistance = QualitySettings.shadowDistance; oldShadowRes = QualitySettings.shadowResolution; oldProjection = QualitySettings.shadowProjection;
            oldAmbientMode = RenderSettings.ambientMode; oldSky = RenderSettings.ambientSkyColor; oldEquator = RenderSettings.ambientEquatorColor; oldGround = RenderSettings.ambientGroundColor;
        }

        /// <summary>The post look: the scene's own values with a thicker sharp band, for playing.</summary>
        public void Tune()
        {
            if (Cam == null) return;
            var fx = Cam.GetComponent<Hd2dEffect>();
            if (fx == null) return;
            float close = Mathf.InverseLerp(1f, MinZoom, Zoom);   // zoomed in: the band thickens a little
            fx.focusHalf = FocusHalf + 0.06f * close;
            fx.focusFeather = FocusFeather;
            fx.bloomThreshold = 1.0f;
            fx.bloomKnee = 0.5f;
            fx.bloomIntensity = 0.9f;
            fx.exposure = LowQuality ? 1.25f : 1.0f;
            fx.vignette = 0.5f;
            fx.grain = 0.035f;
            fx.saturation = 1.1f;
            fx.contrast = 1.08f;
        }

        float DayFactor() { return World == null ? 0f : Mathf.Clamp01(World.WorldLight / 255f); }

        /// <summary>Night by default (the look of the scene); the server's world light level lifts the moon and the ambient toward day.</summary>
        void ApplyDaylight(float d)
        {
            if (Mathf.Abs(d - daylight) < 0.01f) return;
            daylight = d;
            if (moon != null) moon.intensity = Mathf.Lerp(1.0f, 1.9f, d);
            float k = Mathf.Lerp(0.8f, 1.35f, d);
            RenderSettings.ambientSkyColor = new Color(0.30f, 0.36f, 0.58f) * k;
            RenderSettings.ambientEquatorColor = new Color(0.20f, 0.21f, 0.34f) * k;
            RenderSettings.ambientGroundColor = new Color(0.10f, 0.08f, 0.13f) * k;
            var fog = Color.Lerp(new Color(0.06f, 0.06f, 0.11f), new Color(0.12f, 0.13f, 0.20f), d);
            RenderSettings.fogColor = fog;
            if (Cam != null) Cam.backgroundColor = fog;
        }

        // ---- the contract ----

        public double Now => Clock != null ? Clock() : Time.realtimeSinceStartupAsDouble * 1000;

        /// <summary>The middle of a tile at its ground height (a tile on a floor below is drawn shifted, FrontLiveLayout.TileToWorld).</summary>
        public Vector3 TileToWorld(int x, int y, int z)
        {
            if (Layout == null)
            {
                var a = anchored ? Anchor : (World != null ? World.Center : new Pos(x, y, z));
                var w0 = FrontLive.ToWorld(a, x, y, 0f);
                return new Vector3(w0.X, w0.Y, w0.Z);
            }
            var v = Layout.TileToWorld(x, y, z);
            return new Vector3(v.X, v.Y, v.Z);
        }

        public float GroundY(int x, int y, int z) { return TileToWorld(x, y, z).y; }

        /// <summary>Where a creature is drawn now, in tiles, fractional while it walks (x east, y south).</summary>
        public Vector2 DrawnTile(Creature c)
        {
            WalkMath.Drawn(c, Now, out float x, out float y, out float _);   // Core/SmoothWalk.cs
            return new Vector2(x, y);
        }

        /// <summary>The point on the ground a creature stands on now (its smooth position, the ground height between its two tiles).</summary>
        public Vector3 DrawnPoint(Creature c)
        {
            var d = DrawnTile(c);
            var a = Layout != null ? Layout.Anchor : (anchored ? Anchor : c.Position);
            float gy = GroundY(Mathf.FloorToInt(d.x), Mathf.FloorToInt(d.y), c.Position.Z);
            WalkMath.Between(c, Now, out Pos wf, out Pos wt, out float wu);
            if (wf != wt && Layout != null)
                gy = Mathf.Lerp(GroundY(wf.X, wf.Y, wf.Z), GroundY(wt.X, wt.Y, wt.Z), wu);
            var w = FrontLive.ToWorld(a, d.x, d.y, gy);
            return new Vector3(w.X, w.Y, w.Z);
        }

        /// <summary>A light that follows something for one frame (a creature's own light): it is lit with the nearest static ones.</summary>
        public void AddFrameLight(FaLight l) { extra.Add(l); }

        // ---- per frame ----

        void LateUpdate()
        {
            if (!Interactive) return;
            Tick(Time.time);
        }

        /// <summary>Rebuilds when the map changed, moves the camera, flickers and picks the lights, then calls Ticked. t is the clock in seconds.</summary>
        public void Tick(float t)
        {
            if (!ready || World == null || Atlas == null || Cam == null) return;
            float dt = Mathf.Max(0.0001f, t - clock);
            if (dt > 0.5f) dt = 0.016f;
            clock = t;
            Refresh();
            if (Layout == null) return;
            Wheel();
            PlaceCamera(dt);
            ApplyDaylight(DayFactor());
            Tune();
            UpdateLights(t);
            Animate(t);
            Ticked?.Invoke(t);
            extra.Clear();
        }

        /// <summary>Builds the layout and the meshes now if the map changed (Tick does it every frame; the screenshot mode by hand).</summary>
        public void Refresh()
        {
            if (!ready || World == null || Atlas == null) return;
            var c = World.Center;
            bool reanchor = !anchored || Mathf.Abs(c.X - Anchor.X) > 192 || Mathf.Abs(c.Y - Anchor.Y) > 192;
            if (reanchor) { Anchor = new Pos(c.X, c.Y, 0); anchored = true; Layout = null; camSnap = true; }
            int hash = FrontLive.ViewHash(World, options);
            if (Layout == null || hash != Layout.Hash || Layout.Floor != c.Z) Rebuild();
            else if ((Layout.Animated && Time.realtimeSinceStartup >= spriteNext) || glowBuilt != ItemGlowReal) { BuildSprites(); }
        }

        void Rebuild()
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            Layout = FrontLive.Build(World, Anchor, classifier, options, LeanOf);
            Fill(terrain, terrainMats, FrontArtMesher.Terrain(Layout.Grid), "terrain");
            Fill(props, propMats, FrontArtMesher.Boxes(Layout.Grid.Boxes), "props");
            BuildSprites();
            LastBuildMs = (float)sw.Elapsed.TotalMilliseconds;
            Rebuilds++;
            particlesNext = 0f;
        }

        // the measured lean profile of each thing's art (Hd2d.Lean), once per type
        readonly Dictionary<ThingType, float[]> leans = new Dictionary<ThingType, float[]>();

        float[] LeanOf(ThingType t, bool outfit)
        {
            if (leans.TryGetValue(t, out var v)) return v;
            v = Hd2d.Lean(t, outfit, id => id == 0 ? null : Atlas.Raw(id));
            leans[t] = v;
            return v;
        }

        // ---- blocks ----

        static readonly List<Vector3> sv = new List<Vector3>(), sn = new List<Vector3>();
        static readonly List<Vector2> suv = new List<Vector2>();
        static readonly List<Color> sc = new List<Color>();

        void Fill(Pool pool, Material[] mats, FaBucket[] buckets, string name)
        {
            for (int k = 0; k < buckets.Length; k++)
            {
                var b = buckets[k];
                if (b.Quads == 0)
                {
                    if (pool.Renderer[k] != null) pool.Renderer[k].enabled = false;
                    continue;
                }
                if (pool.Go[k] == null)
                {
                    var go = new GameObject(name + " " + (FaTex)k);
                    go.transform.SetParent(transform, false);
                    pool.Mesh[k] = Own(new Mesh { name = "front-live-" + name + "-" + (FaTex)k, indexFormat = IndexFormat.UInt32 });
                    pool.Mesh[k].MarkDynamic();
                    go.AddComponent<MeshFilter>().sharedMesh = pool.Mesh[k];
                    var mr = go.AddComponent<MeshRenderer>();
                    mr.sharedMaterial = mats[k];
                    mr.shadowCastingMode = ShadowCastingMode.On;
                    mr.receiveShadows = true;
                    mr.lightProbeUsage = LightProbeUsage.Off;
                    mr.reflectionProbeUsage = ReflectionProbeUsage.Off;
                    pool.Go[k] = go; pool.Renderer[k] = mr;
                }
                int n = b.Vertices;
                sv.Clear(); sn.Clear(); suv.Clear(); sc.Clear();
                for (int i = 0; i < n; i++)
                {
                    sv.Add(new Vector3(b.V[i * 3], b.V[i * 3 + 1], b.V[i * 3 + 2]));
                    sn.Add(new Vector3(b.N[i * 3], b.N[i * 3 + 1], b.N[i * 3 + 2]));
                    suv.Add(new Vector2(b.UV[i * 2], b.UV[i * 2 + 1]));
                    sc.Add(new Color(b.C[i * 4], b.C[i * 4 + 1], b.C[i * 4 + 2], b.C[i * 4 + 3]));
                }
                var mesh = pool.Mesh[k];
                mesh.Clear();
                mesh.SetVertices(sv); mesh.SetNormals(sn); mesh.SetUVs(0, suv); mesh.SetColors(sc);
                mesh.SetTriangles(b.T, 0);
                mesh.RecalculateBounds();
                pool.Renderer[k].enabled = isActiveAndEnabled;
            }
        }

        // ---- sprites ----

        void BuildSprites()
        {
            int gen = Atlas.Generation;
            glowBuilt = ItemGlowReal;
            AddSprites();
            if (Atlas.Generation != gen) AddSprites();   // the atlas filled up and was cleared while building
            Atlas.Upload();
            spriteMat.mainTexture = Atlas.Texture;
            spriteNext = Time.realtimeSinceStartup + 0.2f;
        }

        void AddSprites()
        {
            Clear(upright); Clear(flat);
            foreach (var p in Layout.Upright) AddItem(p);
            foreach (var p in Layout.Flat) AddItem(p);
            Upload(upright); Upload(flat);
        }

        static void Clear(Batch b) { b.V.Clear(); b.N.Clear(); b.UV.Clear(); b.UV2.Clear(); b.Col.Clear(); b.T.Clear(); }

        static void Upload(Batch b)
        {
            b.Mesh.Clear();
            b.Mesh.SetVertices(b.V);
            b.Mesh.SetNormals(b.N);
            b.Mesh.SetUVs(0, b.UV);
            if (b.UV2.Count == b.V.Count && b.V.Count > 0) { b.Mesh.SetUVs(1, b.UV2); b.Mesh.SetColors(b.Col); }
            b.Mesh.SetTriangles(b.T, 0);
            b.Mesh.RecalculateBounds();
        }

        int Phase(FrameGroup g, long salt)
        {
            if (g.Phases <= 1) return 0;
            int d = g.MinDuration != null && g.MinDuration[0] > 0 ? g.MinDuration[0] : 300;
            return (int)(((long)Now / d + salt) % g.Phases);
        }

        static int Mod(int a, int n) { int m = a % n; return m < 0 ? m + n : m; }

        // the same sprite choice as MapView.DrawItem and Hd2dView.AddItem
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
                float up = 1f / Mathf.Max(0.3f, Mathf.Sin((90f - FrontArtCamera.Pitch) * Mathf.Deg2Rad));
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
            for (int layer = 0; layer < g.Layers; layer++)
                for (int hh = 0; hh < g.Height; hh++)
                    for (int ww = 0; ww < g.Width; ww++)
                        Quad(piece, ww, hh, Atlas.Sprite(g.Sprite(ww, hh, layer, px, py, pz, phase)), layer);
            fxMode = 0; fxStrength = 1f; fxTint = new Color32(255, 255, 255, 255);
        }

        void Quad(Hd2dPiece piece, int ww, int hh, int slot, int layer)
        {
            if (slot == 0) return;
            var b = piece.Flat ? flat : upright;
            var normal = piece.Flat ? Vector3.up : camNormal;
            Vector3 bias = (piece.Flat ? new Vector3(0, 0.0004f * layer, 0) : new Vector3(0, 0, -0.0004f * layer)) + fxOff;
            var r = Atlas.Uv(slot);
            // an upright cell with a lean profile is drawn in strips, each moved by the profile (the art straightened)
            int n = !piece.Flat && piece.Lean != null ? Hd2d.Strips : 1;
            for (int k = 0; k < n; k++)
            {
                var c = n == 1 ? piece.Cell(ww, hh) : piece.Strip(ww, hh, k, n);
                float v0 = r.yMin + (r.yMax - r.yMin) * k / n, v1 = r.yMin + (r.yMax - r.yMin) * (k + 1) / n;
                int i = b.V.Count;
                for (int q = 0; q < 4; q++) { b.V.Add(new Vector3(c[q].X, c[q].Y, c[q].Z) + bias); b.N.Add(normal); b.UV2.Add(new Vector2(fxMode, fxStrength)); b.Col.Add(fxTint); }
                b.UV.Add(new Vector2(r.xMin, v0));
                b.UV.Add(new Vector2(r.xMax, v0));
                b.UV.Add(new Vector2(r.xMax, v1));
                b.UV.Add(new Vector2(r.xMin, v1));
                // corners: bottom-left, bottom-right, top-right, top-left as the camera sees them; these triangles face it
                b.T.Add(i); b.T.Add(i + 2); b.T.Add(i + 1);
                b.T.Add(i); b.T.Add(i + 3); b.T.Add(i + 2);
            }
        }

        // ---- camera ----

        /// <summary>The ground point the camera looks at: the player's drawn position, a little above the floor.</summary>
        Vector3 Focus()
        {
            var me = World.Player;
            if (me != null) return DrawnPoint(me) + new Vector3(0f, 0.9f, 0f);
            return TileToWorld(World.Center.X, World.Center.Y, World.Center.Z) + new Vector3(0f, 0.9f, 0f);
        }

        void Wheel()
        {
            if (!Interactive) return;
            float wheel = Input.mouseScrollDelta.y;
            if (Mathf.Abs(wheel) < 0.01f || (BlockInput != null && BlockInput())) return;
            Zoom = Mathf.Clamp(Zoom - wheel * 0.07f, MinZoom, MaxZoom);
        }

        /// <summary>The distance at which the classic 15 x 11 tiles fill the frame.</summary>
        float FitDistance()
        {
            float aspect = Cam.aspect;
            if (Mathf.Abs(aspect - fitAspect) > 0.001f || fitRows != ChaosApp.ViewTilesH)   // the map zoom changes the rows
            {
                fitAspect = aspect; fitRows = ChaosApp.ViewTilesH;
                fitDist = Hd2dCamera.ForTile(0f, 0f, new Pos(0, 0, 0), aspect, FrontArtCamera.Pitch, FrontArtCamera.Fov, ChaosApp.ViewTilesW, ChaosApp.ViewTilesH).Distance;
            }
            return fitDist;
        }

        void PlaceCamera(float dt)
        {
            var want = Focus();
            if (camSnap || (want - camTarget).sqrMagnitude > 64f) { camTarget = want; camVel = Vector3.zero; camSnap = false; }
            else camTarget = Vector3.SmoothDamp(camTarget, want, ref camVel, 0.10f, float.PositiveInfinity, dt);
            Cam.orthographic = false;
            Cam.fieldOfView = FrontArtCamera.Fov;
            var p = FrontArtCamera.Position(new Vec3(camTarget.x, camTarget.y, camTarget.z), FitDistance() * Zoom, 0f, FrontArtCamera.Pitch);
            Cam.transform.SetPositionAndRotation(new Vector3(p.X, p.Y, p.Z), Quaternion.Euler(FrontArtCamera.Pitch, 0f, 0f));
        }

        /// <summary>Puts the camera on the player at once: `zoom` times the classic fit (the screenshot mode: wide 1.6, close 0.6).</summary>
        public void Frame(float zoom)
        {
            Zoom = Mathf.Clamp(zoom, 0.2f, 3f);
            camSnap = true;
            if (Layout != null) { PlaceCamera(0.016f); Tune(); }
        }

        // ---- lights and life ----

        void UpdateLights(float t)
        {
            var me = World.Player;
            // the nearest lights to the camera's target: the player's own and other creatures' lights first, then the layout's
            picked.Clear();
            var focus = new Vec3(camTarget.x, camTarget.y, camTarget.z);
            int max = MaxLights;
            FrameLights?.Invoke(extra);   // phase 9 track D: the spell lights
            if (me != null && me.LightLevel > 0) picked.Add(CreatureLight(me));
            foreach (var l in extra) if (picked.Count < max) picked.Add(l);
            var all = Layout.Lights;
            // selection of the nearest few: a pass per pick, the list is at most 96 long
            int fixedCount = picked.Count;
            if (usedBuf.Length < all.Count) usedBuf = new bool[all.Count + 32];
            Array.Clear(usedBuf, 0, usedBuf.Length);
            var used = usedBuf;
            while (picked.Count < max)
            {
                int best = -1; float bd = float.MaxValue;
                for (int i = 0; i < all.Count; i++)
                {
                    if (used[i]) continue;
                    float dx = all[i].X - focus.X, dy = all[i].Y - focus.Y, dz = all[i].Z - focus.Z;
                    float d = dx * dx + dy * dy + dz * dz;
                    if (d < bd) { bd = d; best = i; }
                }
                if (best < 0) break;
                used[best] = true;
                picked.Add(all[best]);
            }
            while (pool.Count < MaxLights)
            {
                var go = new GameObject("light " + pool.Count);
                go.transform.SetParent(transform, false);
                var l = go.AddComponent<Light>();
                l.type = LightType.Point;
                l.renderMode = LightRenderMode.ForcePixel;
                pool.Add(l);
            }
            int shadowed = 0;
            for (int i = 0; i < pool.Count; i++)
            {
                var l = pool[i];
                if (i >= picked.Count) { l.enabled = false; continue; }
                var s = picked[i];
                float fl = s.Flame ? Hd2d.Flicker(t, s.Seed) : 1f;
                l.enabled = true;
                l.color = new Color(s.R, s.G, s.B);
                l.range = s.Range;
                l.intensity = s.Intensity * fl;
                var pos = new Vector3(s.X, s.Y, s.Z);
                if (s.Flame) pos += new Vector3(Hd2d.Flicker(t * 1.7f, s.Seed + 11) - 1f, Hd2d.Flicker(t * 1.3f, s.Seed + 21) - 1f, Hd2d.Flicker(t * 1.9f, s.Seed + 31) - 1f) * 0.25f;
                l.transform.position = pos;
                // the two nearest flames cast soft shadows (the figures' shadows fall away from the fire)
                bool casts = !LowQuality && s.Flame && shadowed < 2;
                if (casts) shadowed++;
                l.shadows = casts ? LightShadows.Soft : LightShadows.None;
                if (casts) { l.shadowStrength = 0.85f; l.shadowBias = 0.02f; l.shadowNormalBias = 0.2f; l.shadowNearPlane = 0.2f; }
            }
            // embers rise from the flames; light shafts toward the strongest lights
            shaftPos.Clear(); shaftCol.Clear();
            foreach (var s in picked) { shaftPos.Add(new Vector3(s.X, s.Y, s.Z)); shaftCol.Add(new Color(s.R, s.G, s.B) * Mathf.Min(1f, s.Intensity)); }
            Hd2dEffect.SetLightsWorld(Cam, shaftPos, shaftCol);
            if (Particles != null && Time.realtimeSinceStartup >= particlesNext)
            {
                particlesNext = Time.realtimeSinceStartup + 0.5f;
                var list = new List<Hd2dLight>();
                foreach (var s in picked)
                    list.Add(new Hd2dLight { Position = new Vec3(s.X, s.Y + 0.15f, s.Z), R = s.R, G = s.G, B = s.B, Range = Mathf.Min(s.Range, 4.5f), Intensity = Mathf.Min(1f, s.Intensity * 0.5f) });
                Particles.SetLights(list, focus);
            }
        }

        FaLight CreatureLight(Creature c)
        {
            var p = DrawnPoint(c);
            Hd2d.ColorFromIndex(c.LightColor, out int r, out int g, out int b);
            if (r + g + b == 0) { r = g = b = 255; }
            float level = c.LightLevel;
            return new FaLight { X = p.x, Y = p.y + 1.0f, Z = p.z, R = r / 255f, G = g / 255f, B = b / 255f, Range = Mathf.Clamp(level * 0.85f + 2f, 3f, 8f), Intensity = Mathf.Clamp(0.55f + level * 0.12f, 0.6f, 1.6f), Flame = false, Seed = (int)c.Id };
        }

        // water drifts and lava breathes: the texture offset of their materials
        void Animate(float t)
        {
            var w = terrainMats[(int)FaTex.Water];
            if (w != null) w.mainTextureOffset = new Vector2(t * 0.012f, t * 0.008f);
            var lava = terrainMats[(int)FaTex.Lava];
            if (lava != null && lava.HasProperty("_Emit")) lava.SetFloat("_Emit", 1.3f + 0.25f * Mathf.Sin(t * 1.7f));
        }

        // ---- the screenshot ----

        /// <summary>Dust and embers without frames (the screenshot mode).</summary>
        public void Prewarm()
        {
            if (Particles == null) return;
            Particles.Prewarm(4f);
            Particles.BuildMesh();
        }

        /// <summary>One line for the log: what the last build made.</summary>
        public string Summary()
        {
            if (Layout == null) return "no layout";
            var g = Layout.Grid;
            return Layout.GroundTiles + " ground tiles, " + Layout.WallTiles + " wall, " + Layout.WaterTiles + " water, " + Layout.LavaTiles + " lava, " + Layout.LowerTiles + " lower, " + Layout.VoidTiles + " void, "
                   + g.Boxes.Count + " boxes, " + Layout.Upright.Count + " upright and " + Layout.Flat.Count + " flat sprites, " + Layout.Lights.Count + " lights, built in " + LastBuildMs.ToString("0.0") + " ms";
        }
    }
}
