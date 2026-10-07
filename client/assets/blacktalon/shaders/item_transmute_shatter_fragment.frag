#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D u_Tex0;

// Animation controls
uniform float u_time;
uniform float u_progress;      // 0 = intact, 1 = fully shattered

// Effect tuning
uniform float u_shardCount;    // grid density (default 6.0)
uniform float u_explosionForce; // how far shards fly (default 0.8)
uniform float u_rotationSpeed; // shard spin amount (default 2.0)
uniform float u_gravity;       // downward pull on shards (default 0.3)
uniform vec4  u_colorTint;     // tint color (default white)

varying vec2 v_TexCoord;

const float ALPHA_THRESHOLD = 0.001;
const float PI = 3.14159265;

// ---- Hash functions for deterministic randomness per shard ----

float hash11(float p)
{
  p = fract(p * 0.1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}

vec2 hash22(vec2 p)
{
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

// ---- Voronoi cell ID: which shard does this pixel belong to? ----

// Returns: xy = nearest cell center, zw = cell integer ID
vec4 voronoiCell(vec2 uv, float density)
{
  vec2 scaledUv = uv * density;
  vec2 cellId = floor(scaledUv);
  vec2 localUv = fract(scaledUv);

  float minDist = 10.0;
  vec2 nearestCenter = vec2(0.0);
  vec2 nearestId = vec2(0.0);

  // Check 3x3 neighborhood
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 neighbor = vec2(float(x), float(y));
      vec2 offset = hash22(cellId + neighbor);  // random offset within cell
      vec2 center = neighbor + offset - localUv;
      float dist = dot(center, center);
      if (dist < minDist) {
        minDist = dist;
        nearestCenter = (cellId + neighbor + offset) / density;
        nearestId = cellId + neighbor;
      }
    }
  }

  return vec4(nearestCenter, nearestId);
}

// ---- 2D rotation matrix ----

mat2 rot2D(float angle)
{
  float c = cos(angle);
  float s = sin(angle);
  return mat2(c, -s, s, c);
}

void main()
{
  float progress = clamp(u_progress, 0.0, 1.0);
  float density = max(2.0, u_shardCount);
  float force = max(0.0, u_explosionForce);
  float rotSpeed = u_rotationSpeed;
  float grav = u_gravity;

  if (progress <= 0.001) {
    // No effect yet — draw original
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    gl_FragColor = texColor * u_colorTint;
    if (gl_FragColor.a <= ALPHA_THRESHOLD) discard;
    return;
  }

  // Get Voronoi cell for this pixel
  vec4 cell = voronoiCell(v_TexCoord, density);
  vec2 shardCenter = cell.xy;   // center of this shard in UV space
  vec2 shardId = cell.zw;       // integer ID for deterministic random

  // Deterministic random values per shard
  float randAngle = hash11(dot(shardId, vec2(127.1, 311.7))) * PI * 2.0;
  float randSpeed = 0.6 + hash11(dot(shardId, vec2(269.5, 183.3))) * 0.8;
  float randDelay = hash11(dot(shardId, vec2(419.2, 371.9))) * 0.15;
  float randRotDir = hash11(dot(shardId, vec2(547.3, 251.1))) > 0.5 ? 1.0 : -1.0;

  // Delayed start per shard (shards near center break first)
  float distFromCenter = length(shardCenter - vec2(0.5));
  float shardDelay = randDelay + distFromCenter * 0.1;
  float shardProgress = clamp((progress - shardDelay) / max(0.01, 1.0 - shardDelay), 0.0, 1.0);

  // Easing: ease-out for explosive feel
  float easedProgress = 1.0 - pow(1.0 - shardProgress, 2.0);

  // Direction: outward from item center, with random variation
  vec2 dirFromCenter = normalize(shardCenter - vec2(0.5) + vec2(0.001));
  vec2 explosionDir = vec2(
    dirFromCenter.x * cos(randAngle * 0.3) - dirFromCenter.y * sin(randAngle * 0.3),
    dirFromCenter.x * sin(randAngle * 0.3) + dirFromCenter.y * cos(randAngle * 0.3)
  );

  // Movement: outward + gravity pulling down
  vec2 movement = explosionDir * easedProgress * force * randSpeed;
  movement.y += easedProgress * easedProgress * grav;  // gravity (positive = down in UV space)

  // Rotation around shard center
  float rotAngle = easedProgress * rotSpeed * randRotDir * (1.0 + randSpeed);

  // Transform UV: translate to shard center, rotate, translate back, then apply explosion offset
  vec2 uv = v_TexCoord;
  uv -= shardCenter;                  // center on shard
  uv = rot2D(rotAngle) * uv;         // rotate
  uv += shardCenter;                  // restore
  uv -= movement;                     // reverse the explosion offset to sample original position

  // Sample the original texture at transformed UV
  vec4 texColor = texture2D(u_Tex0, uv);

  // Only show pixels that belong to the original item (avoid sampling outside)
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    discard;
  }

  if (texColor.a <= ALPHA_THRESHOLD) {
    discard;
  }

  // Darken shards as they fly away
  float darken = mix(1.0, 0.3, easedProgress);
  vec3 color = texColor.rgb * u_colorTint.rgb * darken;

  // Edge highlight: brief flash at the crack lines when explosion starts
  float crackFlash = smoothstep(0.0, 0.15, shardProgress) * (1.0 - smoothstep(0.15, 0.4, shardProgress));
  color += vec3(1.0, 0.6, 0.2) * crackFlash * 0.5;

  // Fade out shards at the end
  float fadeOut = 1.0 - smoothstep(0.7, 1.0, shardProgress);
  float finalAlpha = texColor.a * u_colorTint.a * fadeOut;

  if (finalAlpha <= ALPHA_THRESHOLD) {
    discard;
  }

  gl_FragColor = vec4(clamp(color, 0.0, 1.0), finalAlpha);
}
