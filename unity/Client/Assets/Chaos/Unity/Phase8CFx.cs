// Phase 8, track C: the glue between the shader numbers of Core/Phase8CFx.cs and Unity. FxShaders finds the shaders in Assets/Chaos/Resources/Shaders (null when
// a shader is missing or the card cannot run it: every caller then keeps the drawing it had), MapFxLook is what a creature asks of the map shader,
// Phase8CPrefs holds the three options of game_visualfx that the shaders draw, MapGradePost is the colour grade and soft glow of the classic view's camera.
// The shaders are compiled by the CI Unity build only; Client.Check cannot see them.
using System;
using UnityEngine;
using Chaos.Core;

namespace Chaos.Client
{
    /// <summary>Where the track's shaders come from. Each is looked up once; the environment variable CHAOS_NO_FX_SHADERS turns all of them off (the fallback paths then draw).</summary>
    public static class FxShaders
    {
        public const string MapName = "Chaos/MapFx", GradeName = "Chaos/MapGrade";
        static Shader map, grade;
        static bool mapDone, gradeDone;

        static Shader Load(string asset, string name)
        {
            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("CHAOS_NO_FX_SHADERS"))) return null;
            using var _slow = SlowCalls.Scope("FxShaders.Load " + asset, "load");
            Shader s = null;
            try { s = Resources.Load<Shader>("Shaders/" + asset); } catch (Exception) { s = null; }
            if (s == null) s = Shader.Find(name);
            return s != null && s.isSupported ? s : null;
        }

        /// <summary>The classic map's sprite shader (outfit shaders, flashes, outlines, living ground), null when unavailable.</summary>
        public static Shader Map { get { if (!mapDone) { mapDone = true; map = Load("ChaosMapFx", MapName); } return map; } }
        /// <summary>The colour grade and soft glow image effect, null when unavailable.</summary>
        public static Shader Grade { get { if (!gradeDone) { gradeDone = true; grade = Load("ChaosGrade", GradeName); } return grade; } }
    }

    /// <summary>What one creature asks of the map shaders this frame: an outfit shader or a hit flash (Mode, Strength, Tint) and an outline. Null means plain.</summary>
    public sealed class MapFxLook
    {
        public int Mode;
        public float Strength = 1f;
        public Color32 Tint = new Color32(255, 255, 255, 255);
        public OutlineSpec Outline;
        public float OutlineAlpha = 1f;
        public bool Plain => Mode == FxMode.None && Outline == null;
    }

    /// <summary>The options of the drawn effects: the grade and vignette, the soft glow, the living water and lava, the outfit shaders on creatures.
    /// PlayerPrefs, the names of the main client's options (screenGrade, softGlow, liquids); the glow is off by default as there.</summary>
    public static class Phase8CPrefs
    {
        public static bool Grade = true, Bloom, Liquid = true, OutfitShaders = true;
        static bool loaded;

        public static void Load()
        {
            if (loaded) return;
            loaded = true;
            Grade = PlayerPrefs.GetInt(MapGradeFx.GradePref, 1) == 1;
            Bloom = PlayerPrefs.GetInt(MapGradeFx.BloomPref, 0) == 1;
            Liquid = PlayerPrefs.GetInt(MapGradeFx.LiquidPref, 1) == 1;
            OutfitShaders = PlayerPrefs.GetInt("chaos.fx.outfits", 1) == 1;
        }

        public static void Save()
        {
            PlayerPrefs.SetInt(MapGradeFx.GradePref, Grade ? 1 : 0);
            PlayerPrefs.SetInt(MapGradeFx.BloomPref, Bloom ? 1 : 0);
            PlayerPrefs.SetInt(MapGradeFx.LiquidPref, Liquid ? 1 : 0);
            PlayerPrefs.SetInt("chaos.fx.outfits", OutfitShaders ? 1 : 0);
            PlayerPrefs.Save();
        }
    }

    /// <summary>The map's colour grade, vignette and soft glow as an image effect on the classic view's camera (Resources/Shaders/ChaosGrade.shader). Off in HD-2D and the live view,
    /// which grade the picture in Hd2dPost. The area mood arrives in Mood (r, g, b, sat, con of WeatherState.Grade).</summary>
    public sealed class MapGradePost : MonoBehaviour
    {
        public bool Grade, Bloom;
        public float[] Mood = new float[5];
        Material mat;
        public bool Ready => mat != null;

        void Awake()
        {
            var sh = FxShaders.Grade;
            if (sh != null) mat = new Material(sh) { name = "chaos-map-grade", hideFlags = HideFlags.HideAndDontSave };
        }

        void OnDestroy() { if (mat != null) Destroy(mat); }

        void OnRenderImage(RenderTexture src, RenderTexture dst)
        {
            using var _slow = SlowCalls.Scope("MapGradePost.OnRenderImage", "render");   // the first draw with the grade shader compiles it
            float strength = MapGradeFx.Bloom(Bloom);
            if (mat == null || (!Grade && strength <= 0f)) { Graphics.Blit(src, dst); return; }
            var m = MapGradeFx.Clamp(new[] { (double)Mood[0], Mood[1], Mood[2], Mood[3], Mood[4] });
            mat.SetVector("_Mood", new Vector4(m[0], m[1], m[2], m[3]));
            mat.SetVector("_Mood2", new Vector4(m[4], 0f, 0f, 0f));
            mat.SetVector("_Params", new Vector4(Grade ? 1f : 0f, strength, MapGradeFx.BloomThreshold, MapGradeFx.BloomFull));
            RenderTexture a = null, b = null;
            if (strength > 0f)
            {
                int w = Mathf.Max(8, src.width / 4), h = Mathf.Max(8, src.height / 4);
                a = RenderTexture.GetTemporary(w, h, 0, src.format);
                b = RenderTexture.GetTemporary(w, h, 0, src.format);
                a.filterMode = b.filterMode = FilterMode.Bilinear;
                Graphics.Blit(src, a, mat, 0);
                mat.SetVector("_Dir", new Vector4(1f / w, 0f, 0f, 0f));
                Graphics.Blit(a, b, mat, 1);
                mat.SetVector("_Dir", new Vector4(0f, 1f / h, 0f, 0f));
                Graphics.Blit(b, a, mat, 1);
                mat.SetTexture("_GlowTex", a);
            }
            Graphics.Blit(src, dst, mat, 2);
            if (a != null) RenderTexture.ReleaseTemporary(a);
            if (b != null) RenderTexture.ReleaseTemporary(b);
        }
    }
}
