// The loot explosion video (unity/README.md "Loot explosion video", O675): `ChaosUnity -chaosLootTour OUT_DIR [-chaosLootView classic|hd2d|live]` plays on a REAL game server, as a tester
// character, and records the loot explosion of O669 the way a player sees it. It logs in through the app's own login path (ChaosApp.DoLogin, the character list, ChaosApp.Enter), waits for the
// map, then the state machine of Core/LootTour.cs (LootTourStep) runs: a warm-up explosion (the helper steps the tester out of a protection zone and its loot is taken with Loot all, so the video
// starts on a clean spot), the intro, the burst (the tester says `!tester explode run`, the server explodes a loot bag of the tester's own by the real rule of loot_explosion.lua: gold in one stack, the
// items on free tiles within 2, drops 50 to 80 ms apart with a distance effect each), the items on the ground with their labels, a second burst, and Loot all (the Ctrl+Shift+L path:
// GroundLabelsModel.LootAll, extended opcode 230 "lootall") until the ring is empty. PNG frames go to OUT_DIR/loot_tour_0000.png ... with the wall clock of each frame in loot_tour_frames.txt (an ffconcat
// list: the server's drops are staggered in real time and a software rendered frame takes longer than that, so the video keeps the real timing; the CI step encodes loot_tour.mp4 from it, 1280x720,
// 30 fps, yuv420p, libx264) and loot_tour.json (pass, items before / peak / after, labels, asks of Loot all).
// Where it connects comes from the environment, never from the command line: CHAOS_LIVE_HOST, CHAOS_LIVE_PORT, CHAOS_LIVE_IDENTITY, CHAOS_CLIENT_KEY, CHAOS_RSA_PUBLIC as for the live smoke, and the tester
// in CHAOS_LOOT_ACCOUNT, CHAOS_LOOT_PASSWORD, CHAOS_LOOT_CHARACTER (a name "Tester Xxx": the helper of tester_helper.lua acts for those only; tools/ci/unity_live_check.sh --serve-only writes them).
// Exit code 1 when the login, the entry, the explosion, the labels or Loot all fails, the session closes or an exception is logged; the frames are written all the same.
// Own process: next to -chaosHd2dShot, -chaosDemoTour, -chaosWindowSmoke or -chaosWalkTour those run instead. Log lines start with "chaos loot tour:". Nothing of the account is logged.
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        public static bool LootTourRequested(out string dir)
        {
            dir = TourArg("-chaosLootTour");
            return !string.IsNullOrEmpty(dir);
        }

        // -chaosLootTour alone: the normal app starts (Boot) and the director drives it
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void BootLootTour()
        {
            if (!LootTourRequested(out string dir) || Hd2dShot.Requested(out _) || DemoTourRequested(out _) || WindowSmokeRequested(out _) || WalkTourRequested(out _) || LiveSmokeRequested(out _)) return;
            new GameObject("Loot tour").AddComponent<LootTourDirector>().Begin(dir);
        }

        sealed class LootTourDirector : MonoBehaviour
        {
            enum Phase { Start, Login, Entering, Settle, Run, Done }

            const double LoginLimitMs = 60000, EnterLimitMs = 90000, SettleMs = 4000, TotalLimitMs = 600000, SlowFrameMs = 400;

            ChaosApp app;
            string dir;
            LootTourEnv cfg;
            LootTourStep step;
            Phase phase = Phase.Start;
            double startedAt, phaseAt;
            bool logHooked, ending, failed;
            int saved, exceptions;
            readonly List<double> stamps = new List<double>();
            double worstGap;
            string view = "classic";

            static double NowMs => Time.realtimeSinceStartupAsDouble * 1000.0;

            public void Begin(string outDir)
            {
                dir = outDir;
                DontDestroyOnLoad(gameObject);
            }

            void Start()
            {
                startedAt = NowMs;
                string v = TourArg("-chaosLootView");
                if (v == "hd2d" || v == "live") view = v;
                StartCoroutine(Capture());
            }

            void OnDestroy() { Unhook(); }
            void Hook() { if (!logHooked) { Application.logMessageReceived += OnLog; logHooked = true; } }
            void Unhook() { if (logHooked) { Application.logMessageReceived -= OnLog; logHooked = false; } }

            void OnLog(string condition, string stack, LogType type)
            {
                if (type == LogType.Exception) { exceptions++; if (step != null && step.Error.Length == 0) step.Error = "an exception was logged: " + Scrub(condition); }
            }

            string Scrub(string text)
            {
                if (cfg != null) foreach (var s in cfg.Live.Secrets()) text = text.Replace(s, "<removed>");
                return text;
            }

            /// <summary>The run ends here, before there is a step to report on (the login, the entry): the line and the exit code, a report with the reason.</summary>
            void Fail(string why)
            {
                if (phase == Phase.Done) return;
                Debug.Log("chaos loot tour: failed: " + Scrub(why));
                if (step == null) step = new LootTourStep();
                if (step.Error.Length == 0) step.Error = Scrub(why);
                WriteResults();
                Unhook();
                phase = Phase.Done;
                Application.Quit(1);
            }

            void Update()
            {
                if (phase == Phase.Done) return;
                try { Tick(); }
                catch (Exception e) { Fail(e.GetType().Name + ": " + e.Message); }
            }

            void Tick()
            {
                if (app == null)
                {
                    app = FindObjectOfType<ChaosApp>();
                    if (app == null) return;
                }
                if (NowMs - startedAt > TotalLimitMs) { Fail("the loot tour ran over " + (int)(TotalLimitMs / 1000) + " s"); return; }
                if ((phase == Phase.Settle || phase == Phase.Run) && (app.session == null || app.screen != Screen.Game || app.session.Closed != null))
                {
                    Fail("the session closed during the run (" + (string.IsNullOrEmpty(app.status) ? "the connection ended" : app.status) + ")");
                    return;
                }
                switch (phase)
                {
                    case Phase.Start: StartRun(); break;
                    case Phase.Login: StepLogin(); break;
                    case Phase.Entering: StepEntering(); break;
                    case Phase.Settle:
                        if (NowMs - phaseAt >= SettleMs) BeginRun();
                        break;
                    case Phase.Run: StepRun(); break;
                }
            }

            void StartRun()
            {
                Directory.CreateDirectory(dir);
                Hook();
                cfg = LootTourEnv.Read(Environment.GetEnvironmentVariable);
                if (!cfg.Ok) { Fail(string.Join("; ", cfg.Errors)); return; }
                QualitySettings.vSyncCount = 0;
                UnityEngine.Screen.SetResolution(LootTourPlan.Width, LootTourPlan.Height, false);
                Environment.SetEnvironmentVariable("CHAOS_UNITY_IDENTITY", cfg.Live.Identity);   // IdentityChoice reads it
                string pair = Environment.GetEnvironmentVariable("CHAOS_PAIR_DIR");
                if (!string.IsNullOrEmpty(pair)) app.pairDir = pair;
                app.host = cfg.Live.Host;
                app.port = cfg.Live.Port.ToString(System.Globalization.CultureInfo.InvariantCulture);
                app.account = cfg.Live.Account;
                app.password = cfg.Live.Password;
                Debug.Log("chaos loot tour: started, " + cfg.Live.Describe() + ", view " + view);
                app.DoLogin();   // the login screen's path: the pair, the login server, then the character list
                phase = Phase.Login; phaseAt = NowMs;
            }

            void StepLogin()
            {
                if (app.dat == null) { Fail("no sprite pair: " + (app.status ?? "")); return; }
                if (app.login != null && app.login.Error != null) { Fail("login: " + app.login.Error); return; }
                if (app.status != null && app.status.StartsWith("Login failed", StringComparison.Ordinal)) { Fail(app.status); return; }
                if (app.screen == Screen.Characters && app.login != null && app.login.Characters.Count > 0)
                {
                    CharacterEntry ch = null;
                    foreach (var c in app.login.Characters) if (c.Name == cfg.Live.Character) { ch = c; break; }
                    if (ch == null) { Fail("login: the tester is not in the list"); return; }
                    Debug.Log("chaos loot tour: logged in");
                    app.Enter(ch);
                    phase = Phase.Entering; phaseAt = NowMs;
                    return;
                }
                if (NowMs - phaseAt > LoginLimitMs) Fail("no character list after " + (int)(LoginLimitMs / 1000) + " s (status '" + (app.status ?? "") + "')");
            }

            void StepEntering()
            {
                var s = app.session;
                if (s == null || s.Closed != null) { Fail("the session closed: " + (s?.Closed ?? "gone")); return; }
                if (s.Parser.LoggedIn && app.world != null && app.world.Player != null && app.world.Tiles.Count > 0)
                {
                    Debug.Log("chaos loot tour: in the world, " + app.world.Tiles.Count + " tiles");
                    app.hd2d = view != "classic"; app.live = view == "live"; app.world3d = false;
                    app.ApplyHd2d();
                    if (app.windows.Count == 0) app.MakeWindows();
                    app.FindWindow<HowItWorksWindow>()?.MarkAllSeen(app);   // a first-open card would cover the ground
                    phase = Phase.Settle; phaseAt = NowMs;   // the session's own hellos and prefetches arrive meanwhile
                    return;
                }
                if (NowMs - phaseAt > EnterLimitMs) Fail("no world after " + (int)(EnterLimitMs / 1000) + " s (status '" + (app.status ?? "") + "')");
            }

            void BeginRun()
            {
                if (app.FindWindow<LootWindow>() == null || app.FindWindow<LootWindow>().Ground == null) { Fail("no loot window: the ground labels are not there"); return; }
                step = new LootTourStep();
                phase = Phase.Run;
                Debug.Log("chaos loot tour: the run starts (the warm-up explosion first)");
            }

            LootTourView ViewNow()
            {
                var loot = app.FindWindow<LootWindow>();
                var me = app.world.Player.Position;
                var v = new LootTourView { Items = LootTourPlan.CountItems(app.world, me, LootTourPlan.Radius) };
                if (loot != null && loot.Ground != null && loot.Filter != null) v.Labels = loot.Ground.Labels(me, loot.Filter.Settings, false).Count;
                return v;
            }

            void StepRun()
            {
                if (ending) return;
                var act = step.Update(NowMs - startedAt, ViewNow());
                switch (act)
                {
                    case LootTourAction.Explode:
                        app.session.Say(LootTourPlan.SayExplode);
                        Debug.Log("chaos loot tour: explosion " + step.Explosions + " asked at " + Math.Round(step.VideoMs) + " ms of the video, " + step.Start + " items near");
                        break;
                    case LootTourAction.LootAll:
                        app.FindWindow<LootWindow>().Ground.LootAll();
                        Debug.Log("chaos loot tour: Loot all (" + step.State + ")");
                        break;
                    case LootTourAction.Finish:
                    case LootTourAction.Fail:
                        failed = act == LootTourAction.Fail || !step.Pass;
                        ending = true;   // the capture coroutine writes the frame of this moment, then ends the run
                        break;
                }
            }

            /// <summary>The report and the frame list, the line of the result; the exit code.</summary>
            void WriteResults()
            {
                var inv = System.Globalization.CultureInfo.InvariantCulture;
                try
                {
                    File.WriteAllText(Path.Combine(dir, LootTourPlan.FramesFile), LootTourPlan.Concat(stamps));
                    File.WriteAllText(Path.Combine(dir, LootTourPlan.ReportFile), step.ToJson(saved, LootTourPlan.VideoSeconds(stamps), worstGap > SlowFrameMs));
                }
                catch (Exception e) { Debug.LogWarning("chaos loot tour: could not write the report: " + e.Message); }
                if (step.Notes.Count > 0) foreach (var n in step.Notes) Debug.Log("chaos loot tour: note: " + n);
                Debug.Log("chaos loot tour: " + (step.Pass && !failed ? "pass" : "FAIL") + ", " + saved + " frames, " + LootTourPlan.VideoSeconds(stamps).ToString("0.0", inv) + " s of video, items before " + step.Baseline + ", peak "
                          + step.Peak + ", after the second burst " + step.Peak2 + ", labels " + (step.LabelsSeen ? "seen (up to " + step.MaxLabels + ")" : "NOT seen") + ", Loot all " + (step.Taken ? "took everything in " + step.LootAllTries + " asks" : "did not clear the ground")
                          + ", longest frame gap " + Math.Round(worstGap) + " ms" + (step.Error.Length > 0 ? ", error: " + step.Error : ""));
            }

            void Finish()
            {
                phase = Phase.Done;
                WriteResults();
                Unhook();
                bool ok = step.Pass && !failed && exceptions == 0;
                Application.Quit(ok ? 0 : 1);
            }

            IEnumerator Capture()
            {
                var eof = new WaitForEndOfFrame();
                while (true)
                {
                    yield return eof;
                    if (phase != Phase.Run || step == null) continue;
                    if (step.Recording && saved < LootTourPlan.MaxFrames)
                    {
                        double at = NowMs;
                        var tex = ScreenCapture.CaptureScreenshotAsTexture();
                        if (tex == null) { step.Error = "ScreenCapture gave no texture"; ending = true; failed = true; }
                        else
                        {
                            byte[] png = tex.EncodeToPNG();
                            Destroy(tex);
                            File.WriteAllBytes(Path.Combine(dir, LootTourPlan.FrameName(saved)), png);
                            if (stamps.Count > 0) worstGap = Math.Max(worstGap, at - stamps[stamps.Count - 1]);
                            stamps.Add(at);
                            saved++;
                        }
                    }
                    if (ending) { Finish(); yield break; }
                }
            }
        }
    }
}
