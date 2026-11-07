// 3D architecture test (Ruins3d) and 3D world (World3d): real low-poly models take the place of the sprite floors, walls, pillars and
// lights of the HD-2D view; creatures, decals and loose items stay the sprite billboards of Hd2dView. Which piece goes where is
// Core/Hd2dRuins.cs (the demo room) or, with WorldMode, Core/Hd2dWorld3d.cs (real maps: terrain tiles tinted from the sprites, water,
// lava, trees, bushes, rocks, scatter; see unity/README.md "3D world"). Models: Resources/Ruins3d (CC0 Modular Ruins Pack) and
// Resources/Nature3d (CC0 Ultimate Nature Pack), both by Quaternius, see docs/CREDITS.md.
// Attach(view) makes the view skip the sprite pieces that are replaced. Needs the models in Resources: when the required ones are
// missing, Attach does nothing and the view keeps all its sprites. The pack's colours are restyled on copies of its materials (never
// the assets): cold dark stone walls, warm dirt floor, dark wood, warm emissive flames, muted leaves.
// Live (the game): LateUpdate compares a cheap hash of the view (Hd2dWorld3d.ViewHash, no allocation) and rebuilds only when it changed.
// A rebuild reuses a pool of instances per (model, role): nothing is destroyed or created once the pool has grown to the view's need, and
// an instance that stays in use stays active. Standard shader, lit by the view's point lights and ambient. Unity only; the game client
// does not use it.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Rendering;
using Debug = UnityEngine.Debug;

namespace Chaos.Client
{
    // after the view's LateUpdate: the models and the sprites are built from the same centre in a frame
    [DefaultExecutionOrder(100)]
    public sealed class Hd2dRuins3d : MonoBehaviour
    {
        public World World;
        public Hd2dView View;
        /// <summary>The models placed by the last Build.</summary>
        public int Placed;
        /// <summary>The real-map rules (Hd2dWorld3d) instead of the demo room's (Hd2dRuins). Set before Attach.</summary>
        public bool WorldMode;
        /// <summary>True: LateUpdate rebuilds when the view changed. False: the scene is built by hand with Build().</summary>
        public bool Live;
        /// <summary>How many times the models were rebuilt, and how long the last one took.</summary>
        public int Rebuilds;
        public double LastBuildMs;
        /// <summary>The sprite classifier and role rules of WorldMode (null before Attach).</summary>
        public World3dRules Rules { get; private set; }

        const string RuinsFolder = "Ruins3d/", NatureFolder = "Nature3d/";

        sealed class Inst { public GameObject Go; public MeshRenderer Tile; }
        sealed class Pool { public readonly List<Inst> Items = new List<Inst>(); public int Used, Active; }

        readonly Dictionary<string, GameObject> prefabs = new Dictionary<string, GameObject>();
        readonly Dictionary<string, Material> styled = new Dictionary<string, Material>();
        readonly Dictionary<int, Material> tiles = new Dictionary<int, Material>();
        readonly Dictionary<(string, RuinsRole), Pool> pools = new Dictionary<(string, RuinsRole), Pool>();
        readonly List<Pool> poolList = new List<Pool>();
        static readonly Func<Hd2dPiece, bool> ruinsHook = Hd2dRuins.Replaces;
        Func<Hd2dPiece, bool> hook;
        Material tileTemplate;
        Mesh boxMesh, quadMesh;
        bool attached, built;
        int lastHash;

        static string FolderOf(string name) => Hd2dWorld3d.IsNature(name) ? NatureFolder : RuinsFolder;

        GameObject Prefab(string name)
        {
            if (prefabs.TryGetValue(name, out var p)) return p;
            if (name[0] == '@') p = Procedural(name);
            else
            {
                string path = FolderOf(name) + name;
                p = Resources.Load<GameObject>(path);
                if (p == null) Debug.LogWarning("chaos ruins3d: no model Resources/" + path);
            }
            prefabs[name] = p;
            return p;
        }

        // a terrain tile (a thin box, top at y 0) and the water / lava planes: generated, no model file
        GameObject Procedural(string name)
        {
            var go = new GameObject(name);
            go.SetActive(false);
            go.transform.SetParent(transform, false);
            go.AddComponent<MeshFilter>().sharedMesh = name == Hd2dWorld3d.TilePiece ? BoxMesh() : QuadMesh();
            var mr = go.AddComponent<MeshRenderer>();
            mr.shadowCastingMode = ShadowCastingMode.Off;
            mr.receiveShadows = true;
            return go;
        }

        Mesh QuadMesh()
        {
            if (quadMesh != null) return quadMesh;
            quadMesh = new Mesh { name = "chaos-world3d-plane" };
            quadMesh.vertices = new[] { new Vector3(-0.5f, 0, -0.5f), new Vector3(0.5f, 0, -0.5f), new Vector3(0.5f, 0, 0.5f), new Vector3(-0.5f, 0, 0.5f) };
            quadMesh.normals = new[] { Vector3.up, Vector3.up, Vector3.up, Vector3.up };
            quadMesh.uv = new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) };
            quadMesh.triangles = new[] { 0, 2, 1, 0, 3, 2 };
            return quadMesh;
        }

        Mesh BoxMesh()
        {
            if (boxMesh != null) return boxMesh;
            float t = Hd2dTerrain.TileThickness;
            var v = new List<Vector3>(); var n = new List<Vector3>(); var tri = new List<int>();
            Action<Vector3, Vector3, Vector3, Vector3, Vector3> face = (a, b, c, d, nn) =>
            {
                int i = v.Count;
                v.Add(a); v.Add(b); v.Add(c); v.Add(d);
                for (int k = 0; k < 4; k++) n.Add(nn);
                tri.Add(i); tri.Add(i + 2); tri.Add(i + 1); tri.Add(i); tri.Add(i + 3); tri.Add(i + 2);
            };
            // top (faces up) and four sides (face out), wound clockwise seen from outside
            face(new Vector3(-0.5f, 0, -0.5f), new Vector3(0.5f, 0, -0.5f), new Vector3(0.5f, 0, 0.5f), new Vector3(-0.5f, 0, 0.5f), Vector3.up);
            face(new Vector3(-0.5f, -t, -0.5f), new Vector3(0.5f, -t, -0.5f), new Vector3(0.5f, 0, -0.5f), new Vector3(-0.5f, 0, -0.5f), Vector3.back);
            face(new Vector3(0.5f, -t, 0.5f), new Vector3(-0.5f, -t, 0.5f), new Vector3(-0.5f, 0, 0.5f), new Vector3(0.5f, 0, 0.5f), Vector3.forward);
            face(new Vector3(0.5f, -t, -0.5f), new Vector3(0.5f, -t, 0.5f), new Vector3(0.5f, 0, 0.5f), new Vector3(0.5f, 0, -0.5f), Vector3.right);
            face(new Vector3(-0.5f, -t, 0.5f), new Vector3(-0.5f, -t, -0.5f), new Vector3(-0.5f, 0, -0.5f), new Vector3(-0.5f, 0, 0.5f), Vector3.left);
            boxMesh = new Mesh { name = "chaos-world3d-tile" };
            boxMesh.SetVertices(v); boxMesh.SetNormals(n); boxMesh.SetTriangles(tri, 0);
            return boxMesh;
        }

        /// <summary>True when the models the experiment needs can be loaded.</summary>
        public static bool Available()
        {
            foreach (var n in Hd2dRuins.Required)
                if (Resources.Load<GameObject>(RuinsFolder + n) == null) return false;
            return true;
        }

        /// <summary>True when the nature models can be loaded (trees, bushes, rocks, scatter).</summary>
        public static bool NatureAvailable()
        {
            foreach (var n in Hd2dWorld3d.NatureRequired)
                if (Resources.Load<GameObject>(NatureFolder + n) == null) return false;
            return true;
        }

        /// <summary>Hides the sprites the models replace. False (and nothing changed) when the models are not in the build.
        /// In WorldMode the view needs its Atlas (the sprites are classified from its pixels).</summary>
        public bool Attach(Hd2dView view)
        {
            Unhook();
            View = view;
            if (!Available())
            {
                Debug.LogWarning("chaos ruins3d: the models are missing, the view keeps its sprites");
                return false;
            }
            if (WorldMode)
            {
                Rules = new World3dRules(new SpriteClassifier(id => id == 0 || View == null || View.Atlas == null ? null : View.Atlas.Raw(id)));
                Rules.Nature = NatureAvailable();
                if (!Rules.Nature) Debug.LogWarning("chaos world3d: no nature models (Resources/" + NatureFolder + "), trees, bushes and rocks stay sprites");
                hook = Rules.ReplacesFn;
            }
            else hook = ruinsHook;
            attached = true;
            if (isActiveAndEnabled) Hook();
            return true;
        }

        void Hook() { if (View != null) View.Skip = hook; built = false; }

        void Unhook() { if (View != null && hook != null && View.Skip == hook) View.Skip = null; }

        void OnEnable() { if (attached) Hook(); }

        void OnDisable() { Unhook(); }

        void LateUpdate() { if (Live) Refresh(); }

        /// <summary>Rebuilds when what the plan reads changed since the last build (a hash of the view, no allocation). True when it rebuilt.</summary>
        public bool Refresh()
        {
            if (!attached || World == null || View == null || !isActiveAndEnabled) return false;
            int h = Hd2dWorld3d.ViewHash(World);
            if (built && h == lastHash) return false;
            lastHash = h;
            Build();
            return true;
        }

        /// <summary>Places the models for the current world (the layout is the view's: same origin, pitch and art slant). Reuses the pooled instances.</summary>
        public void Build()
        {
            var sw = Stopwatch.StartNew();
            Placed = 0;
            foreach (var pl in poolList) pl.Used = 0;
            if (attached && World != null && View != null)
            {
                var origin = World.Center;
                var pieces = Hd2d.Layout(World, origin, View.Pitch, null, !View.StraightArt);
                var plan = WorldMode ? Hd2dWorld3d.Plan(pieces, origin, Rules) : Hd2dRuins.Plan(pieces, origin);
                foreach (var q in plan) Place(q);
            }
            foreach (var pl in poolList)
            {
                for (int i = pl.Used; i < pl.Active; i++) pl.Items[i].Go.SetActive(false);
                pl.Active = pl.Used;
            }
            built = true;
            Rebuilds++;
            LastBuildMs = sw.Elapsed.TotalMilliseconds;
            if (!Live || Rebuilds <= 3) Debug.Log("chaos ruins3d: placed " + Placed + " models in " + LastBuildMs.ToString("0.0") + " ms (rebuild " + Rebuilds + ", " + poolList.Count + " pools)");
        }

        /// <summary>Hides every model (the pool stays); the next Refresh or Build places them again.</summary>
        public void Clear()
        {
            foreach (var pl in poolList)
            {
                for (int i = 0; i < pl.Active; i++) pl.Items[i].Go.SetActive(false);
                pl.Used = pl.Active = 0;
            }
            Placed = 0;
            built = false;
        }

        void Place(RuinsPlacement q)
        {
            var key = (q.Piece, q.Role);
            if (!pools.TryGetValue(key, out var pool)) { pool = new Pool(); pools[key] = pool; poolList.Add(pool); }
            Inst inst;
            if (pool.Used < pool.Items.Count) inst = pool.Items[pool.Used];
            else
            {
                var prefab = Prefab(q.Piece);
                if (prefab == null) return;
                var go = Instantiate(prefab, transform);
                go.name = q.Piece;
                go.SetActive(false);
                inst = new Inst { Go = go };
                if (q.Piece[0] == '@') inst.Tile = go.GetComponent<MeshRenderer>(); else Restyle(go, q.Role);
                pool.Items.Add(inst);
            }
            if (pool.Used >= pool.Active) inst.Go.SetActive(true);
            pool.Used++;
            var tr = inst.Go.transform;
            tr.localPosition = new Vector3(q.X, q.Y, q.Z);
            tr.localRotation = Quaternion.Euler(0f, q.Yaw, 0f);
            tr.localScale = new Vector3(q.Scale, q.ScaleY > 0f ? q.ScaleY : q.Scale, q.Scale);
            if (inst.Tile != null) inst.Tile.sharedMaterial = TileMaterial(q);
            Placed++;
        }

        // a tile's material by class and the sprite's mean colour at 5 bits a channel: a field has a handful, drawn instanced
        Material TileMaterial(RuinsPlacement q)
        {
            int r = Mathf.Clamp(Mathf.RoundToInt(q.TintR * 31f), 0, 31), g = Mathf.Clamp(Mathf.RoundToInt(q.TintG * 31f), 0, 31), b = Mathf.Clamp(Mathf.RoundToInt(q.TintB * 31f), 0, 31);
            int key = (int)q.Ground | r << 4 | g << 9 | b << 14;
            if (tiles.TryGetValue(key, out var m)) return m;
            if (tileTemplate == null)
            {
                var p = Prefab("Floor_Standard");
                var rd = p != null ? p.GetComponentInChildren<Renderer>() : null;
                tileTemplate = rd != null && rd.sharedMaterial != null ? rd.sharedMaterial : new Material(Shader.Find("Standard"));
            }
            var st = Hd2dTerrain.TileStyle(q.Ground, r / 31f, g / 31f, b / 31f);
            m = new Material(tileTemplate) { name = "chaos-world3d " + q.Ground, enableInstancing = true };
            m.color = new Color(st.R, st.G, st.B, 1f);
            if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", st.Smoothness);
            if (m.HasProperty("_Metallic")) m.SetFloat("_Metallic", 0f);
            if (st.Emissive)
            {
                m.EnableKeyword("_EMISSION");
                m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
                m.SetColor("_EmissionColor", new Color(st.EmitR, st.EmitG, st.EmitB));
            }
            else if (m.IsKeywordEnabled("_EMISSION")) { m.DisableKeyword("_EMISSION"); m.SetColor("_EmissionColor", Color.black); }
            tiles[key] = m;
            return m;
        }

        void Restyle(GameObject go, RuinsRole role)
        {
            foreach (var r in go.GetComponentsInChildren<Renderer>())
            {
                var src = r.sharedMaterials;
                var dst = new Material[src.Length];
                for (int i = 0; i < src.Length; i++) dst[i] = Styled(src[i], role);
                r.sharedMaterials = dst;
                r.shadowCastingMode = ShadowCastingMode.On;
                r.receiveShadows = true;
            }
        }

        Material Styled(Material m, RuinsRole role)
        {
            if (m == null) return null;
            string key = m.GetInstanceID() + "|" + role;
            if (styled.TryGetValue(key, out var s)) return s;
            s = new Material(m) { name = m.name + " (dark)" };
            Color c = m.HasProperty("_Color") ? m.color : Color.grey;
            // the importer hands over the mtl's Kd as it is: Core restyles it from there
            var st = Hd2dRuins.Restyle(m.name, c.r, c.g, c.b, role);
            s.color = new Color(st.R, st.G, st.B, 1f);
            if (s.HasProperty("_Glossiness")) s.SetFloat("_Glossiness", st.Smoothness);
            if (s.HasProperty("_Metallic")) s.SetFloat("_Metallic", 0f);
            if (st.Emissive)
            {
                s.EnableKeyword("_EMISSION");
                s.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
                s.SetColor("_EmissionColor", new Color(st.EmitR, st.EmitG, st.EmitB));
            }
            else if (role == RuinsRole.Wall || role == RuinsRole.Pillar || role == RuinsRole.Trim)
            {
                // The restyled stone is so dark that the flat ambient alone leaves it as black as the background (the first render lost the
                // back wall that way): a fixed faint cold self-light keeps it a dark blue-grey shape, the torches still make the pools.
                s.EnableKeyword("_EMISSION");
                s.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
                s.SetColor("_EmissionColor", new Color(0.07f, 0.08f, 0.11f));
            }
            styled[key] = s;
            return s;
        }
    }
}
