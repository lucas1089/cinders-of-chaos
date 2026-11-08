// The demo tour (unity/README.md "Demo tour video"): `ChaosUnity -chaosDemoTour OUT_DIR` starts a fake game server in this process
// (Core/DemoTour.cs), logs in to it through the normal ChaosApp flow (login port, character list, game port with the guard challenge),
// switches on the F8 front-art live view and plays about 23 seconds: walks, fights, casts, talks to an NPC, opens and closes windows in
// turn, with the HUD (plate, hotbar, chat, buff bar, toasts) on. Every frame is saved as OUT_DIR/demo_tour_0000.png at 60 a second
// (Time.captureFramerate = 60: the game clock is the frame count, never the wall clock) and the CI job encodes them to demo_tour.mp4.
// Together with -chaosHd2dShot the screenshots run first and the tour follows in the same process (Hd2dShot hands over).
// Log lines start with "chaos demo tour:". Exit code 0 when every frame was written, 1 with the reason in the log.
using System;
using System.Collections;
using System.IO;
using System.Text;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        public const int TourFps = 60, TourWidth = 1280, TourHeight = 720;

        static string TourArg(string name)
        {
            var args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++)
                if (args[i] == name) return args[i + 1];
            return null;
        }

        public static bool DemoTourRequested(out string dir)
        {
            dir = TourArg("-chaosDemoTour");
            return !string.IsNullOrEmpty(dir);
        }

        // -chaosDemoTour alone: the normal app starts (Boot) and the director drives it
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void BootDemoTour()
        {
            if (!DemoTourRequested(out string dir) || Hd2dShot.Requested(out _)) return;
            new GameObject("Demo tour").AddComponent<TourDirector>().Begin(dir);
        }

        /// <summary>After the screenshots of -chaosHd2dShot: the shot objects go, the app and the director start in the same process.</summary>
        public static void HandOverToDemoTour(string dir, GameObject keep)
        {
            foreach (var go in UnityEngine.SceneManagement.SceneManager.GetActiveScene().GetRootGameObjects())
                if (go != keep) Destroy(go);
            var app = new GameObject("Cinders of Chaos");
            DontDestroyOnLoad(app);
            app.AddComponent<ChaosApp>();
            new GameObject("Demo tour").AddComponent<TourDirector>().Begin(dir);
        }

        /// <summary>The art of the tour: the real pair's outdoor ids when found, else its temple floors, else the synthetic placeholder art.</summary>
        static TourArt TourChooseArt(out DatFile dat, out SprFile spr, out SpriteAtlas atlas, out string source)
        {
            string dir = TourArg("-chaosPair") ?? Environment.GetEnvironmentVariable("CHAOS_PAIR_DIR") ?? Path.Combine(Path.GetDirectoryName(Application.dataPath) ?? ".", "things");
            string d = Path.Combine(dir, "Tibia.dat"), s = Path.Combine(dir, "Tibia.spr");
            if (File.Exists(d) && File.Exists(s))
            {
                try
                {
                    dat = DatFile.Load(d);
                    spr = SprFile.Open(s);
                    atlas = new SpriteAtlas(spr);
                    var sa = atlas;
                    var ids = Hd2dDemo.PickOutdoor(dat, id => id == 0 ? null : sa.Raw(id), new SpriteClassifier(id => id == 0 ? null : sa.Raw(id)));
                    if (ids != null) { source = "real pair, outdoor ids (" + ids + ")"; return TourArt.FromOutdoor(ids).Probe(dat); }
                    var temple = DemoIds.Temple();
                    if (dat.Item(temple.Torch) != null && dat.Outfit(temple.OutfitA) != null && dat.Outfit(temple.OutfitB) != null)
                    {
                        source = "real pair, temple floors";
                        return TourArt.FromDemo(temple).Probe(dat);
                    }
                    Debug.LogWarning("chaos demo tour: the pair in " + dir + " has neither outdoor ids nor the temple tileset, using the synthetic art");
                }
                catch (Exception e) { Debug.LogWarning("chaos demo tour: the pair in " + dir + " was not usable: " + e.Message); }
            }
            var demo = Hd2dDemo.Synthetic();
            dat = demo.Dat;
            spr = new SprFile(new MemoryStream(demo.SprBytes));
            atlas = new SpriteAtlas(spr);
            source = "synthetic placeholder art";
            return TourArt.FromDemo(DemoIds.Synthetic()).Probe(dat);
        }

        sealed class TourDirector : MonoBehaviour
        {
            enum Phase { Start, Login, Entering, Settle, Record, Done }

            ChaosApp app;
            string dir;
            FakeGameServer server;
            Phase phase = Phase.Start;
            int tick, settleLeft, recTick, saved, walked;
            bool captureNow, attackedSkeleton, attackedGhoul, castFury, castHeal, said, shopOpened, shopClosed, spellbook, partyShown, treeShown, skillsShown;
            int menuStep;
            float startedAt;
            const int TotalFrames = (int)(TourPlan.Total * TourFps / 1000.0) + 1;

            public void Begin(string outDir)
            {
                dir = outDir;
                DontDestroyOnLoad(gameObject);
            }

            /// <summary>The game clock: one fixed step per frame.</summary>
            double Clock => tick * (1000.0 / TourFps);

            void Start()
            {
                startedAt = Time.realtimeSinceStartup;
                StartCoroutine(Capture());
            }

            void Fail(string why)
            {
                Debug.LogError("chaos demo tour: failed: " + why);
                try { server?.Dispose(); } catch (Exception) { }
                phase = Phase.Done;
                Application.Quit(1);
            }

            void Update()
            {
                if (phase == Phase.Done) return;
                tick++;
                try { Step(); }
                catch (Exception e) { Fail(e.ToString()); }
            }

            void Step()
            {
                if (app == null)
                {
                    app = FindObjectOfType<ChaosApp>();
                    if (app == null) return;
                }
                float wall = Time.realtimeSinceStartup - startedAt;
                if (phase != Phase.Record && wall > 300f) { Fail("no recording after 300 s (phase " + phase + ", status '" + app.status + "', server problem '" + (server?.Problem ?? "") + "', logins " + (server?.Logins ?? 0) + ")"); return; }
                if (wall > 2400f) { Fail("the tour ran over 2400 s"); return; }
                switch (phase)
                {
                    case Phase.Start: StartTour(); break;
                    case Phase.Login:
                        if (app.login != null && app.login.Error != null) { Fail("login: " + app.login.Error); break; }
                        if (app.screen == Screen.Characters && app.login != null && app.login.Characters.Count > 0)
                        {
                            Debug.Log("chaos demo tour: logged in, character " + app.login.Characters[0].Name);
                            app.Enter(app.login.Characters[0]);
                            phase = Phase.Entering;
                        }
                        else if (app.status.StartsWith("Login failed", StringComparison.Ordinal)) Fail(app.status);
                        break;
                    case Phase.Entering:
                        if (app.session != null && app.session.Closed != null) { Fail("the session closed: " + app.session.Closed); break; }
                        if (app.session != null && app.session.Parser.LoggedIn && app.world != null && app.world.Player != null && server.InGame)
                        {
                            app.live = true;   // F8: the front-art live view
                            app.ApplyHd2d();
                            app.FindWindow<HotkeyBarWindow>().Open = true;
                            settleLeft = 150;
                            phase = Phase.Settle;
                            Debug.Log("chaos demo tour: in the world at " + app.world.Player.Position + ", front-art live view on");
                        }
                        break;
                    case Phase.Settle:
                        if (--settleLeft <= 0)
                        {
                            Debug.Log("chaos demo tour: recording " + TotalFrames + " frames at " + UnityEngine.Screen.width + "x" + UnityEngine.Screen.height);
                            phase = Phase.Record;
                        }
                        break;
                    case Phase.Record: Record(); break;
                }
            }

            void StartTour()
            {
                Directory.CreateDirectory(dir);
                QualitySettings.vSyncCount = 0;
                Time.captureFramerate = TourFps;
                UnityEngine.Screen.SetResolution(TourWidth, TourHeight, false);
                GameSession.TestClock = () => Clock;
                var art = TourChooseArt(out app.dat, out app.spr, out app.atlas, out string source);
                Debug.Log("chaos demo tour: art " + source);
                server = new FakeGameServer(art);
                server.Begin();
                // the app reads the server's key, RSA modulus and wire from the environment (GuardKey, RsaModulus, IdentityChoice)
                var hex = new StringBuilder();
                foreach (byte b in server.GuardKey) hex.Append(b.ToString("x2"));
                Environment.SetEnvironmentVariable("CHAOS_CLIENT_KEY", hex.ToString());
                Environment.SetEnvironmentVariable("CHAOS_RSA_PUBLIC", server.RsaModulus);
                Environment.SetEnvironmentVariable("CHAOS_UNITY_IDENTITY", "extended");
                app.host = "127.0.0.1";
                app.port = server.Port.ToString();
                app.account = "demo";
                app.password = "demo";
                Debug.Log("chaos demo tour: fake server on port " + server.Port + ", logging in");
                app.DoLogin();
                phase = Phase.Login;
            }

            void Record()
            {
                double t = recTick * (1000.0 / TourFps);
                recTick++;
                var s = app.session;
                if (s == null || s.Closed != null) { Fail("the session closed during the tour: " + (s?.Closed ?? "gone")); return; }
                Plan(t, s);
                server.Advance(t);
                captureNow = true;
            }

            /// <summary>The player's side of the tour: the same times the server script keeps (TourPlan).</summary>
            void Plan(double t, GameSession s)
            {
                if (t >= TourPlan.WalkFrom && walked < TourPlan.Walk.Length && s.CanWalk) { s.Walk(TourPlan.Walk[walked]); walked++; }
                if (!attackedSkeleton && t >= TourPlan.AttackSkeleton) { attackedSkeleton = true; s.Attack(FakeGameServer.SkeletonId); }
                if (!castFury && t >= TourPlan.CastFury - 40) { castFury = true; s.Say("exori gran"); }
                if (!attackedGhoul && t >= TourPlan.AttackGhoul) { attackedGhoul = true; s.Attack(FakeGameServer.GhoulId); }
                if (!castHeal && t >= TourPlan.CastHeal - 40) { castHeal = true; s.Say("exura gran ico"); }
                if (!said && t >= TourPlan.SayHi)
                {
                    said = true;
                    s.SayToNpc("hi");
                    app.FindWindow<NpcTalkWindow>().Open = true;
                }
                if (!shopOpened && t >= TourPlan.ShopOpens + 150)
                {
                    shopOpened = true;
                    app.FindWindow<NpcTradeWindow>().Open = true;
                }
                if (!shopClosed && t >= TourPlan.ShopCloses)
                {
                    shopClosed = true;
                    s.NpcClose();
                    app.FindWindow<NpcTradeWindow>().Open = false;
                    app.FindWindow<NpcTalkWindow>().Open = false;
                }
                Toggle(ref spellbook, t, TourPlan.SpellbookOpens, TourPlan.SpellbookCloses, app.FindWindow<SpellbookWindow>());
                if (!partyShown && t >= TourPlan.PartyJoins + 200) { partyShown = true; app.FindWindow<PartyFramesWindow>().Open = true; }
                if (partyShown && t >= TourPlan.PartyCloses) app.FindWindow<PartyFramesWindow>().Open = false;
                Toggle(ref treeShown, t, TourPlan.TreeOpens, TourPlan.TreeCloses, app.FindWindow<PassiveTreeWindow>());
                Toggle(ref skillsShown, t, TourPlan.SkillsOpens, TourPlan.SkillsCloses, app.FindWindow<SkillsWindow>());
                // the top menu: one drop-down, then another
                int categories = TopMenu.Categories.Length + 1;
                if (menuStep == 0 && t >= TourPlan.MenuFirst) { menuStep = 1; app.topMenuOpen = 0; }
                if (menuStep == 1 && t >= TourPlan.MenuSecond) { menuStep = 2; app.topMenuOpen = Math.Min(2, categories - 1); }
            }

            static void Toggle(ref bool shown, double t, double opens, double closes, GameWindow win)
            {
                if (!shown && t >= opens && t < closes) { shown = true; win.Open = true; }
                else if (shown && t >= closes) { shown = false; win.Open = false; }
            }

            IEnumerator Capture()
            {
                var eof = new WaitForEndOfFrame();
                while (true)
                {
                    yield return eof;
                    if (!captureNow || phase != Phase.Record) continue;
                    captureNow = false;
                    var tex = ScreenCapture.CaptureScreenshotAsTexture();
                    if (tex == null) { Fail("ScreenCapture gave no texture"); yield break; }
                    byte[] png = tex.EncodeToPNG();
                    Destroy(tex);
                    File.WriteAllBytes(Path.Combine(dir, "demo_tour_" + saved.ToString("0000") + ".png"), png);
                    saved++;
                    if (saved >= TotalFrames)
                    {
                        Debug.Log("chaos demo tour: wrote " + saved + " frames to " + dir + " (server: " + server.Steps + " steps, " + server.Attacks + " attacks, script " + (server.Finished ? "finished" : "NOT finished") + ")");
                        phase = Phase.Done;
                        try { server.Dispose(); } catch (Exception) { }
                        Application.Quit(server.Finished ? 0 : 1);
                        yield break;
                    }
                }
            }
        }
    }
}
