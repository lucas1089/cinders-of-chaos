// The front-art scene: a test of a new look. Our 2D art is drawn at a slant, which looks wrong in 3D. The recipe here: a blocky 3D
// diorama with crisp pixel textures (made in code, Core/FrontArtTex.cs: 16 texels per unit, point filtered) and small FRONT-FACING
// pixel sprites standing upright as billboards (Resources/FrontArt/<name>/<direction>.png, 48 x 48, 8 directions picked by the
// facing against the camera yaw, Core/FrontArt.cs). Lit by one moon with soft shadows, a cool trilight ambient and warm flickering
// point lights at braziers and torches; narrow field of view, far away, tilt-shift depth of field and bloom (Hd2dPost.cs),
// ember particles (Hd2dParticles.cs) and fog. Built-in render pipeline. The layout and the meshing are Core (tested); this file turns
// them into Unity objects. Shaders: Resources/FrontArtBlock and Resources/FrontArtSprite (the blob shadow and the glow are the HD-2D ones).
//
// Sprites: an upright quad that turns with the camera's yaw (never tilts), alpha cutout, a bent normal and wrap light (the shader),
// a soft blob under the feet, and a shadow thrown by a second quad that faces the sun (shadow pass only) and sits a little behind the
// picture along the light, so the picture never shadows itself and the ground shadow is the same.
// Extras: purchased pack monsters (Layout.Extras, Resources/FrontArt/pk_<name>/, 64 x 64 at 40 texels per unit) stand around the
// four, playing their idle animations (PackFps); their pictures are not in git (licence: no sharing of the files) but come encrypted, unity/tools/front_art_packs.py, and the
// CI opens them with the CHAOS_ART_KEY secret. Missing pictures leave an extra out.
// Open it: F11 in the game (offline, no login), mouse wheel zooms between the wide view and the close view on the four characters.
// CI: Hd2dShot (-chaosHd2dShot DIR) builds it and writes front_art.png and front_art_close.png.
// The idea (not the code) follows the MIT-licensed Luminati engine, see docs/CREDITS.md.
using System;
using System.Collections.Generic;
using System.Linq;
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
        /// <summary>A sprite's picture covers 1.5 x 1.5 units: 48 texels at 32 per unit, a little finer than the 16 of the blocks.</summary>
        public const float SpriteUnits = 1.5f;
        public const string Folder = "FrontArt/";

        sealed class ActorView
        {
            public FaActor A;
            public readonly Texture2D[] Pics = new Texture2D[8];
            public readonly Texture2D[] Nrm = new Texture2D[8];   // the pictures' normal maps (<dir>_n.png), null when missing
            public readonly Texture2D[] Emit = new Texture2D[8];  // the pictures' emission masks (<dir>_e.png), null when missing
            public Material Mat, ShadowMat;
            public readonly Material[] CastMat = new Material[2];
            public Transform Quad, Proxy;
            public readonly Mesh[] Cast = new Mesh[2];   // ground silhouettes: [0] away from the nearest flame, [1] away from the moon
            public int Dir = -1;
            public float Units = SpriteUnits;   // the picture's side in units
            // pack monsters: an idle animation, frames side by side, [0] facing right, [1] its mirror (idle_w); Frames 0 = none;
            // the walk animation the same way (walk, walk_w; WalkFrames 0 = none: the monster stands)
            public readonly Texture2D[] Strip = new Texture2D[2], StripN = new Texture2D[2], StripE = new Texture2D[2];
            public readonly Texture2D[] Walk = new Texture2D[2], WalkN = new Texture2D[2], WalkE = new Texture2D[2];
            // the attack animation (attack, attack_w; AttackFrames 0 = none: a caster stays in its idle while casting)
            public readonly Texture2D[] Attack = new Texture2D[2], AttackN = new Texture2D[2], AttackE = new Texture2D[2];
            public int Frames, WalkFrames, AttackFrames, Frame = -1;
            public readonly List<int> Casts = new List<int>();   // indices into Layout.Spells this figure casts
            public int Melee = -1;   // index into Layout.Melees of the attack this figure makes, -1 none
            public float HitShown = -1f;   // the _Hit last set on its material
            public float Phase;   // FrontArtWalk.Phase of its index among the extras
            public Transform Blob; // a walker's own contact shadow (the others are in the static blob mesh)
        }

        sealed class LightView { public Light L; public FaLight S; }

        // an attack spell: a missile quad, an impact quad and a light that travels with the missile and flashes on the hit
        sealed class SpellView
        {
            public FaSpell S;
            public Transform Missile, Impact;
            public Renderer MissileR, ImpactR;
            public Material MissileMat, ImpactMat;
            public Light L;
            public int ImpactFrames;
        }

        readonly List<SpellView> spells = new List<SpellView>();

        // a melee blow's slash (drawn in Core, FrontArtSlash) and a flash of light where it lands
        sealed class MeleeView
        {
            public FaMelee M;
            public Transform Slash;
            public Renderer SlashR;
            public Material SlashMat;
            public Light L;
        }

        readonly List<MeleeView> melees = new List<MeleeView>();
        /// <summary>A slash frame's side in units; how fast a runner's walk strip plays; how high a figure without one hops.</summary>
        public const float SlashUnits = 1.35f, RunFps = 16f, Hop = 0.09f;
        /// <summary>The spell art's side in units: a missile frame (64 texels), an impact frame (128 texels).</summary>
        public const float MissileUnits = 1.6f, ImpactUnits = 2.6f, MissileFps = 12f;

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
            BuildSpells();
            BuildMelees();
            BuildLights();
            BuildFlames();
            BuildBlobs();
            BuildParticles();
            SetupLook();
            FrameWide();
            Tick(0.4f);
            Debug.Log("chaos front art: " + Layout.Boxes.Count + " boxes, " + actors.Count + " characters, " + lights.Count + " lights");
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
            foreach (var a in Layout.Actors.Concat(Layout.Extras))
            {
                bool extra = Layout.Extras.Contains(a);
                var v = new ActorView { A = a, Units = a.Units > 0f ? a.Units : SpriteUnits };
                int found = 0;
                if (extra)
                {
                    for (int k = 0; k < 2; k++)
                    {
                        string b = Folder + a.Folder + (k == 0 ? "/idle" : "/idle_w");
                        v.Strip[k] = Point(Resources.Load<Texture2D>(b));
                        v.StripN[k] = Point(Resources.Load<Texture2D>(b + "_n"));
                        v.StripE[k] = Point(Resources.Load<Texture2D>(b + "_e"));
                    }
                    if (v.Strip[0] == null || v.Strip[1] == null) continue;   // the pack monsters (Resources/FrontArt/pk_*) come only with the CHAOS_ART_KEY secret
                    v.Frames = Mathf.Max(1, v.Strip[0].width / Mathf.Max(1, v.Strip[0].height));
                    for (int k = 0; k < 2; k++)
                    {
                        string b = Folder + a.Folder + (k == 0 ? "/walk" : "/walk_w");
                        v.Walk[k] = Point(Resources.Load<Texture2D>(b));
                        v.WalkN[k] = Point(Resources.Load<Texture2D>(b + "_n"));
                        v.WalkE[k] = Point(Resources.Load<Texture2D>(b + "_e"));
                    }
                    if (v.Walk[0] != null && v.Walk[1] != null) v.WalkFrames = Mathf.Max(1, v.Walk[0].width / Mathf.Max(1, v.Walk[0].height));
                    for (int k = 0; k < 2; k++)
                    {
                        string b = Folder + a.Folder + (k == 0 ? "/attack" : "/attack_w");
                        v.Attack[k] = Point(Resources.Load<Texture2D>(b));
                        v.AttackN[k] = Point(Resources.Load<Texture2D>(b + "_n"));
                        v.AttackE[k] = Point(Resources.Load<Texture2D>(b + "_e"));
                    }
                    if (v.Attack[0] != null && v.Attack[1] != null) v.AttackFrames = Mathf.Max(1, v.Attack[0].width / Mathf.Max(1, v.Attack[0].height));
                    v.Phase = FrontArtWalk.Phase(Layout.Extras.IndexOf(a));
                    found = 8;
                }
                else for (int i = 0; i < 8; i++)
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
                    var et = Resources.Load<Texture2D>(Folder + a.Folder + "/" + FrontArtFacing.Dirs[i] + "_e");
                    if (et != null) { et.filterMode = FilterMode.Point; et.wrapMode = TextureWrapMode.Clamp; et.anisoLevel = 0; }
                    v.Emit[i] = et;
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

        /// <summary>The attack spells whose art is there (Resources/FrontArt/fx_*, opened with the pack monsters) and whose caster and
        /// target are in the scene.</summary>
        void BuildSpells()
        {
            var sh = FindShader("FrontArtSpell", "Sprites/Default");
            for (int i = 0; i < Layout.Spells.Count; i++)
            {
                var s = Layout.Spells[i];
                var caster = actors.Find(v => v.A.Name == s.Caster);
                if (caster == null || !actors.Exists(v => v.A.Name == s.Target)) continue;
                var mt = Point(Resources.Load<Texture2D>(Folder + "fx_" + s.Missile + "/missile"));
                var it = Point(Resources.Load<Texture2D>(Folder + "fx_" + s.Impact + "/impact"));
                if (mt == null || it == null) continue;
                var sv = new SpellView { S = s, ImpactFrames = Mathf.Max(1, it.width / Mathf.Max(1, it.height)) };
                sv.MissileMat = Own(new Material(sh) { name = "front-art-missile-" + s.Missile, mainTexture = mt });
                sv.ImpactMat = Own(new Material(sh) { name = "front-art-impact-" + s.Impact, mainTexture = it });
                sv.Missile = MakeSpriteObject("missile " + s.Caster, sv.MissileMat, ShadowCastingMode.Off);
                sv.Impact = MakeSpriteObject("impact " + s.Caster, sv.ImpactMat, ShadowCastingMode.Off);
                sv.MissileR = sv.Missile.GetComponent<Renderer>();
                sv.ImpactR = sv.Impact.GetComponent<Renderer>();
                sv.MissileR.receiveShadows = false; sv.ImpactR.receiveShadows = false;
                sv.MissileR.enabled = false; sv.ImpactR.enabled = false;
                var lgo = new GameObject("spell light " + s.Caster);
                lgo.transform.SetParent(transform, false);
                sv.L = lgo.AddComponent<Light>();
                sv.L.type = LightType.Point;
                sv.L.color = new Color(s.R, s.G, s.B);
                sv.L.range = 3.2f;
                sv.L.shadows = LightShadows.None;
                sv.L.renderMode = LightRenderMode.ForcePixel;
                sv.L.enabled = false;
                caster.Casts.Add(i);
                spells.Add(sv);
            }
            Debug.Log("chaos front art: " + spells.Count + " of " + Layout.Spells.Count + " attack spells");
        }

        /// <summary>The melee attacks whose attacker and target are in the scene: a slash texture each, in its colour.</summary>
        void BuildMelees()
        {
            var sh = FindShader("FrontArtSpell", "Sprites/Default");
            for (int i = 0; i < Layout.Melees.Count; i++)
            {
                var m = Layout.Melees[i];
                var attacker = actors.Find(v => v.A.Name == m.Attacker);
                if (attacker == null || !actors.Exists(v => v.A.Name == m.Target)) continue;
                var tex = Own(new Texture2D(FrontArtSlash.Size * FrontArtSlash.Frames, FrontArtSlash.Size, TextureFormat.RGBA32, false) { name = "front-art-slash-" + m.Attacker });
                tex.LoadRawTextureData(FrontArtSlash.Pixels(m.R, m.G, m.B));
                tex.Apply(false, true);
                Point(tex);
                var mv = new MeleeView { M = m };
                mv.SlashMat = Own(new Material(sh) { name = "front-art-slash-" + m.Attacker, mainTexture = tex });
                mv.Slash = MakeSpriteObject("slash " + m.Attacker, mv.SlashMat, ShadowCastingMode.Off);
                mv.SlashR = mv.Slash.GetComponent<Renderer>();
                mv.SlashR.receiveShadows = false;
                mv.SlashR.enabled = false;
                var lgo = new GameObject("slash light " + m.Attacker);
                lgo.transform.SetParent(transform, false);
                mv.L = lgo.AddComponent<Light>();
                mv.L.type = LightType.Point;
                mv.L.color = Color.Lerp(new Color(m.R, m.G, m.B), Color.white, 0.35f);
                mv.L.range = 2.6f;
                mv.L.shadows = LightShadows.None;
                mv.L.renderMode = LightRenderMode.ForcePixel;
                mv.L.enabled = false;
                attacker.Melee = i;
                melees.Add(mv);
            }
            Debug.Log("chaos front art: " + melees.Count + " of " + Layout.Melees.Count + " melee attacks");
        }

        /// <summary>Places the slashes at time t; mirrored when the blow goes to the left on screen.</summary>
        void TickMelees(float t, Quaternion face)
        {
            Vector3 right = Cam != null ? Cam.transform.right : Vector3.right, up = Cam != null ? Cam.transform.up : Vector3.up;
            foreach (var mv in melees)
            {
                var st = FrontArtMelee.At(Layout, mv.M, t);
                mv.SlashR.enabled = st.Slash;
                mv.L.enabled = st.Slash;
                if (!st.Slash) continue;
                int frame = Mathf.Min(FrontArtSlash.Frames - 1, (int)(st.SlashU * FrontArtSlash.Frames));
                bool left = Vector3.Dot(new Vector3(st.FaceX, 0f, st.FaceZ), right) < 0f;
                mv.SlashMat.mainTextureScale = new Vector2((left ? -1f : 1f) / FrontArtSlash.Frames, 1f);
                mv.SlashMat.mainTextureOffset = new Vector2((float)(left ? frame + 1 : frame) / FrontArtSlash.Frames, 0f);
                var at = new Vector3(st.SX, st.SY, st.SZ);
                mv.Slash.SetPositionAndRotation(at - up * (SlashUnits / 2f) - (Cam != null ? Cam.transform.forward : Vector3.forward) * 0.3f, face);
                mv.Slash.localScale = new Vector3(SlashUnits, SlashUnits, 1f);
                mv.L.transform.position = at;
                mv.L.intensity = 3f * (1f - st.SlashU);
            }
        }

        /// <summary>Places the missiles and impacts at time t. A missile sheet has 8 direction rows (E, SE, S, SW, W, NW, N, NE from the
        /// top) of 8 frames; the row follows the missile's heading on screen.</summary>
        void TickSpells(float t, Quaternion face)
        {
            Vector3 right = Cam != null ? Cam.transform.right : Vector3.right, up = Cam != null ? Cam.transform.up : Vector3.up;
            foreach (var sv in spells)
            {
                var st = FrontArtSpells.At(Layout, sv.S, t);
                sv.MissileR.enabled = st.Flying;
                sv.ImpactR.enabled = st.Hit;
                sv.L.enabled = st.Flying || st.Hit;
                var at = new Vector3(st.X, st.Y, st.Z);
                if (st.Flying)
                {
                    var d = new Vector3(st.DirX, st.DirY, st.DirZ);
                    float sx = Vector3.Dot(d, right), sy = Vector3.Dot(d, up);
                    float deg = Mathf.Atan2(-sy, sx) * Mathf.Rad2Deg;   // clockwise from east on screen: 90 = down (S)
                    int row = ((Mathf.RoundToInt(deg / 45f) % 8) + 8) % 8;
                    int frame = (int)Mathf.Repeat(Mathf.Floor(t * MissileFps), 8f);
                    sv.MissileMat.mainTextureScale = new Vector2(1f / 8f, 1f / 8f);
                    sv.MissileMat.mainTextureOffset = new Vector2(frame / 8f, 1f - (row + 1) / 8f);
                    sv.Missile.SetPositionAndRotation(at - up * (MissileUnits / 2f), face);
                    sv.Missile.localScale = new Vector3(MissileUnits, MissileUnits, 1f);
                    sv.L.transform.position = at;
                    sv.L.intensity = 2.4f;
                }
                if (st.Hit)
                {
                    int frame = Mathf.Min(sv.ImpactFrames - 1, (int)(st.HitU * sv.ImpactFrames));
                    sv.ImpactMat.mainTextureScale = new Vector2(1f / sv.ImpactFrames, 1f);
                    sv.ImpactMat.mainTextureOffset = new Vector2((float)frame / sv.ImpactFrames, 0f);
                    sv.Impact.SetPositionAndRotation(at - up * (ImpactUnits / 2f), face);
                    sv.Impact.localScale = new Vector3(ImpactUnits, ImpactUnits, 1f);
                    sv.L.transform.position = at;
                    sv.L.intensity = 4f * (1f - st.HitU);
                }
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

        static Texture2D Point(Texture2D t)
        {
            if (t != null) { t.filterMode = FilterMode.Point; t.wrapMode = TextureWrapMode.Clamp; t.anisoLevel = 0; }
            return t;
        }

        /// <summary>Frames a second of the pack monsters' idle and walk animations.</summary>
        public const float PackFps = 8f, WalkFps = 10f;

        static void SetFrame(Material m, int frame, int frames)
        {
            m.mainTextureScale = new Vector2(1f / frames, 1f);
            m.mainTextureOffset = new Vector2((float)frame / frames, 0f);
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
            foreach (var av in actors)
                if (!(av.A.Walks && av.WalkFrames > 0)) blob(av.A.X, av.A.Y, av.A.Z, 0.62f * av.Units / SpriteUnits, 0.36f * av.Units / SpriteUnits, 0.9f);
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
            var blobMat = Own(new Material(sh) { name = "front-art-blob" });
            mr.sharedMaterial = blobMat;
            mr.shadowCastingMode = ShadowCastingMode.Off;
            mr.receiveShadows = false;
            // the walkers' blobs move with them (Tick places them)
            foreach (var av in actors)
            {
                if (!(av.A.Walks && av.WalkFrames > 0)) continue;
                v.Clear(); uv.Clear(); t.Clear();
                blob(0f, 0f, 0f, 0.62f * av.Units / SpriteUnits, 0.36f * av.Units / SpriteUnits, 0.9f);
                var one = Own(new Mesh { name = "front-art-blob-" + av.A.Folder });
                one.SetVertices(v); one.SetUVs(0, uv); one.SetTriangles(t, 0);
                one.RecalculateBounds();
                var bgo = new GameObject("blob " + av.A.Name);
                bgo.transform.SetParent(transform, false);
                bgo.AddComponent<MeshFilter>().sharedMesh = one;
                var bmr = bgo.AddComponent<MeshRenderer>();
                bmr.sharedMaterial = blobMat;
                bmr.shadowCastingMode = ShadowCastingMode.Off;
                bmr.receiveShadows = false;
                av.Blob = bgo.transform;
                av.Blob.position = new Vector3(av.A.X, av.A.Y, av.A.Z);
            }
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
        /// <summary>The close look on the pack monsters east of the path (the screenshot mode's animation frames).</summary>
        public void FrameHorde() { zoom = 1f; PlaceCamera(new Vector3(14.4f, Layout.GroundY(14.4f, 7.2f) + 0.9f, 7.2f), 13f); Tune(true); }
        public void FrameFight() { zoom = 1f; PlaceCamera(new Vector3(10.4f, Layout.GroundY(10.4f, 6.8f) + 0.9f, 6.8f), 13.5f); Tune(true); }
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
                // pack monsters patrol (FrontArtWalk); the four stand
                var pose = v.Frames > 0 ? FrontArtWalk.At(v.A, t, v.Phase) : new FrontArtWalk.Pose { X = v.A.X, Z = v.A.Z, FaceX = v.A.FaceX, FaceZ = v.A.FaceZ };
                // a melee attacker runs (or steps) at its target, swings, goes home (FrontArtMelee)
                float swingU = -1f, hop = 0f;
                bool running = false;
                if (v.Melee >= 0)
                {
                    var ms = FrontArtMelee.At(Layout, Layout.Melees[v.Melee], t);
                    if (ms.Active)
                    {
                        pose = new FrontArtWalk.Pose { X = ms.X, Z = ms.Z, FaceX = ms.FaceX, FaceZ = ms.FaceZ, Walking = ms.Moving };
                        running = ms.Moving;
                        if (ms.Swinging) swingU = ms.SwingU;
                    }
                }
                // a figure hit by a blow is pushed back and flashes
                float px, pz, flinch = FrontArtMelee.Flinch(Layout, v.A.Name, t, out px, out pz);
                if (flinch > 0f) { pose.X += px * FrontArtMelee.Knock * flinch; pose.Z += pz * FrontArtMelee.Knock * flinch; }
                if (Mathf.Abs(flinch - v.HitShown) > 1e-3f) { v.HitShown = flinch; v.Mat.SetFloat("_Hit", flinch); }
                // a caster turns to its target and plays its attack while it casts
                float castU = swingU, fx = pose.FaceX, fz = pose.FaceZ;
                foreach (int si in v.Casts)
                {
                    var cs = FrontArtSpells.At(Layout, Layout.Spells[si], t);
                    if (cs.Casting) { castU = cs.CastU; fx = cs.FaceX; fz = cs.FaceZ; break; }
                }
                int dir = FrontArtFacing.Index(fx, fz, yaw);
                bool walking = pose.Walking && v.WalkFrames > 0 && castU < 0f;
                bool attacking = castU >= 0f && v.AttackFrames > 0;
                if (v.Frames > 0)
                {
                    // the pack drawings face right; the three west headings (south-west, west, north-west) show the mirror
                    int side = dir >= 5 ? 1 : 0, key = side + (attacking ? 4 : walking ? 2 : 0);
                    if (key != v.Dir)
                    {
                        v.Dir = key;
                        var pic = attacking ? v.Attack : walking ? v.Walk : v.Strip;
                        var nrm = attacking ? v.AttackN : walking ? v.WalkN : v.StripN;
                        var emit = attacking ? v.AttackE : walking ? v.WalkE : v.StripE;
                        SetPic(v.Mat, pic[side]);
                        v.Mat.SetTexture("_BumpMap", nrm[side] != null ? nrm[side] : Texture2D.normalTexture);
                        v.Mat.SetFloat("_NormalAmount", nrm[side] != null ? 0.85f : 0f);
                        v.Mat.SetTexture("_EmitTex", emit[side] != null ? emit[side] : Texture2D.blackTexture);
                        v.Mat.SetFloat("_EmitAmount", emit[side] != null ? EmitAmount : 0f);
                        SetPic(v.ShadowMat, pic[side]);
                        SetPic(v.CastMat[0], pic[side]);
                        SetPic(v.CastMat[1], pic[side]);
                        v.Frame = -1;
                    }
                    int frames = attacking ? v.AttackFrames : walking ? v.WalkFrames : v.Frames;
                    int frame = attacking ? Mathf.Min(frames - 1, (int)(castU * frames))
                        : (int)Mathf.Repeat(Mathf.Floor(t * (walking ? (running ? RunFps : WalkFps) : PackFps)) + i * 3, frames);
                    if (frame != v.Frame)
                    {
                        v.Frame = frame;
                        SetFrame(v.Mat, frame, frames);
                        SetFrame(v.ShadowMat, frame, frames);
                        SetFrame(v.CastMat[0], frame, frames);
                        SetFrame(v.CastMat[1], frame, frames);
                    }
                }
                else if (dir != v.Dir)
                {
                    v.Dir = dir;
                    SetPic(v.Mat, v.Pics[dir]);
                    if (v.Nrm[dir] != null) v.Mat.SetTexture("_BumpMap", v.Nrm[dir]);
                    v.Mat.SetFloat("_NormalAmount", v.Nrm[dir] != null ? 0.85f : 0f);
                    v.Mat.SetTexture("_EmitTex", v.Emit[dir] != null ? v.Emit[dir] : Texture2D.blackTexture);
                    v.Mat.SetFloat("_EmitAmount", v.Emit[dir] != null ? EmitAmount : 0f);
                    SetPic(v.ShadowMat, v.Pics[dir]);
                    SetPic(v.CastMat[0], v.Pics[dir]);
                    SetPic(v.CastMat[1], v.Pics[dir]);
                }
                float breath = walking ? 1f : 1f + 0.012f * Mathf.Sin(t * 2.1f + i * 1.7f);
                // the four have no walk or attack strips: they hop as they run and lean into the swing
                if (v.Frames == 0 && running) hop = Hop * Mathf.Abs(Mathf.Sin(t * Mathf.PI * 4f));
                if (v.Frames == 0 && swingU >= 0f) { float k = Mathf.Sin(Mathf.PI * Mathf.Clamp01(swingU * 1.6f)); pose.X += fx * 0.12f * k / Mathf.Max(1e-3f, Mathf.Sqrt(fx * fx + fz * fz)); pose.Z += fz * 0.12f * k / Mathf.Max(1e-3f, Mathf.Sqrt(fx * fx + fz * fz)); }
                var pos = new Vector3(pose.X, Layout.GroundY(pose.X, pose.Z) + 0.01f + hop, pose.Z);
                if (v.Blob != null) v.Blob.position = new Vector3(pose.X, pos.y - 0.01f, pose.Z);
                var scale = new Vector3(v.Units, v.Units * breath, 1f);
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
            TickSpells(t, face);
            TickMelees(t, face);
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
                float len = v.Units * Mathf.Clamp(0.55f * dist / h + 0.35f, 0.5f, 1.4f);
                float strength = 0.95f * Mathf.Clamp01(1.15f - dist / Mathf.Max(0.1f, near.S.Range));
                SetCast(v.Cast[0], feet, dist > 0.01f ? away / dist : Vector3.forward, len, v.Units);
                v.CastMat[0].SetFloat("_Strength", strength);
            }
            else v.Cast[0].Clear();
            var flat = new Vector3(sun.x, 0f, sun.z);
            float fl = flat.magnitude;
            float elev = Mathf.Atan2(-sun.y, Mathf.Max(0.01f, fl));
            SetCast(v.Cast[1], feet, fl > 0.01f ? flat / fl : Vector3.forward, v.Units * Mathf.Clamp(0.8f / Mathf.Tan(Mathf.Max(0.2f, elev)), 0.4f, 1.3f), v.Units);
            v.CastMat[1].SetFloat("_Strength", 0.55f);
        }

        static readonly Vector3[] castVerts = new Vector3[4];
        static readonly Vector2[] castUv = { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) };
        static readonly int[] castTris = { 0, 1, 2, 0, 2, 3 };

        /// <summary>How far the ground silhouettes and blobs float over the floor, so they never fight it for depth.</summary>
        const float CastLift = 0.04f;

        /// <summary>How bright the glowing pixels of a picture are, as light added to their colour (past 1 feeds the bloom).</summary>
        const float EmitAmount = 2.2f;

        static void SetCast(Mesh m, Vector3 feet, Vector3 dir, float len, float units)
        {
            var side = Vector3.Cross(Vector3.up, dir) * (units * 0.5f);
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

        /// <summary>The scene's clock, for the screenshot mode.</summary>
        public float Clock => clock;
    }
}
