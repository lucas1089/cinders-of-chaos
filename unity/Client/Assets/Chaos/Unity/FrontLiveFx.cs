// Live combat effects of the front-art view (track C of the front-art game): the missiles, impact bursts, melee slashes, floating damage
// numbers and light flashes of what the server sends, drawn over FrontLiveView in the front-art look. FrontLiveView adds this component
// (by reflection) and we read from it: Cam, World, TileToWorld(x, y, z), GroundY(x, y, z) and the Ticked event.
// What happens: World.Fx (Core/FrontFx.cs) is switched on, the parser queues magic effects (0x83), distance shots (0x85), animated text
// (0x84) and damage / heal / experience messages (0xB4); each tick the queue goes to FrontFxDirector (Core, tested), which says what is
// alive; this file only draws that, in pooled quads (premultiplied shader Resources/FrontArtSpell, camera facing, one material per
// picture, tint and frame by a MaterialPropertyBlock) and a few point lights (at most MaxLights).
// Art: a missile uses the projectile sheet Resources/FrontArt/fx_<kind>/missile (8 direction rows of 8 frames, only in CI after the
// encrypted packs are opened) and falls back to a drawn comet; impacts, slashes and numbers are always drawn in code (Core/FrontFxArt.cs).
// A tile is not assumed to be one unit: sizes scale with the distance between two neighbouring tiles' world points.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace Chaos.Client
{
    public sealed class FrontLiveFx : MonoBehaviour
    {
        public const int MaxLights = 6;
        public const float MissileFps = 14f;
        public const float TexelTiles = 0.06f;        // a font texel, in tiles
        const int NumberSlotW = 80, NumberSlotH = 16;  // 12 characters of the font and the margin fit

        FrontLiveView view;
        readonly FrontFxDirector director = new FrontFxDirector();
        /// <summary>What the effects are doing (FrontLiveCreatures reads the slashes to swing the attacker).</summary>
        public FrontFxDirector Director => director;
        readonly List<FxLight> lightBuf = new List<FxLight>();
        Shader shader;
        Mesh quad;
        readonly List<UnityEngine.Object> owned = new List<UnityEngine.Object>();
        readonly Dictionary<Texture, Material> mats = new Dictionary<Texture, Material>();
        readonly Dictionary<FxElement, Texture2D> impacts = new Dictionary<FxElement, Texture2D>();
        readonly Dictionary<FxElement, Texture2D> comets = new Dictionary<FxElement, Texture2D>();
        readonly Dictionary<FxElement, Texture2D> slashes = new Dictionary<FxElement, Texture2D>();
        readonly Dictionary<string, Texture2D> missileArt = new Dictionary<string, Texture2D>();
        MaterialPropertyBlock block;
        World subscribed;
        bool hooked;

        sealed class Q
        {
            public Transform T; public MeshRenderer R;
        }
        readonly List<Q> missileQ = new List<Q>(), burstQ = new List<Q>(), slashQ = new List<Q>(), numberQ = new List<Q>();
        readonly List<Texture2D> numberTex = new List<Texture2D>();
        readonly List<int> numberItem = new List<int>();
        readonly List<int> numberW = new List<int>(), numberH = new List<int>();
        readonly List<Light> lights = new List<Light>();

        // ---- setup ----

        void Start()
        {
            view = GetComponent<FrontLiveView>();
            if (view == null) { Debug.LogError("chaos front fx: no FrontLiveView beside the effects"); enabled = false; return; }
            shader = Resources.Load<Shader>("FrontArtSpell");
            if (shader == null) shader = Shader.Find("Chaos/FrontArtSpell");
            if (shader == null) shader = Shader.Find("Sprites/Default");
            block = new MaterialPropertyBlock();
            quad = Own(new Mesh { name = "front-live-fx-quad" });
            quad.vertices = new[] { new Vector3(-0.5f, -0.5f, 0), new Vector3(0.5f, -0.5f, 0), new Vector3(0.5f, 0.5f, 0), new Vector3(-0.5f, 0.5f, 0) };
            quad.uv = new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) };
            quad.triangles = new[] { 0, 3, 2, 0, 2, 1 };
            quad.bounds = new Bounds(Vector3.zero, new Vector3(4f, 4f, 0.4f));
            for (int i = 0; i < MaxLights; i++)
            {
                var go = new GameObject("fx light " + i);
                go.transform.SetParent(transform, false);
                var l = go.AddComponent<Light>();
                l.type = LightType.Point; l.shadows = LightShadows.None; l.range = 3f; l.enabled = false;
                lights.Add(l);
            }
            view.Ticked += OnTick;
            hooked = true;
        }

        void OnDisable()
        {
            if (subscribed != null) { subscribed.Fx.Enabled = false; subscribed.Fx.Clear(); subscribed = null; }
        }

        void OnDestroy()
        {
            if (hooked && view != null) view.Ticked -= OnTick;
            OnDisable();
            foreach (var o in owned) if (o != null) Destroy(o);
            owned.Clear();
        }

        T Own<T>(T o) where T : UnityEngine.Object { owned.Add(o); return o; }

        static Texture2D Point(Texture2D t)
        {
            if (t != null) { t.filterMode = FilterMode.Point; t.wrapMode = TextureWrapMode.Clamp; t.anisoLevel = 0; }
            return t;
        }

        Texture2D MakeTex(string name, byte[] rgba, int w, int h)
        {
            var t = Own(new Texture2D(w, h, TextureFormat.RGBA32, false) { name = name });
            t.LoadRawTextureData(rgba);
            t.Apply(false, false);
            return Point(t);
        }

        Material MatFor(Texture tex)
        {
            Material m;
            if (!mats.TryGetValue(tex, out m))
            {
                m = Own(new Material(shader) { name = "front-live-fx-" + tex.name, mainTexture = tex });
                mats[tex] = m;
            }
            return m;
        }

        Q NewQ(string name)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            go.AddComponent<MeshFilter>().sharedMesh = quad;
            var mr = go.AddComponent<MeshRenderer>();
            mr.shadowCastingMode = ShadowCastingMode.Off;
            mr.receiveShadows = false;
            mr.lightProbeUsage = LightProbeUsage.Off;
            mr.reflectionProbeUsage = ReflectionProbeUsage.Off;
            mr.enabled = false;
            return new Q { T = go.transform, R = mr };
        }

        Q Slot(List<Q> pool, int i, string name)
        {
            while (pool.Count <= i) pool.Add(NewQ(name + " " + pool.Count));
            return pool[i];
        }

        static void HideFrom(List<Q> pool, int from)
        {
            for (int i = from; i < pool.Count; i++) pool[i].R.enabled = false;
        }

        // ---- pictures ----

        Texture2D Impact(FxElement e)
        {
            Texture2D t;
            if (!impacts.TryGetValue(e, out t))
            {
                int s = FrontFxArt.ImpactSize;
                t = MakeTex("fx-impact-" + e, FrontFxArt.ImpactStrip(FrontFx.Palette(e), e == FxElement.Heal), s * FrontFxTiming.BurstFrames, s);
                impacts[e] = t;
            }
            return t;
        }

        Texture2D Comet(FxElement e)
        {
            Texture2D t;
            if (!comets.TryGetValue(e, out t))
            {
                t = MakeTex("fx-comet-" + e, FrontFxArt.CometStrip(FrontFx.Palette(e)), FrontFxArt.CometSize * FrontFxArt.CometFrames, FrontFxArt.CometSize);
                comets[e] = t;
            }
            return t;
        }

        Texture2D Slash(FxElement e)
        {
            Texture2D t;
            if (!slashes.TryGetValue(e, out t))
            {
                var p = FrontFx.Palette(e);
                t = MakeTex("fx-slash-" + e, FrontArtSlash.Pixels(p.BR, p.BG, p.BB), FrontArtSlash.Size * FrontArtSlash.Frames, FrontArtSlash.Size);
                slashes[e] = t;
            }
            return t;
        }

        /// <summary>The projectile sheet of a missile kind, or null (the sheets are only there after the packs are opened).</summary>
        Texture2D MissileArt(string kind)
        {
            Texture2D t;
            if (!missileArt.TryGetValue(kind, out t))
            {
                t = Point(Resources.Load<Texture2D>("FrontArt/fx_" + kind + "/missile"));
                missileArt[kind] = t;
            }
            return t;
        }

        // ---- the tick ----

        float tile = 1f;

        Vector3 Where(Pos p, float heightTiles)
        {
            var v = view.TileToWorld(p.X, p.Y, p.Z);
            v.y = view.GroundY(p.X, p.Y, p.Z) + heightTiles * tile;
            return v;
        }

        void Set(Q q, Material m, Vector3 at, Quaternion rot, Vector2 size, Vector4 st, Color tint)
        {
            q.T.SetPositionAndRotation(at, rot);
            q.T.localScale = new Vector3(size.x, size.y, 1f);
            q.R.sharedMaterial = m;
            block.Clear();
            block.SetVector("_MainTex_ST", st);
            block.SetColor("_Tint", tint * VisualRuntime.EffectAlpha);   // the spell effect opacity option (game_effectopacity)
            q.R.SetPropertyBlock(block);
            q.R.enabled = true;
        }

        void OnTick(float dt)
        {
            var world = view.World;
            var cam = view.Cam;
            if (world == null || cam == null) return;
            if (subscribed != world)
            {
                if (subscribed != null) subscribed.Fx.Enabled = false;
                subscribed = world;
                world.Fx.Enabled = true;
                director.Clear();
            }
            director.Scatter.Settings = ScatterPrefs.Current;
            director.Update(Time.unscaledTime);
            FxEvent e;
            while (world.Fx.TryDequeue(out e)) director.Feed(world, e);

            var c = world.Center;
            var a = view.TileToWorld(c.X, c.Y, c.Z);
            float tl = (view.TileToWorld(c.X + 1, c.Y, c.Z) - a).magnitude;
            tile = tl > 1e-4f ? tl : 1f;
            Quaternion face = cam.transform.rotation;
            Vector3 right = cam.transform.right, up = cam.transform.up;
            float now = director.Now;
            int floor = c.Z;

            DrawMissiles(now, floor, face, right, up);
            DrawBursts(now, floor, face);
            DrawSlashes(now, floor, face, right);
            DrawNumbers(now, floor, face, right);
            DrawLights(floor);
        }

        void DrawMissiles(float now, int floor, Quaternion face, Vector3 right, Vector3 up)
        {
            int n = 0;
            foreach (var m in director.Missiles)
            {
                float u = m.U(now);
                if (u < 0f || u > 1f || m.From.Z != floor) continue;
                var from = Where(m.From, 0.5f); var to = Where(m.To, 0.5f);
                var at = Vector3.Lerp(from, to, u) + Vector3.up * (FrontFxTiming.Arc(m.Tiles, u) * tile);
                var d = to - from;
                float sx = Vector3.Dot(d, right), sy = Vector3.Dot(d, up);
                var look = FrontFx.MissileLook(m.El);
                var art = MissileArt(look.Kind);
                var q = Slot(missileQ, n++, "missile");
                if (art != null)
                {
                    float deg = Mathf.Atan2(-sy, sx) * Mathf.Rad2Deg;   // clockwise from east on screen: the sheet's rows are E, SE, S, SW, W, NW, N, NE
                    int row = ((Mathf.RoundToInt(deg / 45f) % 8) + 8) % 8;
                    int frame = (int)Mathf.Repeat(Mathf.Floor(now * MissileFps + m.Id), 8f);
                    Set(q, MatFor(art), at, face, new Vector2(1.2f * tile, 1.2f * tile), new Vector4(1f / 8f, 1f / 8f, frame / 8f, 1f - (row + 1) / 8f), new Color(look.R, look.G, look.B, 1f));
                }
                else
                {
                    float ang = Mathf.Atan2(sy, sx) * Mathf.Rad2Deg;     // counter-clockwise from east: the comet is drawn heading east
                    int frame = (int)Mathf.Repeat(Mathf.Floor(now * MissileFps + m.Id), FrontFxArt.CometFrames);
                    Set(q, MatFor(Comet(m.El)), at, face * Quaternion.Euler(0f, 0f, ang), new Vector2(1.1f * tile, 1.1f * tile), new Vector4(1f / FrontFxArt.CometFrames, 1f, (float)frame / FrontFxArt.CometFrames, 0f), Color.white);
                }
            }
            HideFrom(missileQ, n);
        }

        void DrawBursts(float now, int floor, Quaternion face)
        {
            int n = 0;
            foreach (var b in director.Bursts)
            {
                float u = b.U(now);
                if (u < 0f || u > 1f || b.At.Z != floor) continue;
                int frame = FrontFxTiming.BurstFrame(u);
                var q = Slot(burstQ, n++, "burst");
                float size = (b.Heal ? 1.3f : 1.7f) * b.Scale * tile;
                Set(q, MatFor(Impact(b.El)), Where(b.At, 0.5f), face, new Vector2(size, size), new Vector4(1f / FrontFxTiming.BurstFrames, 1f, (float)frame / FrontFxTiming.BurstFrames, 0f), Color.white);
            }
            HideFrom(burstQ, n);
        }

        void DrawSlashes(float now, int floor, Quaternion face, Vector3 right)
        {
            int n = 0;
            foreach (var s in director.Slashes)
            {
                float u = s.U(now);
                if (u < 0f || u > 1f || s.To.Z != floor) continue;
                var from = Where(s.From, 0.55f); var to = Where(s.To, 0.55f);
                bool left = Vector3.Dot(to - from, right) < 0f;
                int frame = FrontFxTiming.SlashFrame(u);
                var q = Slot(slashQ, n++, "slash");
                float size = 1.4f * tile;
                float f = FrontArtSlash.Frames;
                Set(q, MatFor(Slash(s.El)), Vector3.Lerp(from, to, 0.65f), face, new Vector2(size, size), new Vector4((left ? -1f : 1f) / f, 1f, (left ? frame + 1 : frame) / f, 0f), Color.white);
            }
            HideFrom(slashQ, n);
        }

        // ---- floating numbers ----

        int NumberSlotFor(FxNumberItem item, HashSet<int> live)
        {
            for (int i = 0; i < numberItem.Count; i++) if (numberItem[i] == item.Id) return i;
            int slot = -1;
            for (int i = 0; i < numberItem.Count; i++) if (!live.Contains(numberItem[i])) { slot = i; break; }
            if (slot < 0)
            {
                slot = numberItem.Count;
                numberItem.Add(0); numberW.Add(0); numberH.Add(0);
                var t = Own(new Texture2D(NumberSlotW, NumberSlotH, TextureFormat.RGBA32, false) { name = "fx-number-" + slot });
                numberTex.Add(Point(t));
            }
            var p = FrontFx.Palette(item.El);
            float k = 0.45f;   // the fill leans to the hot colour so a small number stays readable
            int pw, ph;
            var px = FrontFxArt.NumberPixels(item.Text, Mathf.Lerp(p.BR, p.CR, k), Mathf.Lerp(p.BG, p.CG, k), Mathf.Lerp(p.BB, p.CB, k), p.RR * 0.4f, p.RG * 0.4f, p.RB * 0.4f, out pw, out ph);
            int w = Mathf.Min(pw, NumberSlotW), h = Mathf.Min(ph, NumberSlotH);
            var full = new byte[NumberSlotW * NumberSlotH * 4];
            for (int y = 0; y < h; y++) Buffer.BlockCopy(px, y * pw * 4, full, y * NumberSlotW * 4, w * 4);
            numberTex[slot].LoadRawTextureData(full);
            numberTex[slot].Apply(false, false);
            numberItem[slot] = item.Id; numberW[slot] = w; numberH[slot] = h;
            return slot;
        }

        void DrawNumbers(float now, int floor, Quaternion face, Vector3 right)
        {
            var live = new HashSet<int>();
            foreach (var item in director.Numbers) live.Add(item.Id);
            int n = 0;
            foreach (var item in director.Numbers)
            {
                float u = item.U(now);
                if (u < 0f || u > 1f || item.At.Z != floor) continue;
                int slot = NumberSlotFor(item, live);
                var q = Slot(numberQ, n++, "number");
                float rise = FrontFxTiming.NumberRiseAt(u) + FrontFxTiming.NumberHeight + item.Stack * 0.4f;
                float side = (item.Stack % 2 == 0 ? 1f : -1f) * ((item.Stack + 1) / 2) * 0.25f + ((item.Id * 37) % 7 - 3) * 0.04f;
                Pos spot = item.At;
                // a typed number belongs to a creature and follows it (its tile; the creature may have moved since the hit)
                Creature owner;
                if (item.Creature != 0 && subscribed != null && subscribed.Creatures.TryGetValue(item.Creature, out owner) && owner.Position.Z == floor) spot = owner.Position;
                // the scatter (DamageScatter.cs): a shift in pixels (32 px a tile), the drift over the life, the rise scaled to the roll (the stock rise is 48 px)
                if (item.Scattered)
                {
                    side += item.Dx / 32f + item.Sx / 32f * FrontFxTiming.Clamp01(u);
                    rise += -item.Dy / 32f + (-item.Sy - 48f) / 32f * FrontFxTiming.Clamp01(u);
                }
                var at = Where(spot, 0f) + Vector3.up * (rise * tile) + right * (side * tile);
                float scale = FrontFxTiming.NumberScale(u) * item.Size * TexelTiles * tile;
                float w = numberW[slot], h = numberH[slot];
                Set(q, MatFor(numberTex[slot]), at, face, new Vector2(w * scale, h * scale),
                    new Vector4(w / NumberSlotW, h / NumberSlotH, 0f, 0f), new Color(1f, 1f, 1f, FrontFxTiming.NumberAlpha(u)));
            }
            HideFrom(numberQ, n);
        }

        // ---- lights ----

        void DrawLights(int floor)
        {
            director.Lights(lightBuf, MaxLights);
            int n = 0;
            foreach (var l in lightBuf)
            {
                if (l.At.Z != floor) continue;
                var li = lights[n++];
                var p = Vector3.Lerp(Where(l.At, l.Height), Where(l.To, l.Height), l.U);
                li.transform.position = p;
                li.color = new Color(l.R, l.G, l.B);
                li.intensity = l.Intensity;
                li.range = 3.2f * tile;
                li.enabled = true;
            }
            for (int i = n; i < lights.Count; i++) lights[i].enabled = false;
        }
    }
}
