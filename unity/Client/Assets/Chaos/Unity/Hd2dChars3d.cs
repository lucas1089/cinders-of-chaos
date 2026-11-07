// 3D characters (Chars3d): rigged low-poly models (Resources/Chars3d, the CC0 RPG Character Pack by Quaternius, see
// docs/CREDITS.md) stand on the drawn position of each creature of the HD-2D view in place of its sprite billboard. Which model
// a creature gets, its yaw, scale, tint and idle clip are Core/Hd2dChars.cs. Lights, shadows and name labels stay the view's;
// the characters cast and receive shadows.
// Pose: the screenshot mode never finishes a frame (xvfb, software GL), so nothing waits on an Animator. The idle clip is found by
// name (Resources.LoadAll<AnimationClip>) and sampled by hand with clip.SampleAnimation(model, t): the bones move at once, then
// the Animator is switched off so nothing resets the pose. No idle clip: the bind pose stays.
// Textures are bound at runtime (the repo commits no .meta, so the importer may not link them): Resources "Chars3d/NAME_Texture"
// goes on the body material and "Chars3d/NAME_Weapon_Texture" on the weapon material, picked by material name.
// Colours are restyled on copies of the materials: x 0.75 and a little grey (Hd2dChars.Tint). Unity only.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace Chaos.Client
{
    public sealed class Hd2dChars3d : MonoBehaviour
    {
        public World World;
        public Hd2dView View;
        /// <summary>The characters standing now.</summary>
        public int Placed;
        /// <summary>True: Sync runs every frame (positions, facing, animated idle). False: the scene is built by hand with Build().</summary>
        public bool Live;

        const string Folder = "Chars3d/";

        sealed class Model
        {
            public GameObject Prefab;
            public AnimationClip Idle;
            public float Height;            // in prefab units, bind pose
            public float MinY;
        }

        sealed class Entry
        {
            public GameObject Holder, Body;
            public Model Model;
            public Animator Animator;
        }

        readonly Dictionary<string, Model> models = new Dictionary<string, Model>();
        readonly Dictionary<uint, Entry> entries = new Dictionary<uint, Entry>();
        readonly Dictionary<string, Material> styled = new Dictionary<string, Material>();
        bool attached;

        /// <summary>True when the player's model can be loaded.</summary>
        public static bool Available() => Resources.Load<GameObject>(Folder + Hd2dChars.PlayerModel) != null;

        /// <summary>Hides the sprites the characters replace. False (and nothing changed) when the models are not in the build.</summary>
        public bool Attach(Hd2dView view)
        {
            View = view;
            if (!Available())
            {
                Debug.LogWarning("chaos chars3d: no model Resources/" + Folder + Hd2dChars.PlayerModel + ", the view keeps its creature sprites");
                return false;
            }
            view.SkipCreature = Hd2dChars.Replaces;
            attached = true;
            return true;
        }

        void OnDestroy() { if (attached && View != null && View.SkipCreature == (Func<Creature, bool>)Hd2dChars.Replaces) View.SkipCreature = null; }

        void LateUpdate() { if (Live) Sync(); }

        /// <summary>Places the characters for the current world (and resamples their pose).</summary>
        public void Build() { Sync(); }

        /// <summary>The drawn point of a creature's centre at `height` above the floor, in world space; false when it has no character.</summary>
        public bool PointOf(uint id, float height, out Vector3 p)
        {
            p = Vector3.zero;
            if (!entries.TryGetValue(id, out var e) || e.Holder == null) return false;
            p = e.Holder.transform.position + Vector3.up * height;
            return true;
        }

        /// <summary>Creates, moves and turns the characters to match the creatures of the world.</summary>
        public void Sync()
        {
            Placed = 0;
            if (!attached || World == null || View == null) return;
            Pos origin = World.Center;
            var alive = new HashSet<uint>();
            foreach (var c in World.Creatures.Values)
            {
                if (c.Position.Z != origin.Z || !Hd2dChars.Replaces(c)) continue;
                alive.Add(c.Id);
                if (!entries.TryGetValue(c.Id, out var e) || e.Holder == null)
                {
                    e = Make(c, c.Id == World.PlayerId);
                    if (e == null) continue;
                    entries[c.Id] = e;
                }
                var t = View.DrawnTile(c);
                e.Holder.transform.position = new Vector3(Hd2dChars.X(origin, t.x), 0f, Hd2dChars.Z(origin, t.y));
                e.Holder.transform.rotation = Quaternion.Euler(0f, Hd2dChars.Yaw(c.Direction) + Hd2dChars.ModelYaw, 0f);
                if (Live) Pose(e, c.Id, Time.time);
                Placed++;
            }
            List<uint> gone = null;
            foreach (var kv in entries) if (!alive.Contains(kv.Key)) (gone ?? (gone = new List<uint>())).Add(kv.Key);
            if (gone != null) foreach (var id in gone) { if (entries[id].Holder != null) Destroy(entries[id].Holder); entries.Remove(id); }
        }

        Model Load(string name)
        {
            if (models.TryGetValue(name, out var m)) return m;
            m = null;
            var prefab = Resources.Load<GameObject>(Folder + name);
            if (prefab == null) Debug.LogWarning("chaos chars3d: no model Resources/" + Folder + name);
            else
            {
                m = new Model { Prefab = prefab };
                var all = Resources.LoadAll<AnimationClip>(Folder + name);
                var clips = new List<AnimationClip>();
                foreach (var a in all) if (a != null && !a.name.StartsWith("__preview__", StringComparison.Ordinal)) clips.Add(a);
                var names = new string[clips.Count];
                for (int i = 0; i < names.Length; i++) names[i] = clips[i].name;
                int idle = Hd2dChars.IdleClip(names);
                if (idle >= 0) m.Idle = clips[idle];
                else Debug.LogWarning("chaos chars3d: no idle clip in " + name + " (" + clips.Count + " clips), bind pose");
            }
            models[name] = m;
            return m;
        }

        Entry Make(Creature c, bool isPlayer)
        {
            string name = Hd2dChars.ModelFor(c, isPlayer);
            var m = Load(name);
            if (m == null) return null;
            var holder = new GameObject("char " + c.Name + " (" + name + ")");
            holder.transform.SetParent(transform, false);
            var body = Instantiate(m.Prefab, holder.transform);
            body.name = name;
            body.transform.localPosition = Vector3.zero;
            body.transform.localRotation = Quaternion.identity;
            body.transform.localScale = Vector3.one;
            var e = new Entry { Holder = holder, Body = body, Model = m, Animator = body.GetComponentInChildren<Animator>() };
            Restyle(body, name);
            Pose(e, c.Id, 0f);
            if (m.Height <= 0f) Measure(m, holder, body);
            float s = Hd2dChars.ScaleFor(m.Height);
            body.transform.localScale = Vector3.one * s;
            body.transform.localPosition = new Vector3(0f, -m.MinY * s, 0f);   // the feet on the floor
            return e;
        }

        // the posed model's height from its meshes' bounds, in the holder's space at scale 1 (the pose is the idle's first sample)
        void Measure(Model m, GameObject holder, GameObject body)
        {
            float lo = float.MaxValue, hi = float.MinValue;
            var toHolder = holder.transform.worldToLocalMatrix;
            foreach (var r in body.GetComponentsInChildren<Renderer>())
            {
                Bounds b;
                Matrix4x4 mat;
                if (r is SkinnedMeshRenderer smr && smr.sharedMesh != null) { b = smr.sharedMesh.bounds; mat = toHolder * smr.transform.localToWorldMatrix; }
                else if (r is MeshRenderer && r.GetComponent<MeshFilter>() != null && r.GetComponent<MeshFilter>().sharedMesh != null) { b = r.GetComponent<MeshFilter>().sharedMesh.bounds; mat = toHolder * r.transform.localToWorldMatrix; }
                else continue;
                if (r.name.IndexOf("Sword", StringComparison.OrdinalIgnoreCase) >= 0 || r.name.IndexOf("Staff", StringComparison.OrdinalIgnoreCase) >= 0
                    || r.name.IndexOf("Bow", StringComparison.OrdinalIgnoreCase) >= 0 || r.name.IndexOf("Dagger", StringComparison.OrdinalIgnoreCase) >= 0) continue;   // weapons can stand above the head
                for (int i = 0; i < 8; i++)
                {
                    var corner = b.center + Vector3.Scale(b.extents, new Vector3((i & 1) == 0 ? -1 : 1, (i & 2) == 0 ? -1 : 1, (i & 4) == 0 ? -1 : 1));
                    float y = mat.MultiplyPoint3x4(corner).y;
                    lo = Mathf.Min(lo, y); hi = Mathf.Max(hi, y);
                }
            }
            if (hi > lo) { m.MinY = lo; m.Height = hi - lo; }
            else { m.MinY = 0f; m.Height = 0f; Debug.LogWarning("chaos chars3d: could not measure " + body.name + ", scale 1"); }
        }

        void Pose(Entry e, uint id, float time)
        {
            var clip = e.Model.Idle;
            if (clip == null) return;
            try
            {
                float t = clip.length > 0f ? (Hd2dChars.IdleTime(id, clip.length) + (Live ? time : 0f)) % clip.length : 0f;
                clip.SampleAnimation(e.Body, t);
                if (e.Animator != null) e.Animator.enabled = false;   // keep the sampled pose
            }
            catch (Exception ex) { Debug.LogWarning("chaos chars3d: could not sample " + clip.name + ": " + ex.Message); e.Model.Idle = null; }
        }

        void Restyle(GameObject go, string model)
        {
            foreach (var r in go.GetComponentsInChildren<Renderer>())
            {
                var src = r.sharedMaterials;
                var dst = new Material[src.Length];
                for (int i = 0; i < src.Length; i++) dst[i] = Styled(model, src[i], r.name);
                r.sharedMaterials = dst;
                r.shadowCastingMode = ShadowCastingMode.On;
                r.receiveShadows = true;
                if (r is SkinnedMeshRenderer smr) smr.updateWhenOffscreen = true;
            }
        }

        Material Styled(string model, Material m, string rendererName)
        {
            string mname = m != null ? m.name : "";
            // the weapon sub-mesh may carry the body's material name: its mesh name says which one it is
            string texName = Hd2dChars.TextureFor(model, mname);
            if (texName == model + "_Texture" && rendererName.StartsWith(model + "_", StringComparison.Ordinal) && !rendererName.EndsWith("Body", StringComparison.Ordinal))
                texName = Hd2dChars.TextureFor(model, rendererName);
            string key = model + "|" + texName;
            if (styled.TryGetValue(key, out var s)) return s;
            if (m != null && m.shader != null && m.HasProperty("_MainTex")) s = new Material(m);
            else
            {
                var sh = Shader.Find("Standard");
                if (sh == null) sh = Shader.Find("Legacy Shaders/Diffuse");
                s = new Material(sh);
            }
            s.name = texName + " (dark)";
            var tex = Resources.Load<Texture2D>(Folder + texName);
            if (tex == null && texName != model + "_Texture") tex = Resources.Load<Texture2D>(Folder + model + "_Texture");
            if (tex != null) s.mainTexture = tex;
            else Debug.LogWarning("chaos chars3d: no texture Resources/" + Folder + texName);
            Hd2dChars.Tint(1f, 1f, 1f, out float r, out float g, out float b);
            s.color = new Color(r, g, b, 1f);
            if (s.HasProperty("_Glossiness")) s.SetFloat("_Glossiness", 0.12f);
            if (s.HasProperty("_Metallic")) s.SetFloat("_Metallic", 0f);
            styled[key] = s;
            return s;
        }
    }
}
