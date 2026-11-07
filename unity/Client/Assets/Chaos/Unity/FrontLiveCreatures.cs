// Front-art creatures in the live game: every creature of the world (players, monsters, NPCs, summons) drawn as an upright front-facing
// pixel billboard, lit like the front-art scene (Resources/FrontArtSprite.shader), with a contact blob, ground silhouettes, a shadow
// caster, a name and a health bar. FrontLiveView (another file) draws the ground and the things and adds this component to its object
// by reflection; this one reads Cam, TileToWorld, GroundY and World from it and moves on its Ticked event.
//   Look:      Core/FrontLooks.cs: a pack figure for a monster by name, the knight, mage or skeleton for a class, else the outfit's own
//              classic art composed upright (FrontOutfit). Missing art falls back: pack, then the committed skeleton / ghoul pictures, then the outfit.
//   Animation: Core/FrontLiveAnim.cs: smooth steps between tiles, idle / walk / attack clips, facing, a swing when next to a foe, a flinch
//              (pushed back, red flash) when health drops. The server tells no attack or damage events yet (see unity/README.md).
// Pooled: one set of objects per creature on screen, reused.
using System;
using System.Collections.Generic;
using System.Reflection;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace Chaos.Client
{
    public sealed class FrontLiveCreatures : MonoBehaviour
    {
        /// <summary>The id of the creature the local player attacks (0 none): the Game's AttackTarget. Without it a creature fights the foe next to it.</summary>
        public Func<uint> LocalTarget;
        /// <summary>The 32 x 32 RGBA of a sprite id (SpriteAtlas.Raw), for the outfit art. Found by reflection on the view's "Atlas" when unset.</summary>
        public Func<uint, byte[]> SpriteSource;
        public bool ShowLabels = true;
        /// <summary>The shadow of a figure and the blob; off on phones.</summary>
        public bool Silhouettes = true;

        FrontLiveView view;
        bool subscribed;
        float clock;
        int frameId;
        readonly Dictionary<uint, Slot> active = new Dictionary<uint, Slot>();
        readonly Stack<Slot> free = new Stack<Slot>();
        readonly List<Creature> onFloor = new List<Creature>();
        readonly List<uint> gone = new List<uint>();
        readonly Dictionary<string, FrontArtSet> sets = new Dictionary<string, FrontArtSet>();
        readonly Dictionary<ulong, Texture2D> outfitCache = new Dictionary<ulong, Texture2D>();
        readonly List<UnityEngine.Object> owned = new List<UnityEngine.Object>();
        Transform root;
        Mesh quad, blobMesh;
        Shader spriteShader;
        Material blobMat, labelMat;
        Light[] lightCache = new Light[0];
        float nextLightScan;
        Light sunLight;
        bool warnedSource;

        public const int MaxOutfitTextures = 400;
        public const float Hop = 0.09f;
        /// <summary>Colour intensity of the glowing pixels, as in the scene.</summary>
        public const float EmitAmount = 2.2f;

        /// <summary>Creatures drawn in the last tick.</summary>
        public int Drawn { get; private set; }

        sealed class Slot
        {
            public uint Id;
            public GameObject Root;
            public Transform Quad, Proxy, Blob, Label;
            public Material Mat, ShadowMat;
            public readonly Mesh[] Cast = new Mesh[2];
            public readonly Material[] CastMat = new Material[2];
            public MeshRenderer LabelR;
            public Texture2D LabelTex;
            public int LabelKey = int.MinValue;
            public FrontCreatureState State;
            public FrontLook Look;
            public int LookKey;
            public FrontArtSet Set;            // null: the outfit
            public bool HeroArt;               // Set is a hero set (8 directions), not strips
            public float Units;
            public int Seen;
            public int Frame = -1, PicKey = -1;
            public float HitShown = -1f;
            public Texture2D Outfit;
            public float OutW, OutH;
            public int Phase;
        }

        // ---- set up ----------------------------------------------------------------------------------------------------------

        void Awake() { Hook(); }
        void OnEnable() { Hook(); if (root != null) root.gameObject.SetActive(true); }
        void OnDisable() { if (root != null) root.gameObject.SetActive(false); }

        void Hook()
        {
            if (subscribed) return;
            view = GetComponent<FrontLiveView>();
            if (view == null) return;
            view.Ticked += Tick;
            subscribed = true;
            if (SpriteSource == null) SpriteSource = FindSource(view);
        }

        /// <summary>The view's sprite atlas by reflection: a member called Atlas or SpriteAtlas of type SpriteAtlas.</summary>
        static Func<uint, byte[]> FindSource(object o)
        {
            var t = o.GetType();
            const BindingFlags f = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;
            foreach (var n in new[] { "Atlas", "SpriteAtlas", "Sprites" })
            {
                object v = null;
                var fi = t.GetField(n, f); if (fi != null) v = fi.GetValue(o);
                else { var pi = t.GetProperty(n, f); if (pi != null) v = pi.GetValue(o); }
                if (v is SpriteAtlas a) return a.Raw;
            }
            return null;
        }

        void OnDestroy()
        {
            if (subscribed && view != null) view.Ticked -= Tick;
            foreach (var o in owned) if (o != null) Destroy(o);
            foreach (var t in outfitCache.Values) if (t != null) Destroy(t);
            if (root != null) Destroy(root.gameObject);
        }

        T Own<T>(T o) where T : UnityEngine.Object { owned.Add(o); return o; }

        void EnsureShared()
        {
            if (root != null) return;
            root = new GameObject("front creatures").transform;
            root.SetParent(transform, false);
            quad = Own(FrontArtSprites.MakeQuad());
            spriteShader = FrontArtSprites.FindShader("FrontArtSprite", "Unlit/Transparent Cutout");
            // the contact blob: a flat unit quad, radial alpha from the uv (Hd2dBlob)
            blobMesh = Own(new Mesh { name = "front-live-blob" });
            blobMesh.SetVertices(new List<Vector3> { new Vector3(-0.5f, 0, -0.5f), new Vector3(0.5f, 0, -0.5f), new Vector3(0.5f, 0, 0.5f), new Vector3(-0.5f, 0, 0.5f) });
            blobMesh.SetUVs(0, new List<Vector4> { new Vector4(0, 0, 0, 0.9f), new Vector4(1, 0, 0, 0.9f), new Vector4(1, 1, 0, 0.9f), new Vector4(0, 1, 0, 0.9f) });
            blobMesh.SetTriangles(new[] { 0, 3, 2, 0, 2, 1 }, 0);
            blobMesh.bounds = new Bounds(Vector3.zero, new Vector3(1f, 1f, 1f));
            blobMat = Own(new Material(FrontArtSprites.FindShader("Hd2dBlob", "Sprites/Default")) { name = "front-live-blob" });
            labelMat = Own(new Material(Shader.Find("Sprites/Default")) { name = "front-live-label", renderQueue = 3100 });
        }

        Slot NewSlot()
        {
            var s = free.Count > 0 ? free.Pop() : null;
            if (s != null) return s;
            s = new Slot();
            s.Root = new GameObject("creature");
            s.Root.transform.SetParent(root, false);
            var rt = s.Root.transform;
            s.Mat = Own(new Material(spriteShader) { name = "front-live-sprite" });
            s.ShadowMat = Own(new Material(spriteShader) { name = "front-live-shadow" });
            s.Quad = FrontArtSprites.MakeSpriteObject(rt, quad, "sprite", s.Mat, ShadowCastingMode.Off);
            s.Proxy = FrontArtSprites.MakeSpriteObject(rt, quad, "shadow", s.ShadowMat, ShadowCastingMode.ShadowsOnly);
            for (int k = 0; k < 2; k++)
            {
                FrontArtSprites.MakeCastObject(rt, "cast " + k, "front-live-cast-" + k, out Mesh cm, out Material cmat);
                s.Cast[k] = Own(cm); s.CastMat[k] = Own(cmat);
            }
            var bgo = new GameObject("blob");
            bgo.transform.SetParent(rt, false);
            bgo.AddComponent<MeshFilter>().sharedMesh = blobMesh;
            var bmr = bgo.AddComponent<MeshRenderer>();
            bmr.sharedMaterial = blobMat; bmr.shadowCastingMode = ShadowCastingMode.Off; bmr.receiveShadows = false;
            s.Blob = bgo.transform;
            var lm = new Material(labelMat) { name = "front-live-label" };
            Own(lm);
            s.Label = FrontArtSprites.MakeSpriteObject(rt, quad, "label", lm, ShadowCastingMode.Off);
            s.LabelR = s.Label.GetComponent<MeshRenderer>();
            s.LabelR.receiveShadows = false;
            return s;
        }

        void Release(Slot s)
        {
            s.Root.SetActive(false);
            s.State = null; s.Look = null; s.LookKey = 0; s.Set = null; s.Frame = -1; s.PicKey = -1; s.HitShown = -1f; s.Outfit = null; s.LabelKey = int.MinValue;
            free.Push(s);
        }

        FrontArtSet GetSet(string folder, bool pack)
        {
            string key = (pack ? "p:" : "h:") + folder;
            if (!sets.TryGetValue(key, out var s))
            {
                s = FrontArtSet.Load(folder, pack);
                sets[key] = s;
                if (!s.Ok) Debug.Log("chaos front creatures: " + folder + " is not in the build, its creatures use a fallback");
            }
            return s;
        }

        // ---- the look of a creature ------------------------------------------------------------------------------------------

        void Choose(Slot s, Creature c, bool isLocal, int vocation)
        {
            s.Look = FrontLooks.For(c, isLocal, vocation);
            s.Set = null; s.HeroArt = false;
            var l = s.Look;
            if (l.Kind == FlKind.Pack)
            {
                var set = GetSet(l.Folder, true);
                if (set.Ok) { s.Set = set; s.Units = l.Units; }
                else if (l.Alt.Length > 0)
                {
                    var alt = GetSet(l.Alt, false);
                    if (alt.Ok) { s.Set = alt; s.HeroArt = true; s.Units = l.Units >= 1.5f ? FrontLooks.HeroUnits : 1.2f; }
                }
            }
            else if (l.Kind == FlKind.Hero)
            {
                var set = GetSet(l.Folder, false);
                if (set.Ok) { s.Set = set; s.HeroArt = true; s.Units = l.Units; }
            }
            // tint only where the picture is the look's own (a class's hero); a fallback picture stays as drawn
            if (s.Set != null && !s.Set.Pack && l.Kind == FlKind.Hero) s.Mat.SetColor("_Tint", new Color(l.R, l.G, l.B, 1f));
            else s.Mat.SetColor("_Tint", Color.white);
            s.Frame = -1; s.PicKey = -1;
            s.ShadowMat.SetColor("_Tint", Color.white);
        }

        // ---- every frame -----------------------------------------------------------------------------------------------------

        void Tick(float dt)
        {
            if (view == null || view.World == null || view.Cam == null) return;
            EnsureShared();
            clock += dt;
            frameId++;
            var w = view.World;
            var cam = view.Cam;
            int floor = w.Center.Z;
            float yaw = cam.transform.eulerAngles.y;
            var face = Quaternion.Euler(0f, yaw, 0f);
            ScanLights();
            Vector3 sun = SunDirection();
            float sunYaw = Mathf.Atan2(sun.x, sun.z) * Mathf.Rad2Deg;
            var sunFace = Quaternion.Euler(0f, sunYaw, 0f);
            if (outfitCache.Count > MaxOutfitTextures) ClearOutfits();

            // the world's axes: one tile east and one tile south in world space
            var o0 = view.TileToWorld(w.Center.X, w.Center.Y, floor);
            var ex = view.TileToWorld(w.Center.X + 1, w.Center.Y, floor) - o0;
            var ey = view.TileToWorld(w.Center.X, w.Center.Y + 1, floor) - o0;

            onFloor.Clear();
            foreach (var c in w.Creatures.Values) if (c.Position.Z == floor) onFloor.Add(c);
            uint pick = w.PlayerId != 0 && LocalTarget != null ? LocalTarget() : 0;
            int drawn = 0;
            foreach (var c in onFloor)
            {
                bool isLocal = c.Id == w.PlayerId;
                if (!active.TryGetValue(c.Id, out var s))
                {
                    s = NewSlot();
                    s.Id = c.Id; s.State = new FrontCreatureState(c.Id);
                    active[c.Id] = s;
                    s.Root.SetActive(true);
                }
                s.Seen = frameId;
                int key = FrontLooks.KeyOf(c, isLocal, w.PlayerVocation);
                if (s.Look == null || key != s.LookKey) { s.LookKey = key; Choose(s, c, isLocal, w.PlayerVocation); }
                var foe = FrontTargets.Foe(onFloor, c, isLocal ? pick : 0);
                s.State.Update(clock, c, foe);
                if (Draw(s, c, w, yaw, face, sun, sunFace, o0, ex, ey)) drawn++;
            }
            gone.Clear();
            foreach (var kv in active) if (kv.Value.Seen != frameId) gone.Add(kv.Key);
            foreach (var id in gone) { Release(active[id]); active.Remove(id); }
            Drawn = drawn;
        }

        void ScanLights()
        {
            if (Time.unscaledTime < nextLightScan) return;
            nextLightScan = Time.unscaledTime + 0.5f;
            lightCache = FindObjectsOfType<Light>();
            sunLight = null;
            foreach (var l in lightCache) if (l != null && l.type == LightType.Directional && l.enabled) { sunLight = l; break; }
        }

        Vector3 SunDirection()
        {
            if (sunLight != null) return sunLight.transform.forward;
            var m = FrontArtCamera.MoonForward();
            return new Vector3(m.X, m.Y, m.Z);
        }

        bool NearestFlame(Vector3 feet, out Vector3 pos, out float range)
        {
            pos = Vector3.zero; range = 0f;
            float best = float.MaxValue;
            foreach (var l in lightCache)
            {
                if (l == null || !l.enabled || l.type != LightType.Point || l.intensity < 0.2f) continue;
                float d = (l.transform.position - feet).sqrMagnitude;
                if (d < best && d < l.range * l.range) { best = d; pos = l.transform.position; range = l.range; }
            }
            return best < float.MaxValue;
        }

        bool Draw(Slot s, Creature c, World w, float yaw, Quaternion face, Vector3 sun, Quaternion sunFace, Vector3 o0, Vector3 ex, Vector3 ey)
        {
            var st = s.State;
            // where it stands: its tile plus the offset to where the picture is now (a step, a push)
            var tw = view.TileToWorld(c.Position.X, c.Position.Y, c.Position.Z);
            float dx = st.X + st.OffX - c.Position.X, dy = st.Y - st.OffZ - c.Position.Y;
            float px = tw.x + ex.x * dx + ey.x * dy, pz = tw.z + ex.z * dx + ey.z * dy;
            float gy = view.GroundY(c.Position.X, c.Position.Y, c.Position.Z);
            if (st.Walking && (c.WalkFrom.X != c.Position.X || c.WalkFrom.Y != c.Position.Y))
                gy = Mathf.Lerp(view.GroundY(c.WalkFrom.X, c.WalkFrom.Y, c.WalkFrom.Z), gy, st.WalkU);
            bool hop = false;
            Vector3 scale;
            int dirIdx = FrontArtFacing.Index(st.FaceX, st.FaceZ, yaw);
            var set = s.Set;
            if (set != null && s.HeroArt)
            {
                SetHero(s, set, dirIdx);
                scale = new Vector3(s.Units, s.Units, 1f);
                hop = st.Clip == FcClip.Walk;
            }
            else if (set != null)
            {
                SetPack(s, set, st, dirIdx);
                scale = new Vector3(s.Units, s.Units, 1f);
                bool strip = (st.Clip == FcClip.Walk && set.WalkFrames > 0) || (st.Clip == FcClip.Attack && set.AttackFrames > 0);
                hop = st.Clip == FcClip.Walk && !strip;
            }
            else
            {
                if (!SetOutfit(s, c, w, st)) { s.Root.SetActive(false); return false; }
                s.Root.SetActive(true);
                scale = new Vector3(s.OutW, s.OutH, 1f);
                s.Units = Mathf.Max(s.OutW, s.OutH);
            }
            float breath = st.Walking ? 1f : 1f + 0.012f * Mathf.Sin(clock * 2.1f + (c.Id & 15) * 1.7f);
            scale.y *= breath;
            float lift = hop ? Hop * Mathf.Abs(Mathf.Sin(clock * Mathf.PI * 4f)) : 0f;
            var feet = new Vector3(px, gy + 0.01f, pz);
            var pos = feet + Vector3.up * lift;
            s.Quad.SetPositionAndRotation(pos, face);
            s.Quad.localScale = scale;
            if (Silhouettes)
            {
                s.Proxy.gameObject.SetActive(true);
                s.Proxy.SetPositionAndRotation(pos + sun * 0.18f, sunFace);
                s.Proxy.localScale = scale;
                bool flame = NearestFlame(feet, out var fp, out float fr);
                FrontArtSprites.ApplyCast(s.Cast, s.CastMat, feet, s.Units, flame, fp, fr, sun);
                s.Blob.gameObject.SetActive(true);
                float k = s.Units / FrontArtScene.SpriteUnits;
                s.Blob.position = new Vector3(px, gy + FrontArtSprites.CastLift, pz);
                s.Blob.localScale = new Vector3(1.24f * k, 1f, 0.72f * k);
            }
            else { s.Proxy.gameObject.SetActive(false); s.Blob.gameObject.SetActive(false); s.Cast[0].Clear(); s.Cast[1].Clear(); }
            if (Mathf.Abs(st.Flinch - s.HitShown) > 1e-3f) { s.HitShown = st.Flinch; s.Mat.SetFloat("_Hit", st.Flinch); }
            DrawLabel(s, c, feet, scale.y, cam: view.Cam);
            return true;
        }

        // hero pictures: one of 8 directions
        void SetHero(Slot s, FrontArtSet set, int dir)
        {
            if (s.PicKey != dir)
            {
                s.PicKey = dir;
                SetPictures(s, set.Pics[dir], set.Nrm[dir], set.Emit[dir]);
                FrontArtSprites.SetFrame(s.Mat, 0, 1); FrontArtSprites.SetFrame(s.ShadowMat, 0, 1);
                FrontArtSprites.SetFrame(s.CastMat[0], 0, 1); FrontArtSprites.SetFrame(s.CastMat[1], 0, 1);
            }
        }

        // pack figures: strips facing right, mirror strips for the three west headings
        void SetPack(Slot s, FrontArtSet set, FrontCreatureState st, int dir)
        {
            int side = dir >= 5 ? 1 : 0;
            int clip = st.Clip == FcClip.Attack && set.AttackFrames > 0 ? 2 : st.Clip == FcClip.Walk && set.WalkFrames > 0 ? 1 : 0;
            int key = side + clip * 2;
            Texture2D[] pic = clip == 2 ? set.Attack : clip == 1 ? set.Walk : set.Idle;
            Texture2D[] nrm = clip == 2 ? set.AttackN : clip == 1 ? set.WalkN : set.IdleN;
            Texture2D[] emit = clip == 2 ? set.AttackE : clip == 1 ? set.WalkE : set.IdleE;
            if (key != s.PicKey)
            {
                s.PicKey = key;
                SetPictures(s, pic[side], nrm[side], emit[side]);
                s.Frame = -1;
            }
            int frames = clip == 2 ? set.AttackFrames : clip == 1 ? set.WalkFrames : set.IdleFrames;
            int frame = FrontFrames.Index(clip == 2 ? FcClip.Attack : clip == 1 ? FcClip.Walk : FcClip.Idle, frames, clock, st.SwingU, st.StepSeconds, (int)(s.Id % 7) * 3);
            if (frame != s.Frame)
            {
                s.Frame = frame;
                FrontArtSprites.SetFrame(s.Mat, frame, frames); FrontArtSprites.SetFrame(s.ShadowMat, frame, frames);
                FrontArtSprites.SetFrame(s.CastMat[0], frame, frames); FrontArtSprites.SetFrame(s.CastMat[1], frame, frames);
            }
        }

        void SetPictures(Slot s, Texture2D pic, Texture2D nrm, Texture2D emit)
        {
            FrontArtSprites.SetPic(s.Mat, pic);
            s.Mat.SetTexture("_BumpMap", nrm != null ? nrm : Texture2D.normalTexture);
            s.Mat.SetFloat("_NormalAmount", nrm != null ? 0.85f : 0f);
            s.Mat.SetTexture("_EmitTex", emit != null ? emit : Texture2D.blackTexture);
            s.Mat.SetFloat("_EmitAmount", emit != null ? EmitAmount : 0f);
            FrontArtSprites.SetPic(s.ShadowMat, pic);
            FrontArtSprites.SetPic(s.CastMat[0], pic);
            FrontArtSprites.SetPic(s.CastMat[1], pic);
        }

        // the classic art of the outfit, composed (FrontOutfit) and drawn upright with no normal map
        bool SetOutfit(Slot s, Creature c, World w, FrontCreatureState st)
        {
            var type = FrontOutfit.TypeOf(w.Dat, c.Outfit);
            if (type == null) return false;
            if (SpriteSource == null)
            {
                if (!warnedSource) { warnedSource = true; Debug.LogWarning("chaos front creatures: no sprite source for outfit art (set FrontLiveCreatures.SpriteSource)"); }
                return false;
            }
            var o = c.Outfit;
            var dir = FrontLooks.DirOf(st.FaceX, st.FaceZ);
            bool walking = st.Walking && type.Category == ThingCategory.Outfit;
            var g = FrontOutfit.Group(type, walking, st.WalkU, out int phase);
            int pd = FrontOutfit.PatternDir(dir, g.PatternX);
            ulong key = FrontOutfit.Key(type, o, pd, phase) ^ (walking ? 0x5555UL : 0UL);
            if (!outfitCache.TryGetValue(key, out var tex) || tex == null)
            {
                var rgba = FrontOutfit.Compose(type, o, dir, walking, st.WalkU, SpriteSource, out int cw, out int ch);
                if (rgba == null) return false;
                int tw = cw * FrontOutfit.Cell, th = ch * FrontOutfit.Cell;
                var flip = new byte[rgba.Length];
                for (int row = 0; row < th; row++) Buffer.BlockCopy(rgba, row * tw * 4, flip, (th - 1 - row) * tw * 4, tw * 4);
                tex = new Texture2D(tw, th, TextureFormat.RGBA32, false) { name = "front-live-outfit", filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp, anisoLevel = 0 };
                tex.LoadRawTextureData(flip);
                tex.Apply(false, false);
                outfitCache[key] = tex;
            }
            if (s.Outfit != tex)
            {
                s.Outfit = tex;
                s.OutW = tex.width / (float)FrontOutfit.Cell; s.OutH = tex.height / (float)FrontOutfit.Cell;
                s.Mat.SetColor("_Tint", Color.white);
                SetPictures(s, tex, null, null);
                FrontArtSprites.SetFrame(s.Mat, 0, 1); FrontArtSprites.SetFrame(s.ShadowMat, 0, 1);
                FrontArtSprites.SetFrame(s.CastMat[0], 0, 1); FrontArtSprites.SetFrame(s.CastMat[1], 0, 1);
            }
            return true;
        }

        void ClearOutfits()
        {
            foreach (var t in outfitCache.Values) if (t != null) Destroy(t);
            outfitCache.Clear();
            foreach (var s in active.Values) s.Outfit = null;
        }

        // ---- name and health bar ---------------------------------------------------------------------------------------------

        void DrawLabel(Slot s, Creature c, Vector3 feet, float height, Camera cam)
        {
            if (!ShowLabels || string.IsNullOrEmpty(c.Name) && c.Type == 2) { s.Label.gameObject.SetActive(false); return; }
            bool bar = c.Type != 2;
            int hp = Mathf.Clamp(c.HealthPercent, 0, 100);
            int key = FrontLooks.KeyOf(c, false, 0) * 31 + hp * 2 + (bar ? 1 : 0);
            if (key != s.LabelKey)
            {
                s.LabelKey = key;
                var px = FrontLabel.Pixels(c.Name, hp, bar, out int w, out int h);
                if (s.LabelTex == null || s.LabelTex.width != w || s.LabelTex.height != h)
                {
                    if (s.LabelTex != null) Destroy(s.LabelTex);
                    s.LabelTex = new Texture2D(w, h, TextureFormat.RGBA32, false) { name = "front-live-label", filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
                    s.LabelR.sharedMaterial.mainTexture = s.LabelTex;
                }
                s.LabelTex.LoadRawTextureData(px);
                s.LabelTex.Apply(false, false);
                s.Label.localScale = new Vector3(w * FrontLabel.Texel, h * FrontLabel.Texel, 1f);
            }
            s.Label.gameObject.SetActive(true);
            // above the head (the picture's top margin is empty), turned to the camera, a little toward it so a wall never hides it
            var toCam = cam != null ? -cam.transform.forward : Vector3.back;
            s.Label.SetPositionAndRotation(feet + Vector3.up * (height * 0.92f + 0.05f) + toCam * 0.3f, Quaternion.Euler(0f, cam != null ? cam.transform.eulerAngles.y : 0f, 0f));
        }
    }
}
