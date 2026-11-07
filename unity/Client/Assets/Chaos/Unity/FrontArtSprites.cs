// Shared pieces of the front-art look (Unity/FrontArtScene.cs, the diorama, and Unity/FrontLiveCreatures.cs, the live game): the shader
// lookup, point filtered pictures, the strip frame of a material, the upright quad that turns with the camera's yaw, and the ground
// silhouettes (one stretched away from the nearest flame, one away from the moon) that stand in for a shadow map.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace Chaos.Client
{
    public static class FrontArtSprites
    {
        public const string Folder = "FrontArt/";
        /// <summary>How far the ground silhouettes and blobs float over the floor, so they never fight it for depth.</summary>
        public const float CastLift = 0.04f;

        public static Shader FindShader(string name, string fallback)
        {
            var sh = Resources.Load<Shader>(name);
            if (sh == null) sh = Shader.Find("Chaos/" + name);
            if (sh == null) sh = Shader.Find(fallback);
            return sh;
        }

        public static Texture2D Point(Texture2D t)
        {
            if (t != null) { t.filterMode = FilterMode.Point; t.wrapMode = TextureWrapMode.Clamp; t.anisoLevel = 0; }
            return t;
        }

        /// <summary>Shows frame `frame` of `frames` side by side on a material (texture scale and offset).</summary>
        public static void SetFrame(Material m, int frame, int frames)
        {
            m.mainTextureScale = new Vector2(1f / frames, 1f);
            m.mainTextureOffset = new Vector2((float)frame / frames, 0f);
        }

        public static void SetPic(Material m, Texture2D t)
        {
            m.mainTexture = t;
            if (m.HasProperty("_Cutoff")) m.SetFloat("_Cutoff", 0.5f);
        }

        /// <summary>A unit quad standing on its bottom middle, facing -z (the camera side).</summary>
        public static Mesh MakeQuad()
        {
            var q = new Mesh { name = "front-art-quad" };
            q.vertices = new[] { new Vector3(-0.5f, 0, 0), new Vector3(0.5f, 0, 0), new Vector3(0.5f, 1, 0), new Vector3(-0.5f, 1, 0) };
            q.normals = new[] { new Vector3(0, 0, -1), new Vector3(0, 0, -1), new Vector3(0, 0, -1), new Vector3(0, 0, -1) };
            q.uv = new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) };
            q.triangles = new[] { 0, 3, 2, 0, 2, 1 };
            q.bounds = new Bounds(new Vector3(0, 0.5f, 0), new Vector3(1.2f, 1.2f, 0.4f));
            return q;
        }

        public static Transform MakeSpriteObject(Transform parent, Mesh quad, string name, Material m, ShadowCastingMode mode)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.AddComponent<MeshFilter>().sharedMesh = quad;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = m;
            mr.shadowCastingMode = mode;
            mr.receiveShadows = mode != ShadowCastingMode.ShadowsOnly;
            mr.lightProbeUsage = LightProbeUsage.Off;
            mr.reflectionProbeUsage = ReflectionProbeUsage.Off;
            return go.transform;
        }

        /// <summary>One flat mesh and material for a ground silhouette, under `parent`.</summary>
        public static GameObject MakeCastObject(Transform parent, string name, string matName, out Mesh mesh, out Material mat)
        {
            var cgo = new GameObject(name);
            cgo.transform.SetParent(parent, false);
            mesh = new Mesh { name = "front-art-cast" };
            mesh.MarkDynamic();
            cgo.AddComponent<MeshFilter>().sharedMesh = mesh;
            var cmr = cgo.AddComponent<MeshRenderer>();
            mat = new Material(FindShader("FrontArtCast", "Sprites/Default")) { name = matName };
            cmr.sharedMaterial = mat;
            cmr.shadowCastingMode = ShadowCastingMode.Off;
            cmr.receiveShadows = false;
            cmr.lightProbeUsage = LightProbeUsage.Off;
            cmr.reflectionProbeUsage = ReflectionProbeUsage.Off;
            return cgo;
        }

        static readonly Vector3[] castVerts = new Vector3[4];
        static readonly Vector2[] castUv = { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) };
        static readonly int[] castTris = { 0, 1, 2, 0, 2, 3 };

        public static void SetCast(Mesh m, Vector3 feet, Vector3 dir, float len, float units)
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

        /// <summary>The figure's ground silhouettes: [0] stretched away from the nearest flame (strong when close, longer the lower the flame;
        /// cleared when there is none), [1] away from the moon (faint, length from its height).</summary>
        public static void ApplyCast(Mesh[] cast, Material[] mats, Vector3 feet, float units, bool hasFlame, Vector3 flamePos, float flameRange, Vector3 sun)
        {
            if (hasFlame)
            {
                var away = new Vector3(feet.x - flamePos.x, 0f, feet.z - flamePos.z);
                float dist = away.magnitude;
                float h = Mathf.Max(0.35f, flamePos.y - feet.y);
                float len = units * Mathf.Clamp(0.55f * dist / h + 0.35f, 0.5f, 1.4f);
                float strength = 0.95f * Mathf.Clamp01(1.15f - dist / Mathf.Max(0.1f, flameRange));
                SetCast(cast[0], feet, dist > 0.01f ? away / dist : Vector3.forward, len, units);
                mats[0].SetFloat("_Strength", strength);
            }
            else cast[0].Clear();
            var flat = new Vector3(sun.x, 0f, sun.z);
            float fl = flat.magnitude;
            float elev = Mathf.Atan2(-sun.y, Mathf.Max(0.01f, fl));
            SetCast(cast[1], feet, fl > 0.01f ? flat / fl : Vector3.forward, units * Mathf.Clamp(0.8f / Mathf.Tan(Mathf.Max(0.2f, elev)), 0.4f, 1.3f), units);
            mats[1].SetFloat("_Strength", 0.55f);
        }
    }

    /// <summary>The pictures of one front-art figure folder (Resources/FrontArt/NAME), loaded once: the 8 direction pictures of a hero, or the
    /// idle, walk and attack strips of a pack figure (each with its mirror for the west headings), each with its normal map and emission mask.</summary>
    public sealed class FrontArtSet
    {
        public string Name;
        public bool Pack, Ok;
        public readonly Texture2D[] Pics = new Texture2D[8], Nrm = new Texture2D[8], Emit = new Texture2D[8];
        // pack strips: [0] facing right, [1] mirror
        public readonly Texture2D[] Idle = new Texture2D[2], IdleN = new Texture2D[2], IdleE = new Texture2D[2];
        public readonly Texture2D[] Walk = new Texture2D[2], WalkN = new Texture2D[2], WalkE = new Texture2D[2];
        public readonly Texture2D[] Attack = new Texture2D[2], AttackN = new Texture2D[2], AttackE = new Texture2D[2];
        public int IdleFrames, WalkFrames, AttackFrames;

        static int Frames(Texture2D t) => t == null ? 0 : Mathf.Max(1, t.width / Mathf.Max(1, t.height));

        static void Strip(string root, string name, Texture2D[] pic, Texture2D[] nrm, Texture2D[] emit)
        {
            for (int k = 0; k < 2; k++)
            {
                string b = root + (k == 0 ? "/" + name : "/" + name + "_w");
                pic[k] = FrontArtSprites.Point(Resources.Load<Texture2D>(b));
                nrm[k] = FrontArtSprites.Point(Resources.Load<Texture2D>(b + "_n"));
                emit[k] = FrontArtSprites.Point(Resources.Load<Texture2D>(b + "_e"));
            }
        }

        /// <summary>Loads a folder; Ok is false when its pictures are not in the build (a pack figure without the art key).</summary>
        public static FrontArtSet Load(string folder, bool pack)
        {
            var s = new FrontArtSet { Name = folder, Pack = pack };
            string root = FrontArtSprites.Folder + folder;
            if (pack)
            {
                Strip(root, "idle", s.Idle, s.IdleN, s.IdleE);
                if (s.Idle[0] == null || s.Idle[1] == null) return s;
                s.IdleFrames = Frames(s.Idle[0]);
                Strip(root, "walk", s.Walk, s.WalkN, s.WalkE);
                if (s.Walk[0] != null && s.Walk[1] != null) s.WalkFrames = Frames(s.Walk[0]);
                Strip(root, "attack", s.Attack, s.AttackN, s.AttackE);
                if (s.Attack[0] != null && s.Attack[1] != null) s.AttackFrames = Frames(s.Attack[0]);
                s.Ok = true;
                return s;
            }
            int found = 0;
            for (int i = 0; i < 8; i++)
            {
                string b = root + "/" + FrontArtFacing.Dirs[i];
                s.Pics[i] = FrontArtSprites.Point(Resources.Load<Texture2D>(b));
                if (s.Pics[i] != null) found++;
                s.Nrm[i] = FrontArtSprites.Point(Resources.Load<Texture2D>(b + "_n"));
                s.Emit[i] = FrontArtSprites.Point(Resources.Load<Texture2D>(b + "_e"));
            }
            s.Ok = found == 8;
            return s;
        }
    }
}
