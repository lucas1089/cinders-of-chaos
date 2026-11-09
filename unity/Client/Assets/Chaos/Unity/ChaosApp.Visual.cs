// Map effects, layout and the options of phase 5, track R, in both map views (the classic MapView and the front-art live view; the HD-2D scene draws none yet).
// Everything is drawn in the map group of GameGui through TileScreenPx (ChaosApp.Loot.cs), so one implementation serves both views:
//   under the feet   ground rings (game_groundfx ids), combat decals, footprints, chest auras, the Templar foot aura and its range frame
//   over the map     hit flashes, level-up wings, loot beams, cosmetic glows
// The rules are Core/Visual.cs and Core/Layout.cs, the session models Core/GameVisual.cs. Pictures: the main client's own PNG files from the overlay folder
// (OverlayPath); where a picture is missing a drawn one stands in (soft discs, rings, feathers), so nothing needs a new binary in Unity.
// Also here: the map zoom, the camera shake, the movable HUD pieces with their edit mode, the saved window layout and the window fade hooks.
using System.Collections.Generic;
using System.IO;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    /// <summary>What the map effects and the live view share: the spell effect opacity.</summary>
    public static class VisualRuntime
    {
        /// <summary>0.25 to 1: the live view's effect quads are multiplied by it (FrontLiveFx).</summary>
        public static float EffectAlpha = 1f;
        /// <summary>Phase 8 B: the ground marks (game_groundfx) and the session clock in ms; the live view draws them as flat quads on the floor (FrontLiveFx), under its creatures.</summary>
        public static List<GroundMark> Grounds;
        public static System.Func<double> GroundNow;
    }

    public sealed partial class ChaosApp
    {
        // the HUD pieces read the screen in UI units
        static float hudW = 960f, hudH = 540f;
        Texture2D texSoft, texRing, texBeam, texFeather;
        readonly Dictionary<string, Texture2D> visualTex = new Dictionary<string, Texture2D>();
        WindowLayout layout = new WindowLayout();
        string layoutFor, hudFor;
        double layoutSaved;
        string hudDrag;
        Vector2 hudDragStart;
        readonly Dictionary<GameWindow, UiFade> fades = new Dictionary<GameWindow, UiFade>();
        readonly Dictionary<GameWindow, bool> fadeWasOpen = new Dictionary<GameWindow, bool>();
        List<KeyValuePair<Pos, BeamLook>> beams = new List<KeyValuePair<Pos, BeamLook>>();
        readonly SessionStamp beamsStamp = new SessionStamp();   // a stamp of one session: a new login draws beams at once (Core/Phase29.cs)
        Rect shakeBase;
        bool shaken;
        static readonly string[] LayoutOpenWindows = { "MinimapWindow", "BattleListWindow", "EquipmentWindow", "ContainersWindow" };

        VisualEffects Vis => session?.Visual;

        // ------------------------------------------------------------------------------------------------ every frame
        /// <summary>Called first in Update on every screen: the options, the sounds and the music, the zoom, the layout.</summary>
        void VisualUpdate()
        {
            using var _slow = SlowCalls.Scope("VisualUpdate", "Update");
            VisualPrefs.Load();
            BossAnimate.Clock = () => session != null ? session.Now : Time.timeAsDouble * 1000.0;
            VisualRuntime.EffectAlpha = EffectOpacity.Alpha(VisualPrefs.EffectPercent);
            var v = screen == Screen.Game ? Vis : null;
            if (v != null)
            {
                VisualPrefs.Apply(v);
                v.LootKills = () => FindWindow<LootWindow>()?.Filter?.Kills;
                v.LootAlerted = k => FindWindow<LootWindow>()?.Filter?.AlertedKill == k;
                v.Activity = ActivityRegion;
                v.Random = () => Random.value;
            }
            ViewCharacterUpdate();
            GroundFlatsUpdate(v);
            Phase8BUpdate();   // ChaosApp.Phase8B.cs
            Phase7QUpdate();
            ApplyViewRows(VisualPrefs.ViewRows);
            Phase7YUpdate();   // ChaosApp.Phase7Y.cs: monster sizes, item outlines, fonts
            Phase8CUpdate();   // ChaosApp.Phase8C.cs: shader callbacks of the views, the grade post
            AwareUpdate();
            AudioUpdate(v);
            if (v == null) return;
            VisualLayoutUpdate();
            ViewWheelZoom();
        }

        /// <summary>"arena" or "dungeon" while an activity HUD window shows (the main client's game_chaosmusic ACTIVITIES), else null.</summary>
        string ActivityRegion()
        {
            foreach (var win in windows)
            {
                if (!win.Open) continue;
                switch (win.GetType().Name)
                {
                    case "ArenaHudWindow": case "BattlegroundHudWindow": case "SiegeHudWindow": case "PvpZoneHudWindow": case "InvasionHudWindow": return "arena";
                    case "RiftWindow": case "DungeonCounterWindow": case "TowerPanelWindow": case "DescentHudWindow": case "RaidHudWindow": return "dungeon";
                }
            }
            return null;
        }

        // ------------------------------------------------------------------------------------------------ map zoom and shake
        int appliedRows, appliedMax;
        string viewFor;
        AwareRange awareAskedFor;
        bool awareSent;

        /// <summary>The most rows any view can draw: what the aware range holds (phase 8 B: HD-2D and the live view read the tile window from World.Range and fit their camera to ViewTilesW x ViewTilesH too).</summary>
        public int ViewMaxRows => screen == Screen.Game && world != null ? ViewZoom.MaxRowsFor(world.Range) : ViewZoom.MaxRows;

        void ApplyViewRows(int rows)
        {
            int max = ViewMaxRows;
            rows = ViewZoom.Clamp(rows, max);
            if (rows == appliedRows && max == appliedMax) return;
            appliedRows = rows; appliedMax = max;
            ViewTilesH = rows;
            ViewTilesW = ViewZoom.Cols(rows, world != null ? world.Range.Width : 17);
        }

        /// <summary>Per character zoom (game_chaosview): when the character is known its saved rows are loaded, a new one starts at about 72 px a tile.</summary>
        void ViewCharacterUpdate()
        {
            using var _slow = SlowCalls.Scope("ViewCharacterUpdate", "Update");
            string name = screen == Screen.Game ? world?.Player?.Name : null;
            if (string.IsNullOrEmpty(name)) { viewFor = null; VisualPrefs.CurrentCharacter = null; return; }
            if (viewFor == name) return;
            viewFor = name;
            VisualPrefs.CurrentCharacter = name;
            string key = ViewZoom.CharKey(name);
            int saved = key != null && PlayerPrefs.HasKey(key) ? PlayerPrefs.GetInt(key) : 0;
            VisualPrefs.ViewRows = saved >= 3 ? ViewZoom.Clamp(saved, ViewZoom.HardMaxRows) : ViewZoom.Clamp(ViewZoom.DefaultZoom(UnityEngine.Screen.height, ViewZoom.HardMaxRows), ViewZoom.HardMaxRows);
        }

        /// <summary>The option "Wide view": asks the server for 29 x 21 (or the default 17 x 13 when off) once after the login and again when the option changes.
        /// CHAOS_UNITY_AWARE keeps its own say; a connection without the Chaos markers cannot ask and stays at the default.</summary>
        void AwareUpdate()
        {
            using var _slow = SlowCalls.Scope("AwareUpdate", "Update");
            if (screen != Screen.Game || session == null || world?.Player == null || !string.IsNullOrEmpty(System.Environment.GetEnvironmentVariable("CHAOS_UNITY_AWARE"))) { if (screen != Screen.Game) awareSent = false; return; }
            var want = ViewZoom.Wanted(VisualPrefs.WideView);
            if (awareSent && want.Width == awareAskedFor.Width && want.Height == awareAskedFor.Height) return;
            awareSent = true; awareAskedFor = want;
            if (want.Width != world.Range.Width || want.Height != world.Range.Height) session.RequestAwareRange(want.Width, want.Height);
        }

        /// <summary>Ctrl + wheel over the map zooms the classic view by whole rows (7 to 11). The live view has its own wheel zoom.</summary>
        void ViewWheelZoom()
        {
            using var _slow = SlowCalls.Scope("ViewWheelZoom", "Update");
            if (LiveOn || hd2d || chatFocused) return;
            bool ctrl = Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
            float wheel = Input.mouseScrollDelta.y;
            if (!ctrl || Mathf.Abs(wheel) < 0.5f || OverUi(Input.mousePosition)) return;
            VisualPrefs.ViewRows = ViewZoom.Step(ViewZoom.Clamp(VisualPrefs.ViewRows, ViewMaxRows), wheel > 0 ? -1 : 1, ViewMaxRows);   // wheel up: closer, fewer rows
            VisualPrefs.Save();
        }

        void LateUpdate()
        {
            if (shaken && cam != null)
            {
                if (cam.rect == shakeRectApplied) cam.rect = shakeBase;
                shaken = false;
            }
            var v = screen == Screen.Game ? Vis : null;
            if (v == null || cam == null || hd2d || !VisualPrefs.Fx.ScreenShake || !v.Shake.Running(session.Now)) return;
            v.Shake.Offset(session.Now, () => Random.value, out int dx, out int dy);
            if (dx == 0 && dy == 0) return;
            shakeBase = cam.rect;
            // 1x sprite pixels of a 32 px tile, shown at the map's tile size
            float px = UnityEngine.Screen.height * shakeBase.height / ViewTilesH / 32f;
            var r = shakeBase;
            r.x += dx * px / UnityEngine.Screen.width;
            r.y += dy * px / UnityEngine.Screen.height;
            cam.rect = r;
            shakeRectApplied = cam.rect;
            shaken = true;
        }

        Rect shakeRectApplied;

        // ------------------------------------------------------------------------------------------------ textures
        Texture2D OverlayTex(string rel)
        {
            if (visualTex.TryGetValue(rel, out var t)) return t;
            t = null;
            using var _slow = SlowCalls.Scope(SlowCalls.Log.On ? "OverlayTex " + rel : null, "load");
            string path = OverlayPath(rel);
            if (path != null)
            {
                try
                {
                    t = new Texture2D(2, 2, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
                    if (!t.LoadImage(File.ReadAllBytes(path))) { Destroy(t); t = null; }
                }
                catch (System.Exception) { t = null; }
            }
            visualTex[rel] = t;
            return t;
        }

        static Texture2D MakeTex(int w, int h, System.Func<float, float, float> alpha)
        {
            var t = new Texture2D(w, h, TextureFormat.RGBA32, false) { filterMode = FilterMode.Bilinear, wrapMode = TextureWrapMode.Clamp };
            var px = new Color32[w * h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    px[y * w + x] = new Color(1f, 1f, 1f, Mathf.Clamp01(alpha((x + 0.5f) / w, (y + 0.5f) / h)));
            t.SetPixels32(px);
            t.Apply(false, true);
            return t;
        }

        void VisualTextures()
        {
            using var _slow = SlowCalls.Scope("VisualTextures", "load");
            if (texSoft != null) return;
            texSoft = MakeTex(64, 64, (u, v) => { float d = Mathf.Sqrt((u - 0.5f) * (u - 0.5f) + (v - 0.5f) * (v - 0.5f)) * 2f; return 1f - d * d; });
            texRing = MakeTex(64, 64, (u, v) => { float d = Mathf.Sqrt((u - 0.5f) * (u - 0.5f) + (v - 0.5f) * (v - 0.5f)) * 2f; return Mathf.Max(0f, 1f - Mathf.Abs(d - 0.85f) / 0.12f); });
            texBeam = MakeTex(16, 64, (u, v) => { float side = 1f - Mathf.Abs(u - 0.5f) * 2f; return side * side * (1f - v); });   // v is 0 at the bottom row: bright at the foot of the beam
            texFeather = MakeTex(16, 64, (u, v) => { float side = 1f - Mathf.Abs(u - 0.5f) * 2f; return Mathf.Pow(side, 1.5f) * (1f - v * 0.6f) * Mathf.Min(1f, v * 6f); });
        }

        // ------------------------------------------------------------------------------------------------ geometry
        /// <summary>The middle of a tile in the map group and the tile's width, false when the view cannot say.</summary>
        bool TileGeom(Pos p, Rect map, float scale, out Vector2 at, out float tile)
        {
            tile = 0f;
            if (!TileInGroup(p, map, scale, out at)) return false;
            tile = map.height / ViewTilesH;
            if (TileInGroup(new Pos(p.X + 1, p.Y, p.Z), map, scale, out Vector2 east))
            {
                float d = Mathf.Abs(east.x - at.x);
                if (d >= 4f) tile = d;
            }
            return at.x > -tile * 3 && at.x < map.width + tile * 3 && at.y > -tile * 3 && at.y < map.height + tile * 3;
        }

        /// <summary>A creature's middle on screen, between the tile it left and the tile it is on while it walks.</summary>
        bool CreatureCenter(Creature c, Rect map, float scale, out Vector2 at, out float tile)
        {
            if (!TileGeom(c.Position, map, scale, out at, out tile)) return false;
            WalkMath.Between(c, session.Now, out Pos wf, out Pos wt, out float wu);   // Core/SmoothWalk.cs
            if (wf != wt && TileGeom(wt, map, scale, out Vector2 toAt, out _) && TileInGroup(wf, map, scale, out Vector2 from))
                at = Vector2.Lerp(from, toAt, wu);
            return true;
        }

        static void Pic(Texture2D t, Rect r, Color c)
        {
            if (t == null) return;
            GUI.DrawTexture(r, t, ScaleMode.StretchToFill, true, 0f, c, 0f, 0f);
        }

        static Rect Around(Vector2 at, float w, float h) => new Rect(at.x - w / 2f, at.y - h / 2f, w, h);

        /// <summary>One frame of a horizontal strip of square frames.</summary>
        static void Strip(Texture2D t, int frame, int frames, Rect r, Color c)
        {
            if (t == null) return;
            var old = GUI.color; GUI.color = c;
            GUI.DrawTextureWithTexCoords(r, t, new Rect(frame / (float)frames, 0f, 1f / frames, 1f));
            GUI.color = old;
        }

        /// <summary>A picture cut in nine along a border of b (of 1) of each side, so the corners keep their size while the middle stretches.</summary>
        static void NineSlice(Texture2D t, Rect r, float edge, float bu, Color c)
        {
            if (t == null) return;
            var old = GUI.color; GUI.color = c;
            float[] xs = { r.x, r.x + edge, r.xMax - edge, r.xMax }, ys = { r.y, r.y + edge, r.yMax - edge, r.yMax };
            float[] us = { 0f, bu, 1f - bu, 1f };
            for (int j = 0; j < 3; j++)
                for (int i = 0; i < 3; i++)
                {
                    var dst = new Rect(xs[i], ys[j], Mathf.Max(0f, xs[i + 1] - xs[i]), Mathf.Max(0f, ys[j + 1] - ys[j]));
                    var src = new Rect(us[i], 1f - us[j + 1], us[i + 1] - us[i], us[j + 1] - us[j]);
                    GUI.DrawTextureWithTexCoords(dst, t, src);
                }
            GUI.color = old;
        }

        // ------------------------------------------------------------------------------------------------ the map overlays
        /// <summary>Called inside the map group (map is its rect in UI units), after the world overlays.</summary>
        void DrawVisualOverlays(Rect map, float scale)
        {
            using var _slow = SlowCalls.Scope("DrawVisualOverlays", "OnGUI");
            var v = Vis;
            if (v == null || world?.Player == null || Event.current.type != EventType.Repaint || (hd2d && !LiveOn)) return;
            VisualTextures();
            double now = session.Now;
            float fxA = VisualRuntime.EffectAlpha;
            // the ground rings are quads of the map mesh (MapView.Flats) or of the floor of the live view: under the creatures, not here
            DrawDecals(v, map, scale);
            DrawPrints(v, map, scale, now);
            DrawChestAuras(v, map, scale, now);
            DrawFootAuras(v, map, scale, now);
            DrawGlows(v, map, scale, now);
            DrawBeams(v, map, scale, now);
            DrawFlashes(v, map, scale, now);
            DrawPhase9D(v, map, scale, now);   // ChaosApp.Phase9D.cs: spell effects of the art file and the spell light (classic view)
            DrawWings(v, map, scale, now, fxA);
        }

        readonly List<float[]> ringQuads = new List<float[]>();

        /// <summary>Every frame: the ground marks as flat quads of the classic map mesh (drawn in the tile's turn, before its creatures). In the live view FrontLiveFx reads
        /// VisualRuntime.Grounds, in HD-2D there are none yet.</summary>
        void GroundFlatsUpdate(VisualEffects v)
        {
            using var _slow = SlowCalls.Scope("GroundFlatsUpdate", "Update");
            VisualRuntime.Grounds = v != null ? v.Grounds : null;
            VisualRuntime.GroundNow = () => session != null ? session.Now : 0.0;
            if (view == null) return;
            view.Flats.Clear();
            if (v == null || hd2d || LiveOn || session == null) return;
            double now = session.Now;
            float fxA = VisualRuntime.EffectAlpha;
            foreach (var g in v.Grounds)
            {
                float t = Mathf.Clamp01((float)((now - g.Born) / VisualEffects.GroundMs));
                var pal = FrontFx.Palette(FrontFx.EffectTable.TryGetValue(g.Id, out var el) ? el : FxElement.Arcane);
                ringQuads.Clear();
                GroundRing.Quads(t, ringQuads);
                foreach (var q in ringQuads)
                    view.Flats.Add(new MapView.FlatMark { Pos = g.Pos, W = q[0], H = q[1], Alpha = q[2] * fxA, Ring = q[3] > 0.5f, Tint = q[3] > 0.5f ? new Color(pal.BR, pal.BG, pal.BB) : new Color(pal.CR, pal.CG, pal.CB) });
            }
        }

        void DrawDecals(VisualEffects v, Rect map, float scale)
        {
            foreach (var d in v.Decals.Decals)
            {
                if (!TileGeom(d.Pos, map, scale, out Vector2 at, out float tile)) continue;
                var tex = OverlayTex("game_combatdecals/images/" + CombatDecals.Art(d.Kind, d.Variant) + ".png");
                var col = new Color(1f, 1f, 1f, d.Alpha);
                if (tex != null) Pic(tex, Around(at, tile, tile), col);
                else Pic(texSoft, Around(at, tile * 0.8f, tile * 0.5f), DecalFallback(d.Kind, d.Alpha));
            }
        }

        static Color DecalFallback(string kind, float a)
        {
            switch (kind)
            {
                case "fire": return new Color(0.12f, 0.08f, 0.05f, a);
                case "ice": return new Color(0.7f, 0.9f, 1f, a * 0.7f);
                case "poison": return new Color(0.3f, 0.7f, 0.2f, a * 0.8f);
                default: return new Color(0.55f, 0.05f, 0.05f, a * 0.8f);
            }
        }

        void DrawPrints(VisualEffects v, Rect map, float scale, double now)
        {
            foreach (var p in v.Cosmetic.Prints)
            {
                float a = CosmeticFxState.PrintOpacity(now - p.Born);
                if (a <= 0 || !TileGeom(p.Pos, map, scale, out Vector2 at, out float tile)) continue;
                var tex = OverlayTex("game_cosmeticfx/images/prints/" + p.Art + ".png");
                if (tex == null) continue;
                var m = GUI.matrix;
                GUIUtility.RotateAroundPivot(p.Rotation, at);
                float s = tile * 0.9f;
                Pic(tex, Around(at, s, s), new Color(1f, 1f, 1f, a));
                GUI.matrix = m;
            }
        }

        void DrawChestAuras(VisualEffects v, Rect map, float scale, double now)
        {
            if (!v.Aura.Enabled) return;
            foreach (var c in v.Chests)
            {
                if (!TileGeom(c.Pos, map, scale, out Vector2 at, out float tile)) continue;
                var tex = OverlayTex(ChestAuraState.ChestPath(c.Def.Art));
                float size = tile * c.Def.Px / ChestAuraState.Sprite;
                var center = c.Def.Big ? new Vector2(at.x - tile * 0.5f, at.y - tile * 0.5f) : at;
                int f = ChestAuraState.FrameIndex(now, ChestAuraState.ChestFrameMs, ChestAuraState.ChestFrames);
                if (tex != null) Strip(tex, f, ChestAuraState.ChestFrames, Around(center, size, size), Color.white);
                else Pic(texSoft, Around(center, size * 0.7f, size * 0.45f), new Color(1f, 0.85f, 0.4f, 0.25f));
            }
            foreach (uint id in v.Aura.Cursed)
            {
                if (!world.Creatures.TryGetValue(id, out var c) || !CreatureCenter(c, map, scale, out Vector2 at, out float tile)) continue;
                var tex = OverlayTex(ChestAuraState.ChestPath("cursed_smoke"));
                int f = ChestAuraState.FrameIndex(now, ChestAuraState.ChestFrameMs, ChestAuraState.ChestFrames);
                if (tex != null) Strip(tex, f, ChestAuraState.ChestFrames, Around(new Vector2(at.x, at.y + tile * 0.15f), tile * 2f, tile * 2f), Color.white);
            }
        }

        void DrawFootAuras(VisualEffects v, Rect map, float scale, double now)
        {
            if (!v.Aura.Enabled) return;
            foreach (var row in v.Aura.Rows.Values)
            {
                if (!world.Creatures.TryGetValue(row.Id, out var c) || !CreatureCenter(c, map, scale, out Vector2 at, out float tile)) continue;
                if (row.Party)
                {
                    var frame = OverlayTex(ChestAuraState.FramePath(row.Line));
                    float side = tile * (2 * row.Radius + 1);
                    if (frame != null) NineSlice(frame, Around(at, side, side), tile, ChestAuraState.Sprite / (float)ChestAuraState.FramePx, new Color(1f, 1f, 1f, 0.9f));
                }
                var tex = OverlayTex(ChestAuraState.FootPath(row.Line));
                float size = tile * ChestAuraState.FootPx / ChestAuraState.Sprite;
                int f = ChestAuraState.FrameIndex(now, ChestAuraState.FootFrameMs, ChestAuraState.FootFrames);
                var feet = new Vector2(at.x, at.y + tile * 12f / ChestAuraState.Sprite);
                if (tex != null) Strip(tex, f, ChestAuraState.FootFrames, Around(feet, size, size), Color.white);
                else Pic(texRing, Around(feet, size, size * 0.6f), new Color(1f, 0.9f, 0.5f, 0.6f));
            }
        }

        void DrawGlows(VisualEffects v, Rect map, float scale, double now)
        {
            if (v.Cosmetic.Looks.Count == 0) return;
            foreach (var c in world.Creatures.Values)
            {
                if (c.Type != 0 || !v.Cosmetic.Looks.TryGetValue(c.Name, out var look) || look.Glow == null) continue;
                bool mine = c.Id == world.PlayerId;
                if (!v.Cosmetic.Allowed(false, mine) || c.Position.Z != world.Center.Z) continue;
                if ((ShaderMapOn || LiveFxOn) && OutlineFx.Cosmetic(look.Glow, look.Pulse) != null) continue;   // the shader draws it as an outline (Phase8CLook)
                if (!CreatureCenter(c, map, scale, out Vector2 at, out float tile)) continue;
                var tex = OverlayTex("game_cosmeticfx/images/glows/" + look.Glow + ".png");
                if (tex == null) continue;
                float a = look.Pulse ? CosmeticFxState.PulseOpacity(now) : 1f;
                float s = tile * 3f;
                Pic(tex, Around(at, s, s), new Color(1f, 1f, 1f, 0.8f * a));
            }
        }

        void DrawBeams(VisualEffects v, Rect map, float scale, double now)
        {
            var s = v.Beams;
            if (!s.Enabled) return;
            var loot = FindWindow<LootWindow>();
            if (loot == null || loot.Ground == null || loot.Filter == null) return;
            if (beamsStamp.Due(session, now, 250))
            {
                beamsStamp.Mark(session, now);
                var all = new List<KeyValuePair<Pos, BeamLook>>();
                var seen = new HashSet<Pos>();
                // corpses the server named (opcode 238 "beam"): they come first, the ground labels fill in the rest
                foreach (var sb in loot.Filter.Beams.Values)
                {
                    if (sb.Pos.Z != world.Player.Position.Z || !seen.Add(sb.Pos)) continue;
                    var look = LootBeams.BeamOf(sb.Items, loot.Filter.Settings, s);
                    if (look != null) all.Add(new KeyValuePair<Pos, BeamLook>(sb.Pos, look));
                }
                foreach (var l in loot.Ground.Labels(world.Player.Position, loot.Filter.Settings, false))
                {
                    if (!seen.Add(l.Tile) || l.Row == null) continue;
                    if (!l.Row.Corpse && !s.Ground) continue;
                    var items = l.Row.Corpse ? l.Row.Inside : new List<LootInfo> { l.Row.Info };
                    var look = LootBeams.BeamOf(items, loot.Filter.Settings, s);
                    if (look != null) all.Add(new KeyValuePair<Pos, BeamLook>(l.Tile, look));
                }
                var me = world.Player.Position;
                beams = LootBeams.Cap(all, p => System.Math.Max(System.Math.Abs(p.X - me.X), System.Math.Abs(p.Y - me.Y)));
            }
            foreach (var kv in beams)
            {
                if (!TileGeom(kv.Key, map, scale, out Vector2 at, out float tile)) continue;
                var look = kv.Value;
                if (DrawBeamPack(kv.Key, look, map, scale, now)) continue;   // the pair's own beam effect (pair 36)
                var c = HexColor(look.Color, Color.white);
                float pulse = 0.88f + 0.12f * Mathf.Sin((float)now / 260f + kv.Key.X * 1.7f);
                float h = tile * look.Height, w = tile * 0.24f;
                Pic(texSoft, Around(new Vector2(at.x, at.y + tile * 0.1f), tile * 0.9f, tile * 0.4f), new Color(c.r, c.g, c.b, 0.45f * look.Intensity * pulse));
                Pic(texBeam, new Rect(at.x - w / 2f, at.y - h + tile * 0.1f, w, h), new Color(c.r, c.g, c.b, look.Intensity * pulse));
            }
        }

        void DrawFlashes(VisualEffects v, Rect map, float scale, double now)
        {
            if (!VisualPrefs.Fx.HitFlash || ShaderMapOn || LiveFxOn) return;   // the classic mesh and the live view's sprites flash the outfit itself (hit modes of the shaders)
            foreach (var f in v.Flashes)
            {
                float k = HitFlasher.Strength(now, f.Start, f.Ms);
                if (k <= 0 || !world.Creatures.TryGetValue(f.Creature, out var c) || !CreatureCenter(c, map, scale, out Vector2 at, out float tile)) continue;
                var col = f.Red ? new Color(1f, 0.15f, 0.1f, 0.6f * k) : new Color(1f, 1f, 1f, 0.55f * k);
                Pic(texSoft, Around(at, tile * 1.1f, tile * 1.1f), col);
            }
        }

        void DrawWings(VisualEffects v, Rect map, float scale, double now, float fxA)
        {
            foreach (var p in v.Wings.Active)
            {
                float t = LevelWingsState.Progress(now, p.Start);
                if (t < 0 || !world.Creatures.TryGetValue(p.Creature, out var c)) continue;
                if (DrawWingsPack(p, c, map, scale, now, fxA)) continue;   // the pair's level-up effect (pair 36)
                if (!CreatureCenter(c, map, scale, out Vector2 at, out float tile)) continue;
                float open = 1f - (1f - Mathf.Min(1f, t * 2.2f)) * (1f - Mathf.Min(1f, t * 2.2f));
                float a = Mathf.Sin(t * Mathf.PI) * fxA;
                var rise = new Vector2(at.x, at.y - tile * (0.15f + 0.45f * t));
                Pic(texSoft, Around(rise, tile * 2.2f * (0.5f + 0.5f * open), tile * 2.2f * (0.5f + 0.5f * open)), new Color(1f, 0.85f, 0.35f, 0.35f * a));
                for (int side = -1; side <= 1; side += 2)
                    for (int i = 0; i < 6; i++)
                    {
                        float ang = side * (25f + i * 15f) * open;
                        float len = tile * (1.1f + 0.14f * i);
                        var m = GUI.matrix;
                        GUIUtility.RotateAroundPivot(ang, rise);
                        Pic(texFeather, new Rect(rise.x - len * 0.09f, rise.y - len, len * 0.18f, len), new Color(1f, 0.9f - 0.04f * i, 0.45f, 0.9f * a));
                        GUI.matrix = m;
                    }
            }
        }

        /// <summary>The colour of a creature's name: the own character wears the name shader it picked (a moving gradient), the others keep theirs.</summary>
        Color VisualNameColor(Creature c, Color col)
        {
            var v = Vis;
            if (v == null || c.Id != world.PlayerId || v.Names.Current <= 0) return col;
            var s = v.Names.Find(v.Names.Current);
            if (s == null) return col;
            uint rgb = NameShaderState.At(s.Name, session.Now);
            return new Color(((rgb >> 16) & 255) / 255f, ((rgb >> 8) & 255) / 255f, (rgb & 255) / 255f);
        }

        // ------------------------------------------------------------------------------------------------ movable HUD
        /// <summary>The place of a HUD piece: its default moved by the saved offset, kept on screen.</summary>
        static Rect HudPlace(string id, Rect def)
        {
            float x = def.x, y = def.y;
            HudLayout.Place(id, ref x, ref y, def.width, def.height, hudW, hudH);
            return new Rect(x, y, def.width, def.height);
        }

        /// <summary>How far a piece is from its default place (for pieces that lay themselves out, like the top menu).</summary>
        static Vector2 HudShift(string id, Rect def)
        {
            var r = HudPlace(id, def);
            return new Vector2(r.x - def.x, r.y - def.y);
        }

        void HudLayoutUpdate(float w, float h)
        {
            using var _slow = SlowCalls.Scope("HudLayoutUpdate", "OnGUI");
            hudW = w; hudH = h;
            string name = world?.Player?.Name;
            if (name == null || hudFor == name) return;
            hudFor = name;
            HudLayout.Load(PlayerPrefs.GetString(HudLayout.Key(name), ""));
        }

        /// <summary>The edit mode: each piece gets a frame you drag; double click puts it back. Called at the end of GameGui.</summary>
        void HudEditGui(float w, float h, float scale)
        {
            using var _slow = SlowCalls.Scope("HudEditGui", "OnGUI");
            hudW = w; hudH = h;
            if (!HudLayout.Editing) { hudDrag = null; return; }
            var e = Event.current;
            Fill(new Rect(0, 0, w, 22), new Color(0f, 0f, 0f, 0.75f));
            GUI.Label(new Rect(8, 2, w - 120, 20), Loc.T("Drag the frames to move the HUD pieces. Double click puts one back."), small);
            var done = new Rect(w - 108, 0, 100, 22);
            uiRects.Add(Scaled(done, scale));
            if (GUI.Button(done, Loc.T("Done"))) { HudLayout.Editing = false; SaveHud(); return; }
            var defaults = new Dictionary<string, Rect>
            {
                { "status", new Rect(8, 8, 248, 92) }, { "logout", new Rect(w - 96, 8, 88, 30) },
                { "chat", ChatDefault(w, h) }, { "toolbar", new Rect(w - 104 - 76 * 7, 8, 76 * 7, 30) },
            };
            foreach (string id in HudLayout.Pieces)
            {
                var def = defaults[id];
                var r = HudPlace(id, def);
                uiRects.Add(Scaled(r, scale));
                bool dragging = hudDrag == id;
                Fill(new Rect(r.x - 2, r.y - 2, r.width + 4, 2), dragging ? Color.yellow : new Color(0.4f, 0.8f, 1f, 0.9f));
                Fill(new Rect(r.x - 2, r.yMax, r.width + 4, 2), dragging ? Color.yellow : new Color(0.4f, 0.8f, 1f, 0.9f));
                Fill(new Rect(r.x - 2, r.y, 2, r.height), dragging ? Color.yellow : new Color(0.4f, 0.8f, 1f, 0.9f));
                Fill(new Rect(r.xMax, r.y, 2, r.height), dragging ? Color.yellow : new Color(0.4f, 0.8f, 1f, 0.9f));
                Fill(r, new Color(0.4f, 0.8f, 1f, dragging ? 0.25f : 0.12f));
                if (e.type == EventType.MouseDown && r.Contains(e.mousePosition))
                {
                    if (e.clickCount >= 2) { HudLayout.Reset(id); SaveHud(); }
                    else { hudDrag = id; hudDragStart = e.mousePosition; }
                    e.Use();
                }
            }
            if (hudDrag != null && e.type == EventType.MouseDrag)
            {
                var d = e.mousePosition - hudDragStart;
                if (d.magnitude >= HudLayout.DragMin || HudLayout.Moved(hudDrag))
                {
                    var def = defaults[hudDrag];
                    HudLayout.Drag(hudDrag, def.x, def.y, def.width, def.height, w, h, d.x, d.y);
                    hudDragStart = e.mousePosition;
                }
                e.Use();
            }
            if (hudDrag != null && e.type == EventType.MouseUp) { hudDrag = null; SaveHud(); e.Use(); }
        }

        public void SaveHud()
        {
            string key = HudLayout.Key(world?.Player?.Name);
            if (key == null) return;
            PlayerPrefs.SetString(key, HudLayout.ToJson());
            PlayerPrefs.Save();
        }

        /// <summary>The options page's "put every piece back".</summary>
        public void ResetHud() { HudLayout.ResetAll(); SaveHud(); }

        // ------------------------------------------------------------------------------------------------ saved window layout and fade
        void VisualLayoutUpdate()
        {
            using var _slow = SlowCalls.Scope("VisualLayoutUpdate", "Update");
            string name = world?.Player?.Name;
            if (name == null) return;
            if (layoutFor != name)
            {
                layoutFor = name;
                layout = WindowLayout.From(PlayerPrefs.GetString(WindowLayout.Key(name), ""));
                if (VisualPrefs.LayoutOn)
                    foreach (var win in windows)
                        if (layout.TryGet(win.GetType().Name, out var slot) && slot.Open && System.Array.IndexOf(LayoutOpenWindows, win.GetType().Name) >= 0) win.Open = true;
                GameWindow.Placed = RestoreWindowPlace;
            }
            if (!VisualPrefs.LayoutOn) return;
            foreach (var win in windows)
                if (win.Area.width > 0)
                {
                    layout.Note(win.GetType().Name, win.Area.x, win.Area.y, win.Open);
                    layout.NoteSize(win.GetType().Name, win.Resizable && win.UserSized ? win.Area.width : 0f, win.Resizable && win.UserSized ? win.Area.height : 0f);   // phase 9, track E: the size a player gave
                }
            if (layout.Dirty && !Input.GetMouseButton(0) && Time.unscaledTime - layoutSaved > 1f)
            {
                layoutSaved = Time.unscaledTime;
                PlayerPrefs.SetString(WindowLayout.Key(name), layout.ToJson());
            }
        }

        /// <summary>Called when a window is placed for the first time: the saved spot of this character wins over the default.</summary>
        void RestoreWindowPlace(GameWindow win)
        {
            if (!VisualPrefs.LayoutOn || !layout.TryGet(win.GetType().Name, out var slot)) return;
            win.Area.x = slot.X; win.Area.y = slot.Y;
            if (win.Resizable && slot.W > 0 && slot.H > 0)
            {
                float w = slot.W, h = slot.H;
                WindowSize.Clamp(ref w, ref h, UnityEngine.Screen.width / UiScale(UnityEngine.Screen.width, UnityEngine.Screen.height, UnityEngine.Screen.dpi), UnityEngine.Screen.height / UiScale(UnityEngine.Screen.width, UnityEngine.Screen.height, UnityEngine.Screen.dpi));
                win.Area.width = w; win.Area.height = h; win.UserSized = true;
            }
        }

        /// <summary>The fade bookkeeping of one window: false when it is closed and its fade is over. Sets the window's alpha.</summary>
        bool WindowShown(GameWindow win)
        {
            if (!VisualPrefs.UiFadeOn || !UiFade.Eligible(true, win.Area.width, win.Area.height)) { win.Alpha = 1f; fadeWasOpen[win] = win.Open; return win.Open; }
            if (!fades.TryGetValue(win, out var f)) { fades[win] = f = new UiFade(); f.Snap(win.Open); fadeWasOpen[win] = win.Open; }
            double now = Time.unscaledTimeAsDouble * 1000.0;
            if (fadeWasOpen[win] != win.Open) { fadeWasOpen[win] = win.Open; f.Begin(win.Open, now); }
            f.Step(now);
            win.Alpha = f.Value;
            return win.Open || f.Running || f.Value > 0.001f;
        }
    }
}
