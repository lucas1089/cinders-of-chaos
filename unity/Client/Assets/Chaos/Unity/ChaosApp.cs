// The prototype's whole app: a login form (IMGUI), the character list, then the map with walking.
// Created from code at start, so the project needs no hand-made scene or prefab.
using System;
using System.Collections.Generic;
using System.IO;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp : MonoBehaviour
    {
        enum Screen { Login, Characters, Game }

        Screen screen = Screen.Login;
        string host = "play.cindersofchaos.com", port = "7171", account = "", password = "", pairDir = "", status = "";
        LoginResult login;
        GameSession session;
        World world;
        DatFile dat;
        SprFile spr;
        SpriteAtlas atlas;
        MapView view;
        Hd2dView hd2dView;
        bool hd2d;   // F9: the HD-2D view (Hd2dView) instead of the classic flat one
        FrontLiveView frontLive;
        bool live;   // F8: the front-art live view (FrontLiveView) instead of the classic or HD-2D one
        bool world3d;   // F10: the 3D world (Hd2dRuins3d in WorldMode and Hd2dChars3d), only together with HD-2D
        GameObject world3dRoot;
        bool world3dReady;   // the 3D models are in the build
        Camera cam;
        Vector2 charScroll;
        readonly List<string> log = new List<string>();
        GUIStyle small, nameStyle, chatStyle, titleStyle;
        Vector2 chatScroll;
        string chatInput = "";
        bool chatOpen = true, chatFocused, showDebug;
        readonly List<Rect> uiRects = new List<Rect>();   // screen pixels the windows cover: clicks there do not walk

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            if (FindObjectOfType<ChaosApp>() != null) return;
            if (Hd2dShot.Requested(out string shotDir))
            {
                // screenshot mode (-chaosHd2dShot DIR): an offline demo room, no login, no app
                new GameObject("Hd2d shot").AddComponent<Hd2dShot>().OutDir = shotDir;
                return;
            }
            var go = new GameObject("Cinders of Chaos");
            DontDestroyOnLoad(go);
            go.AddComponent<ChaosApp>();
        }

        void Awake()
        {
            Application.targetFrameRate = 60;
            Loc.Set(Loc.Choose(PlayerPrefs.GetString("chaos.lang", ""), Application.systemLanguage.ToString()));
            pairDir = PlayerPrefs.GetString("chaos.pair", DefaultPairDir());
            host = PlayerPrefs.GetString("chaos.host", host);
            port = PlayerPrefs.GetString("chaos.port", port);
            account = PlayerPrefs.GetString("chaos.account", "");
            hd2d = PlayerPrefs.GetInt("chaos.hd2d", 0) == 1;
            world3d = PlayerPrefs.GetInt("chaos.world3d", 0) == 1;
            live = PlayerPrefs.GetInt("chaos.frontlive", 0) == 1;
            var camGo = new GameObject("Camera");
            camGo.transform.SetParent(transform);
            cam = camGo.AddComponent<Camera>();
            cam.orthographic = true;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color32(12, 10, 14, 255);
            cam.transform.position = new Vector3(0.5f, -0.5f, -10);
            cam.orthographicSize = 5.5f;
            // a second camera under the map clears the whole screen: the map camera draws only its 15 x 11 view
            var backGo = new GameObject("Backdrop");
            backGo.transform.SetParent(transform);
            var back = backGo.AddComponent<Camera>();
            back.depth = cam.depth - 1;
            back.cullingMask = 0;
            back.clearFlags = CameraClearFlags.SolidColor;
            back.backgroundColor = new Color32(6, 5, 8, 255);
        }

        // The server sends the 15 x 11 view plus one tile left and top and two right and bottom (World.Range*). A wider
        // view showed unknown tiles at the sides, black, and they flashed while walking. The map keeps the 15 x 11 shape
        // and is centred; the rest of the screen is the backdrop.
        public const float ViewTilesW = 15f, ViewTilesH = 11f;
        public static float UiScale(float screenW, float screenH, float dpi)
        {
            float byHeight = Mathf.Min(screenH / 720f, screenW / 960f);
            return Mathf.Max(1f, Mathf.Max(byHeight, dpi / 160f));
        }

        public static Rect MapRect(float screenW, float screenH)
        {
            float target = ViewTilesW / ViewTilesH, a = screenW / Mathf.Max(1f, screenH);
            if (a > target) { float w = target / a; return new Rect((1f - w) / 2f, 0f, w, 1f); }
            float h = a / target;
            return new Rect(0f, (1f - h) / 2f, 1f, h);
        }

        static string DefaultPairDir()
        {
            // beside the executable: things/ (the folder that holds Tibia.dat and Tibia.spr)
            string exe = Path.GetDirectoryName(Application.dataPath) ?? ".";
            return Path.Combine(exe, "things");
        }

        bool LoadPair()
        {
            if (dat != null) return true;
            try
            {
                string d = Path.Combine(pairDir, "Tibia.dat"), s = Path.Combine(pairDir, "Tibia.spr");
                if (!File.Exists(d) || !File.Exists(s))
                {
                    status = "No Tibia.dat / Tibia.spr in " + pairDir;
                    return false;
                }
                dat = DatFile.Load(d);
                spr = SprFile.Open(s);
                atlas = new SpriteAtlas(spr);
                return true;
            }
            catch (Exception e)
            {
                status = "Could not read the pair: " + e.Message;
                dat = null;
                return false;
            }
        }

        static byte[] GuardKey()
        {
            // the environment, else a key the build embedded on purpose (CHAOS_EMBED_CLIENT_KEY=1), else the dev key
            var key = ClientGuard.ParseKey(Environment.GetEnvironmentVariable("CHAOS_CLIENT_KEY"));
            if (key == null)
            {
                var asset = Resources.Load<TextAsset>("chaos_client_key");
                if (asset != null) key = ClientGuard.ParseKey(asset.text);
            }
            return key ?? ClientGuard.DevKey;
        }

        static string RsaModulus()
        {
            // the server's public key: the environment, else the one the build baked in (CHAOS_RSA_PUBLIC), else the open one
            string m = Environment.GetEnvironmentVariable("CHAOS_RSA_PUBLIC");
            if (string.IsNullOrWhiteSpace(m))
            {
                var asset = Resources.Load<TextAsset>("chaos_rsa");
                if (asset != null) m = asset.text;
            }
            m = (m ?? "").Trim();
            return m.Length > 0 && System.Text.RegularExpressions.Regex.IsMatch(m, "^[0-9]+$") ? m : Protocol.OpenRsaModulus;
        }

        /// <summary>Extended (plain 10.98 wire, extended opcodes) or Chaos (the main client's markers too: feature list, wings / aura /
        /// shader, 0x4B floors, item attributes). The setting "chaos.identity" or the environment CHAOS_UNITY_IDENTITY names it.
        /// Extended until a live test has passed with Chaos (unity/README.md "Both clients").</summary>
        static ClientIdentity IdentityChoice()
        {
            string env = Environment.GetEnvironmentVariable("CHAOS_UNITY_IDENTITY");
            return ClientIdentity.Parse(string.IsNullOrEmpty(env) ? PlayerPrefs.GetString("chaos.identity", "extended") : env, ClientBuild());
        }

        static ushort ClientBuild()
        {
            var asset = Resources.Load<TextAsset>("chaos_build");
            return asset != null && ushort.TryParse(asset.text.Trim(), out var b) ? b : (ushort)30;
        }

        async void DoLogin()
        {
            if (!LoadPair()) return;
            PlayerPrefs.SetString("chaos.pair", pairDir);
            PlayerPrefs.SetString("chaos.host", host);
            PlayerPrefs.SetString("chaos.port", port);
            PlayerPrefs.SetString("chaos.account", account);
            status = "Connecting...";
            try
            {
                login = await LoginClient.Login(host, int.Parse(port), account, password, RsaModulus(), ClientBuild());
                if (login.Error != null) { status = login.Error; return; }
                status = "";
                screen = Screen.Characters;
            }
            catch (Exception e)
            {
                status = "Login failed: " + e.Message;
            }
        }

        void Enter(CharacterEntry ch)
        {
            world = new World(dat);
            world.PlayerVocation = ch.Vocation;   // the 3D character's class (Hd2dChars.SpecFor)
            session = new GameSession(world, new GameSession.Options
            {
                Host = ch.Host,
                Port = ch.Port,
                Account = account,
                Password = password,
                SessionKey = login.SessionKey,
                Character = ch.Name,
                GuardKey = GuardKey(),
                Build = ClientBuild(),
                RsaModulus = RsaModulus(),
                Identity = IdentityChoice(),
            });
            session.Log += line => { lock (log) { log.Add(line); if (log.Count > 8) log.RemoveAt(0); } };
            ChatEntered();
            session.Start();
            var go = new GameObject("Map");
            go.transform.SetParent(transform);
            view = go.AddComponent<MapView>();
            view.World = world;
            view.Atlas = atlas;
            view.Clock = () => session.Now;
            var hd = new GameObject("Hd2d");
            hd.transform.SetParent(go.transform, false);
            hd.SetActive(false);   // Awake / OnEnable run when the mode turns it on
            hd2dView = hd.AddComponent<Hd2dView>();
            hd2dView.World = world;
            hd2dView.Atlas = atlas;
            hd2dView.Clock = () => session.Now;
            hd2dView.Cam = cam;
            SetupWorld3d();
            SetupFrontLive(go.transform);
            ApplyHd2d();
            screen = Screen.Game;
        }

        void Leave(string why)
        {
            session?.Dispose();
            session = null;
            if (view != null) Destroy(view.gameObject);
            view = null;
            hd2dView = null;
            frontLive = null;
            world3dRoot = null;
            ApplyMode(false);
            cam.rect = new Rect(0f, 0f, 1f, 1f);
            ResetWindows();
            world = null;
            status = why;
            screen = Screen.Characters;
        }

        FrontArtScene frontArt;   // F11: the front-art test scene (FrontArtScene.cs), offline, on its own camera
        Camera frontCam;

        /// <summary>F11 opens the front-art test scene on its own camera over the screen, F11 again closes it. The mouse wheel zooms.</summary>
        void ToggleFrontArt()
        {
            if (frontArt != null)
            {
                Destroy(frontArt.gameObject);
                if (frontCam != null) Destroy(frontCam.gameObject, 0.2f);   // after the scene gave the camera's look back
                frontArt = null; frontCam = null;
                cam.enabled = true;
                return;
            }
            var cg = new GameObject("Front art camera");
            frontCam = cg.AddComponent<Camera>();
            frontCam.clearFlags = CameraClearFlags.SolidColor;
            frontCam.depth = cam.depth + 1;
            cam.enabled = false;
            frontArt = FrontArtScene.Open(frontCam, Hd2dView.LowQuality, true);
        }

        void Update()
        {
            if (Input.GetKeyDown(KeyCode.F11) && !chatFocused) ToggleFrontArt();
            if (screen != Screen.Game || session == null) return;
            session.Poll();
            if (session.Closed != null) { Leave(session.Closed); return; }
            // exactly the 15 x 11 view, centred (MapRect): nothing outside what the server sent is on screen
            if (!hd2d && !live)
            {
                cam.orthographic = true;
                cam.transform.SetPositionAndRotation(new Vector3(0.5f, -0.5f, -10), Quaternion.identity);
                cam.rect = MapRect(UnityEngine.Screen.width, UnityEngine.Screen.height);
                cam.orthographicSize = ViewTilesH / 2f;
            }
            if (Input.GetKeyDown(KeyCode.F12)) showDebug = !showDebug;
            // F9 switches classic / HD-2D. F9 is also hotkey slot 9: while the hotkey bar is open and the chat line has no
            // focus use Ctrl+F9 instead.
            if (Input.GetKeyDown(KeyCode.F9) && !chatFocused)
            {
                bool ctrl = Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
                bool barOpen = windows.Exists(win => win is HotkeyBarWindow && win.Open);
                if (ctrl || !barOpen) { hd2d = !hd2d; PlayerPrefs.SetInt("chaos.hd2d", hd2d ? 1 : 0); ApplyHd2d(); }
            }
            // F8 switches the front-art live view (FrontLiveView) on and off over the other two. F8 is hotkey slot 8: Ctrl+F8 while the bar is open
            if (Input.GetKeyDown(KeyCode.F8) && !chatFocused)
            {
                bool ctrl = Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
                bool barOpen = windows.Exists(win => win is HotkeyBarWindow && win.Open);
                if (ctrl || !barOpen) { live = !live; PlayerPrefs.SetInt("chaos.frontlive", live ? 1 : 0); ApplyHd2d(); }
            }
            // F10 switches the 3D world (models instead of sprites for the map) on top of HD-2D; F10 is hotkey slot 10: Ctrl+F10 while the bar is open
            if (Input.GetKeyDown(KeyCode.F10) && !chatFocused)
            {
                bool ctrl = Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
                bool barOpen = windows.Exists(win => win is HotkeyBarWindow && win.Open);
                if (ctrl || !barOpen)
                {
                    world3d = !world3d;
                    PlayerPrefs.SetInt("chaos.world3d", world3d ? 1 : 0);
                    ApplyWorld3d();
                    if (world3d && !world3dReady) AddChat("", "3D world: the 3D models are not in this build, the map stays sprites.", 0);
                    else if (world3d && !hd2d) AddChat("", "3D world is on, it shows with the HD-2D view (F9).", 0);
                }
            }
            if (!chatFocused)
                foreach (var win in windows)
                    if (win.Hotkey != KeyCode.None && Input.GetKeyDown(win.Hotkey) && (Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl)))
                        win.Open = !win.Open;
            CombatUpdate();
            HandleWalk();
        }

        void ApplyHd2d() { ApplyMode(hd2d && !live); ApplyWorld3d(); ApplyLive(); }

        /// <summary>The live view (F8): made once per session next to the HD-2D view; FrontLiveView adds the creatures and effects components itself.</summary>
        void SetupFrontLive(Transform parent)
        {
            var g = new GameObject("FrontLive");
            g.transform.SetParent(parent, false);
            g.SetActive(false);   // Init first, then the mode turns it on
            frontLive = g.AddComponent<FrontLiveView>();
            frontLive.Init(world, atlas, cam, () => session.Now);
            frontLive.BlockInput = () => OverUi(Input.mousePosition);
            // the creatures (added by Init) swing at our target; ChaosApp draws the names and health bars from FrontLiveView.Labels
            var creatures = frontLive.GetComponent<FrontLiveCreatures>();
            if (creatures != null) { creatures.LocalTarget = () => session != null ? session.AttackTarget : 0u; creatures.ShowLabels = false; }
        }

        void ApplyLive()
        {
            if (frontLive == null) return;
            bool on = live && screen == Screen.Game;
            if (on && view != null) view.SetVisible(false);   // the classic mesh and the live view never draw together
            frontLive.gameObject.SetActive(on);
        }

        /// <summary>True while the live view is on screen.</summary>
        bool LiveOn => live && frontLive != null && frontLive.isActiveAndEnabled;

        /// <summary>The 3D world's objects under the HD-2D view: the map's models (Hd2dRuins3d, WorldMode, Live) and the 3D characters.
        /// Created once per session; switched on and off with SetActive (each hooks and unhooks the view's Skip on enable / disable).</summary>
        void SetupWorld3d()
        {
            world3dRoot = new GameObject("World3d");
            world3dRoot.transform.SetParent(hd2dView.transform, false);
            world3dRoot.SetActive(false);
            var ruins = world3dRoot.AddComponent<Hd2dRuins3d>();
            ruins.World = world;
            ruins.WorldMode = true;
            ruins.Live = true;
            world3dReady = ruins.Attach(hd2dView);
            var chars = world3dRoot.AddComponent<Hd2dChars3d>();
            chars.World = world;
            chars.Live = true;
            chars.Attach(hd2dView);
        }

        /// <summary>The 3D world is on only together with the HD-2D view and when the models are in the build.</summary>
        void ApplyWorld3d()
        {
            if (world3dRoot != null) world3dRoot.SetActive(world3d && hd2d && !live && world3dReady);
        }

        /// <summary>Turns the HD-2D view on or off: the classic mesh and the 3D scene never draw together.</summary>
        void ApplyMode(bool on)
        {
            if (view != null) view.SetVisible(!on);
            if (hd2dView != null) hd2dView.gameObject.SetActive(on);
            if (!on)
            {
                cam.orthographic = true;
                cam.transform.SetPositionAndRotation(new Vector3(0.5f, -0.5f, -10), Quaternion.identity);
            }
        }

        /// <summary>A client-side notice in the Server Log tab (the server's lines go there from the parser).</summary>
        void AddChat(string who, string text, byte type) { session?.Talks.AddLocal(text); }

        bool OverUi(Vector2 mouse)
        {
            var p = new Vector2(mouse.x, UnityEngine.Screen.height - mouse.y);
            foreach (var r in uiRects) if (r.Contains(p)) return true;
            return false;
        }

        void HandleWalk()
        {
            if (chatFocused || TextEditing) return;   // typing: the letters go to the chat line
            Dir? d = null;
            bool up = Input.GetKey(KeyCode.UpArrow) || Input.GetKey(KeyCode.W) || Input.GetKey(KeyCode.Keypad8);
            bool down = Input.GetKey(KeyCode.DownArrow) || Input.GetKey(KeyCode.S) || Input.GetKey(KeyCode.Keypad2);
            bool left = Input.GetKey(KeyCode.LeftArrow) || Input.GetKey(KeyCode.A) || Input.GetKey(KeyCode.Keypad4);
            bool right = Input.GetKey(KeyCode.RightArrow) || Input.GetKey(KeyCode.D) || Input.GetKey(KeyCode.Keypad6);
            if (Input.GetKey(KeyCode.Keypad7)) d = Dir.NorthWest;
            else if (Input.GetKey(KeyCode.Keypad9)) d = Dir.NorthEast;
            else if (Input.GetKey(KeyCode.Keypad1)) d = Dir.SouthWest;
            else if (Input.GetKey(KeyCode.Keypad3)) d = Dir.SouthEast;
            else if (up && left) d = Dir.NorthWest;
            else if (up && right) d = Dir.NorthEast;
            else if (down && left) d = Dir.SouthWest;
            else if (down && right) d = Dir.SouthEast;
            else if (up) d = Dir.North;
            else if (down) d = Dir.South;
            else if (left) d = Dir.West;
            else if (right) d = Dir.East;
            if (d == null && Input.GetMouseButton(0) && GUIUtility.hotControl == 0 && !OverUi(Input.mousePosition))
            {
                // touch / click: walk towards the pointer from the screen centre
                Vector2 v = (Vector2)Input.mousePosition - new Vector2(UnityEngine.Screen.width, UnityEngine.Screen.height) / 2;
                if (v.magnitude > 40)
                {
                    float a = Mathf.Atan2(v.y, v.x) * Mathf.Rad2Deg;
                    int oct = Mathf.RoundToInt(a / 45f);
                    d = oct switch
                    {
                        0 => Dir.East, 1 => Dir.NorthEast, 2 => Dir.North, 3 => Dir.NorthWest,
                        -1 => Dir.SouthEast, -2 => Dir.South, -3 => Dir.SouthWest, _ => Dir.West,
                    };
                }
            }
            if (d != null) session.Walk(d.Value);
        }

        void OnGUI()
        {
            if (small == null)
            {
                small = new GUIStyle(GUI.skin.label) { fontSize = 14 };
                nameStyle = new GUIStyle(GUI.skin.label) { fontSize = 13, alignment = TextAnchor.LowerCenter, fontStyle = FontStyle.Bold, clipping = TextClipping.Overflow };
                chatStyle = new GUIStyle(GUI.skin.label) { fontSize = 14, wordWrap = true, richText = false, padding = new RectOffset(2, 2, 0, 0), margin = new RectOffset(0, 0, 0, 0) };
                titleStyle = new GUIStyle(GUI.skin.label) { fontSize = 14, fontStyle = FontStyle.Bold };
                GUI.skin.button.fontSize = 14;
                GUI.skin.textField.fontSize = 14;
                GUI.skin.label.fontSize = 14;
            }
            // the UI is laid out for 720 px of height and grows with the window (and with dense phone screens)
            float scale = UiScale(UnityEngine.Screen.width, UnityEngine.Screen.height, UnityEngine.Screen.dpi);
            GUI.matrix = Matrix4x4.Scale(new Vector3(scale, scale, 1));
            float w = UnityEngine.Screen.width / scale, h = UnityEngine.Screen.height / scale;
            switch (screen)
            {
                case Screen.Login: LoginGui(w, h); break;
                case Screen.Characters: CharactersGui(w, h); break;
                case Screen.Game: GameGui(w, h, scale); break;
            }
        }

        Texture2D logo;
        bool logoTried;

        /// <summary>Our logo above the login and character boxes (docs/brand, copied in by ChaosBuild).</summary>
        void Logo(float w, float top)
        {
            if (!logoTried) { logo = Resources.Load<Texture2D>("chaos_logo"); logoTried = true; }
            if (logo == null || top < 60) return;
            float lh = Mathf.Min(top - 16, 220f), lw = lh * logo.width / logo.height;
            GUI.DrawTexture(new Rect(w / 2 - lw / 2, top - lh - 8, lw, lh), logo, ScaleMode.ScaleToFit, true);
        }

        void LoginGui(float w, float h)
        {
            Logo(w, h / 2 - 150);
            GUILayout.BeginArea(new Rect(w / 2 - 170, h / 2 - 150, 340, 300), GUI.skin.box);
            GUILayout.Label("Cinders of Chaos - Unity prototype");
            GUILayout.Label("Server");
            GUILayout.BeginHorizontal();
            host = GUILayout.TextField(host, GUILayout.Width(240));
            port = GUILayout.TextField(port);
            GUILayout.EndHorizontal();
            GUILayout.Label("Account");
            account = GUILayout.TextField(account);
            GUILayout.Label("Password");
            password = GUILayout.PasswordField(password, '*');
            GUILayout.Label("Folder with Tibia.dat and Tibia.spr");
            pairDir = GUILayout.TextField(pairDir);
            if (GUILayout.Button("Log in")) DoLogin();
            GUILayout.Label(status, small);
            GUILayout.EndArea();
        }

        void CharactersGui(float w, float h) { CharSelectGui(w, h); }   // ChaosApp.CharSelect.cs

        void GameGui(float w, float h, float scale)
        {
            uiRects.Clear();
            // the windows, in UI units: names under them are not drawn
            var covers = new List<Rect> { StatusRect(), ChatRect(w, h), LogoutRect(w), ToolbarRect(w) };
            foreach (var win in windows) if (win.Open) covers.Add(win.Area);
            if (view != null)
            {
                // the map on screen, in UI units: names are clipped to it, creatures outside the 15 x 11 view get none
                Rect px = cam.pixelRect;
                Rect map = new Rect(px.x / scale, (UnityEngine.Screen.height - px.yMax) / scale, px.width / scale, px.height / scale);
                GUI.BeginGroup(map);
                // one tile in UI units: names and bars follow the map's zoom
                float tile = map.height / ViewTilesH;
                float barW = Mathf.Round(tile * 0.8f), barH = Mathf.Max(3f, Mathf.Round(tile / 14f));
                foreach (var (c, sp) in LabelPoints())
                {
                    // above the creature's tile, left-shifted by its outfit's displacement
                    float x = sp.x / scale, y = (UnityEngine.Screen.height - sp.y) / scale;
                    if (x < map.x || x > map.xMax || y < map.y || y > map.yMax + tile * 0.5f) continue;
                    x -= map.x;
                    y -= map.y;
                    var col = c.Type == 1 ? new Color(1f, 0.6f, 0.6f) : c.Type == 2 ? new Color(0.6f, 0.9f, 1f) : new Color(0.6f, 1f, 0.6f);
                    var hp = c.HealthPercent > 50 ? new Color(0.2f, 0.85f, 0.2f) : c.HealthPercent > 20 ? new Color(0.95f, 0.8f, 0.1f) : new Color(0.9f, 0.15f, 0.1f);
                    Rect nr = new Rect(x - 100, y - barH - 22, 200, 18);
                    Rect onScreen = new Rect(map.x + x - 60, map.y + nr.y, 120, 22 + barH);
                    bool hidden = false;
                    foreach (var r in covers) if (r.Overlaps(onScreen)) { hidden = true; break; }
                    if (hidden) continue;
                    nameStyle.normal.textColor = Color.black;
                    GUI.Label(new Rect(nr.x + 1, nr.y + 1, nr.width, nr.height), c.Name, nameStyle);
                    nameStyle.normal.textColor = col;
                    GUI.Label(nr, c.Name, nameStyle);
                    DrawBubbles(c, x, nr.y);
                    Rect bar = new Rect(x - barW / 2, y - barH - 3, barW, barH);
                    Fill(new Rect(bar.x - 1, bar.y - 1, bar.width + 2, bar.height + 2), new Color(0f, 0f, 0f, 0.85f));
                    Fill(new Rect(bar.x, bar.y, bar.width * c.HealthPercent / 100f, bar.height), hp);
                }
                DrawGroundLabels(map, scale);
                DrawAttackFrame(map, scale);
                GUI.EndGroup();
            }
            StatusPanel(scale);
            ChatWindow(w, h, scale);
            DrawWindows(w, h, scale);
            DeathWindow(w, h, scale);
            if (showDebug)
            {
                var me = world?.Player;
                string where = me != null ? me.Name + "  " + me.Position : "entering...";
                GUI.Label(new Rect(8, h - 24, w - 16, 20), where + "   " + session?.Stats, small);
                lock (log)
                    for (int i = 0; i < log.Count; i++) GUI.Label(new Rect(w * 0.45f, 120 + 20 * i, w * 0.55f - 8, 20), log[i], small);
            }
            Rect outR = LogoutRect(w);
            uiRects.Add(Scaled(outR, scale));
            if (GUI.Button(outR, "Log out")) { session?.Logout(); Leave("Logged out."); }
            HudGui(w, h, scale);     // toasts, buffs, monster and cast bars, anti-bot (ChaosApp.Hud.cs)
            PartyGui(w, h, scale);   // the right-click menu and the party invitation, over the windows
            ItemsGui(w, h, scale);   // the item tooltip, the modal window and the text window (ChaosApp.Items.cs)
        }

        public static void Fill(Rect r, Color c) => GUI.DrawTexture(r, Texture2D.whiteTexture, ScaleMode.StretchToFill, false, 0, c, 0, 0);
        static Rect Scaled(Rect r, float s) => new Rect(r.x * s, r.y * s, r.width * s, r.height * s);

        static Rect StatusRect() => new Rect(8, 8, 248, 92);
        static Rect LogoutRect(float w) => new Rect(w - 96, 8, 88, 30);
        Rect ChatRect(float w, float h)
        {
            if (!chatOpen) return new Rect(8, h - 38, 90, 30);
            float ch = Mathf.Min(240f, h * 0.36f);
            return new Rect(8, h - ch - 8, Mathf.Min(460f, w * 0.42f), ch);
        }

        void StatusPanel(float scale) { PlatePanel(scale); }   // the character plate: ChaosApp.Plate.cs

        void Bar(Rect r, int v, int max, Color c)
        {
            Fill(r, new Color(0f, 0f, 0f, 0.9f));
            if (max > 0) Fill(new Rect(r.x + 1, r.y + 1, (r.width - 2) * Mathf.Clamp01((float)v / max), r.height - 2), c);
            var st = new GUIStyle(small) { alignment = TextAnchor.MiddleCenter, fontSize = 13 };
            st.normal.textColor = Color.white;
            GUI.Label(r, v + " / " + max, st);
        }

        void ChatWindow(float w, float h, float scale) => ChatPanel(w, h, scale);

        void OnApplicationQuit() { session?.Dispose(); spr?.Dispose(); }
    }
}
