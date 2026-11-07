// HD-2D post maths without the engine (O432): the filmic curve, the light shaft ranking and the screen edge fade.
// The shader Hd2dPost.shader repeats Aces; keep both in step. Tested in Core.Tests/Hd2dTests.cs.
using System;

namespace Chaos.Core
{
    public static class Hd2dGrade
    {
        /// <summary>ACES filmic curve, fitted form (Narkowicz). 0 maps to 0, large values roll off towards 1, never above.</summary>
        public static float Aces(float x)
        {
            if (x <= 0f) return 0f;
            float v = (x * (2.51f * x + 0.03f)) / (x * (2.43f * x + 0.59f) + 0.14f);
            return v < 0f ? 0f : (v > 1f ? 1f : v);
        }

        /// <summary>Rank of a light as a shaft source: brighter and nearer wins. distance is in world units (tiles).</summary>
        public static float ShaftScore(float brightness, float distance)
        {
            if (brightness <= 0f) return 0f;
            return brightness / (1f + Math.Max(0f, distance) * 0.15f);
        }

        /// <summary>1 while the light is on screen, falling to 0 at 0.35 of a screen outside it, so shafts do not pop when a light leaves the frame.</summary>
        public static float EdgeFade(float u, float v)
        {
            float du = Math.Max(0f, Math.Max(-u, u - 1f));
            float dv = Math.Max(0f, Math.Max(-v, v - 1f));
            float d = Math.Max(du, dv);
            float t = 1f - d / 0.35f;
            return t < 0f ? 0f : (t > 1f ? 1f : t);
        }
    }
}
