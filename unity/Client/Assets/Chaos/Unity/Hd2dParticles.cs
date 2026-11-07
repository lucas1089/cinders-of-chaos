// Life in the air and fire of the HD-2D view (O432): slow dust motes around the focus, embers rising from every flame light
// and a soft additive halo on every light. Own CPU particles drawn as one dynamic mesh of camera-facing quads (shader
// Resources/Hd2dGlow, texture made in code): deterministic (fixed seed, own time), no frame needed once Prewarm and
// BuildMesh ran, which is how the CI screenshot gets them. The flicker maths is Hd2d.Flicker (Core).
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace Chaos.Client
{
    public sealed class Hd2dParticles : MonoBehaviour
    {
        public Camera Cam;
        public const int Motes = 60, EmbersPerLight = 12, MaxLights = 8;

        struct P { public Vector3 Pos, Vel; public float Age, Life, Size, Phase; }

        readonly List<Hd2dLight> lights = new List<Hd2dLight>();
        Vec3 focus;
        readonly System.Random rng = new System.Random(1432);
        P[] motes, embers;
        float time;
        bool ready;
        Mesh mesh;
        Material material;
        Texture2D glow;
        MeshRenderer meshRenderer;
        readonly List<Vector3> V = new List<Vector3>();
        readonly List<Color> C = new List<Color>();
        readonly List<Vector2> UV = new List<Vector2>();
        readonly List<int> T = new List<int>();

        public int MoteCount => Hd2dView.LowQuality ? Motes / 2 : Motes;
        public int EmberCount => Hd2dView.LowQuality ? EmbersPerLight / 2 : EmbersPerLight;
        public int QuadCount => V.Count / 4;

        float R() { return (float)rng.NextDouble(); }

        void Init()
        {
            if (ready) return;
            ready = true;
            motes = new P[Motes];
            embers = new P[MaxLights * EmbersPerLight];
            for (int i = 0; i < motes.Length; i++) motes[i] = NewMote();
            for (int i = 0; i < embers.Length; i++) { embers[i].Age = 1f; embers[i].Life = 1f; }   // dead until its light is a flame
            glow = new Texture2D(32, 32, TextureFormat.RGBA32, false) { name = "chaos-hd2d-glow", wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            for (int y = 0; y < 32; y++)
                for (int x = 0; x < 32; x++)
                {
                    float dx = (x + 0.5f - 16f) / 16f, dy = (y + 0.5f - 16f) / 16f;
                    float d = Mathf.Clamp01(1f - Mathf.Sqrt(dx * dx + dy * dy));
                    float g = d * d * (3f - 2f * d);
                    glow.SetPixel(x, y, new Color(g, g, g, g));
                }
            glow.Apply();
            var shader = Resources.Load<Shader>("Hd2dGlow");
            if (shader == null) shader = Shader.Find("Chaos/Hd2dGlow");
            if (shader == null) shader = Shader.Find("Legacy Shaders/Particles/Additive");
            if (shader == null) shader = Shader.Find("Sprites/Default");
            material = new Material(shader) { name = "chaos-hd2d-glow", mainTexture = glow };
            mesh = new Mesh { name = "chaos-hd2d-particles" };
            mesh.MarkDynamic();
            var mf = gameObject.GetComponent<MeshFilter>();
            if (mf == null) mf = gameObject.AddComponent<MeshFilter>();
            mf.sharedMesh = mesh;
            meshRenderer = gameObject.GetComponent<MeshRenderer>();
            if (meshRenderer == null) meshRenderer = gameObject.AddComponent<MeshRenderer>();
            meshRenderer.sharedMaterial = material;
            meshRenderer.shadowCastingMode = ShadowCastingMode.Off;
            meshRenderer.receiveShadows = false;
            meshRenderer.lightProbeUsage = LightProbeUsage.Off;
            meshRenderer.reflectionProbeUsage = ReflectionProbeUsage.Off;
        }

        void Awake() { Init(); }
        void OnEnable() { Init(); meshRenderer.enabled = true; }
        void OnDisable() { if (meshRenderer != null) meshRenderer.enabled = false; }
        void OnDestroy()
        {
            if (mesh != null) Destroy(mesh);
            if (material != null) Destroy(material);
            if (glow != null) Destroy(glow);
        }

        P NewMote()
        {
            return new P
            {
                Pos = new Vector3(focus.X + (R() - 0.5f) * 16f, 0.3f + R() * 3.2f, focus.Z + (R() - 0.5f) * 12f),
                Vel = new Vector3((R() - 0.5f) * 0.12f, (R() - 0.5f) * 0.05f, (R() - 0.5f) * 0.12f),
                Age = 0f, Life = 1f, Size = 0.04f + R() * 0.05f, Phase = R() * 6.2832f,
            };
        }

        void SpawnEmber(int slot, bool aged)
        {
            var l = lights[slot / EmbersPerLight];
            var e = new P
            {
                Pos = new Vector3(l.Position.X + (R() - 0.5f) * 0.25f, l.Position.Y + R() * 0.1f, l.Position.Z + (R() - 0.5f) * 0.25f),
                Vel = new Vector3((R() - 0.5f) * 0.25f, 0.45f + R() * 0.6f, (R() - 0.5f) * 0.25f),
                Age = 0f, Life = 1.2f + R() * 1.6f, Size = 0.035f + R() * 0.03f, Phase = R() * 6.2832f,
            };
            if (aged) { e.Age = R() * e.Life; e.Pos += e.Vel * e.Age; }
            embers[slot] = e;
        }

        /// <summary>The lights to decorate (the same list the view lights the scene with) and the point the motes gather around.</summary>
        public void SetLights(List<Hd2dLight> list, Vec3 focusPoint)
        {
            Init();
            lights.Clear();
            if (list != null) for (int i = 0; i < list.Count && i < MaxLights; i++) lights.Add(list[i]);
            focus = focusPoint;
        }

        void Update() { Step(Time.deltaTime); }
        void LateUpdate() { BuildMesh(); }

        /// <summary>Advances every particle by dt seconds.</summary>
        public void Step(float dt)
        {
            Init();
            if (dt <= 0f) return;
            time += dt;
            int nm = MoteCount;
            for (int i = 0; i < nm; i++)
            {
                var m = motes[i];
                m.Pos += (m.Vel + new Vector3(Mathf.Sin(time * 0.35f + m.Phase), Mathf.Sin(time * 0.5f + m.Phase * 2f) * 0.3f, Mathf.Cos(time * 0.3f + m.Phase)) * 0.05f) * dt;
                // keep them in a box around the focus: leave on one side, come back on the other
                m.Pos.x = Wrap(m.Pos.x, focus.X, 8f);
                m.Pos.z = Wrap(m.Pos.z, focus.Z, 6f);
                if (m.Pos.y < 0.2f) m.Pos.y = 3.5f; else if (m.Pos.y > 3.6f) m.Pos.y = 0.3f;
                motes[i] = m;
            }
            int ne = EmberCount;
            for (int li = 0; li < MaxLights; li++)
            {
                bool on = li < lights.Count && Hd2d.IsFlame(lights[li]);
                for (int k = 0; k < EmbersPerLight; k++)
                {
                    int s = li * EmbersPerLight + k;
                    if (!on || k >= ne) { embers[s].Age = 1f; embers[s].Life = 1f; continue; }
                    var e = embers[s];
                    if (e.Age >= e.Life) { SpawnEmber(s, true); continue; }
                    e.Age += dt;
                    e.Pos += e.Vel * dt + new Vector3(Mathf.Sin(time * 3f + e.Phase), 0f, Mathf.Cos(time * 2.4f + e.Phase)) * 0.12f * dt;
                    e.Vel.y *= 1f - 0.15f * dt;
                    embers[s] = e;
                }
            }
        }

        static float Wrap(float v, float center, float half)
        {
            float d = v - center;
            d = Mathf.Repeat(d + half, 2f * half) - half;
            return center + d;
        }

        /// <summary>Steps many times so a still picture shows a filled scene (no frames needed).</summary>
        public void Prewarm(float seconds)
        {
            Init();
            for (float t = 0f; t < seconds; t += 1f / 30f) Step(1f / 30f);
        }

        void Quad(Vector3 c, float half, Color col, Vector3 right, Vector3 up)
        {
            int i = V.Count;
            V.Add(c - right * half - up * half); V.Add(c + right * half - up * half);
            V.Add(c + right * half + up * half); V.Add(c - right * half + up * half);
            for (int k = 0; k < 4; k++) C.Add(col);
            UV.Add(new Vector2(0, 0)); UV.Add(new Vector2(1, 0)); UV.Add(new Vector2(1, 1)); UV.Add(new Vector2(0, 1));
            T.Add(i); T.Add(i + 2); T.Add(i + 1); T.Add(i); T.Add(i + 3); T.Add(i + 2);
        }

        /// <summary>Builds the quad mesh for the current state facing the camera (LateUpdate, or the screenshot mode by hand).</summary>
        public void BuildMesh()
        {
            Init();
            V.Clear(); C.Clear(); UV.Clear(); T.Clear();
            var cam = Cam != null ? Cam : Camera.main;
            Vector3 right = cam != null ? cam.transform.right : Vector3.right, up = cam != null ? cam.transform.up : Vector3.up;
            Vector3 toCam = cam != null ? -cam.transform.forward * 0.15f : Vector3.zero;
            for (int li = 0; li < lights.Count; li++)
            {
                var l = lights[li];
                float f = Hd2d.Flicker(time, li + 1);
                float k = Hd2d.IsFlame(l) ? 0.5f : 0.2f;
                float half = Mathf.Clamp(l.Range * 0.18f, 0.5f, 1.4f) * (0.95f + 0.5f * (f - 1f));
                Quad(new Vector3(l.Position.X, l.Position.Y, l.Position.Z) + toCam, half, new Color(l.R, l.G, l.B, k * f * Mathf.Min(1.5f, l.Intensity)), right, up);
            }
            int nm = MoteCount;
            for (int i = 0; i < nm; i++)
            {
                var m = motes[i];
                float a = 0.10f + 0.10f * Mathf.Sin(time * 0.9f + m.Phase);
                Quad(m.Pos, m.Size, new Color(0.85f, 0.85f, 0.95f, a), right, up);
            }
            for (int li = 0; li < lights.Count; li++)
            {
                if (!Hd2d.IsFlame(lights[li])) continue;
                for (int k = 0; k < EmberCount; k++)
                {
                    var e = embers[li * EmbersPerLight + k];
                    if (e.Age >= e.Life) continue;
                    float u = e.Age / e.Life;
                    float fade = Mathf.Min(1f, u * 8f) * (1f - u);
                    var col = Color.Lerp(new Color(1f, 0.75f, 0.3f), new Color(1f, 0.25f, 0.05f), u);
                    col.a = 0.9f * fade;
                    Quad(e.Pos, e.Size * (1f - 0.4f * u), col, right, up);
                }
            }
            mesh.Clear();
            if (V.Count == 0) return;
            mesh.SetVertices(V);
            mesh.SetColors(C);
            mesh.SetUVs(0, UV);
            mesh.SetTriangles(T, 0);
            mesh.bounds = new Bounds(new Vector3(focus.X, 2f, focus.Z), new Vector3(60f, 20f, 60f));
        }
    }
}
