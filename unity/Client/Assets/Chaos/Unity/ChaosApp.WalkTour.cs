// The walking video (unity/README.md "Walking video"): `ChaosUnity -chaosWalkTour OUT_DIR` starts the demo tour's fake game server in this process with its walking
// mode (FakeGameServer.UseWalkTour: every step answered after a simulated 120 ms round trip, 8 directions, creatures that glide), logs in through the normal
// ChaosApp flow and records about 30 seconds at 1280x720, 60 frames a second: the hero walks a loop with held keys in all 8 directions, turns on the spot and
// walks a click path, in the classic view, HD-2D, the live front-art view and the 3D world (when the models are in the build), with a pt-BR caption at the top of
// each segment. The plan and the numbers are Core/WalkTour.cs (WalkTourPlan, WalkTourConductor); this file is the player side: the frame clock, the view switches,
// the click, the caption and the PNG frames (OUT_DIR/walk_tour_0000.png, the CI job encodes walk_tour.mp4).
// The keys go the player's way: the conductor gives a WalkInput mask to HandleWalk (ChaosApp.WalkMaskSource), WalkInputState folds it into a direction and
// GameSession.Walk sends the step, with prediction and pre-walk. Per segment a log line gives steps sent, steps confirmed and the longest time the drawn hero stood
// still while a key was held; over 50 ms the run fails (exit code 1, after the last frame, so the video can be looked at).
// Own process: next to -chaosHd2dShot, -chaosDemoTour or -chaosWindowSmoke those run instead. Log lines start with "chaos walk tour:".
using System;
using System.Collections;
using System.IO;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        public static bool WalkTourRequested(out string dir)
        {
            dir = TourArg("-chaosWalkTour");
            return !string.IsNullOrEmpty(dir);
        }

        // -chaosWalkTour alone: the normal app starts (Boot) and the director drives it
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void BootWalkTour()
        {
            if (!WalkTourRequested(out string dir) || Hd2dShot.Requested(out _) || DemoTourRequested(out _) || WindowSmokeRequested(out _)) return;
            new GameObject("Walk tour").AddComponent<WalkTourDirector>().Begin(dir);
        }

        sealed class WalkTourDirector : MonoBehaviour
        {
            enum Phase { Start, Login, Entering, Settle, Record, Done }

            const int MaxFrames = 75 * TourFps;   // the plan is about 33 s; a run that is still going after 75 s is stuck
            const int TailFrames = TourFps;        // a second of the last view after the plan

            ChaosApp app;
            string dir;
            FakeGameServer server;
            WalkTourConductor conductor;
            Phase phase = Phase.Start;
            int tick, settleLeft, recTick, recorded, saved, logged, tail;
            bool captureNow, recFrame, ending, with3d;
            float startedAt;
            GUIStyle capStyle;
            Texture2D capBg;

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
                Debug.LogError("chaos walk tour: failed: " + why);
                try { server?.Dispose(); } catch (Exception) { }
                if (app != null) app.WalkMaskSource = null;
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

            void LateUpdate()
            {
                if (phase != Phase.Record || !recFrame) return;
                recFrame = false;
                try
                {
                    conductor.Observe(1000.0 / TourFps);   // after the frame's update: the drawn position of the hero is final
                    LogReports();
                    captureNow = true;
                    recorded++;
                }
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
                if (wall > 2400f) { Fail("the walking video ran over 2400 s"); return; }
                switch (phase)
                {
                    case Phase.Start: StartTour(); break;
                    case Phase.Login:
                        if (app.login != null && app.login.Error != null) { Fail("login: " + app.login.Error); break; }
                        if (app.screen == Screen.Characters && app.login != null && app.login.Characters.Count > 0)
                        {
                            Debug.Log("chaos walk tour: logged in, character " + app.login.Characters[0].Name);
                            app.Enter(app.login.Characters[0]);
                            phase = Phase.Entering;
                        }
                        else if (app.status.StartsWith("Login failed", StringComparison.Ordinal)) Fail(app.status);
                        break;
                    case Phase.Entering:
                        if (app.session != null && app.session.Closed != null) { Fail("the session closed: " + app.session.Closed); break; }
                        if (app.session != null && app.session.Parser.LoggedIn && app.world != null && app.world.Player != null && server.InGame)
                        {
                            app.hd2d = false; app.live = false; app.world3d = false;   // the classic view first
                            app.ApplyHd2d();
                            settleLeft = 90;
                            phase = Phase.Settle;
                            Debug.Log("chaos walk tour: in the world at " + app.world.Player.Position);
                        }
                        break;
                    case Phase.Settle:
                        if (--settleLeft <= 0) StartRecording();
                        break;
                    case Phase.Record: Record(); break;
                }
            }

            void StartTour()
            {
                Directory.CreateDirectory(dir);
                QualitySettings.vSyncCount = 0;
                Time.captureFramerate = TourFps;
                UnityEngine.Screen.SetResolution(WalkTourPlan.Width, WalkTourPlan.Height, false);
                GameSession.TestClock = () => Clock;
                Loc.Set(Loc.Portuguese);   // the captions, and the HUD, in pt-BR
                server = TourStartServer(app, true);
                phase = Phase.Login;
            }

            void StartRecording()
            {
                with3d = app.world3dReady;
                if (!with3d) Debug.Log("chaos walk tour: the 3D world is skipped, the 3D models are not in this build");
                var host = new WalkTourHost { Session = app.session, World = app.world, SetView = SetView, Click = Click };
                conductor = new WalkTourConductor(host, with3d);
                app.WalkMaskSource = conductor.PollMask;
                Debug.Log("chaos walk tour: recording at " + UnityEngine.Screen.width + "x" + UnityEngine.Screen.height + ", plan about " + (WalkTourPlan.EstimateMs(with3d) / 1000.0).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture) + " s");
                phase = Phase.Record;
            }

            void SetView(WalkView v)
            {
                app.hd2d = v == WalkView.Hd2d || v == WalkView.World3d;
                app.live = v == WalkView.Live;
                app.world3d = v == WalkView.World3d;
                app.ApplyHd2d();
                Debug.Log("chaos walk tour: view " + v + " at frame " + recTick);
            }

            int Click(Pos goal)
            {
                var me = app.world.Player.Position;
                uint self = app.world.PlayerId;
                var path = PathFinder.Find(me, goal, p => WalkMap.Walkable(app.world, p, self), 0);
                if (path == null || path.Count == 0) return -1;
                app.npcApproach.Cancel();
                return app.StartAutoWalk(me, goal, 0) ? path.Count : -1;
            }

            void LogReports()
            {
                while (logged < conductor.Reports.Count) { Debug.Log("chaos walk tour: " + conductor.Reports[logged].Line(logged + 1)); logged++; }
            }

            void Record()
            {
                double t = recTick * (1000.0 / TourFps);
                recTick++;
                var s = app.session;
                if (s == null || s.Closed != null) { Fail("the session closed during the walk: " + (s?.Closed ?? "gone")); return; }
                if (recTick > MaxFrames) { Fail("the plan did not finish in " + MaxFrames / TourFps + " s (segment " + (conductor.SegmentIndex + 1) + ")"); return; }
                conductor.PollMask();   // the plan moves on before the app reads the keys (and again from the app's walk input)
                server.Advance(t);
                recFrame = true;
                if (conductor.Done && !ending)
                {
                    if (tail == 0) Debug.Log("chaos walk tour: plan done at frame " + recTick);
                    if (++tail > TailFrames) ending = true;
                }
            }

            void OnGUI()
            {
                if (phase != Phase.Record || conductor == null) return;
                string text = conductor.Caption;
                if (string.IsNullOrEmpty(text)) return;
                if (capStyle == null)
                {
                    capStyle = new GUIStyle(GUI.skin.label) { fontSize = 26, fontStyle = FontStyle.Bold, alignment = TextAnchor.MiddleCenter };
                    capStyle.normal.textColor = Color.white;
                    capBg = new Texture2D(1, 1);
                    capBg.SetPixel(0, 0, new Color(0f, 0f, 0f, 0.55f));
                    capBg.Apply();
                }
                GUI.depth = -1000;
                var r = new Rect(0, 12, UnityEngine.Screen.width, 46);
                GUI.DrawTexture(r, capBg);
                GUI.Label(r, text, capStyle);
            }

            void Finish()
            {
                phase = Phase.Done;
                app.WalkMaskSource = null;
                double worst = 0;
                int sent = 0, confirmed = 0;
                foreach (var r in conductor.Reports) { worst = Math.Max(worst, r.Standstill); sent += r.Sent; confirmed += r.Confirmed; }
                var inv = System.Globalization.CultureInfo.InvariantCulture;
                Debug.Log("chaos walk tour: wrote " + saved + " frames to " + dir + " (" + conductor.Reports.Count + " segments, steps sent " + sent + ", confirmed " + confirmed + ", longest standstill "
                          + worst.ToString("0", inv) + " ms of " + WalkTourPlan.StandstillLimitMs.ToString("0", inv) + " allowed; server: " + server.Steps + " steps, " + server.Turns + " turns, "
                          + server.AutoRequests + " auto-walks, " + server.Cancels + " cancels)");
                foreach (var p in conductor.Problems) Debug.LogError("chaos walk tour: failed: " + p);
                if (server.Cancels > 0) Debug.LogError("chaos walk tour: failed: the server refused " + server.Cancels + " steps (a blocked tile)");
                if (conductor.Reports.Count < WalkTourPlan.Segments(with3d).Count) Debug.LogError("chaos walk tour: failed: only " + conductor.Reports.Count + " segments were walked");
                bool ok = conductor.Problems.Count == 0 && server.Cancels == 0 && conductor.Reports.Count >= WalkTourPlan.Segments(with3d).Count;
                try { server.Dispose(); } catch (Exception) { }
                Application.Quit(ok ? 0 : 1);
            }

            IEnumerator Capture()
            {
                var eof = new WaitForEndOfFrame();
                while (true)
                {
                    yield return eof;
                    if (phase != Phase.Record) continue;
                    if (captureNow)
                    {
                        captureNow = false;
                        var tex = ScreenCapture.CaptureScreenshotAsTexture();
                        if (tex == null) { Fail("ScreenCapture gave no texture"); yield break; }
                        byte[] png = tex.EncodeToPNG();
                        Destroy(tex);
                        File.WriteAllBytes(Path.Combine(dir, "walk_tour_" + saved.ToString("0000") + ".png"), png);
                        saved++;
                    }
                    if (ending && saved >= recorded) { Finish(); yield break; }
                }
            }
        }
    }
}
