// The prototype's whole app: a login form (IMGUI), the character list, then the map with walking.
// Created from code at start, so the project needs no hand-made scene or prefab.
using System;
using System.Collections.Generic;
using System.IO;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed class ChaosApp : MonoBehaviour
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
        Camera cam;
        Vector2 charScroll;
        double walkReady;
        readonly List<string> log = new List<string>();
        GUIStyle small, nameStyle;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            if (FindObjectOfType<ChaosApp>() != null) return;
            var go = new GameObject("Cinders of Chaos");
            DontDestroyOnLoad(go);
            go.AddComponent<ChaosApp>();
        }

        void Awake()
        {
            Application.targetFrameRate = 60;
            pairDir = PlayerPrefs.GetString("chaos.pair", DefaultPairDir());
            host = PlayerPrefs.GetString("chaos.host", host);
            port = PlayerPrefs.GetString("chaos.port", port);
            account = PlayerPrefs.GetString("chaos.account", "");
            var camGo = new GameObject("Camera");
            camGo.transform.SetParent(transform);
            cam = camGo.AddComponent<Camera>();
            cam.orthographic = true;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color32(12, 10, 14, 255);
            cam.transform.position = new Vector3(0.5f, -0.5f, -10);
            cam.orthographicSize = 5.5f;
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
            // runtime only, never built in: the environment, else a client_key.txt (hex) beside the pair, else the dev key
            string hex = Environment.GetEnvironmentVariable("CHAOS_CLIENT_KEY");
            if (string.IsNullOrEmpty(hex))
            {
                var key = Resources.Load<TextAsset>("chaos_client_key");
                if (key != null) hex = key.text.Trim();
            }
            if (string.IsNullOrEmpty(hex)) return ClientGuard.DevKey;
            var b = new byte[hex.Length / 2];
            for (int i = 0; i < b.Length; i++) b[i] = Convert.ToByte(hex.Substring(2 * i, 2), 16);
            return b;
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
                login = await LoginClient.Login(host, int.Parse(port), account, password);
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
            session = new GameSession(world, new GameSession.Options
            {
                Host = ch.Host,
                Port = ch.Port,
                Account = account,
                Password = password,
                SessionKey = login.SessionKey,
                Character = ch.Name,
                GuardKey = GuardKey(),
                Build = 1,
            });
            session.Log += line => { lock (log) { log.Add(line); if (log.Count > 8) log.RemoveAt(0); } };
            session.Start();
            var go = new GameObject("Map");
            go.transform.SetParent(transform);
            view = go.AddComponent<MapView>();
            view.World = world;
            view.Atlas = atlas;
            view.Clock = () => session.Now;
            screen = Screen.Game;
        }

        void Leave(string why)
        {
            session?.Dispose();
            session = null;
            if (view != null) Destroy(view.gameObject);
            view = null;
            world = null;
            status = why;
            screen = Screen.Characters;
        }

        void Update()
        {
            if (screen != Screen.Game || session == null) return;
            session.Poll();
            if (session.Closed != null) { Leave(session.Closed); return; }
            // keep ~11 rows visible whatever the aspect, as the stock view shows 15 x 11
            cam.orthographicSize = Mathf.Max(5.5f, 7.5f / Mathf.Max(0.1f, cam.aspect));
            HandleWalk();
        }

        void HandleWalk()
        {
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
            if (d == null && Input.GetMouseButton(0) && GUIUtility.hotControl == 0)
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
            if (d == null || session.Now < walkReady) return;
            walkReady = session.Now + session.Walk(d.Value);
        }

        void OnGUI()
        {
            if (small == null)
            {
                small = new GUIStyle(GUI.skin.label) { fontSize = 12 };
                nameStyle = new GUIStyle(GUI.skin.label) { fontSize = 11, alignment = TextAnchor.LowerCenter, fontStyle = FontStyle.Bold };
            }
            float scale = Mathf.Max(1, UnityEngine.Screen.dpi / 160f);
            GUI.matrix = Matrix4x4.Scale(new Vector3(scale, scale, 1));
            float w = UnityEngine.Screen.width / scale, h = UnityEngine.Screen.height / scale;
            switch (screen)
            {
                case Screen.Login: LoginGui(w, h); break;
                case Screen.Characters: CharactersGui(w, h); break;
                case Screen.Game: GameGui(w, h, scale); break;
            }
        }

        void LoginGui(float w, float h)
        {
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

        void CharactersGui(float w, float h)
        {
            GUILayout.BeginArea(new Rect(w / 2 - 170, h / 2 - 160, 340, 320), GUI.skin.box);
            GUILayout.Label("Characters");
            charScroll = GUILayout.BeginScrollView(charScroll, GUILayout.Height(220));
            foreach (var ch in login.Characters)
                if (GUILayout.Button(ch.Name + "  (" + ch.World + ")")) Enter(ch);
            GUILayout.EndScrollView();
            if (GUILayout.Button("Back")) { screen = Screen.Login; status = ""; }
            GUILayout.Label(status, small);
            GUILayout.EndArea();
        }

        void GameGui(float w, float h, float scale)
        {
            if (view != null)
            {
                foreach (var (c, at) in view.Labels)
                {
                    // above the creature's tile, left-shifted by its outfit's displacement
                    Vector3 sp = cam.WorldToScreenPoint(new Vector3(at.x + 0.25f, at.y + 0.4f, 0));
                    float x = sp.x / scale, y = (UnityEngine.Screen.height - sp.y) / scale;
                    nameStyle.normal.textColor = c.Type == 1 ? new Color(1f, 0.6f, 0.6f) : c.Type == 2 ? new Color(0.6f, 0.9f, 1f) : new Color(0.6f, 1f, 0.6f);
                    GUI.Label(new Rect(x - 80, y - 22, 160, 16), c.Name, nameStyle);
                    GUI.DrawTexture(new Rect(x - 14, y - 5, 28, 4), Texture2D.blackTexture);
                    var hp = c.HealthPercent > 50 ? Color.green : c.HealthPercent > 20 ? Color.yellow : Color.red;
                    GUI.DrawTexture(new Rect(x - 13, y - 4, 26 * c.HealthPercent / 100f, 2), Texture2D.whiteTexture, ScaleMode.StretchToFill, false, 0, hp, 0, 0);
                }
            }
            var me = world?.Player;
            string where = me != null ? me.Name + "  " + me.Position : "entering...";
            GUI.Label(new Rect(8, 8, 600, 20), where + "   " + session?.Stats, small);
            lock (log)
                for (int i = 0; i < log.Count; i++) GUI.Label(new Rect(8, h - 20 * (log.Count - i) - 8, w - 16, 20), log[i], small);
            if (GUI.Button(new Rect(w - 88, 8, 80, 26), "Log out")) { session?.Logout(); Leave("Logged out."); }
        }

        void OnApplicationQuit() { session?.Dispose(); spr?.Dispose(); }
    }
}
