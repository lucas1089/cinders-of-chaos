// Phase 9, track D: the glue of the visual outline and shader rows (game_itemrarity, game_visualfx, game_cosmeticfx). Rules: Core/Phase9D.cs; shaders: Resources/Shaders/ChaosFx.cginc.
//   rarity outline and Divine metal   drawn by the views themselves (MapView.DrawItem, Hd2dView.AddItem, FrontLiveView.AddItem); this file hands them the option and tells
//                                     DrawItemRings (the ground ring) to stand down when the shader draws the real outline
//   hover outline                     the creature under the mouse gets a faint white silhouette (option hoverOutline, off by default)
//   spell light                       a light round a spell effect for 320 ms: a Unity point light in HD-2D, a frame light of the live view, a soft coloured disc in the classic view
//   spell effects from the art        the classic view draws the magic effects of the client pair frame by frame (DrawPackEffect); the live view keeps FrontLiveFx
// Every path checks its shader or art and keeps the older drawing when it is missing.
using System.Collections.Generic;
using Chaos.Core;
using UnityEngine;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        uint hoverCreature;
        readonly List<Hd2dLight> spellHd = new List<Hd2dLight>();
        readonly List<SpellFxMark> spellFxTmp = new List<SpellFxMark>();

        /// <summary>The live view's creature sprite shader draws the flash and the outline (FrontArtSprite.shader): the soft disc and the glow picture stand down.</summary>
        bool LiveFxOn
        {
            get
            {
                if (!LiveOn) return false;
                var fc = frontLive.GetComponent<FrontLiveCreatures>();
                return fc != null && fc.FxShaderOk;
            }
        }

        /// <summary>The scene views' sprite shader draws the rarity outline of items: the ground ring is not needed.</summary>
        bool ItemGlowRealOn => LiveOn ? frontLive.ItemGlowReal : hd2d && hd2dView != null && hd2dView.ItemGlowReal;

        /// <summary>Called every frame from Phase8CUpdate while a world is shown.</summary>
        void Phase9DUpdate()
        {
            bool items = VisualPrefs.ItemOutlines;
            if (hd2dView != null) { hd2dView.ItemOutlines = items; hd2dView.SpellLights = SpellLightsHd; }
            if (frontLive != null) { frontLive.ItemOutlines = items; frontLive.FrameLights = SpellLightsLive; }
            hoverCreature = VisualPrefs.Fx.HoverOutline ? HoverCreatureId() : 0;
        }

        // ------------------------------------------------------------------------------------------------ hover
        /// <summary>The creature under the pointer (not the player), 0 for none: the sprite box in the scene views, the tile in the classic view.</summary>
        uint HoverCreatureId()
        {
            if (cam == null || world == null || !PointerOnMap) return 0;
            uint me = world.PlayerId;
            Vector2 m = Input.mousePosition;
            if (HdLabelsOn)
            {
                float best = float.MaxValue;
                uint hit = 0;
                foreach (var l in HdLabels)
                {
                    Vector3 a = cam.WorldToScreenPoint(l.BottomLeft), b = cam.WorldToScreenPoint(l.TopRight);
                    var r = Rect.MinMaxRect(Mathf.Min(a.x, b.x), Mathf.Min(a.y, b.y), Mathf.Max(a.x, b.x), Mathf.Max(a.y, b.y));
                    if (l.C.Id != me && r.Contains(m) && a.z < best) { best = a.z; hit = l.C.Id; }
                }
                return hit;
            }
            if (view == null) return 0;
            Vector3 wp = cam.ScreenToWorldPoint(new Vector3(m.x, m.y, 10f));
            uint found = 0;
            foreach (var (c, at) in view.Labels)
                if (c.Id != me && wp.x >= at.x && wp.x < at.x + 1f && wp.y <= at.y && wp.y > at.y - 1f) found = c.Id;
            return found;
        }

        // ------------------------------------------------------------------------------------------------ spell light
        /// <summary>HD-2D: the spell lights as scene lights over the tile (positions relative to the origin tile, like the rest of the layout).</summary>
        List<Hd2dLight> SpellLightsHd(Pos origin)
        {
            spellHd.Clear();
            var v = Vis;
            if (v == null || world == null || session == null || !VisualPrefs.Fx.SpellLight) return spellHd;
            int floor = world.Center.Z;
            foreach (var kv in v.SpellLights.Now(session.Now))
            {
                var l = kv.Key;
                if (l.Pos.Z != floor) continue;
                float f = kv.Value;
                float radius = SpellLightFx.RadiusAt(SpellLightFx.Radius, f);
                spellHd.Add(new Hd2dLight { Position = new Vec3(Hd2d.WorldX(origin, l.Pos.X), 0.8f, Hd2d.WorldZ(origin, l.Pos.Y)), R = l.R, G = l.G, B = l.B, Range = radius * 1.2f, Intensity = 1.1f * f });
                if (spellHd.Count >= 4) break;
            }
            return spellHd;
        }

        /// <summary>The live view: the spell lights as frame lights, picked before the nearest layout lights.</summary>
        void SpellLightsLive(List<FaLight> into)
        {
            var v = Vis;
            if (v == null || world == null || session == null || frontLive == null || !VisualPrefs.Fx.SpellLight) return;
            int floor = world.Center.Z, n = 0;
            foreach (var kv in v.SpellLights.Now(session.Now))
            {
                var l = kv.Key;
                if (l.Pos.Z != floor) continue;
                float f = kv.Value;
                float radius = SpellLightFx.RadiusAt(SpellLightFx.Radius, f);
                var w = frontLive.TileToWorld(l.Pos.X, l.Pos.Y, l.Pos.Z);
                into.Add(new FaLight { X = w.x, Y = w.y + 0.9f, Z = w.z, R = l.R, G = l.G, B = l.B, Range = radius * 1.2f + 1f, Intensity = 1.1f * f, Flame = false, Seed = l.Effect });
                if (++n >= 4) break;
            }
        }

        // ------------------------------------------------------------------------------------------------ classic view
        /// <summary>Called inside the map group after the other overlays: the spell effects of the art file, then the spell light over them. Classic view only.</summary>
        void DrawPhase9D(VisualEffects v, Rect map, float scale, double now)
        {
            if (!ClassicView) return;
            DrawSpellFx(v, map, scale, now);
            if (!VisualPrefs.Fx.SpellLight || !DrawSpellLightAdd(v, map, scale, now)) DrawSpellLightDiscs(v, map, scale, now);   // phase 15 track B: light added to the map, the faint tint when the additive shader is missing
        }

        /// <summary>The magic effects of the client pair, frame by frame at their tile (the classic view drew none from the art file before). An effect the pair does not have is
        /// forgotten. The glowing themes (AddFx.Glows, option spellLight) are drawn added (phase 15 track B, ChaosApp.Phase15B.cs), the others and every effect without the
        /// additive shader with the normal blend.</summary>
        void DrawSpellFx(VisualEffects v, Rect map, float scale, double now)
        {
            float a = VisualRuntime.EffectAlpha;
            if (a <= 0.01f || v.SpellFx.Marks.Count == 0 || world?.Dat == null) return;
            int floor = world.Center.Z;
            bool glowOn = VisualPrefs.Fx.SpellLight && AddOn;
            spellFxTmp.Clear();
            spellFxTmp.AddRange(v.SpellFx.Marks);
            foreach (var m in spellFxTmp)
            {
                var t = world.Dat.Effect(m.Id);
                if (t == null || t.Groups == null || t.Groups.Length == 0) { v.SpellFx.NoArt(m.Id); continue; }
                double el = now - m.Born;
                if (el > PackFx.Length(t.Idle) + 50) { v.SpellFx.Remove(m); continue; }
                if (m.Pos.Z != floor) continue;
                DrawPackEffect(m.Id, m.Pos, el, false, map, scale, a, glowOn && AddFx.Glows(m.Id));
            }
        }

        /// <summary>A soft coloured disc round the tile of a spell effect for 320 ms. The main client adds light to its dark map; the immediate-mode GUI can only lay a faint
        /// tint over it, so the disc is kept low.</summary>
        void DrawSpellLightDiscs(VisualEffects v, Rect map, float scale, double now)
        {
            if (!VisualPrefs.Fx.SpellLight || texSoft == null) return;
            int floor = world.Center.Z;
            foreach (var kv in v.SpellLights.Now(now))
            {
                var l = kv.Key;
                if (l.Pos.Z != floor || !TileGeom(l.Pos, map, scale, out Vector2 at, out float tile)) continue;
                float f = kv.Value;
                float size = tile * 2f * SpellLightFx.RadiusAt(SpellLightFx.Radius, f);
                Pic(texSoft, Around(at, size, size), new Color(l.R, l.G, l.B, 0.32f * f));
            }
        }
    }
}
