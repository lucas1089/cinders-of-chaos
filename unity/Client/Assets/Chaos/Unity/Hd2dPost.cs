// HD-2D look (O432): bloom on bright pixels, light shafts from the strongest lights, tilt-shift depth of field (sharp middle
// band, two blur levels toward top and bottom), distance fog, ACES tonemap, split-toned grade, tinted vignette and light grain,
// on one camera.
//
// PIPELINE: the built-in render pipeline with our own image effect (OnRenderImage on Hd2dEffect), shaders in
// Assets/Chaos/Shaders. Why not URP: the URP and Post Processing assemblies are not on NuGet, so unity/Client.Check
// (no Unity license, reference assemblies only) could not compile code that uses them, and the URP asset would have to
// be made by an editor script that no CI run can check. This path compiles in Client.Check and needs no new package.
// DoF is by screen Y (no depth texture), which is what the tilt-shift look is.
//
// Use: Hd2dPost.Attach(cam, lowQuality) once the 3D scene exists, Detach(cam) to go back.
// Shafts: Hd2dEffect.SetLightsWorld(cam, positions, colours) once per frame (none without the call).
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

        /// <summary>Turns the HD-2D look on for this camera. lowQuality (phones): bloom, tonemap, grade and fog stay; depth of field, shafts, grain and soft shadows go.</summary>
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
            fx.shafts = !lowQuality;
            fx.lowQuality = lowQuality;
            fx.exposure = lowQuality ? 1.3f : 1.0f;   // the LDR image tops out at 1 and the curve would dim it
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
        /// <summary>A light shaft source: position on screen as viewport uv (0..1, y up), colour (rgb), strength 0..1.</summary>
        public struct ShaftSource
        {
            public Vector2 uv; public Color color; public float strength;
            public ShaftSource(Vector2 uv, Color color, float strength) { this.uv = uv; this.color = color; this.strength = strength; }
        }

        public bool dof = true, shafts = true, lowQuality;
        public float bloomThreshold = 0.8f, bloomKnee = 0.5f, bloomIntensity = 0.95f;
        public float focusHalf = 0.14f, focusFeather = 0.22f;   // sharp band is the middle 28% of the screen height
        // tonemap (ACES fitted), applied before the grade
        public float exposure = 1.0f;
        // grade
        public Color shadowTint = new Color(0.78f, 0.86f, 1.16f);      // teal-violet shadows (multiply)
        public Color highlightTint = new Color(1.14f, 1.0f, 0.80f);    // warm highlights (multiply)
        public float splitStrength = 0.75f;
        public Color lift = new Color(0.020f, 0.018f, 0.045f);         // blacks rise to deep blue-violet
        public Color tint = new Color(1.02f, 0.99f, 0.95f);            // overall, light
        public float saturation = 1.04f, midSaturation = 0.22f, contrast = 1.05f;
        public float vignette = 0.38f, grain = 0.025f;
        // light shafts
        public float shaftIntensity = 0.55f, shaftDecay = 0.93f, shaftDensity = 0.9f;
        Material mat;
        readonly ShaftSource[] sources = new ShaftSource[2];
        int sourceCount;

        void OnEnable()
        {
            var sh = Shader.Find(Hd2dPost.PostShaderName);
            if (sh == null || !sh.isSupported) { Debug.LogWarning("hd2d: post shader missing or unsupported"); enabled = false; return; }
            mat = new Material(sh) { hideFlags = HideFlags.HideAndDontSave };
        }

        void OnDisable() { if (mat != null) Destroy(mat); mat = null; }

        /// <summary>Sets up to 2 shaft sources (screen uv, colour, strength). null or an empty list turns shafts off. Without a call there are none.</summary>
        public void SetShaftSources(IList<ShaftSource> src)
        {
            sourceCount = 0;
            if (src == null) return;
            for (int i = 0; i < src.Count && sourceCount < 2; i++) sources[sourceCount++] = src[i];
        }

        static readonly ShaftSource[] pick = new ShaftSource[2];
        static readonly float[] pickScore = new float[2];

        /// <summary>
        /// Picks the 1-2 strongest lights in front of the camera from world positions and colours and passes them to the effect on cam
        /// (nothing happens if the camera has none). Call once per frame, after the camera has moved. Brightness is the largest colour channel.
        /// </summary>
        public static void SetLightsWorld(Camera cam, IList<Vector3> pos, IList<Color> col)
        {
            if (cam == null) return;
            var fx = cam.GetComponent<Hd2dEffect>();
            if (fx == null) return;
            int n = 0;
            pickScore[0] = pickScore[1] = 0f;
            if (pos != null && col != null)
            {
                int count = Mathf.Min(pos.Count, col.Count);
                for (int i = 0; i < count; i++)
                {
                    var vp = cam.WorldToViewportPoint(pos[i]);
                    if (vp.z <= 0.1f) continue;                         // behind the camera
                    float fade = Chaos.Core.Hd2dGrade.EdgeFade(vp.x, vp.y);
                    if (fade <= 0f) continue;
                    var c = col[i];
                    float br = Mathf.Max(c.r, Mathf.Max(c.g, c.b));
                    float score = Chaos.Core.Hd2dGrade.ShaftScore(br, vp.z) * fade;
                    if (score <= 0f) continue;
                    var s = new ShaftSource(new Vector2(vp.x, vp.y), new Color(c.r / br, c.g / br, c.b / br, 1f), Mathf.Clamp01(br) * fade);
                    int slot;
                    if (n < 2) slot = n++;
                    else if (score > pickScore[0] || score > pickScore[1]) slot = pickScore[0] <= pickScore[1] ? 0 : 1;
                    else continue;
                    pick[slot] = s; pickScore[slot] = score;
                }
            }
            fx.sourceCount = 0;
            for (int i = 0; i < n; i++) fx.sources[fx.sourceCount++] = pick[i];
        }

        void OnRenderImage(RenderTexture src, RenderTexture dst)
        {
            if (mat == null) { Graphics.Blit(src, dst); return; }
            int w = Mathf.Max(2, src.width / 2), h = Mathf.Max(2, src.height / 2);
            var fmt = src.format;
            RenderTexture half = null, halfB = null, q1 = null, q2 = null, qs = null, qh1 = null, qh2 = null;
            bool useDof = dof && !lowQuality, useShafts = shafts && !lowQuality && sourceCount > 0 && shaftIntensity > 0f;
            try
            {
                // bloom: bright pass to half size, blur at quarter size
                half = RenderTexture.GetTemporary(w, h, 0, fmt);
                mat.SetFloat("_Threshold", bloomThreshold);
                mat.SetFloat("_Knee", bloomKnee);
                Graphics.Blit(src, half, mat, 0);
                q1 = RenderTexture.GetTemporary(w / 2, h / 2, 0, fmt);
                q2 = RenderTexture.GetTemporary(w / 2, h / 2, 0, fmt);

                // light shafts: radial blur of the bright pass toward the sources, at quarter size (before half is reused)
                if (useShafts)
                {
                    qs = RenderTexture.GetTemporary(w / 2, h / 2, 0, fmt);
                    SetShaft("_ShaftA", "_ShaftColA", 0);
                    SetShaft("_ShaftB", "_ShaftColB", 1);
                    mat.SetFloat("_ShaftDecay", shaftDecay);
                    mat.SetFloat("_ShaftDensity", shaftDensity);
                    Graphics.Blit(half, qs, mat, 3);
                    mat.SetTexture("_ShaftTex", qs);
                }
                mat.SetFloat("_ShaftOn", useShafts ? 1f : 0f);

                Graphics.Blit(half, q1);
                for (int i = 0; i < 2; i++)
                {
                    mat.SetVector("_Dir", new Vector4(1, 0, 0, 0)); Graphics.Blit(q1, q2, mat, 1);
                    mat.SetVector("_Dir", new Vector4(0, 1, 0, 0)); Graphics.Blit(q2, q1, mat, 1);
                }
                mat.SetTexture("_BloomTex", q1);
                mat.SetFloat("_BloomIntensity", bloomIntensity);

                // depth of field: a light blur at half size and a heavy blur at quarter size, blended in the shader by the distance from the focus band
                if (useDof)
                {
                    halfB = RenderTexture.GetTemporary(w, h, 0, fmt);
                    Graphics.Blit(src, half);
                    for (int i = 0; i < 2; i++)   // the light level; the heavy level is the quarter-size blur below
                    {
                        mat.SetVector("_Dir", new Vector4(1.5f, 0, 0, 0)); Graphics.Blit(half, halfB, mat, 1);
                        mat.SetVector("_Dir", new Vector4(0, 1.5f, 0, 0)); Graphics.Blit(halfB, half, mat, 1);
                    }
                    mat.SetTexture("_BlurTex", half);
                    qh1 = RenderTexture.GetTemporary(w / 2, h / 2, 0, fmt);
                    qh2 = RenderTexture.GetTemporary(w / 2, h / 2, 0, fmt);
                    Graphics.Blit(half, qh1);
                    for (int i = 0; i < 3; i++)
                    {
                        mat.SetVector("_Dir", new Vector4(2.5f, 0, 0, 0)); Graphics.Blit(qh1, qh2, mat, 1);
                        mat.SetVector("_Dir", new Vector4(0, 2.5f, 0, 0)); Graphics.Blit(qh2, qh1, mat, 1);
                    }
                    mat.SetTexture("_BlurTex2", qh1);
                }
                mat.SetFloat("_DofOn", useDof ? 1f : 0f);
                mat.SetFloat("_FocusHalf", focusHalf);
                mat.SetFloat("_FocusFeather", focusFeather);
                mat.SetFloat("_Vignette", vignette);
                mat.SetVector("_Tint", new Vector4(tint.r, tint.g, tint.b, 1));
                mat.SetFloat("_Saturation", saturation);
                mat.SetFloat("_MidSat", midSaturation);
                mat.SetFloat("_Contrast", contrast);
                mat.SetFloat("_Exposure", exposure);
                mat.SetVector("_ShadowTint", new Vector4(shadowTint.r, shadowTint.g, shadowTint.b, 1));
                mat.SetVector("_HighlightTint", new Vector4(highlightTint.r, highlightTint.g, highlightTint.b, 1));
                mat.SetFloat("_SplitStrength", splitStrength);
                mat.SetVector("_Lift", new Vector4(lift.r, lift.g, lift.b, 0));
                mat.SetFloat("_Grain", lowQuality ? 0f : grain);
                mat.SetFloat("_GrainSeed", Mathf.Floor(Time.time * 24f) * 17.31f);
                Graphics.Blit(src, dst, mat, 2);
            }
            finally
            {
                if (half != null) RenderTexture.ReleaseTemporary(half);
                if (halfB != null) RenderTexture.ReleaseTemporary(halfB);
                if (q1 != null) RenderTexture.ReleaseTemporary(q1);
                if (q2 != null) RenderTexture.ReleaseTemporary(q2);
                if (qs != null) RenderTexture.ReleaseTemporary(qs);
                if (qh1 != null) RenderTexture.ReleaseTemporary(qh1);
                if (qh2 != null) RenderTexture.ReleaseTemporary(qh2);
            }
        }

        void SetShaft(string posName, string colName, int index)
        {
            if (index < sourceCount)
            {
                var s = sources[index];
                mat.SetVector(posName, new Vector4(s.uv.x, s.uv.y, shaftIntensity * Mathf.Clamp01(s.strength), 0));
                mat.SetVector(colName, new Vector4(s.color.r, s.color.g, s.color.b, 1));
            }
            else
            {
                mat.SetVector(posName, Vector4.zero);
                mat.SetVector(colName, Vector4.zero);
            }
        }
    }
}
