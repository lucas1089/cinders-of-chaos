// 3D architecture test (Ruins3d): real low-poly models (Resources/Ruins3d, the CC0 Modular Ruins Pack by Quaternius, see
// docs/CREDITS.md) take the place of the sprite floors, walls, pillars and lights of the HD-2D view; creatures, decals and
// loose items stay the sprite billboards of Hd2dView. Which piece goes where is Core/Hd2dRuins.cs.
// Attach(view) makes the view skip the sprite pieces that are replaced; Build() places the models once. Needs the models in
// Resources: when the required ones are missing, Attach does nothing and the view keeps all its sprites.
// The pack's colours are restyled on copies of its materials (never the assets): cold grey stone, dark wood, warm emissive flames.
// Standard shader, lit by the view's point lights and ambient. Unity only; the game client does not use it.
using System;
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace Chaos.Client
{
    public sealed class Hd2dRuins3d : MonoBehaviour
    {
        public World World;
        public Hd2dView View;
        /// <summary>The models placed by the last Build.</summary>
        public int Placed;

        const string Folder = "Ruins3d/";
        readonly Dictionary<string, GameObject> prefabs = new Dictionary<string, GameObject>();
        readonly Dictionary<Material, Material> styled = new Dictionary<Material, Material>();
        readonly List<GameObject> made = new List<GameObject>();
        bool attached;

        GameObject Prefab(string name)
        {
            if (prefabs.TryGetValue(name, out var p)) return p;
            p = Resources.Load<GameObject>(Folder + name);
            if (p == null) Debug.LogWarning("chaos ruins3d: no model Resources/" + Folder + name);
            prefabs[name] = p;
            return p;
        }

        /// <summary>True when the models the experiment needs can be loaded.</summary>
        public static bool Available()
        {
            foreach (var n in Hd2dRuins.Required)
                if (Resources.Load<GameObject>(Folder + n) == null) return false;
            return true;
        }

        /// <summary>Hides the sprites the models replace. False (and nothing changed) when the models are not in the build.</summary>
        public bool Attach(Hd2dView view)
        {
            View = view;
            if (!Available())
            {
                Debug.LogWarning("chaos ruins3d: the models are missing, the view keeps its sprites");
                return false;
            }
            view.Skip = Hd2dRuins.Replaces;
            attached = true;
            return true;
        }

        void OnDestroy() { if (attached && View != null && View.Skip == (Func<Hd2dPiece, bool>)Hd2dRuins.Replaces) View.Skip = null; }

        /// <summary>Places the models for the current world (the layout is the view's: same origin, pitch and art slant).</summary>
        public void Build()
        {
            foreach (var g in made) if (g != null) Destroy(g);
            made.Clear();
            Placed = 0;
            if (!attached || World == null || View == null) return;
            var pieces = Hd2d.Layout(World, World.Center, View.Pitch, null, !View.StraightArt);
            var plan = Hd2dRuins.Plan(pieces, World.Center);
            foreach (var q in plan)
            {
                var prefab = Prefab(q.Piece);
                if (prefab == null) continue;
                var go = Instantiate(prefab, transform);
                go.name = q.Piece;
                go.transform.localPosition = new Vector3(q.X, q.Y, q.Z);
                go.transform.localRotation = Quaternion.Euler(0f, q.Yaw, 0f);
                go.transform.localScale = Vector3.one * q.Scale;
                Restyle(go);
                made.Add(go);
                Placed++;
            }
            Debug.Log("chaos ruins3d: placed " + Placed + " models of " + plan.Count + " planned");
        }

        void Restyle(GameObject go)
        {
            foreach (var r in go.GetComponentsInChildren<Renderer>())
            {
                var src = r.sharedMaterials;
                var dst = new Material[src.Length];
                for (int i = 0; i < src.Length; i++) dst[i] = Styled(src[i]);
                r.sharedMaterials = dst;
                r.shadowCastingMode = ShadowCastingMode.On;
                r.receiveShadows = true;
            }
        }

        Material Styled(Material m)
        {
            if (m == null) return null;
            if (styled.TryGetValue(m, out var s)) return s;
            s = new Material(m) { name = m.name + " (dark)" };
            Color c = m.HasProperty("_Color") ? m.color : Color.grey;
            // the importer hands over the mtl's Kd as it is: Core restyles it from there
            var st = Hd2dRuins.Restyle(m.name, c.r, c.g, c.b);
            s.color = new Color(st.R, st.G, st.B, 1f);
            if (s.HasProperty("_Glossiness")) s.SetFloat("_Glossiness", st.Smoothness);
            if (s.HasProperty("_Metallic")) s.SetFloat("_Metallic", 0f);
            if (st.Emissive)
            {
                s.EnableKeyword("_EMISSION");
                s.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
                s.SetColor("_EmissionColor", new Color(st.EmitR, st.EmitG, st.EmitB));
            }
            styled[m] = s;
            return s;
        }
    }
}
