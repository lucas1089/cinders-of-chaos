// The player on a live server (unity/README.md "Player on a live server (CI)"): `ChaosUnity -chaosLiveSmoke OUT_DIR` plays on a REAL game server, not the fake one of the demo tour.
// It logs in through the app's own login path (ChaosApp.DoLogin, the character list, ChaosApp.Enter: no side channel), waits for the map, walks east, west, north and south with held
// keys through the player's key path (ChaosApp.WalkMaskSource, WalkInputState, GameSession.Walk: the same road as the walking video), on the tiles round the start that the client calls walkable, opens the main game windows one at a time
// (the step list of the window smoke run, Core/Phase10F.cs, here with the real server's answers instead of the fake ones), takes screenshots and a contact sheet, logs out and writes
// OUT_DIR/live_smoke.json: steps, exceptions, IMGUI errors, which extended opcodes answered per window, map tiles drawn, steps confirmed. The pure parts (environment, window list, walk
// legs, report, pass rule) are Core/LiveSmoke.cs.
// Where it connects comes from the environment, never from the command line: CHAOS_LIVE_HOST, CHAOS_LIVE_PORT (login port), CHAOS_LIVE_ACCOUNT, CHAOS_LIVE_PASSWORD, CHAOS_LIVE_CHARACTER
// (optional), CHAOS_LIVE_IDENTITY (extended or chaos), and the variables every login reads: CHAOS_CLIENT_KEY (guard key), CHAOS_RSA_PUBLIC (modulus). The sprite pair: -chaosThings DIR or
// CHAOS_PAIR_DIR. Nothing of that is logged: the log line holds host, port and identity, and the json has every secret cut out.
// Every window ends as answered, prefetched at login (Skills, Dungeons), local-only (native windows, Helper, Item Finder), needs a condition or no answer; only the last is a listed warning. The exit code is 1 when the login, entering the game or the walk fails, the session closes or an exception is logged.
// Own process: next to -chaosHd2dShot, -chaosDemoTour, -chaosWindowSmoke or -chaosWalkTour those run instead. Log lines start with "chaos live smoke:".
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
        public static bool LiveSmokeRequested(out string dir)
        {
            dir = TourArg("-chaosLiveSmoke");
            return !string.IsNullOrEmpty(dir);
        }

        // -chaosLiveSmoke alone: the normal app starts (Boot) and the director drives it
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void BootLiveSmoke()
        {
            if (!LiveSmokeRequested(out string dir) || Hd2dShot.Requested(out _) || DemoTourRequested(out _) || WindowSmokeRequested(out _) || WalkTourRequested(out _)) return;
            new GameObject("Live smoke").AddComponent<LiveSmokeDirector>().Begin(dir);
        }

        sealed class LiveSmokeDirector : MonoBehaviour
        {
            enum Phase { Start, Login, Entering, Settle, Shot, Walk, WalkEnd, Steps, Logout, Sheets, Done }

            sealed class Tile { public string Name; public Texture2D Tex; public bool Problem; public string Flags = ""; }

            const double EnterLimitMs = 90000, LoginLimitMs = 60000, TotalLimitMs = 900000, SettleMs = 4000, WalkEndLimitMs = 3000, LogoutLimitMs = 5000;

            ChaosApp app;
            string dir;
            LiveSmokeEnv cfg;
            readonly LiveSmokeReport rep = new LiveSmokeReport();
            Phase phase = Phase.Start;
            bool logHooked;
            double startedAt, phaseAt;
            readonly int[] extCount = new int[256];
            double lastExtMs;
            int cancels;
            // the walk
            LiveWalker walker;
            int walkMask, moves0, sent0, cancels0;
            Pos walkFrom;
            // a screenshot of the whole screen
            string shotName;
            Action shotThen;
            // the window steps
            readonly Queue<SmokeStep> pending = new Queue<SmokeStep>();
            SmokeStep current;
            SmokeRecord rec;
            LiveSmokeWindow curWin;
            readonly int[] stepBase = new int[256];
            double stepStart;
            readonly List<Tile> tiles = new List<Tile>();
            int sheetIndex, sheetFrames;
            double logoutAt;

            static double NowMs => Time.realtimeSinceStartupAsDouble * 1000.0;

            public void Begin(string outDir)
            {
                dir = outDir;
                DontDestroyOnLoad(gameObject);
            }

            void Start()
            {
                startedAt = NowMs;
                StartCoroutine(Capture());
            }

            void OnDestroy() { Unhook(); }

            void Hook() { if (!logHooked) { Application.logMessageReceived += OnLog; logHooked = true; } }
            void Unhook() { if (logHooked) { Application.logMessageReceived -= OnLog; logHooked = false; } }

            void OnLog(string condition, string stack, LogType type)
            {
                rep.Smoke.Log(type == LogType.Exception, type == LogType.Error || type == LogType.Assert, condition, stack);
            }

            void SetPhase(Phase p) { phase = p; phaseAt = NowMs; }

            void WriteJson()
            {
                if (dir == null) return;
                try { File.WriteAllText(Path.Combine(dir, "live_smoke.json"), rep.ToJson(cfg != null ? cfg.Secrets() : null)); }
                catch (Exception e) { Debug.LogWarning("chaos live smoke: could not write live_smoke.json: " + e.Message); }
            }

            void Fail(string why)
            {
                if (phase == Phase.Done) return;
                var was = phase;
                if (was == Phase.Start || was == Phase.Login) { if (!rep.LoginOk && rep.LoginError.Length == 0) rep.LoginError = why; }
                else if (was == Phase.Entering) { if (rep.EnterError.Length == 0) rep.EnterError = why; }
                else rep.Aborted = why;
                if (cfg != null) Debug.Log(rep.SummaryLine());
                Debug.Log("chaos live smoke: failed: " + (cfg != null ? Scrub(why) : why));
                WriteJson();
                Unhook();
                SetPhase(Phase.Done);
                Application.Quit(1);
            }

            string Scrub(string text)
            {
                foreach (var s in cfg.Secrets()) text = text.Replace(s, "<removed>");
                return text;
            }

            void Update()
            {
                if (phase == Phase.Done) return;
                try { Step(); }
                catch (Exception e) { Fail(e.GetType().Name + ": " + e.Message); }
            }

            void Step()
            {
                if (app == null)
                {
                    app = FindObjectOfType<ChaosApp>();
                    if (app == null) return;
                }
                if (NowMs - startedAt > TotalLimitMs) { Fail("the live smoke run ran over " + (int)(TotalLimitMs / 1000) + " s"); return; }
                // the session went away on its own (the server closed it, a kick): not a clean end
                if ((phase == Phase.Settle || phase == Phase.Shot || phase == Phase.Walk || phase == Phase.WalkEnd || phase == Phase.Steps) && (app.session == null || app.screen != Screen.Game))
                {
                    rep.Closed = app.status ?? "";
                    if (rep.Closed.Length == 0) rep.Closed = "the connection ended";
                    Fail("the session closed during the run");
                    return;
                }
                switch (phase)
                {
                    case Phase.Start: StartRun(); break;
                    case Phase.Login: StepLogin(); break;
                    case Phase.Entering: StepEntering(); break;
                    case Phase.Settle:
                        if (NowMs - phaseAt >= SettleMs)
                        {
                            rep.TilesDrawn = LiveSmokePlan.TilesDrawn(app.world, (int)ViewTilesW, (int)ViewTilesH);
                            rep.TilesInModel = app.world.Tiles.Count;
                            RequestShot("live_smoke_world.png", BeginWalk);
                        }
                        break;
                    case Phase.Walk: StepWalk(); break;
                    case Phase.WalkEnd: StepWalkEnd(); break;
                    case Phase.Steps: RunSteps(); break;
                    case Phase.Logout: StepLogout(); break;
                }
            }

            // ------------------------------------------------------------------------------------ login and entry
            void StartRun()
            {
                Directory.CreateDirectory(dir);
                Hook();
                cfg = LiveSmokeEnv.Read(Environment.GetEnvironmentVariable);
                rep.Identity = cfg.Identity;
                if (!cfg.Ok) { rep.LoginError = string.Join("; ", cfg.Errors); Fail(rep.LoginError); return; }
                QualitySettings.vSyncCount = 0;
                UnityEngine.Screen.SetResolution(TourWidth, TourHeight, false);
                VisualPrefs.UiFadeOn = false;   // a closed window is gone at once, so one window is on screen at a time
                Environment.SetEnvironmentVariable("CHAOS_UNITY_IDENTITY", cfg.Identity);   // IdentityChoice reads it
                string pair = Environment.GetEnvironmentVariable("CHAOS_PAIR_DIR");
                if (!string.IsNullOrEmpty(pair)) app.pairDir = pair;
                app.host = cfg.Host;
                app.port = cfg.Port.ToString(System.Globalization.CultureInfo.InvariantCulture);
                app.account = cfg.Account;
                app.password = cfg.Password;
                Debug.Log("chaos live smoke: started, " + cfg.Describe());
                app.DoLogin();   // the login screen's path: the pair, the login server, then the character list
                SetPhase(Phase.Login);
            }

            void StepLogin()
            {
                if (app.dat == null) { Fail("no sprite pair: " + (app.status ?? "")); return; }   // DoLogin loads the pair before it connects; a miss ends it at once
                if (app.login != null && app.login.Error != null) { Fail("login: " + app.login.Error); return; }
                if (app.status != null && app.status.StartsWith("Login failed", StringComparison.Ordinal)) { Fail(app.status); return; }
                if (app.screen == Screen.Characters && app.login != null && app.login.Characters.Count > 0)
                {
                    CharacterEntry ch = null;
                    foreach (var c in app.login.Characters) if (cfg.Character != null && c.Name == cfg.Character) { ch = c; break; }
                    if (ch == null && cfg.Character == null) ch = app.login.Characters[0];
                    if (ch == null) { Fail("login: the character is not in the list"); return; }
                    rep.LoginOk = true;
                    Debug.Log("chaos live smoke: logged in, " + app.login.Characters.Count + " characters in the list");
                    app.Enter(ch);   // the list's own path
                    HookSession();
                    SetPhase(Phase.Entering);
                    return;
                }
                if (NowMs - phaseAt > LoginLimitMs) Fail("no character list after " + (int)(LoginLimitMs / 1000) + " s (status '" + (app.status ?? "") + "')");
            }

            /// <summary>Counts every extended message the server sends (per opcode) and every refused step, without changing what the session does with them.</summary>
            void HookSession()
            {
                var p = app.session.Parser;
                var prev = p.ExtendedOpcode;
                p.ExtendedOpcode = (op, data) =>
                {
                    extCount[op]++;
                    lastExtMs = NowMs;
                    rep.OpcodesSeen.Add(op);
                    prev(op, data);
                };
                var prevCancel = p.WalkCancelled;
                p.WalkCancelled = d => { cancels++; prevCancel(d); };
            }

            void StepEntering()
            {
                var s = app.session;
                if (s == null || s.Closed != null) { Fail("the session closed: " + (s?.Closed ?? "gone")); return; }
                if (s.Parser.LoggedIn && app.world != null && app.world.Player != null && app.world.Tiles.Count > 0)
                {
                    rep.EnterOk = true;
                    rep.EnterMs = NowMs - phaseAt;
                    Debug.Log("chaos live smoke: in the world, " + app.world.Tiles.Count + " tiles in " + Math.Round(rep.EnterMs) + " ms");
                    app.hd2d = false; app.live = false; app.world3d = false;   // the classic view, whatever the saved settings say
                    app.ApplyHd2d();
                    SetPhase(Phase.Settle);   // the session's own hellos and prefetches (spells, progression) arrive meanwhile
                    return;
                }
                if (NowMs - phaseAt > EnterLimitMs) Fail("no world after " + (int)(EnterLimitMs / 1000) + " s (status '" + (app.status ?? "") + "')");
            }

            // ------------------------------------------------------------------------------------ a screenshot of the whole screen
            void RequestShot(string name, Action then)
            {
                shotName = name; shotThen = then;
                SetPhase(Phase.Shot);
            }

            // ------------------------------------------------------------------------------------ the walk
            void BeginWalk()
            {
                var s = app.session;
                walkFrom = app.world.Player.Position;
                // the legs go where the client itself says the tile is walkable (the check of the walk prediction), out and back: a refused step is then a finding, not the start place's wall
                var world = app.world;
                Func<Pos, bool> free = p => WalkMap.Walkable(world, p, world.PlayerId);
                // every tile a leg can reach, the margin tile past its end included, is one the client calls walkable
                var legs = LiveWalker.LegsAround(walkFrom, free);
                if (legs.Count == 0) { legs = LiveWalker.LegsAround(walkFrom, free, 2, 0); Debug.Log("chaos live smoke: no leg has a free margin tile, planned without it"); }
                walker = new LiveWalker(legs, () => app.world.Player.Position);
                rep.StepsPlanned = 0;
                foreach (var l in legs) rep.StepsPlanned += l.Steps;
                moves0 = s.Parser.PlayerMoves; sent0 = s.WalksSent; cancels0 = cancels;
                walkMask = 0;
                app.WalkMaskSource = () => walkMask;   // the player's key path takes the mask of this frame
                Debug.Log("chaos live smoke: walking, " + legs.Count + " legs of held keys, " + rep.StepsPlanned + " steps planned on tiles the client calls walkable");
                SetPhase(Phase.Walk);
            }

            void StepWalk()
            {
                var s = app.session;
                walkMask = walker.Mask(NowMs, s.Parser.PlayerMoves, cancels, s.WalksSent);
                if (!walker.Done) return;
                walkMask = 0;
                SetPhase(Phase.WalkEnd);
            }

            void StepWalkEnd()
            {
                var s = app.session;
                if (!s.WalkIdle && NowMs - phaseAt < WalkEndLimitMs) return;   // the last glide ends
                app.WalkMaskSource = null;
                rep.Legs = walker.Results;
                rep.StepsSent = s.WalksSent - sent0;
                rep.StepsConfirmed = s.Parser.PlayerMoves - moves0;
                rep.StepsCancelled = cancels - cancels0;
                var now = app.world.Player.Position;
                rep.NetDx = now.X - walkFrom.X; rep.NetDy = now.Y - walkFrom.Y;
                rep.TilesDrawnAfterWalk = LiveSmokePlan.TilesDrawn(app.world, (int)ViewTilesW, (int)ViewTilesH);
                foreach (var l in walker.Results) Debug.Log("chaos live smoke: leg " + l.Name + ": " + l.Sent + " sent of " + l.Wanted + " planned, " + l.Confirmed + " confirmed, " + l.Cancelled + " refused" + (l.TimedOut ? ", timed out" : ""));
                Debug.Log("chaos live smoke: " + rep.WalkAccounts() + ", net " + rep.NetDx + "," + rep.NetDy);
                RequestShot("live_smoke_walked.png", BeginWindows);
            }

            // ------------------------------------------------------------------------------------ the windows
            void BeginWindows()
            {
                if (app.windows.Count == 0) app.MakeWindows();
                app.FindWindow<HowItWorksWindow>()?.MarkAllSeen(app);   // the first-open card would cover the window of every step
                var classes = new List<string>();
                foreach (var w in app.windows) classes.Add(w.GetType().Name);
                var steps = LiveSmokePlan.Windows(classes, out var missing);
                rep.MissingWindows.AddRange(missing);
                foreach (var st in steps) pending.Enqueue(st);
                foreach (int op in rep.OpcodesSeen) rep.Prefetched.Add(op);   // what the login asked for (a Prefetch window's data) is there before the first step
                Debug.Log("chaos live smoke: " + steps.Count + " windows to open, " + missing.Count + " not in this build");
                SetPhase(Phase.Steps);
            }

            void CloseAll()
            {
                app.topMenuOpen = -1; app.topSubOpen = -1;
                app.loginMenuOpen = -1; app.loginOptions = false; app.loginCredits = false;
                foreach (var w in app.windows) w.Open = false;
            }

            void RunSteps()
            {
                if (current != null) return;   // the capture coroutine ends it
                if (pending.Count == 0) { BeginLogout(); return; }
                current = pending.Dequeue();
                CloseAll();
                rec = rep.Smoke.Begin(current.Name, current.Kind);
                curWin = new LiveSmokeWindow { Name = current.Name, Class = current.Id, Record = rec };
                Array.Copy(extCount, stepBase, extCount.Length);
                stepStart = NowMs;
                lastExtMs = stepStart;
                try
                {
                    var win = app.WindowNamed(current.Id);
                    if (win == null) SmokeReport.AddIssue(rec, SmokeIssueKind.Error, "no window of class " + current.Id, "");
                    else
                    {
                        win.Open = true;   // a window with a module asks its server module in its own Tick: the real answer arrives while the step stays open
                        if (current.Id == "HowItWorksWindow" && win is HowItWorksWindow how && InfoStore.How != null)
                            foreach (var c in InfoStore.How.Cards) { if (how.Show(c.Key)) break; }
                    }
                }
                catch (Exception e) { SmokeReport.AddIssue(rec, SmokeIssueKind.Exception, e.GetType().Name + ": " + e.Message, e.StackTrace); }
            }

            bool StepReady()
            {
                double now = NowMs;
                int answered = 0;
                for (int i = 0; i < extCount.Length; i++) answered += extCount[i] - stepBase[i];
                return LiveSmokePlan.StepReady(now - stepStart, now - lastExtMs, answered > 0);
            }

            void FinishStep()
            {
                var s = current;
                float scale = UiScale(UnityEngine.Screen.width, UnityEngine.Screen.height, UnityEngine.Screen.dpi);
                float uw = UnityEngine.Screen.width / scale, uh = UnityEngine.Screen.height / scale;
                var win = app.WindowNamed(s.Id);
                var crop = new SmokeBox(0, 0, UnityEngine.Screen.width, UnityEngine.Screen.height);
                if (win != null)
                {
                    var r = win.Area;
                    rec.OpenAtEnd = win.Open;
                    rec.HasRect = true;
                    rec.Rect = new SmokeBox(r.x, r.y, r.width, r.height);
                    rec.ZeroSize = SmokeRect.Zero(r.width, r.height);
                    rec.OffScreen = SmokeRect.OffScreen(r.x, r.y, r.width, r.height, uw, uh);
                    rec.Oversize = SmokeRect.Oversize(r.width, r.height, uw, uh);
                    crop = SmokeSheet.Crop(r.x * scale, r.y * scale, r.width * scale, r.height * scale, 8f, UnityEngine.Screen.width, UnityEngine.Screen.height);
                }
                else rec.OpenAtEnd = false;
                var tile = new Tile { Name = s.Name };
                var shot = ScreenCapture.CaptureScreenshotAsTexture();
                if (shot == null) SmokeReport.AddIssue(rec, SmokeIssueKind.Error, "ScreenCapture gave no texture", "");
                else
                {
                    try { tile.Tex = MakeTile(shot, crop); }
                    catch (Exception e) { SmokeReport.AddIssue(rec, SmokeIssueKind.Exception, "tile: " + e.GetType().Name + ": " + e.Message, e.StackTrace); }
                    Destroy(shot);
                }
                for (int i = 0; i < extCount.Length; i++)
                {
                    int d = extCount[i] - stepBase[i];
                    if (d > 0) { curWin.Opcodes.Add(i); curWin.Answers += d; }
                }
                curWin.Ms = NowMs - stepStart;
                rep.Windows.Add(curWin);
                rep.Smoke.End();
                var status = rep.StatusOf(curWin);
                tile.Problem = rec.Problem || status == LiveWindowStatus.NoAnswer;
                tile.Flags = Flags(rec, status);
                tiles.Add(tile);
                if (tile.Problem) Debug.Log("chaos live smoke: " + s.Name + ": " + (tile.Flags.Length > 0 ? tile.Flags : "problem"));
                current = null; rec = null; curWin = null;
            }

            static string Flags(SmokeRecord r, LiveWindowStatus status)
            {
                string f = "";
                int e = r.Count(SmokeIssueKind.Exception), l = r.Count(SmokeIssueKind.Layout), g = r.Count(SmokeIssueKind.Error);
                if (e > 0) f += "EX" + e + " ";
                if (l > 0) f += "GUI" + l + " ";
                if (g > 0) f += "ERR" + g + " ";
                if (r.ZeroSize) f += "ZERO ";
                if (r.OffScreen) f += "OFF ";
                if (r.Oversize) f += "OVER ";
                if (!r.OpenAtEnd) f += "SHUT ";
                if (status == LiveWindowStatus.NoAnswer) f += "NOANS ";
                else if (status == LiveWindowStatus.NeedsCondition) f += "COND ";
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

            // ------------------------------------------------------------------------------------ logout, sheets, the end
            void BeginLogout()
            {
                CloseAll();
                app.session.Logout();   // the log out button's call: the server closes the connection and the app goes back to the character list
                logoutAt = NowMs;
                SetPhase(Phase.Logout);
            }

            void StepLogout()
            {
                if (app.screen != Screen.Game || app.session == null) { rep.LoggedOut = true; BeginSheets(); return; }
                if (NowMs - logoutAt > LogoutLimitMs)
                {
                    rep.LoggedOut = false;
                    app.Leave("Logged out.");
                    BeginSheets();
                }
            }

            void BeginSheets()
            {
                rep.Sheets = SmokeSheet.SheetCount(tiles.Count);
                Debug.Log(rep.SummaryLine());
                foreach (var w in rep.Warnings()) Debug.Log("chaos live smoke: warning: " + w);
                foreach (var n in rep.Notes()) Debug.Log("chaos live smoke: note: " + n);
                foreach (var f in rep.Failures()) Debug.Log("chaos live smoke: failure: " + f);
                WriteJson();
                if (tiles.Count == 0) { Finish(); return; }
                sheetIndex = 0; sheetFrames = 0;
                SetPhase(Phase.Sheets);
            }

            void Finish()
            {
                rep.Finished = true;
                WriteJson();
                Unhook();
                SetPhase(Phase.Done);
                Debug.Log("chaos live smoke: wrote live_smoke.json, " + rep.Screenshots + " screenshots and " + rep.Sheets + " sheets to " + dir + ", " + (rep.Pass ? "pass" : "FAIL"));
                Application.Quit(rep.Pass ? 0 : 1);
            }

            IEnumerator Capture()
            {
                var eof = new WaitForEndOfFrame();
                while (true)
                {
                    yield return eof;
                    if (phase == Phase.Shot && shotName != null)
                    {
                        var tex = ScreenCapture.CaptureScreenshotAsTexture();
                        if (tex == null) { Fail("ScreenCapture gave no texture"); yield break; }
                        File.WriteAllBytes(Path.Combine(dir, shotName), tex.EncodeToPNG());
                        Destroy(tex);
                        rep.Screenshots++;
                        var then = shotThen;
                        shotName = null; shotThen = null;
                        try { then(); }
                        catch (Exception e) { Fail(e.GetType().Name + ": " + e.Message); yield break; }
                    }
                    else if (phase == Phase.Steps && current != null)
                    {
                        if (StepReady())
                        {
                            try { FinishStep(); }
                            catch (Exception e) { Fail("finishing " + current.Name + ": " + e.GetType().Name + ": " + e.Message); yield break; }
                        }
                    }
                    else if (phase == Phase.Sheets)
                    {
                        if (++sheetFrames < 2) continue;
                        sheetFrames = 0;
                        var tex = ScreenCapture.CaptureScreenshotAsTexture();
                        if (tex == null) { Fail("ScreenCapture gave no texture for a sheet"); yield break; }
                        File.WriteAllBytes(Path.Combine(dir, LiveSmokeReport.SheetName(sheetIndex)), tex.EncodeToPNG());
                        Destroy(tex);
                        if (++sheetIndex >= rep.Sheets) { Finish(); yield break; }
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
