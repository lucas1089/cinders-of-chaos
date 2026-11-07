// HD-2D look (O432): bloom on bright pixels, tilt-shift depth of field (sharp middle band, blurred top and bottom),
// distance fog, a slight vignette and warm grading, on one camera.
//
// PIPELINE: the built-in render pipeline with our own image effect (OnRenderImage on Hd2dEffect), shaders in
// Assets/Chaos/Shaders. Why not URP: the URP and Post Processing assemblies are not on NuGet, so unity/Client.Check
// (no Unity license, reference assemblies only) could not compile code that uses them, and the URP asset would have to
// be made by an editor script that no CI run can check. This path compiles in Client.Check and needs no new package.
// DoF is by screen Y (no depth texture), which is what the tilt-shift look is.
//
// Use: Hd2dPost.Attach(cam, lowQuality) once the 3D scene exists, Detach(cam) to go back.
// Sprites and billboards: Hd2dPost.SpriteMaterial(atlas) (lit, cutout, casts shadows).
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Chaos.Client
{
    public static class Hd2dPost
    {
        public const string PostShaderName = "Hidden/Chaos/Hd2dPost";
        public const string SpriteShaderName = "Chaos/Hd2dSprite";

        sealed class Saved
        {
            public bool fog, hdr, msaaAllowed;
            public Color fogColor, ambient;
            public FogMode fogMode;
            public float fogDensity;
            public AmbientMode ambientMode;
            public ShadowQuality shadows;
            public CameraClearFlags clear;
            public Color background;
        }
        static readonly Dictionary<Camera, Saved> saved = new Dictionary<Camera, Saved>();

        /// <summary>Turns the HD-2D look on for this camera. lowQuality (phones): bloom and fog stay, depth of field and soft shadows go.</summary>
        public static void Attach(Camera cam, bool lowQuality)
        {
            if (cam == null) return;
            if (!saved.ContainsKey(cam))
            {
                saved[cam] = new Saved
                {
                    fog = RenderSettings.fog, fogColor = RenderSettings.fogColor, fogMode = RenderSettings.fogMode,
                    fogDensity = RenderSettings.fogDensity, ambient = RenderSettings.ambientLight,
                    ambientMode = RenderSettings.ambientMode, shadows = QualitySettings.shadows,
                    hdr = cam.allowHDR, msaaAllowed = cam.allowMSAA, clear = cam.clearFlags, background = cam.backgroundColor,
                };
            }
            var fogColor = new Color(0.10f, 0.08f, 0.12f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Exponential;
            RenderSettings.fogDensity = lowQuality ? 0.025f : 0.016f;
            RenderSettings.fogColor = fogColor;
            RenderSettings.ambientMode = AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.34f, 0.30f, 0.32f);
            QualitySettings.shadows = lowQuality ? ShadowQuality.HardOnly : ShadowQuality.All;
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = fogColor;
            cam.allowHDR = !lowQuality;
            cam.allowMSAA = false;   // the effect reads the finished image; sprites are point filtered anyway

            var fx = cam.GetComponent<Hd2dEffect>();
            if (fx == null) fx = cam.gameObject.AddComponent<Hd2dEffect>();
            fx.dof = !lowQuality;
            fx.enabled = true;
        }

        /// <summary>Takes the effect off and puts the camera and RenderSettings back as they were.</summary>
        public static void Detach(Camera cam)
        {
            if (cam == null) return;
            var fx = cam.GetComponent<Hd2dEffect>();
            if (fx != null) Object.Destroy(fx);
            if (!saved.TryGetValue(cam, out var s)) return;
            RenderSettings.fog = s.fog; RenderSettings.fogColor = s.fogColor; RenderSettings.fogMode = s.fogMode;
            RenderSettings.fogDensity = s.fogDensity; RenderSettings.ambientMode = s.ambientMode;
            RenderSettings.ambientLight = s.ambient;
            QualitySettings.shadows = s.shadows;
            cam.allowHDR = s.hdr; cam.allowMSAA = s.msaaAllowed; cam.clearFlags = s.clear; cam.backgroundColor = s.background;
            saved.Remove(cam);
        }

        /// <summary>Lit alpha-cutout material for sprite billboards: point filtering, sampled at mip 0, casts and receives shadows.</summary>
        public static Material SpriteMaterial(Texture atlas)
        {
            var sh = Shader.Find(SpriteShaderName);
            if (sh == null) { Debug.LogWarning("hd2d: shader " + SpriteShaderName + " missing, using a fallback"); sh = Shader.Find("Unlit/Transparent Cutout"); }
            var m = new Material(sh) { name = "Hd2dSprite" };
            if (atlas != null)
            {
                atlas.filterMode = FilterMode.Point;
                atlas.anisoLevel = 0;
                atlas.wrapMode = TextureWrapMode.Clamp;
                m.mainTexture = atlas;
            }
            m.SetFloat("_Cutoff", 0.5f);
            return m;
        }
    }

    /// <summary>The image effect itself: added to the camera by Hd2dPost.Attach.</summary>
    [RequireComponent(typeof(Camera))]
    public sealed class Hd2dEffect : MonoBehaviour
    {
        public bool dof = true;
        public float bloomThreshold = 0.8f, bloomKnee = 0.5f, bloomIntensity = 0.95f;
        public float focusHalf = 0.14f, focusFeather = 0.22f;   // sharp band is the middle 28% of the screen height (tilt-shift)
        public float vignette = 0.35f, saturation = 1.08f, contrast = 1.05f;
        public Color tint = new Color(1.06f, 0.98f, 0.86f);      // warm
        Material mat;

        void OnEnable()
        {
            var sh = Shader.Find(Hd2dPost.PostShaderName);
            if (sh == null || !sh.isSupported) { Debug.LogWarning("hd2d: post shader missing or unsupported"); enabled = false; return; }
            mat = new Material(sh) { hideFlags = HideFlags.HideAndDontSave };
        }

        void OnDisable() { if (mat != null) Destroy(mat); mat = null; }

        void OnRenderImage(RenderTexture src, RenderTexture dst)
        {
            if (mat == null) { Graphics.Blit(src, dst); return; }
            int w = Mathf.Max(2, src.width / 2), h = Mathf.Max(2, src.height / 2);
            var fmt = src.format;
            RenderTexture half = null, halfB = null, q1 = null, q2 = null;
            try
            {
                // bloom: bright pass to half size, blur at quarter size
                half = RenderTexture.GetTemporary(w, h, 0, fmt);
                mat.SetFloat("_Threshold", bloomThreshold);
                mat.SetFloat("_Knee", bloomKnee);
                Graphics.Blit(src, half, mat, 0);
                q1 = RenderTexture.GetTemporary(w / 2, h / 2, 0, fmt);
                q2 = RenderTexture.GetTemporary(w / 2, h / 2, 0, fmt);
                Graphics.Blit(half, q1);
                for (int i = 0; i < 2; i++)
                {
                    mat.SetVector("_Dir", new Vector4(1, 0, 0, 0)); Graphics.Blit(q1, q2, mat, 1);
                    mat.SetVector("_Dir", new Vector4(0, 1, 0, 0)); Graphics.Blit(q2, q1, mat, 1);
                }
                mat.SetTexture("_BloomTex", q1);
                mat.SetFloat("_BloomIntensity", bloomIntensity);

                // depth of field: blurred copy at half size
                if (dof)
                {
                    halfB = RenderTexture.GetTemporary(w, h, 0, fmt);
                    Graphics.Blit(src, half);
                    for (int i = 0; i < 4; i++)   // a wide, soft blur: the miniature look
                    {
                        mat.SetVector("_Dir", new Vector4(2.2f, 0, 0, 0)); Graphics.Blit(half, halfB, mat, 1);
                        mat.SetVector("_Dir", new Vector4(0, 2.2f, 0, 0)); Graphics.Blit(halfB, half, mat, 1);
                    }
                    mat.SetTexture("_BlurTex", half);
                }
                mat.SetFloat("_DofOn", dof ? 1f : 0f);
                mat.SetFloat("_FocusHalf", focusHalf);
                mat.SetFloat("_FocusFeather", focusFeather);
                mat.SetFloat("_Vignette", vignette);
                mat.SetVector("_Tint", new Vector4(tint.r, tint.g, tint.b, 1));
                mat.SetFloat("_Saturation", saturation);
                mat.SetFloat("_Contrast", contrast);
                Graphics.Blit(src, dst, mat, 2);
            }
            finally
            {
                if (half != null) RenderTexture.ReleaseTemporary(half);
                if (halfB != null) RenderTexture.ReleaseTemporary(halfB);
                if (q1 != null) RenderTexture.ReleaseTemporary(q1);
                if (q2 != null) RenderTexture.ReleaseTemporary(q2);
            }
        }
    }
}
