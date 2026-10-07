#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D u_Tex0;

// Time/progress controls
uniform float u_time;
uniform float u_progress;

// Effect tuning controls
uniform vec2 u_windDir;
uniform float u_noiseScale;
uniform float u_burnWidth;
uniform float u_ashAmount;
uniform vec4 u_colorTint;

varying vec2 v_TexCoord;

const float ALPHA_THRESHOLD = 0.001;

// Fast 2D hash
float hash12(vec2 p)
{
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Value noise
float valueNoise(vec2 p)
{
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);

  float a = hash12(i + vec2(0.0, 0.0));
  float b = hash12(i + vec2(1.0, 0.0));
  float c = hash12(i + vec2(0.0, 1.0));
  float d = hash12(i + vec2(1.0, 1.0));

  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal noise used as dissolve mask
float fbm(vec2 p)
{
  float value = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < 4; ++i) {
    value += valueNoise(p) * amplitude;
    p = p * 2.03 + vec2(7.13, 11.17);
    amplitude *= 0.5;
  }
  return value;
}

void main()
{
  vec4 texColor = texture2D(u_Tex0, v_TexCoord);
  if (texColor.a <= ALPHA_THRESHOLD) {
    discard;
  }

  // Inverted from dust_dissolve: u_progress=0 means "fully dissolved/invisible"
  // and u_progress=1 means "fully solid/visible". The internal pipeline still
  // uses the dissolve semantic (high internal progress = more dissolved), so
  // we flip the input once here and reuse all the original fragment logic.
  float progress = 1.0 - clamp(u_progress, 0.0, 1.0);
  float noiseScale = max(0.5, u_noiseScale);
  float burnWidth = max(0.003, u_burnWidth);
  float ashAmount = clamp(u_ashAmount, 0.0, 1.0);

  // If u_colorTint never got initialized (default vec4(0)), fall back to opaque
  // white so the sprite isn't multiplied to black/zero alpha.
  vec4 colorTint = u_colorTint;
  if (colorTint.a <= 0.001) colorTint = vec4(1.0);

  // 1) Dissolve field from procedural fractal noise
  vec2 uv = v_TexCoord;
  vec2 noiseUv = uv * noiseScale;
  float n1 = fbm(noiseUv + vec2(1.37, -2.11));
  float n2 = fbm((noiseUv * 0.65) + vec2(-4.43, 3.19));
  float dissolveField = (n1 * 0.72) + (n2 * 0.28);

  float threshold = progress * 1.08;
  float burnDistance = dissolveField - threshold;
  float survive = smoothstep(-0.035, 0.08, burnDistance);
  float dissolved = 1.0 - survive;

  // 2) Short hot edge around threshold (orange -> gray)
  float edge = 1.0 - smoothstep(0.0, burnWidth, abs(burnDistance));
  edge *= smoothstep(0.02, 0.98, progress + 0.06);
  vec3 hotEdgeColor = mix(vec3(1.00, 0.54, 0.15), vec3(0.47, 0.47, 0.47), smoothstep(0.0, 1.0, progress * 1.15));

  // 4) Darken sprite before vanishing
  float darken = mix(1.0, 0.45, smoothstep(0.04, 1.0, progress));
  vec3 baseColor = texColor.rgb * colorTint.rgb * darken;
  vec3 shadedColor = mix(baseColor, hotEdgeColor, edge * 0.92);

  // 3) Ash particles detached and drifting upward with light wind
  vec2 wind = normalize(vec2(u_windDir.x, -1.0 + (u_windDir.y * 0.35)));
  float lift = (0.08 + (0.26 * ashAmount)) * progress;
  vec2 turbulence = vec2(
    valueNoise(uv * 17.0 + vec2(u_time * 1.7, -u_time * 1.3)) - 0.5,
    valueNoise(uv * 13.0 + vec2(-u_time * 1.1, u_time * 1.6)) - 0.5
  ) * (0.045 * ashAmount);
  vec2 ashSampleUv = uv - (wind * lift) + turbulence;
  float ashSourceAlpha = texture2D(u_Tex0, ashSampleUv).a;
  float ashNoise = valueNoise(uv * (18.0 + noiseScale) + vec2(u_time * 6.8, -u_time * 7.1));
  float ashThreshold = mix(0.94, 0.56, ashAmount);
  float ashParticleMask = step(ashThreshold, ashNoise);
  float ashGate = smoothstep(0.12, 1.0, progress) * dissolved;
  float ashAlpha = ashSourceAlpha * ashParticleMask * ashGate * (0.35 + (0.65 * ashAmount));
  vec3 ashColor = mix(vec3(0.42, 0.42, 0.42), vec3(0.20, 0.20, 0.20), valueNoise(uv * 24.0 + vec2(u_time * 2.3, -u_time * 1.9)));

  float residualAlpha = texColor.a * (1.0 - progress) * 0.22;
  float finalAlpha = ((texColor.a * survive) + residualAlpha + ashAlpha) * colorTint.a;

  // Fade out everything in the last 15% of progress to guarantee full disappearance.
  // Use the well-defined form (edge0 < edge1) to avoid GLSL undefined behavior
  // for inverted smoothstep ranges (some GPUs/drivers return 0 in that case,
  // which would make the sprite invisible at every progress).
  float fadeOut = 1.0 - smoothstep(0.85, 1.0, progress);
  finalAlpha *= fadeOut;

  if (finalAlpha <= ALPHA_THRESHOLD) {
    discard;
  }

  vec3 finalColor = (shadedColor * survive) + (ashColor * ashAlpha) + (hotEdgeColor * edge * (0.28 + ((1.0 - progress) * 0.45)));
  gl_FragColor = vec4(clamp(finalColor, 0.0, 1.0), finalAlpha);
}
