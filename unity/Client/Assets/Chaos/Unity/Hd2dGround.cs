// Grounding of the HD-2D view (O432): contact shadows under every upright piece and ambient occlusion along the foot of
// walls. The maths is Core (Hd2d.ContactShadows, Hd2d.WallAo); this builds one small dynamic mesh of flat quads just above
// the floor, drawn with Resources/Hd2dBlob.shader (procedural soft alpha, no texture). Hd2dView calls Build once per Build.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace Chaos.Client
{
    public sealed class Hd2dGround
    {
        readonly Mesh mesh = new Mesh { name = "chaos-hd2d-ground" };
        readonly List<Vector3> v = new List<Vector3>();
        readonly List<Vector4> uv = new List<Vector4>();   // x, y: quad coordinates 0..1; z: 0 blob, 1 wall strip; w: strength
        readonly List<int> t = new List<int>();
        readonly MeshRenderer renderer;
        readonly Material material;

        public Hd2dGround(Transform parent)
        {
            var shader = Resources.Load<Shader>("Hd2dBlob");
            if (shader == null) shader = Shader.Find("Sprites/Default");
            material = new Material(shader) { name = "chaos-hd2d-blob" };
            var go = new GameObject("ground shadows");
            go.transform.SetParent(parent, false);
            mesh.indexFormat = IndexFormat.UInt32;
            mesh.MarkDynamic();
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            renderer = go.AddComponent<MeshRenderer>();
            renderer.sharedMaterial = material;
            renderer.shadowCastingMode = ShadowCastingMode.Off;
            renderer.receiveShadows = false;
        }

        public bool Enabled { get { return renderer.enabled; } set { renderer.enabled = value; } }

        public void Build(List<Hd2dPiece> pieces)
        {
            v.Clear(); uv.Clear(); t.Clear();
            foreach (var s in Hd2d.WallAo(pieces))
            {
                // u runs along the wall, v from the wall (0) to the far edge (1); the strip lies south of the wall
                Add(s.X0, s.ZWall - s.Depth, s.X1, s.ZWall, s.Y, 1f, s.Strength, true);
            }
            foreach (var b in Hd2d.ContactShadows(pieces))
                Add(b.X - b.RadiusX, b.Z - b.RadiusZ, b.X + b.RadiusX, b.Z + b.RadiusZ, b.Y, 0f, b.Strength, false);
            mesh.Clear();
            mesh.SetVertices(v);
            mesh.SetUVs(0, uv);
            mesh.SetTriangles(t, 0);
            mesh.RecalculateBounds();
        }

        // corners: south-west, south-east, north-east, north-west seen from above (+y); the winding faces up
        void Add(float x0, float z0, float x1, float z1, float y, float mode, float strength, bool strip)
        {
            int i = v.Count;
            v.Add(new Vector3(x0, y, z0)); v.Add(new Vector3(x1, y, z0)); v.Add(new Vector3(x1, y, z1)); v.Add(new Vector3(x0, y, z1));
            // strip: v = 1 at the wall (north edge), 0 at the far south edge
            uv.Add(new Vector4(0, 0, mode, strength)); uv.Add(new Vector4(1, 0, mode, strength));
            uv.Add(new Vector4(1, 1, mode, strength)); uv.Add(new Vector4(0, 1, mode, strength));
            t.Add(i); t.Add(i + 2); t.Add(i + 1);
            t.Add(i); t.Add(i + 3); t.Add(i + 2);
        }
    }
}
