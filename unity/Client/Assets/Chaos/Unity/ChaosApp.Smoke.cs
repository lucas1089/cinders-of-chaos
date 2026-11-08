// The window smoke run (unity/README.md "Window smoke run"): `ChaosUnity -chaosWindowSmoke OUT_DIR` starts the fake game server of the demo tour in this process, logs in
// to it and opens every window the app can open, one at a time: the login screen with its System bar and option pages, the character list, every top menu drop-down
// (and its More sub-menu), every window class of ChaosApp.MakeWindows, every Info page and every options page. Each step draws a few frames, then closes.
// Per step it records the exceptions and IMGUI layout errors Unity logged (Application.logMessageReceived), a try/catch around the open, and whether the window's rect
// is empty or off the 1280x720 screen. It writes OUT_DIR/window_smoke.json, contact sheets OUT_DIR/window_smoke_sheet_N.png (24 crops per sheet, labelled) and logs
// "chaos window smoke: N windows, M with errors". The pure parts (order, classification, rect checks, sheet maths, json) are Core/Phase10F.cs.
// The fake server answers the requests of the Chaos windows with sample messages (Core/FakeModules.cs, switched on here only: FakeGameServer.ModuleResponder), the context HUDs
// (raid, arena, rift ...) get their server push before their step and lose it after (FakeModules.Context), and every How it works card counts as seen so the window itself is
// captured. What nothing answers draws its empty state. A report, not a gate: the exit code is 0 unless the run itself broke (login failed, no screenshot at all, over time), then 1.
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
        public static bool WindowSmokeRequested(out string dir)
        {
            dir = TourArg("-chaosWindowSmoke");
            return !string.IsNullOrEmpty(dir);
        }

        // -chaosWindowSmoke alone: the normal app starts (Boot) and the director drives it. Next to -chaosHd2dShot or -chaosDemoTour those run instead (the CI step runs the smoke as its own player run).
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void BootWindowSmoke()
        {
            if (!WindowSmokeRequested(out string dir) || Hd2dShot.Requested(out _) || DemoTourRequested(out _)) return;
            new GameObject("Window smoke").AddComponent<SmokeDirector>().Begin(dir);
        }

        sealed class SmokeDirector : MonoBehaviour
        {
            enum Phase { Start, Steps, Login, Entering, Settle, Sheets, Done }

            sealed class Tile { public string Name; public Texture2D Tex; public bool Problem; public string Flags = ""; }

            const int DrawFrames = 4;   // frames each step stays open: the placement frame, then three more
            const int MaxFrames = 60;   // a step that waits for a server answer or a context push ends here at the latest
            const int QuietFrames = 3;  // no new extended message for this many frames: the answers are in

            ChaosApp app;
            string dir;
            FakeGameServer server;
            Phase phase = Phase.Start;
            int tick, settleLeft, gameStart = -1, framesInStep, sheetIndex, sheetFrames;
            float startedAt;
            readonly Queue<SmokeStep> pending = new Queue<SmokeStep>();
            SmokeStep current;
            SmokeRecord rec;
            Action afterSteps;
            readonly SmokeReport report = new SmokeReport();
            readonly List<Tile> tiles = new List<Tile>();
            bool logHooked;
            FakeContext ctx;             // the context of the open step (a HUD the server pushes open), null for the rest
            int quiet, lastReceived;

            public void Begin(string outDir)
            {
                dir = outDir;
                DontDestroyOnLoad(gameObject);
            }

            double Clock => tick * (1000.0 / TourFps);

            void Start()
            {
                startedAt = Time.realtimeSinceStartup;
                StartCoroutine(Capture());
            }

            void OnDestroy() { Unhook(); }

            void Hook() { if (!logHooked) { Application.logMessageReceived += OnLog; logHooked = true; } }
            void Unhook() { if (logHooked) { Application.logMessageReceived -= OnLog; logHooked = false; } }

            void OnLog(string condition, string stack, LogType type)
            {
                report.Log(type == LogType.Exception, type == LogType.Error || type == LogType.Assert, condition, stack);
            }

            void Fail(string why)
            {
                Debug.LogError("chaos window smoke: failed: " + why);
                try { WriteJson(); } catch (Exception) { }
                try { server?.Dispose(); } catch (Exception) { }
                phase = Phase.Done;
                Unhook();
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
                if ((phase == Phase.Login || phase == Phase.Entering) && wall > 300f) { Fail("no world after 300 s (phase " + phase + ", status '" + app.status + "', server problem '" + (server?.Problem ?? "") + "')"); return; }
                if (wall > 1500f) { Fail("the smoke run ran over 1500 s (" + report.Records.Count + " steps done)"); return; }
                if (gameStart >= 0 && server != null)
                {
                    // the server's script keeps playing (monsters, buffs, messages) so the windows have something to show
                    try { server.Advance((tick - gameStart) * (1000.0 / TourFps)); } catch (Exception e) { Debug.LogWarning("chaos window smoke: server script: " + e.Message); }
                }
                switch (phase)
                {
                    case Phase.Start: StartSmoke(); break;
                    case Phase.Steps: RunSteps(); break;
                    case Phase.Login:
                        if (app.login != null && app.login.Error != null) { Fail("login: " + app.login.Error); break; }
                        if (app.screen == Screen.Characters && app.login != null && app.login.Characters.Count > 0)
                        {
                            foreach (var s in WindowSmokePlan.CharacterSteps()) pending.Enqueue(s);
                            afterSteps = EnterGame;
                            phase = Phase.Steps;
                        }
                        else if (app.status.StartsWith("Login failed", StringComparison.Ordinal)) Fail(app.status);
                        break;
                    case Phase.Entering:
                        if (app.session != null && app.session.Closed != null) { Fail("the session closed: " + app.session.Closed); break; }
                        if (app.session != null && app.session.Parser.LoggedIn && app.world != null && app.world.Player != null && server.InGame)
                        {
                            settleLeft = 90;
                            gameStart = tick;
                            phase = Phase.Settle;
                            Debug.Log("chaos window smoke: in the world at " + app.world.Player.Position);
                        }
                        break;
                    case Phase.Settle:
                        if (--settleLeft <= 0) BeginGameSteps();
                        break;
                }
            }

            void StartSmoke()
            {
                Directory.CreateDirectory(dir);
                Hook();
                QualitySettings.vSyncCount = 0;
                Time.captureFramerate = TourFps;
                UnityEngine.Screen.SetResolution(TourWidth, TourHeight, false);
                GameSession.TestClock = () => Clock;
                VisualPrefs.UiFadeOn = false;   // a closed window is gone at once, so one window is on screen at a time
                foreach (var s in WindowSmokePlan.LoginSteps(LoginMenu.OptionPages)) pending.Enqueue(s);
                afterSteps = BeginLogin;
                phase = Phase.Steps;
                Debug.Log("chaos window smoke: started, " + pending.Count + " login screen steps first");
            }

            void BeginLogin()
            {
                server = TourStartServer(app);
                server.ModuleResponder = true;   // only the smoke run: the demo tour keeps the server it had
                phase = Phase.Login;
            }

            void EnterGame()
            {
                app.Enter(app.login.Characters[0]);
                phase = Phase.Entering;
            }

            // ------------------------------------------------------------------------------------ the plan of the game steps
            void BeginGameSteps()
            {
                if (app.windows.Count == 0) app.MakeWindows();
                app.FindWindow<HowItWorksWindow>()?.MarkAllSeen(app);   // the first-open card would cover the window of every step
                int count = TopMenuAdmin.ButtonCount(TopMenu.Categories.Length, app.StaffMenu());
                var menus = new List<string>();
                var more = new List<int>();
                var infoPages = new List<string>();
                for (int i = 0; i < count; i++)
                {
                    menus.Add(app.CategoryText(i));
                    foreach (var it in app.CategoryItems(i)) if (it.Subs != null) { more.Add(i); break; }
                }
                foreach (var c in TopMenu.Categories)
                    foreach (var e in TopMenu.Leaves(c))
                        if (e.Target.StartsWith("info:", StringComparison.Ordinal)) infoPages.Add(e.Target.Substring(5));
                foreach (var p in ChaosInfo.Pages) infoPages.Add(p.Id);
                var classes = new List<string>();
                foreach (var w in app.windows) classes.Add(w.GetType().Name);
                var steps = WindowSmokePlan.GameSteps(menus, more, classes, infoPages, VisualOptionsUi.Pages);
                foreach (var s in steps) pending.Enqueue(s);
                afterSteps = BeginSheets;
                phase = Phase.Steps;
                Debug.Log("chaos window smoke: " + steps.Count + " game steps (" + classes.Count + " window classes, " + menus.Count + " menu buttons)");
            }

            // ------------------------------------------------------------------------------------ one step
            void CloseAll()
            {
                app.topMenuOpen = -1; app.topSubOpen = -1;
                app.loginMenuOpen = -1; app.loginOptions = false; app.loginCredits = false;
                foreach (var w in app.windows) w.Open = false;
            }

            void RunSteps()
            {
                if (current != null) return;   // the capture coroutine ends it
                if (pending.Count == 0)
                {
                    var next = afterSteps;
                    afterSteps = null;
                    if (next == null) { Fail("no step to run and nothing after them"); return; }
                    next();
                    return;
                }
                current = pending.Dequeue();
                framesInStep = 0;
                quiet = 0; lastReceived = app.session != null ? app.session.Ext.Received : 0;
                ctx = null;
                CloseAll();
                rec = report.Begin(current.Name, current.Kind);
                try { Prepare(current); }
                catch (Exception e) { SmokeReport.AddIssue(rec, SmokeIssueKind.Exception, e.GetType().Name + ": " + e.Message, e.StackTrace); }
            }

            void Prepare(SmokeStep s)
            {
                switch (s.Kind)
                {
                    case WindowSmokePlan.Screen: break;
                    case WindowSmokePlan.Login:
                        if (s.Id == "bar" || s.Id == "characters bar") app.loginMenuOpen = 0;
                        else if (s.Id == "credits") app.loginCredits = true;
                        else { app.loginOptions = true; app.loginOptionsPage = s.Index; }
                        break;
                    case WindowSmokePlan.Menu: app.topMenuOpen = s.Index; break;
                    case WindowSmokePlan.More:
                        {
                            app.topMenuOpen = s.Index;
                            var items = app.CategoryItems(s.Index);
                            for (int i = 0; i < items.Count; i++) if (items[i].Subs != null) { app.topSubOpen = i; break; }
                            break;
                        }
                    case WindowSmokePlan.Window:
                        {
                            var win = app.WindowNamed(s.Id);
                            if (win == null) { SmokeReport.AddIssue(rec, SmokeIssueKind.Error, "no window of class " + s.Id, ""); break; }
                            ctx = FakeModules.Context(s.Id);
                            if (ctx != null && !ctx.Drivable) { rec.Context = ctx.Reason; win.Open = true; break; }   // classified "context": no push opens it
                            if (ctx != null && server != null && !server.Push(ctx.Pushes)) rec.Context = "the fake server had nobody to push to";
                            win.Open = true;   // a window with a module asks its server module in its own Tick; the answer arrives while the step stays open
                            SetupWindow(win, s.Id);
                            break;
                        }
                    case WindowSmokePlan.Info:
                        app.OpenInfoPage(s.Id);
                        break;
                    case WindowSmokePlan.Options:
                        app.FindWindow<OptionsWindow>().ShowPage(s.Index);
                        break;
                }
            }

            /// <summary>Phase 13, track G: what a window needs that no module request can give (the fake server answers the rest): the How it works window needs a card, the Inspect window a
            /// name to ask for (the answer is the sample of Core/FakeModulesP13.cs), the trade window a trade partner (base protocol packets 0x7D and 0x7E from the fake server). Real behaviour
            /// is not changed: these are the calls a player's click makes.</summary>
            void SetupWindow(GameWindow win, string id)
            {
                switch (id)
                {
                    case "HowItWorksWindow":
                        if (win is HowItWorksWindow how && InfoStore.How != null)
                            foreach (var c in InfoStore.How.Cards) { if (how.Show(c.Key)) break; }
                        break;
                    case "InspectWindow":
                        app.Session?.Social?.Inspect?.InspectName(FakeModules.InspectName);
                        break;
                    case "TradeWindow":
                        if (server != null && !server.PushTrade(FakeModules.TradePartner)) rec.Context = "the fake server had nobody to push the trade to";
                        break;
                }
            }

            /// <summary>Phase 13, track G: the share of the step's window that open windows drawn after it hide (a later place in the window list is drawn above). A report: json "covered".</summary>
            void MeasureCover(SmokeStep s, bool open)
            {
                int index = -1;
                for (int i = 0; i < app.windows.Count; i++) if (app.windows[i].GetType().Name == s.Id) { index = i; break; }
                if (index < 0) return;
                var above = new List<SmokeBox>();
                for (int j = index + 1; j < app.windows.Count; j++)
                {
                    var o = app.windows[j];
                    if (o.Open) above.Add(new SmokeBox(o.Area.x, o.Area.y, o.Area.width, o.Area.height));
                }
                rec.CoverShare = SmokeCover.Share(rec.Rect, above);
                rec.Covered = open && SmokeCover.Covered(rec.CoverShare);
            }

            /// <summary>The rect of what the step opened, in UI units; false for steps that are the whole screen or a drop-down.</summary>
            bool StepRect(SmokeStep s, out Rect r, out bool open)
            {
                r = default; open = true;
                switch (s.Kind)
                {
                    case WindowSmokePlan.Window: { var w = app.WindowNamed(s.Id); if (w == null) { open = false; return false; } r = w.Area; open = w.Open; return true; }
                    case WindowSmokePlan.Info: { var w = app.FindWindow<InfoWindow>(); r = w.Area; open = w.Open; return true; }
                    case WindowSmokePlan.Options: { var w = app.FindWindow<OptionsWindow>(); r = w.Area; open = w.Open; return true; }
                    case WindowSmokePlan.Menu: open = app.topMenuOpen == s.Index; return false;
                    case WindowSmokePlan.More: open = app.topMenuOpen == s.Index && app.topSubOpen >= 0; return false;
                    case WindowSmokePlan.Login:
                        if (s.Id == "bar" || s.Id == "characters bar") { open = app.loginMenuOpen == 0; return false; }
                        if (s.Id == "credits") { r = app.loginCreditsRect; open = app.loginCredits; return true; }
                        r = app.loginOptionsRect; open = app.loginOptions; return true;
                }
                return false;
            }

            void FinishStep()
            {
                var s = current;
                float scale = UiScale(UnityEngine.Screen.width, UnityEngine.Screen.height, UnityEngine.Screen.dpi);
                float uw = UnityEngine.Screen.width / scale, uh = UnityEngine.Screen.height / scale;
                bool hasRect = StepRect(s, out Rect r, out bool open);
                rec.OpenAtEnd = open;
                var crop = new SmokeBox(0, 0, UnityEngine.Screen.width, UnityEngine.Screen.height);
                if (hasRect)
                {
                    rec.HasRect = true;
                    rec.Rect = new SmokeBox(r.x, r.y, r.width, r.height);
                    rec.ZeroSize = SmokeRect.Zero(r.width, r.height);
                    rec.OffScreen = SmokeRect.OffScreen(r.x, r.y, r.width, r.height, uw, uh);
                    rec.Oversize = SmokeRect.Oversize(r.width, r.height, uw, uh);   // phase 12, track H
                    if (s.Kind != WindowSmokePlan.Login) rec.Thin = open && SmokeBody.Thin(r.height);
                    if (s.Kind == WindowSmokePlan.Window) MeasureCover(s, open);   // phase 13, track G
                    crop = SmokeSheet.Crop(r.x * scale, r.y * scale, r.width * scale, r.height * scale, 8f, UnityEngine.Screen.width, UnityEngine.Screen.height);
                }
                if (ctx != null && ctx.Drivable && rec.Context.Length == 0 && !open) rec.Context = "the push did not open it: " + ctx.Source;
                var tile = new Tile { Name = s.Name };
                var shot = ScreenCapture.CaptureScreenshotAsTexture();
                if (shot == null) SmokeReport.AddIssue(rec, SmokeIssueKind.Error, "ScreenCapture gave no texture", "");
                else
                {
                    try { tile.Tex = MakeTile(shot, crop); }
                    catch (Exception e) { SmokeReport.AddIssue(rec, SmokeIssueKind.Exception, "tile: " + e.GetType().Name + ": " + e.Message, e.StackTrace); }
                    if (hasRect && open && s.Kind != WindowSmokePlan.Login) MeasureBody(shot, rec, scale);
                    Destroy(shot);
                }
                tiles.Add(tile);
                report.End();
                rec.Frames = framesInStep;
                tile.Problem = rec.Problem;
                tile.Flags = Flags(rec);
                if (rec.Problem) Debug.Log("chaos window smoke: problem in " + s.Name + ": " + tile.Flags);
                if (rec.Context.Length > 0) Debug.Log("chaos window smoke: context only: " + s.Name + ": " + rec.Context);
                if (rec.Covered) Debug.Log("chaos window smoke: covered: " + s.Name + ": " + Mathf.RoundToInt(rec.CoverShare * 100) + "% hidden by windows drawn after it");
                EndContext();
                current = null; rec = null;
            }

            /// <summary>Phase 12, track H: the ink share of the window's body in the screenshot (pixels unlike the body's main colour). A window with none drew no text, icon or bar.</summary>
            void MeasureBody(Texture2D shot, SmokeRecord r, float scale)
            {
                try
                {
                    var f = shot.format;
                    if (f != TextureFormat.RGBA32 && f != TextureFormat.ARGB32 && f != TextureFormat.BGRA32) return;
                    var box = SmokeBody.Inner(r.Rect, scale, shot.width, shot.height);
                    byte[] px = shot.GetRawTextureData();
                    float ink = SmokeBody.Ink(px, shot.width, shot.height, box, true, out int samples);
                    if (samples < SmokeBody.MinSamples) return;
                    r.Ink = ink;
                    r.EmptyBody = SmokeBody.Empty(ink, samples);
                }
                catch (Exception e) { Debug.LogWarning("chaos window smoke: body check: " + e.Message); }
            }

            /// <summary>The step has drawn its frames and the server's answers are in. A context HUD also waits for its window to open (the push arrives some frames after the request).</summary>
            bool StepReady()
            {
                if (framesInStep < DrawFrames) return false;
                if (framesInStep >= MaxFrames) return true;
                if (ctx != null && ctx.Drivable && rec.Context.Length == 0)
                {
                    var w = app.WindowNamed(current.Id);
                    if (w == null || !w.Open) return false;
                }
                if (current.Kind == WindowSmokePlan.Window && current.Id == "TradeWindow" && rec.Context.Length == 0 && app.Session != null && !app.Session.PlayerTrade.Open) return false;   // the trade packets are not extended messages: wait for them
                return quiet >= QuietFrames;
            }

            /// <summary>After a context step: the server's end messages, then the player-side state of every context HUD goes (a push cannot be taken back otherwise).</summary>
            void EndContext()
            {
                if (ctx == null) return;
                try
                {
                    if (server != null && ctx.Close.Count > 0) server.Push(ctx.Close);
                    var s = app.session;
                    if (s != null) { s.Endgame?.Clear(); s.Progress?.Rift?.Hide(); s.Utils?.Waystone?.Clear(); }
                }
                catch (Exception e) { Debug.LogWarning("chaos window smoke: ending the context of " + current.Name + ": " + e.Message); }
                ctx = null;
            }

            static string Flags(SmokeRecord r)
            {
                string f = "";
                int e = r.Count(SmokeIssueKind.Exception), l = r.Count(SmokeIssueKind.Layout), g = r.Count(SmokeIssueKind.Error);
                if (e > 0) f += "EX" + e + " ";
                if (l > 0) f += "GUI" + l + " ";
                if (g > 0) f += "ERR" + g + " ";
                if (r.ZeroSize) f += "ZERO ";
                if (r.OffScreen) f += "OFF ";
                if (r.Oversize) f += "OVER ";
                if (r.Thin) f += "THIN ";
                if (r.EmptyBody) f += "EMPTY ";
                if (r.Covered) f += "COVER ";   // phase 13, track G: reported, not a problem
                if (!r.OpenAtEnd && r.Context.Length == 0) f += "SHUT ";
                if (r.Context.Length > 0) f += "CTX ";
                return f.TrimEnd();
            }

            /// <summary>The crop of a screenshot as a texture the size it takes on the sheet (the GPU does the shrinking).</summary>
            Texture2D MakeTile(Texture2D shot, SmokeBox crop)
            {
                var fit = SmokeSheet.Fit(crop.W, crop.H, SmokeSheet.Image(SmokeSheet.Cell(0, UnityEngine.Screen.width, UnityEngine.Screen.height)));
                int fw = Mathf.Max(1, Mathf.RoundToInt(fit.W)), fh = Mathf.Max(1, Mathf.RoundToInt(fit.H));
                shot.filterMode = FilterMode.Bilinear;
                var rt = RenderTexture.GetTemporary(fw, fh, 0, RenderTextureFormat.ARGB32);
                var prev = RenderTexture.active;
                try
                {
                    Graphics.Blit(shot, rt, new Vector2(crop.W / shot.width, crop.H / shot.height), new Vector2(crop.X / shot.width, 1f - (crop.Y + crop.H) / shot.height));
                    RenderTexture.active = rt;
                    var t = new Texture2D(fw, fh, TextureFormat.RGBA32, false);
                    t.ReadPixels(new Rect(0, 0, fw, fh), 0, 0);
                    t.Apply(false, false);
                    return t;
                }
                finally { RenderTexture.active = prev; RenderTexture.ReleaseTemporary(rt); }
            }

            // ------------------------------------------------------------------------------------ the end: json and sheets
            void WriteJson()
            {
                if (dir == null) return;
                float scale = UiScale(UnityEngine.Screen.width, UnityEngine.Screen.height, UnityEngine.Screen.dpi);
                File.WriteAllText(Path.Combine(dir, "window_smoke.json"), report.ToJson(UnityEngine.Screen.width / scale, UnityEngine.Screen.height / scale));
            }

            void BeginSheets()
            {
                CloseAll();
                WriteJson();
                Debug.Log(report.DetailLine());
                Debug.Log(report.SummaryLine());
                if (tiles.Count == 0) { Finish(1); return; }
                sheetIndex = 0; sheetFrames = 0;
                phase = Phase.Sheets;
            }

            void Finish(int code)
            {
                phase = Phase.Done;
                try { server?.Dispose(); } catch (Exception) { }
                Unhook();
                Debug.Log("chaos window smoke: wrote window_smoke.json and " + SmokeSheet.SheetCount(tiles.Count) + " sheets to " + dir);
                Application.Quit(code);
            }

            IEnumerator Capture()
            {
                var eof = new WaitForEndOfFrame();
                while (true)
                {
                    yield return eof;
                    if (phase == Phase.Steps && current != null)
                    {
                        framesInStep++;
                        int received = app.session != null ? app.session.Ext.Received : 0;
                        if (received != lastReceived) { lastReceived = received; quiet = 0; } else quiet++;
                        if (StepReady())
                        {
                            try { FinishStep(); }
                            catch (Exception e) { Fail("finishing " + current.Name + ": " + e); yield break; }
                        }
                    }
                    else if (phase == Phase.Sheets)
                    {
                        if (++sheetFrames < 2) continue;
                        sheetFrames = 0;
                        var tex = ScreenCapture.CaptureScreenshotAsTexture();
                        if (tex == null) { Fail("ScreenCapture gave no texture for a sheet"); yield break; }
                        File.WriteAllBytes(Path.Combine(dir, SmokeSheet.FileName(sheetIndex)), tex.EncodeToPNG());
                        Destroy(tex);
                        if (++sheetIndex >= SmokeSheet.SheetCount(tiles.Count)) { Finish(0); yield break; }
                    }
                }
            }

            GUIStyle labelStyle;

            /// <summary>The contact sheet, drawn over the whole screen in front of the app (GUI depth) so the capture of the frame is the sheet.</summary>
            void OnGUI()
            {
                if (phase != Phase.Sheets) return;
                GUI.depth = -1000;
                GUI.matrix = Matrix4x4.identity;
                if (labelStyle == null) labelStyle = new GUIStyle(GUI.skin.label) { fontSize = 11, clipping = TextClipping.Clip, padding = new RectOffset(0, 0, 0, 0), margin = new RectOffset(0, 0, 0, 0) };
                float sw = UnityEngine.Screen.width, sh = UnityEngine.Screen.height;
                var old = GUI.color;
                GUI.color = new Color(0.07f, 0.06f, 0.08f, 1f);
                GUI.DrawTexture(new Rect(0, 0, sw, sh), Texture2D.whiteTexture);
                int first = sheetIndex * SmokeSheet.PerSheet;
                for (int k = 0; k < SmokeSheet.PerSheet && first + k < tiles.Count; k++)
                {
                    var t = tiles[first + k];
                    var cell = SmokeSheet.Cell(first + k, sw, sh);
                    GUI.color = t.Problem ? new Color(0.9f, 0.2f, 0.15f, 1f) : new Color(0.25f, 0.45f, 0.3f, 1f);
                    GUI.DrawTexture(new Rect(cell.X + 1, cell.Y + 1, cell.W - 2, 1), Texture2D.whiteTexture);
                    GUI.DrawTexture(new Rect(cell.X + 1, cell.YMax - 2, cell.W - 2, 1), Texture2D.whiteTexture);
                    GUI.DrawTexture(new Rect(cell.X + 1, cell.Y + 1, 1, cell.H - 2), Texture2D.whiteTexture);
                    GUI.DrawTexture(new Rect(cell.XMax - 2, cell.Y + 1, 1, cell.H - 2), Texture2D.whiteTexture);
                    var lab = SmokeSheet.Label(cell);
                    GUI.color = t.Problem ? new Color(1f, 0.6f, 0.5f, 1f) : Color.white;
                    labelStyle.alignment = TextAnchor.MiddleLeft;
                    GUI.Label(new Rect(lab.X + 2, lab.Y + 1, lab.W - 4, lab.H), SmokeSheet.LabelText(t.Name, t.Flags.Length > 0 ? 24 : 36), labelStyle);
                    if (t.Flags.Length > 0)
                    {
                        labelStyle.alignment = TextAnchor.MiddleRight;
                        GUI.Label(new Rect(lab.X + 2, lab.Y + 1, lab.W - 4, lab.H), t.Flags, labelStyle);
                    }
                    GUI.color = Color.white;
                    if (t.Tex != null)
                    {
                        var img = SmokeSheet.Image(cell);
                        var fit = SmokeSheet.Fit(t.Tex.width, t.Tex.height, img);
                        GUI.DrawTexture(new Rect(Mathf.Round(fit.X), Mathf.Round(fit.Y), t.Tex.width, t.Tex.height), t.Tex);
                    }
                }
                GUI.color = old;
            }
        }
    }
}
