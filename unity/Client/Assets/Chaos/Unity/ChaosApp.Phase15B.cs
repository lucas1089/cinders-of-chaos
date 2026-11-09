// Phase 15, track B: additive drawing in the classic view (game_visualfx). The immediate-mode GUI has no additive blend, so during a repaint the glowing spell effects and
// the spell light go through Graphics.DrawTexture with the Chaos/Add material (Resources/Shaders/ChaosAdd.shader, blend SrcAlpha One). Graphics.DrawTexture ignores the GUI
// clip, so every quad is cut to the map rect first (AddFx.Clip). Without the shader the older drawing stays (normal blend, faint tint). Rules: Core/Phase15B.cs.
using System;
using UnityEngine;
using Chaos.Core;

namespace Chaos.Client
{
    public sealed partial class ChaosApp
    {
        Material addMat;
        bool addMatDone;

        /// <summary>The additive material, null when the shader is missing, the card cannot run it or CHAOS_NO_FX_SHADERS is set.</summary>
        Material AddMat
        {
            get
            {
                if (addMatDone) return addMat;
                addMatDone = true;
                using var _slow = SlowCalls.Scope("AddMat (Chaos/Add shader load)", "load");
                if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("CHAOS_NO_FX_SHADERS"))) return null;
                Shader s = null;
                try { s = Resources.Load<Shader>("Shaders/ChaosAdd"); } catch (Exception) { s = null; }
                if (s == null) s = Shader.Find("Chaos/Add");
                if (s != null && s.isSupported) addMat = new Material(s) { hideFlags = HideFlags.HideAndDontSave };
                return addMat;
            }
        }

        /// <summary>True when an additive quad can be drawn now: the material is there and this is a repaint.</summary>
        bool AddOn => Event.current != null && Event.current.type == EventType.Repaint && AddMat != null;

        /// <summary>One textured quad added onto the picture, cut to the clip rect (the map). uv: the part of the texture, v up like GUI.DrawTextureWithTexCoords.</summary>
        void AddQuad(Rect dst, Texture tex, Rect uv, Color col, Rect clip)
        {
            using var _slow = SlowCalls.Scope("AddQuad", "OnGUI");
            if (tex == null || !AddOn) return;
            if (!AddFx.Clip(dst.x, dst.y, dst.width, dst.height, uv.x, uv.y, uv.width, uv.height, clip.x, clip.y, clip.width, clip.height,
                    out float x, out float y, out float w, out float h, out float u, out float v, out float uw, out float vh)) return;
            Graphics.DrawTexture(new Rect(x, y, w, h), tex, new Rect(u, v, uw, vh), 0, 0, 0, 0, col, AddMat);
        }

        /// <summary>The spell light added to the map: the soft disc in the colour of the theme, so a dark area brightens round a spell. False when the additive path is not
        /// available (the caller lays the faint tint).</summary>
        bool DrawSpellLightAdd(VisualEffects v, Rect map, float scale, double now)
        {
            using var _slow = SlowCalls.Scope("DrawSpellLightAdd", "OnGUI");
            if (!AddOn || texSoft == null) return false;
            int floor = world.Center.Z;
            foreach (var kv in v.SpellLights.Now(now))
            {
                var l = kv.Key;
                if (l.Pos.Z != floor || !TileGeom(l.Pos, map, scale, out Vector2 at, out float tile)) continue;
                float f = kv.Value;
                float size = tile * AddFx.LightTiles(f);
                AddQuad(Around(at, size, size), texSoft, new Rect(0f, 0f, 1f, 1f), new Color(l.R, l.G, l.B, AddFx.LightAlpha(f)), map);
            }
            return true;
        }
    }
}
