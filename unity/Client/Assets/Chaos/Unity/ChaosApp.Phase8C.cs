// Phase 8, track C: the shader side of the visual effect rows (game_chaosshaders, game_nameshaders, game_levelwings, game_lootbeams, game_cosmeticfx, game_visualfx).
//   outfit shaders, hit flash, outlines   what a creature asks of the map shaders (MapFxLook): the classic mesh (Chaos/MapFx), the HD-2D batches (Hd2dSprite.shader) and the live view's
//                                         creature materials (FrontArtSprite.shader). Flash and outline are shader work in the classic and HD-2D views; the live view keeps the soft disc.
//   grade, vignette, soft glow            MapGradePost on the classic camera (Chaos/MapGrade), the area mood of the weather state goes in as its tint
//   water and lava                        MapView / Hd2dView LiquidFx (the ground quads of the liquid ids)
//   level-up effect and loot beams        the pack effects of the client pair (pair 36) drawn from the dat frame by frame (PackFx); a pair without them keeps the drawn stand-ins
//   cooldown pulse                        a pale flash on a hotkey slot when a cooldown of 3 s or more ends
// Every path checks that its shader was found (FxShaders) and falls back to the drawing it had. Numbers: Core/Phase8CFx.cs.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        MapGradePost gradePost;
        readonly CooldownPulseFx hotPulse = new CooldownPulseFx();
        readonly int[] hotPeak = new int[24];
        readonly Dictionary<string, MapFxLook> outfitLooks = new Dictionary<string, MapFxLook>();
        readonly Dictionary<LevelWingsState.Play, Pos> wingsAt = new Dictionary<LevelWingsState.Play, Pos>();

        /// <summary>The classic flat view is on screen (neither HD-2D nor the live view).</summary>
        bool ClassicView => screen == Screen.Game && !hd2d && !LiveOn;
        /// <summary>The classic mesh draws with the Chaos/MapFx shader: flashes and outlines are shader work there.</summary>
        bool ShaderMapOn => ClassicView && view != null && view.FxOn;
        /// <summary>The grade image effect is drawing, so the weather's flat mood tint stays off (it would grade twice).</summary>
        bool GradePostActive => gradePost != null && gradePost.enabled && gradePost.Ready && Phase8CPrefs.Grade;

        // ------------------------------------------------------------------------------------------------ every frame
        /// <summary>Called from VisualUpdate: hands the views their effect callbacks and keeps the grade post on the right camera.</summary>
        void Phase8CUpdate()
        {
            Phase8CPrefs.Load();
            if (screen != Screen.Game || session == null) { if (gradePost != null) gradePost.enabled = false; return; }
            if (view != null) { view.CreatureFx = c => Phase8CLook(c, true, true); view.LiquidFx = Phase8CPrefs.Liquid; }
            if (hd2dView != null) { hd2dView.CreatureFx = c => Phase8CLook(c, true, true); hd2dView.LiquidFx = Phase8CPrefs.Liquid; }
            if (frontLive != null)
            {
                var fc = frontLive.GetComponent<FrontLiveCreatures>();
                if (fc != null) { bool ok = fc.FxShaderOk; fc.CreatureFx = c => Phase8CLook(c, ok, ok); }   // phase 9 track D: flash and outlines in the live view when its sprite shader is there
            }
            Phase9DUpdate();   // ChaosApp.Phase9D.cs: item outline option, hover, spell lights
            bool want = ClassicView && cam != null && FxShaders.Grade != null && (Phase8CPrefs.Grade || Phase8CPrefs.Bloom);
            if (want && gradePost == null) gradePost = cam.GetComponent<MapGradePost>() ?? cam.gameObject.AddComponent<MapGradePost>();
            if (gradePost != null)
            {
                gradePost.enabled = want;
                gradePost.Grade = Phase8CPrefs.Grade;
                gradePost.Bloom = Phase8CPrefs.Bloom;
                var mood = Utils != null && Phase7Prefs.WeatherOn ? Utils.Weather.Grade : null;
                for (int i = 0; i < 5; i++) gradePost.Mood[i] = mood != null ? (float)mood[i] : 0f;
            }
        }

        /// <summary>What a creature asks of the map shaders now: a hit flash first, else its outfit shader; an outline besides (target, follow or a bought one). Null: plain.
        /// flash and outline are off for the live view (it keeps the soft disc and the glow picture).</summary>
        MapFxLook Phase8CLook(Creature c, bool flash, bool outline)
        {
            var v = Vis;
            if (v == null || c == null || session == null) return null;
            double now = session.Now;
            MapFxLook look = null;
            if (flash && VisualPrefs.Fx.HitFlash)
            {
                foreach (var f in v.Flashes)
                {
                    if (f.Creature != c.Id) continue;
                    float k = HitFlasher.Strength(now, f.Start, f.Ms);
                    if (k > 0) { look = new MapFxLook { Mode = HitFlashFx.ModeOf(f.Red), Strength = k }; break; }
                }
            }
            OutlineSpec ol = null;
            if (outline)
            {
                OutlineSpec bought = null;
                bool mine = c.Id == world.PlayerId;
                if (c.Type == 0 && v.Cosmetic.Looks.TryGetValue(c.Name, out var cl) && cl.Glow != null && v.Cosmetic.Allowed(false, mine))
                    bought = OutlineFx.Cosmetic(cl.Glow, cl.Pulse);
                ol = OutlineRules.Of(c.Id, world.PlayerId, session.AttackTarget, session.Parser.FollowTarget, hoverCreature, VisualPrefs.Fx.TargetOutline, VisualPrefs.Fx.HoverOutline, bought);
            }
            if (look == null && Phase8CPrefs.OutfitShaders)
            {
                string name = c.Outfit.Shader;
                var fx = OutfitFxTable.For(name);
                if (fx != null)
                {
                    if (!outfitLooks.TryGetValue(name, out look))
                        outfitLooks[name] = look = new MapFxLook { Mode = fx.Mode, Tint = new Color(fx.R, fx.G, fx.B, 1f) };
                    if (ol != null) look = new MapFxLook { Mode = look.Mode, Tint = look.Tint };   // a copy, the cached one stays shared
                }
            }
            if (ol != null)
            {
                if (look == null) look = new MapFxLook();
                look.Outline = ol;
                look.OutlineAlpha = OutlineFx.PulseAlpha(now, ol.PulseMs);
            }
            return look;
        }

        // ------------------------------------------------------------------------------------------------ pack effects of the pair
        /// <summary>Draws an effect of the client pair on a tile frame by frame (the art's bottom-right cell is the tile). Returns false when the pair has no such effect
        /// (the caller then draws its stand-in), true when it handled it, a finished play included. frame: the dat frame, -1 for none.</summary>
        bool DrawPackEffect(int effectId, Pos tile, double elapsed, bool loop, Rect map, float scale, float alpha)
        {
            var t = world?.Dat?.Effect(effectId);
            if (t == null || atlas == null || t.Groups == null || t.Groups.Length == 0) return false;
            var g = t.Idle;
            int frame = loop ? PackFx.LoopPhase(g, elapsed) : PackFx.Phase(g, elapsed);
            if (frame < 0) return true;
            if (!TileGeom(tile, map, scale, out Vector2 at, out float size)) return true;
            int px = Mod8(tile.X, g.PatternX), py = Mod8(tile.Y, g.PatternY), pz = Mod8(tile.Z, g.PatternZ);
            var old = GUI.color;
            GUI.color = new Color(1f, 1f, 1f, Mathf.Clamp01(alpha));
            for (int layer = 0; layer < g.Layers; layer++)
                for (int hh = 0; hh < g.Height; hh++)
                    for (int ww = 0; ww < g.Width; ww++)
                    {
                        int slot = atlas.Sprite(g.Sprite(ww, hh, layer, px, py, pz, frame));
                        if (slot == 0) continue;
                        atlas.Upload();
                        var uv = atlas.Uv(slot);
                        var dst = new Rect(at.x - size * (0.5f + ww), at.y - size * (0.5f + hh), size, size);
                        GUI.DrawTextureWithTexCoords(dst, atlas.Texture, uv);
                    }
            GUI.color = old;
            return true;
        }

        static int Mod8(int a, int n) { if (n <= 1) return 0; int m = a % n; return m < 0 ? m + n : m; }

        /// <summary>The level-up effect of the pair on the tile the main client adds it to (the creature's tile and one south-east of it, where it stood when the message came).</summary>
        bool DrawWingsPack(LevelWingsState.Play p, Creature c, Rect map, float scale, double now, float fxA)
        {
            if (world?.Dat?.Effect(PackFx.LevelUpId) == null) return false;
            if (!wingsAt.TryGetValue(p, out Pos at))
            {
                at = c.Position;
                wingsAt[p] = at;
                if (wingsAt.Count > 32) wingsAt.Clear();
            }
            return DrawPackEffect(PackFx.LevelUpId, new Pos(at.X + PackFx.LevelUpDx, at.Y + PackFx.LevelUpDy, at.Z), now - p.Start, false, map, scale, fxA);
        }

        /// <summary>A loot beam as the pair's beam effect of its group, looping every 1.75 s. False: the pair has none and the drawn beam stands.</summary>
        bool DrawBeamPack(Pos tile, BeamLook look, Rect map, float scale, double now)
        {
            int id = PackFx.BeamId(look.Group);
            if (id == 0) return false;
            return DrawPackEffect(id, tile, now, true, map, scale, look.Intensity);
        }

        // ------------------------------------------------------------------------------------------------ cooldown pulse
        /// <summary>Called by a hotkey slot with its cooldown seconds: a cooldown of 3 s or more that ends flashes the slot pale for 280 ms.</summary>
        public void Phase8CCooldown(int slot, int seconds, Rect r)
        {
            if (slot < 0 || slot >= hotPeak.Length) return;
            double now = Time.unscaledTimeAsDouble * 1000.0;
            string key = "hk" + slot;
            if (seconds > 0) hotPeak[slot] = Mathf.Max(hotPeak[slot], seconds);
            else
            {
                if (hotPeak[slot] > 0 && CooldownPulseFx.ShouldPulse(hotPeak[slot] * 1000.0, hotPeak[slot] * 1000.0)) hotPulse.Start(key, now);
                hotPeak[slot] = 0;
            }
            float a = hotPulse.Now(key, now);
            if (a > 0.001f) Fill(r, new Color(1f, 1f, 1f, a));
        }
    }
}
