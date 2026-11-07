// 3D characters: rigged low-poly models stand on the drawn position of each creature of the HD-2D view in place of its sprite
// billboard. Which model, items, tint and size a creature gets (a class per vocation id, a monster per name) is Core/Hd2dChars.cs.
// Models, in order: Resources/KayKit (the CC0 KayKit Adventurers and Skeletons packs by Kay Lousberg, fetched at build time by
// unity/tools/fetch_3d_assets.py, see docs/CREDITS.md), then Resources/Chars3d (the CC0 RPG Character Pack by Quaternius, committed),
// then the sprites stay. Lights, shadows and name labels stay the view's; the characters cast and receive shadows.
// Pose: the screenshot mode never finishes a frame (xvfb, software GL), so nothing waits on an Animator. The idle clip is found by
// name (Resources.LoadAll<AnimationClip>: Idle, else Idle_Combat; a two-handed grip or bare hands prefer their own idle) and sampled by
// hand with clip.SampleAnimation(model, t): the bones move at once, then the Animator is switched off so nothing resets the pose.
// No idle clip: the bind pose stays.
// Items: an adventurer's FBX carries every weapon and shield as a node of the rig (Hd2dChars.WeaponNodes): the ones the spec does not
// name are hidden. A skeleton's weapons are separate FBX files (Resources/KayKit/Skeleton_Blade, ...) attached to the hand bone
// ("handslot.r" or "handslot.l"). Textures are bound at runtime (the repo commits no .meta, so the importer may not link them):
// Resources "KayKit/NAME_texture" for KayKit, "Chars3d/NAME_Texture" for the fallback pack. Colours are restyled on copies of the
// materials: a dark restyle (Hd2dChars.Tint) times the spec's tint; a skeleton's glowing eyes (the "Glow" material) stay bright and
// emissive. Unity only.
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

        sealed class Model
        {
            public GameObject Prefab;
            public string Folder, Name;
            public bool Kay;
            public AnimationClip[] Clips;
            public string[] ClipNames;
            public readonly Dictionary<string, AnimationClip> IdleBy = new Dictionary<string, AnimationClip>();
            public float Height;            // in prefab units, bind pose
            public float MinY;
            public bool Measured;
        }

        sealed class Entry
        {
            public GameObject Holder, Body;
            public Model Model;
            public Animator Animator;
            public AnimationClip Idle;
        }

        readonly Dictionary<string, Model> models = new Dictionary<string, Model>();
        readonly Dictionary<uint, Entry> entries = new Dictionary<uint, Entry>();
        readonly HashSet<uint> alive = new HashSet<uint>();   // reused by Sync: no allocation per frame
        readonly List<uint> gone = new List<uint>();
        readonly Dictionary<string, Material> styled = new Dictionary<string, Material>();
        readonly HashSet<string> warned = new HashSet<string>();
        bool attached;

        /// <summary>True when the KayKit models are in the build (Resources/KayKit/Knight, from unity/tools/fetch_3d_assets.py).</summary>
        public static bool HaveKayKit() => Resources.Load<GameObject>(Hd2dChars.KayKitFolder + Hd2dChars.KayKitProbe) != null;

        /// <summary>True when the player's model can be loaded: KayKit, else the fallback pack.</summary>
        public static bool Available() => HaveKayKit() || Resources.Load<GameObject>(Hd2dChars.FallbackFolder + Hd2dChars.PlayerModel) != null;

        /// <summary>Hides the sprites the characters replace. False (and nothing changed) when no models are in the build.</summary>
        public bool Attach(Hd2dView view)
        {
            View = view;
            if (!Available())
            {
                Debug.LogWarning("chaos chars3d: no model in Resources/" + Hd2dChars.KayKitFolder + " or Resources/" + Hd2dChars.FallbackFolder + ", the view keeps its creature sprites");
                return false;
            }
            if (!HaveKayKit()) Debug.LogWarning("chaos chars3d: no KayKit models (python3 -I unity/tools/fetch_3d_assets.py), using the " + Hd2dChars.FallbackFolder + " fallback pack");
            attached = true;
            if (isActiveAndEnabled) Hook();
            return true;
        }

        // enabled and disabled with its object (the game's F10 switch): the sprites come back while it is off
        void Hook() { if (View != null) View.SkipCreature = Hd2dChars.Replaces; }

        void Unhook() { if (View != null && View.SkipCreature == (Func<Creature, bool>)Hd2dChars.Replaces) View.SkipCreature = null; }

        void OnEnable() { if (attached) Hook(); }

        void OnDisable() { Unhook(); }

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

        /// <summary>Forgets every character (the next Sync makes them again, for example after the world's creatures changed).</summary>
        public void Clear()
        {
            foreach (var e in entries.Values) if (e.Holder != null) Destroy(e.Holder);
            entries.Clear();
            Placed = 0;
        }

        /// <summary>Creates, moves and turns the characters to match the creatures of the world.</summary>
        public void Sync()
        {
            Placed = 0;
            if (!attached || World == null || View == null) return;
            Pos origin = World.Center;
            alive.Clear();
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
            gone.Clear();
            foreach (var kv in entries) if (!alive.Contains(kv.Key)) gone.Add(kv.Key);
            foreach (var id in gone) { if (entries[id].Holder != null) Destroy(entries[id].Holder); entries.Remove(id); }
        }

        void WarnOnce(string key, string text)
        {
            if (warned.Add(key)) Debug.LogWarning("chaos chars3d: " + text);
        }

        Model Load(string folder, string name)
        {
            string key = folder + name;
            if (models.TryGetValue(key, out var m)) return m;
            m = null;
            var prefab = Resources.Load<GameObject>(folder + name);
            if (prefab != null)
            {
                m = new Model { Prefab = prefab, Folder = folder, Name = name, Kay = folder == Hd2dChars.KayKitFolder };
                var all = Resources.LoadAll<AnimationClip>(folder + name);
                var clips = new List<AnimationClip>();
                foreach (var a in all) if (a != null && !a.name.StartsWith("__preview__", StringComparison.Ordinal)) clips.Add(a);
                m.Clips = clips.ToArray();
                m.ClipNames = new string[m.Clips.Length];
                for (int i = 0; i < m.Clips.Length; i++) m.ClipNames[i] = m.Clips[i].name;
            }
            models[key] = m;
            return m;
        }

        // KayKit first, then the fallback pack; null when neither has the model
        Model ModelFor(CharSpec spec)
        {
            var m = Load(Hd2dChars.KayKitFolder, spec.Model);
            if (m != null) return m;
            m = Load(Hd2dChars.FallbackFolder, spec.Fallback);
            if (m == null) WarnOnce("model " + spec.Model, "no model Resources/" + Hd2dChars.KayKitFolder + spec.Model + " or Resources/" + Hd2dChars.FallbackFolder + spec.Fallback);
            return m;
        }

        AnimationClip IdleOf(Model m, string prefer)
        {
            prefer = prefer ?? "";
            if (m.IdleBy.TryGetValue(prefer, out var c)) return c;
            int idle = Hd2dChars.IdleClip(m.ClipNames, prefer);
            c = idle >= 0 ? m.Clips[idle] : null;
            if (c == null) WarnOnce("idle " + m.Folder + m.Name, "no idle clip in " + m.Name + " (" + m.Clips.Length + " clips), bind pose");
            m.IdleBy[prefer] = c;
            return c;
        }

        // the sprite size of the creature's outfit, in tiles (a 2 x 2 look is a big monster)
        float SizeOf(Creature c)
        {
            int w = 1, h = 1;
            var t = World != null && World.Dat != null && c.Outfit != null ? World.Dat.Outfit(c.Outfit.LookType) : null;
            if (t != null && t.Groups != null && t.Groups.Length > 0 && t.Groups[0] != null) { w = Mathf.Max(1, t.Groups[0].Width); h = Mathf.Max(1, t.Groups[0].Height); }
            return Hd2dChars.SizeFor(c, w, h);
        }

        Entry Make(Creature c, bool isPlayer)
        {
            var spec = Hd2dChars.SpecFor(c, isPlayer, World != null ? World.PlayerVocation : 0);
            var m = ModelFor(spec);
            if (m == null) return null;
            var holder = new GameObject("char " + c.Name + " (" + m.Name + ", " + spec.Label + ")");
            holder.transform.SetParent(transform, false);
            var body = Instantiate(m.Prefab, holder.transform);
            body.name = m.Name;
            body.transform.localPosition = Vector3.zero;
            body.transform.localRotation = Quaternion.identity;
            body.transform.localScale = Vector3.one;
            if (m.Kay) Items(body, spec);
            var e = new Entry { Holder = holder, Body = body, Model = m, Animator = body.GetComponentInChildren<Animator>() };
            Restyle(body, m, spec);
            e.Idle = IdleOf(m, m.Kay ? spec.Idle : "");
            Pose(e, c.Id, 0f);
            if (!m.Measured) Measure(m, holder, body);
            float s = Hd2dChars.ScaleFor(m.Height) * (m.Kay ? spec.Scale : 1f) * SizeOf(c);
            body.transform.localScale = Vector3.one * s;
            body.transform.localPosition = new Vector3(0f, -m.MinY * s, 0f);   // the feet on the floor
            return e;
        }

        // ---- items ----------------------------------------------------------------------------------------------------------

        // an adventurer's weapon and shield nodes: only the spec's items are shown; a skeleton's weapon files go on its hand bones
        void Items(GameObject body, CharSpec spec)
        {
            var all = body.GetComponentsInChildren<Transform>(true);
            foreach (var t in all)
                if (Hd2dChars.IsWeaponNode(t.name)) t.gameObject.SetActive(Array.IndexOf(spec.Items, t.name) >= 0);
            var bones = new string[all.Length];
            for (int i = 0; i < all.Length; i++) bones[i] = all[i].name;
            foreach (var item in spec.Items)
            {
                if (Hd2dChars.IsWeaponNode(item)) continue;
                var prefab = Resources.Load<GameObject>(Hd2dChars.KayKitFolder + item);
                if (prefab == null) { WarnOnce("item " + item, "no weapon Resources/" + Hd2dChars.KayKitFolder + item); continue; }
                int hand = Hd2dChars.HandBone(bones, !Hd2dChars.LeftHand(item));
                if (hand < 0) { WarnOnce("hand " + spec.Model, "no hand bone in " + spec.Model + " for " + item); continue; }
                var bone = all[hand];
                var w = Instantiate(prefab, bone, false);
                w.name = item;
                w.transform.localPosition = Vector3.zero;
                w.transform.localRotation = Quaternion.identity;
                // the weapon is modelled in character units: cancel any scale the rig's bones carry
                Vector3 bs = bone.lossyScale, ks = body.transform.lossyScale;
                w.transform.localScale = new Vector3(Div(ks.x, bs.x), Div(ks.y, bs.y), Div(ks.z, bs.z));
            }
        }

        static float Div(float a, float b) => Mathf.Abs(b) > 1e-6f ? a / b : 1f;

        // a renderer on a hand slot (a weapon) is not part of the body's height
        static bool OnHand(Transform t, Transform root)
        {
            for (var p = t; p != null && p != root; p = p.parent)
            {
                string n = p.name.ToLowerInvariant();
                if (n.IndexOf("hand", StringComparison.Ordinal) >= 0 && n.IndexOf("ik", StringComparison.Ordinal) < 0) return true;
            }
            return false;
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
                if (OnHand(r.transform, body.transform) || Hd2dChars.IsWeaponNode(r.name)) continue;
                for (int i = 0; i < 8; i++)
                {
                    var corner = b.center + Vector3.Scale(b.extents, new Vector3((i & 1) == 0 ? -1 : 1, (i & 2) == 0 ? -1 : 1, (i & 4) == 0 ? -1 : 1));
                    float y = mat.MultiplyPoint3x4(corner).y;
                    lo = Mathf.Min(lo, y); hi = Mathf.Max(hi, y);
                }
            }
            m.Measured = true;
            if (hi > lo) { m.MinY = lo; m.Height = hi - lo; }
            else { m.MinY = 0f; m.Height = 0f; WarnOnce("measure " + m.Name, "could not measure " + body.name + ", scale 1"); }
        }

        void Pose(Entry e, uint id, float time)
        {
            var clip = e.Idle;
            if (clip == null) return;
            try
            {
                float t = clip.length > 0f ? (Hd2dChars.IdleTime(id, clip.length) + (Live ? time : 0f)) % clip.length : 0f;
                clip.SampleAnimation(e.Body, t);
                if (e.Animator != null) e.Animator.enabled = false;   // keep the sampled pose
            }
            catch (Exception ex) { Debug.LogWarning("chaos chars3d: could not sample " + clip.name + ": " + ex.Message); e.Idle = null; }
        }

        // ---- look -----------------------------------------------------------------------------------------------------------

        void Restyle(GameObject go, Model model, CharSpec spec)
        {
            foreach (var r in go.GetComponentsInChildren<Renderer>(true))
            {
                var src = r.sharedMaterials;
                var dst = new Material[src.Length];
                for (int i = 0; i < src.Length; i++) dst[i] = Styled(model, spec, src[i], r.name);
                r.sharedMaterials = dst;
                bool eyes = model.Kay && src.Length == 1 && src[0] != null && CleanName(src[0]) == Hd2dChars.GlowMaterial;
                r.shadowCastingMode = eyes ? ShadowCastingMode.Off : ShadowCastingMode.On;
                r.receiveShadows = !eyes;
                if (r is SkinnedMeshRenderer smr) smr.updateWhenOffscreen = true;
            }
        }

        static string CleanName(Material m) => m != null ? m.name.Replace(" (Instance)", "").Trim() : "";

        Material Styled(Model model, CharSpec spec, Material m, string rendererName)
        {
            string mname = CleanName(m);
            bool glow = model.Kay && mname == Hd2dChars.GlowMaterial;
            string texName;
            if (glow) texName = "";
            else if (model.Kay) texName = Hd2dChars.KayKitTexture(spec.Model);
            else
            {
                // the weapon sub-mesh may carry the body's material name: its mesh name says which one it is
                texName = Hd2dChars.TextureFor(model.Name, mname);
                if (texName == model.Name + "_Texture" && rendererName.StartsWith(model.Name + "_", StringComparison.Ordinal) && !rendererName.EndsWith("Body", StringComparison.Ordinal))
                    texName = Hd2dChars.TextureFor(model.Name, rendererName);
            }
            string key = glow ? "glow" : model.Folder + model.Name + "|" + texName + "|" + spec.R.ToString("0.00") + "," + spec.G.ToString("0.00") + "," + spec.B.ToString("0.00") + "," + spec.Dim.ToString("0.00");
            if (styled.TryGetValue(key, out var s)) return s;
            if (m != null && m.shader != null && m.HasProperty("_MainTex")) s = new Material(m);
            else
            {
                var sh = Shader.Find("Standard");
                if (sh == null) sh = Shader.Find("Legacy Shaders/Diffuse");
                s = new Material(sh);
            }
            if (glow)
            {
                // the eyes: bright, never dimmed or tinted, emissive where the shader has an emission colour
                s.name = "Glow (eyes)";
                s.mainTexture = null;
                s.color = new Color(Hd2dChars.GlowR, Hd2dChars.GlowG, Hd2dChars.GlowB, 1f);
                if (s.HasProperty("_EmissionColor"))
                {
                    s.EnableKeyword("_EMISSION");
                    s.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
                    s.SetColor("_EmissionColor", new Color(Hd2dChars.GlowR, Hd2dChars.GlowG, Hd2dChars.GlowB, 1f) * Hd2dChars.GlowEmission);
                }
                if (s.HasProperty("_Glossiness")) s.SetFloat("_Glossiness", 0f);
                if (s.HasProperty("_Metallic")) s.SetFloat("_Metallic", 0f);
                styled[key] = s;
                return s;
            }
            s.name = texName + " (dark)";
            var tex = Resources.Load<Texture2D>(model.Folder + texName);
            if (tex == null && !model.Kay && texName != model.Name + "_Texture") tex = Resources.Load<Texture2D>(model.Folder + model.Name + "_Texture");
            if (tex != null) s.mainTexture = tex;
            else WarnOnce("tex " + model.Folder + texName, "no texture Resources/" + model.Folder + texName);
            Hd2dChars.Tint(spec, out float r, out float g, out float b);
            s.color = new Color(r, g, b, 1f);
            if (s.HasProperty("_Glossiness")) s.SetFloat("_Glossiness", 0.12f);
            if (s.HasProperty("_Metallic")) s.SetFloat("_Metallic", 0f);
            styled[key] = s;
            return s;
        }
    }
}
