// Screenshot mode of the HD-2D view (O432): `ChaosUnity -chaosHd2dShot OUT_DIR` skips the login, builds the offline demo room
// (Core/Hd2dDemo.cs), renders it once in the classic flat view and once in HD-2D into a 1200 x 880 texture (the 15 : 11
// shape of the classic view), writes classic.png and hd2d.png, then hd2d_3d.png (the 3D architecture test,
// Unity/Hd2dRuins3d.cs, when its models are in the build) to OUT_DIR and quits (exit code 0, or 1 with the reason in
// the log). It needs no server and no game files: the art is the synthetic demo art, unless the real pair is found
// (`-chaosPair DIR`, the env CHAOS_PAIR_DIR, or things/ beside the executable) and holds the temple tileset (pair 60).
// The CI run (unity-prototype.yml, Linux target) runs it under xvfb with software OpenGL.
using System;
using System.Collections;
using System.IO;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class Hd2dShot : MonoBehaviour
    {
        public string OutDir;
        public const int Width = 1200, Height = 880;

        static string Arg(string name)
        {
            var args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++)
                if (args[i] == name) return args[i + 1];
            return null;
        }

        public static bool Requested(out string dir)
        {
            dir = Arg("-chaosHd2dShot");
            return !string.IsNullOrEmpty(dir);
        }

        void Start() { StartCoroutine(Run()); }

        IEnumerator Run()
        {
            // xvfb reports a 0 Hz screen: no vsync, so frames never wait on a swap
            QualitySettings.vSyncCount = 0;
            Application.targetFrameRate = 30;
            Debug.Log("chaos hd2d shot: " + SystemInfo.graphicsDeviceType + ", " + SystemInfo.graphicsDeviceName + ", " + SystemInfo.graphicsDeviceVersion);
            int code = 0;
            var body = Body();
            while (true)
            {
                bool more;
                try { more = body.MoveNext(); }
                catch (Exception e)
                {
                    Debug.LogError("chaos hd2d shot failed: " + e);
                    code = 1;
                    break;
                }
                if (!more) break;
                yield return body.Current;
            }
            if (rt != null) rt.Release();
            Application.Quit(code);
        }

        RenderTexture rt;

        IEnumerator Body()
        {
            Directory.CreateDirectory(OutDir);
            string source = Demo(out World world, out SprFile spr);
            Debug.Log("chaos hd2d shot: art " + source);
            var atlas = new SpriteAtlas(spr);
            Debug.Log("chaos hd2d shot: atlas ready");

            var camGo = new GameObject("Camera");
            var cam = camGo.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color32(12, 10, 14, 255);
            rt = new RenderTexture(Width, Height, 24, RenderTextureFormat.ARGB32);
            var tex = new Texture2D(Width, Height, TextureFormat.RGB24, false);
            cam.targetTexture = rt;

            // classic: the flat 15 x 11 view
            var mapGo = new GameObject("Map");
            var map = mapGo.AddComponent<MapView>();
            map.World = world;
            map.Atlas = atlas;
            cam.orthographic = true;
            cam.orthographicSize = ChaosApp.ViewTilesH / 2f;
            cam.transform.SetPositionAndRotation(new Vector3(0.5f, -0.5f, -10), Quaternion.identity);
            // no frame waits: xvfb with software GL may never finish a frame, so build and render by hand
            Debug.Log("chaos hd2d shot: building the classic mesh");
            map.Refresh();
            Debug.Log("chaos hd2d shot: rendering classic");
            Save(cam, tex, "classic.png");
            Debug.Log("chaos hd2d shot: wrote classic.png");

            // HD-2D: the same world in the 3D scene
            map.SetVisible(false);
            var hdGo = new GameObject("Hd2d");
            hdGo.SetActive(false);
            var hd = hdGo.AddComponent<Hd2dView>();
            hd.World = world;
            hd.Atlas = atlas;
            hd.Cam = cam;
            hd.StraightArt = source.StartsWith("synthetic", StringComparison.Ordinal);
            hdGo.SetActive(true);
            Debug.Log("chaos hd2d shot: building the HD-2D meshes");
            hd.Refresh();
            if (hd.Particles != null) { hd.Particles.Prewarm(4f); hd.Particles.BuildMesh(); }   // dust and embers without a frame
            Debug.Log("chaos hd2d shot: rendering HD-2D");
            Save(cam, tex, "hd2d.png");
            Debug.Log("chaos hd2d shot: wrote classic.png and hd2d.png to " + OutDir);

            // 3D architecture test (Ruins3d): the same room with 3D pieces in place of the sprite floors, walls, pillars and lights
            var ruinsGo = new GameObject("Ruins3d");
            var ruins = ruinsGo.AddComponent<Hd2dRuins3d>();
            ruins.World = world;
            if (ruins.Attach(hd))
            {
                Debug.Log("chaos hd2d shot: building the 3D architecture");
                hd.Refresh();   // the view skips the sprites the models replace
                ruins.Build();
                Debug.Log("chaos hd2d shot: rendering HD-2D with 3D architecture");
                Save(cam, tex, "hd2d_3d.png");
                Debug.Log("chaos hd2d shot: wrote hd2d_3d.png (" + ruins.Placed + " models)");
            }
            else Debug.LogWarning("chaos hd2d shot: no 3D models in this build, hd2d_3d.png skipped");
            yield break;
        }

        void Save(Camera cam, Texture2D tex, string name)
        {
            cam.Render();
            var old = RenderTexture.active;
            RenderTexture.active = rt;
            tex.ReadPixels(new Rect(0, 0, Width, Height), 0, 0);
            tex.Apply();
            RenderTexture.active = old;
            File.WriteAllBytes(Path.Combine(OutDir, name), tex.EncodeToPNG());
        }

        /// <summary>The demo world and its sprites: the real pair's temple room when found, else the synthetic art.</summary>
        static string Demo(out World world, out SprFile spr)
        {
            string dir = Arg("-chaosPair") ?? Environment.GetEnvironmentVariable("CHAOS_PAIR_DIR") ?? Path.Combine(Path.GetDirectoryName(Application.dataPath) ?? ".", "things");
            string d = Path.Combine(dir, "Tibia.dat"), s = Path.Combine(dir, "Tibia.spr");
            if (File.Exists(d) && File.Exists(s))
            {
                try
                {
                    var dat = DatFile.Load(d);
                    var room = Hd2dDemo.FromPair(dat);
                    if (room != null)
                    {
                        world = room.World;
                        spr = SprFile.Open(s);
                        return "real pair, temple room (" + dir + ")";
                    }
                }
                catch (Exception e) { Debug.LogWarning("chaos hd2d shot: the pair in " + dir + " was not usable: " + e.Message); }
            }
            var demo = Hd2dDemo.Synthetic();
            world = demo.World;
            spr = new SprFile(new MemoryStream(demo.SprBytes));
            return "synthetic placeholder sprites (no game files)";
        }
    }
}
