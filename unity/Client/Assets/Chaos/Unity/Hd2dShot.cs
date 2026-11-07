// Screenshot mode of the HD-2D view (O432): `ChaosUnity -chaosHd2dShot OUT_DIR` skips the login, builds the offline demo room
// (Core/Hd2dDemo.cs), renders it once in the classic flat view and once in HD-2D into a 1200 x 880 texture (the 15 : 11
// shape of the classic view), writes classic.png and hd2d.png, then hd2d_3d.png (the 3D architecture test,
// Unity/Hd2dRuins3d.cs, when its models are in the build, with the 3D characters of Unity/Hd2dChars3d.cs when theirs are) and
// hd2d_3d_close.png (the same scene from half the distance, aimed at the hero) and hd2d_3d_cast.png (the line-up: a 3D character per
// class group and the four dark skeleton monsters on the temple floor, with name labels drawn from Core/PixelText.cs, the camera fitted
// to the cast) to OUT_DIR, then front_art.png (the front-art test scene, Unity/FrontArtScene.cs: a blocky diorama with front-facing pixel
// sprites, wide) and front_art_close.png (the four characters across a brazier), and quits (exit code 0, or 1 with the reason in the
// log; a failure of the front-art scene alone is logged as an error and does not stop the run). It needs no server and no game files: the art is the synthetic demo art, unless the real pair is found
// (`-chaosPair DIR`, the env CHAOS_PAIR_DIR, or things/ beside the executable) and holds the temple tileset (pair 60).
// The CI run (unity-prototype.yml, Linux target) runs it under xvfb with software OpenGL.
using System;
using System.Collections;
using System.Collections.Generic;
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
            GameObject charsGo = null;
            var ruinsGo = new GameObject("Ruins3d");
            var ruins = ruinsGo.AddComponent<Hd2dRuins3d>();
            ruins.World = world;
            if (ruins.Attach(hd))
            {
                // 3D characters (Chars3d) in place of the creature sprites; without their models the sprites stay
                charsGo = new GameObject("Chars3d");
                var chars = charsGo.AddComponent<Hd2dChars3d>();
                chars.World = world;
                bool haveChars = chars.Attach(hd);
                Debug.Log("chaos hd2d shot: building the 3D architecture");
                hd.Refresh();   // the view skips the sprites the models replace
                ruins.Build();
                if (haveChars) { chars.Build(); Debug.Log("chaos hd2d shot: placed " + chars.Placed + " 3D characters"); }
                Debug.Log("chaos hd2d shot: rendering HD-2D with 3D architecture");
                Save(cam, tex, "hd2d_3d.png");
                Debug.Log("chaos hd2d shot: wrote hd2d_3d.png (" + ruins.Placed + " models)");

                var camPos0 = cam.transform.position;
                var camRot0 = cam.transform.rotation;
                // the same scene from half the distance, aimed at the hero, so the characters show in detail
                if (haveChars && world.Player != null && chars.PointOf(world.Player.Id, 0.9f, out Vector3 heroPt))
                {
                    var camPos = cam.transform.position;
                    float dist = Vector3.Distance(camPos, heroPt);
                    var toHero = (heroPt - camPos).normalized;
                    cam.transform.SetPositionAndRotation(heroPt - toHero * (dist * 0.5f), Quaternion.LookRotation(toHero, Vector3.up));
                    Debug.Log("chaos hd2d shot: rendering the close view");
                    Save(cam, tex, "hd2d_3d_close.png");
                    Debug.Log("chaos hd2d shot: wrote hd2d_3d_close.png");
                }

                // the line-up: the room's two creatures give way to the cast (a class per group in front, four dark skeletons behind)
                cam.transform.SetPositionAndRotation(camPos0, camRot0);
                if (haveChars && demoRoom != null) CastShot(cam, tex, hd, ruins, chars);
            }
            else Debug.LogWarning("chaos hd2d shot: no 3D models in this build, hd2d_3d.png skipped");

            // 3D world (World3d): a meadow with a path, a pond and trees from the real pair, the ids picked by the sprites' pixels
            DestroyImmediate(ruinsGo);   // the demo room's models and characters go; no frame runs to destroy them later
            if (charsGo != null) DestroyImmediate(charsGo);
            Outdoor(cam, tex, hd, atlas, source);

            // the front-art scene: the HD-2D view and the world models give way to it
            hdGo.SetActive(false);
            var w3 = GameObject.Find("World3d");
            if (w3 != null) DestroyImmediate(w3);
            FrontArt(cam, tex);
            yield break;
        }

        /// <summary>The front-art scene (Unity/FrontArtScene.cs): front_art.png wide and front_art_close.png on the four characters.
        /// Log lines start with "chaos front art:". A failure is logged and does not stop the run: its shaders only compile in CI.</summary>
        void FrontArt(Camera cam, Texture2D tex)
        {
            FrontArtScene scene = null;
            try
            {
                Debug.Log("chaos front art: building the scene");
                scene = FrontArtScene.Open(cam, false, false);
                Debug.Log("chaos front art: " + scene.ActorCount + " characters, " + scene.LightCount + " lights, " + (scene.Particles != null ? scene.Particles.QuadCount : 0) + " particle quads");
                scene.FrameWide();
                scene.Tick(0.4f);
                Debug.Log("chaos front art: rendering the wide view");
                Save(cam, tex, "front_art.png");
                Debug.Log("chaos front art: wrote front_art.png");
                scene.FrameClose();
                scene.Tick(0.4f);
                Debug.Log("chaos front art: rendering the close view");
                Save(cam, tex, "front_art_close.png");
                Debug.Log("chaos front art: wrote front_art_close.png");
                scene.DebugCastsOnTop(true, false);
                Save(cam, tex, "front_art_debug_z.png");
                scene.DebugCastsOnTop(false, true);
                Save(cam, tex, "front_art_debug_s.png");
                Debug.Log("chaos front art: wrote front_art_debug_z.png and front_art_debug_s.png");
            }
            catch (Exception e)
            {
                Debug.LogError("chaos front art: failed: " + e);
            }
            finally
            {
                if (scene != null) DestroyImmediate(scene.gameObject);
            }
        }

        // the temple room the demo built (null: no line-up)
        static Hd2dDemo demoRoom;

        void CastShot(Camera cam, Texture2D tex, Hd2dView hd, Hd2dRuins3d ruins, Hd2dChars3d chars)
        {
            var cast = demoRoom.Lineup();
            chars.Clear();
            hd.Refresh();      // the view lays the new creatures out and skips their sprites
            ruins.Build();     // the torches the line-up added
            chars.Build();
            Debug.Log("chaos hd2d shot: line-up of " + cast.Count + " creatures, " + chars.Placed + " 3D characters placed");
            // fit the camera: keep its angle, slide it along its view direction until every head and foot is inside the picture
            var pts = new List<Vector3>();
            foreach (var c in cast)
                foreach (float h in new[] { 0f, 2.5f })
                    if (chars.PointOf(c.Id, h, out Vector3 p)) pts.Add(p);
            if (pts.Count == 0) { Debug.LogWarning("chaos hd2d shot: the line-up has no characters, hd2d_3d_cast.png skipped"); return; }
            FitCamera(cam, pts);
            Debug.Log("chaos hd2d shot: rendering the line-up");
            Save(cam, tex, "hd2d_3d_cast.png", px =>
            {
                for (int i = 0; i < cast.Count; i++)
                {
                    if (!chars.PointOf(cast[i].Id, 2.2f, out Vector3 head)) continue;
                    Vector3 sp = cam.WorldToScreenPoint(head);
                    bool monster = cast[i].Type == 1;
                    int stagger = monster ? 0 : (i % 2) * 18;
                    DrawLabel(px, cast[i].Name, Mathf.RoundToInt(sp.x), Mathf.RoundToInt(sp.y) + 6 + stagger, monster ? new Color32(240, 150, 130, 255) : new Color32(245, 225, 160, 255));
                }
            });
            Debug.Log("chaos hd2d shot: wrote hd2d_3d_cast.png");
        }

        /// <summary>Slides the camera back along its view direction (angle kept) from the cast's centre until every point is in the picture.</summary>
        static void FitCamera(Camera cam, List<Vector3> pts)
        {
            Vector3 centre = Vector3.zero;
            foreach (var p in pts) centre += p;
            centre /= pts.Count;
            Vector3 fwd = cam.transform.forward;
            for (float d = 4f; d < 80f; d += 0.25f)
            {
                cam.transform.position = centre - fwd * d;
                bool ok = true;
                foreach (var p in pts)
                {
                    Vector3 v = cam.WorldToViewportPoint(p);
                    if (v.z <= 0f || v.x < 0.05f || v.x > 0.95f || v.y < 0.06f || v.y > 0.90f) { ok = false; break; }
                }
                if (ok) { Debug.Log("chaos hd2d shot: the line-up fits at distance " + d.ToString("0.00")); return; }
            }
            Debug.LogWarning("chaos hd2d shot: the line-up did not fit in any distance up to 80");
        }

        /// <summary>A text centred on (cx, cy) (pixels from the bottom left) with a dark outline, in the 5 x 7 font of Core/PixelText.cs.</summary>
        static void DrawLabel(Color32[] px, string text, int cx, int cy, Color32 col)
        {
            const int scale = 2;
            var mask = PixelText.Mask(text, scale, out int w, out int h);
            int x0 = Mathf.Clamp(cx - w / 2, 2, Width - w - 2), y0 = Mathf.Clamp(cy, 2, Height - h - 2);
            var dark = new Color32(10, 8, 12, 255);
            for (int pass = 0; pass < 2; pass++)
                for (int y = 0; y < h; y++)
                    for (int x = 0; x < w; x++)
                    {
                        if (!mask[y * w + x]) continue;
                        int px0 = x0 + x, py0 = y0 + (h - 1 - y);   // the mask's top row is the top of the text
                        if (pass == 0)
                        {
                            for (int dy = -1; dy <= 1; dy++)
                                for (int dx = -1; dx <= 1; dx++)
                                {
                                    int xx = px0 + dx, yy = py0 + dy;
                                    if (xx >= 0 && xx < Width && yy >= 0 && yy < Height) px[yy * Width + xx] = dark;
                                }
                        }
                        else px[py0 * Width + px0] = col;
                    }
        }

        void Outdoor(Camera cam, Texture2D tex, Hd2dView hd, SpriteAtlas roomAtlas, string source)
        {
            if (realDat == null) { Debug.Log("chaos hd2d shot: no real sprite pair, hd2d_3d_outdoor.png skipped"); return; }
            var atlas = roomAtlas;
            if (!source.StartsWith("real pair", StringComparison.Ordinal)) atlas = new SpriteAtlas(SprFile.Open(realSpr));
            var cls = new SpriteClassifier(id => id == 0 ? null : atlas.Raw(id));
            var sw = System.Diagnostics.Stopwatch.StartNew();
            var outdoor = Hd2dDemo.Outdoor(realDat, id => id == 0 ? null : atlas.Raw(id), cls);
            if (outdoor == null) { Debug.Log("chaos hd2d shot: the pair has no grass, water and tree to pick, hd2d_3d_outdoor.png skipped"); return; }
            Debug.Log("chaos hd2d shot: outdoor ids " + outdoor.Ids + " (picked from pixels in " + sw.ElapsedMilliseconds + " ms, " + cls.Count + " items measured)");
            hd.World = outdoor.World;
            hd.Atlas = atlas;
            hd.StraightArt = false;
            var go = new GameObject("World3d");
            var ruins = go.AddComponent<Hd2dRuins3d>();
            ruins.World = outdoor.World;
            ruins.WorldMode = true;
            if (!ruins.Attach(hd)) { Debug.LogWarning("chaos hd2d shot: no 3D models in this build, hd2d_3d_outdoor.png skipped"); return; }
            var chars = go.AddComponent<Hd2dChars3d>();
            chars.World = outdoor.World;
            bool haveChars = chars.Attach(hd);
            hd.Refresh();   // the view skips the sprites the models replace
            ruins.Build();
            if (haveChars) chars.Build();
            Debug.Log("chaos hd2d shot: 3D world placed " + ruins.Placed + " models in " + ruins.LastBuildMs.ToString("0.0") + " ms");
            bool again = ruins.Refresh();   // nothing changed: no rebuild
            Debug.Log("chaos hd2d shot: a second Refresh with nothing changed rebuilt: " + again);
            Debug.Log("chaos hd2d shot: rendering the 3D world");
            Save(cam, tex, "hd2d_3d_outdoor.png");
            Debug.Log("chaos hd2d shot: wrote hd2d_3d_outdoor.png");
        }

        // the real pair when found, even without the temple tileset (the outdoor demo needs only its grass, water and tree)
        static DatFile realDat;
        static string realSpr;

        void Save(Camera cam, Texture2D tex, string name, Action<Color32[]> overlay = null)
        {
            cam.Render();
            var old = RenderTexture.active;
            RenderTexture.active = rt;
            tex.ReadPixels(new Rect(0, 0, Width, Height), 0, 0);
            tex.Apply();
            RenderTexture.active = old;
            if (overlay != null)
            {
                var px = tex.GetPixels32();
                overlay(px);
                tex.SetPixels32(px);
                tex.Apply();
            }
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
                    realDat = dat; realSpr = s;
                    var room = Hd2dDemo.FromPair(dat);
                    if (room != null)
                    {
                        demoRoom = room;
                        world = room.World;
                        spr = SprFile.Open(s);
                        return "real pair, temple room (" + dir + ")";
                    }
                }
                catch (Exception e) { Debug.LogWarning("chaos hd2d shot: the pair in " + dir + " was not usable: " + e.Message); }
            }
            var demo = Hd2dDemo.Synthetic();
            demoRoom = demo;
            world = demo.World;
            spr = new SprFile(new MemoryStream(demo.SprBytes));
            return "synthetic placeholder sprites (no game files)";
        }
    }
}
