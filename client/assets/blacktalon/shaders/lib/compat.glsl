// ============================================================================
// GLSL Compatibility Library for BlackTalon
// ============================================================================
// This file provides cross-platform compatibility functions for shaders
// that need to work on both OpenGL Desktop and OpenGL ES (DirectX/ANGLE).
//
// Usage: Copy the functions you need to the top of your shader file.
// Note: GLSL doesn't support #include, so you must copy-paste these functions.
// ============================================================================

// ============================================================================
// HYPERBOLIC FUNCTIONS (not available in GLSL ES 1.00/2.00)
// ============================================================================

// tanh - Hyperbolic tangent
// Formula: tanh(x) = (e^2x - 1) / (e^2x + 1)
float compat_tanh(float x) {
    float e2x = exp(2.0 * x);
    return (e2x - 1.0) / (e2x + 1.0);
}

vec2 compat_tanh(vec2 x) {
    vec2 e2x = exp(2.0 * x);
    return (e2x - 1.0) / (e2x + 1.0);
}

vec3 compat_tanh(vec3 x) {
    vec3 e2x = exp(2.0 * x);
    return (e2x - 1.0) / (e2x + 1.0);
}

vec4 compat_tanh(vec4 x) {
    vec4 e2x = exp(2.0 * x);
    return (e2x - 1.0) / (e2x + 1.0);
}

// sinh - Hyperbolic sine
// Formula: sinh(x) = (e^x - e^-x) / 2
float compat_sinh(float x) {
    return (exp(x) - exp(-x)) * 0.5;
}

vec2 compat_sinh(vec2 x) {
    return (exp(x) - exp(-x)) * 0.5;
}

vec3 compat_sinh(vec3 x) {
    return (exp(x) - exp(-x)) * 0.5;
}

vec4 compat_sinh(vec4 x) {
    return (exp(x) - exp(-x)) * 0.5;
}

// cosh - Hyperbolic cosine
// Formula: cosh(x) = (e^x + e^-x) / 2
float compat_cosh(float x) {
    return (exp(x) + exp(-x)) * 0.5;
}

vec2 compat_cosh(vec2 x) {
    return (exp(x) + exp(-x)) * 0.5;
}

vec3 compat_cosh(vec3 x) {
    return (exp(x) + exp(-x)) * 0.5;
}

vec4 compat_cosh(vec4 x) {
    return (exp(x) + exp(-x)) * 0.5;
}

// ============================================================================
// INVERSE HYPERBOLIC FUNCTIONS
// ============================================================================

// asinh - Inverse hyperbolic sine
// Formula: asinh(x) = ln(x + sqrt(x^2 + 1))
float compat_asinh(float x) {
    return log(x + sqrt(x * x + 1.0));
}

// acosh - Inverse hyperbolic cosine
// Formula: acosh(x) = ln(x + sqrt(x^2 - 1)), x >= 1
float compat_acosh(float x) {
    return log(x + sqrt(x * x - 1.0));
}

// atanh - Inverse hyperbolic tangent
// Formula: atanh(x) = 0.5 * ln((1 + x) / (1 - x)), |x| < 1
float compat_atanh(float x) {
    return 0.5 * log((1.0 + x) / (1.0 - x));
}

// ============================================================================
// INTEGER OPERATIONS (% operator not available in GLSL ES for integers)
// ============================================================================

// Integer modulo using float mod()
// Use: float result = compat_imod(i, 3); if (result < 0.5) ...
float compat_imod(int i, int n) {
    return mod(float(i), float(n));
}

// Check if integer i is divisible by n
bool compat_divisible(int i, int n) {
    return mod(float(i), float(n)) < 0.5;
}

// ============================================================================
// ROUNDING FUNCTIONS (not in GLSL ES 1.00)
// ============================================================================

// round - Round to nearest integer
float compat_round(float x) {
    return floor(x + 0.5);
}

vec2 compat_round(vec2 x) {
    return floor(x + 0.5);
}

vec3 compat_round(vec3 x) {
    return floor(x + 0.5);
}

vec4 compat_round(vec4 x) {
    return floor(x + 0.5);
}

// trunc - Truncate towards zero
float compat_trunc(float x) {
    return x < 0.0 ? ceil(x) : floor(x);
}

vec2 compat_trunc(vec2 x) {
    return vec2(compat_trunc(x.x), compat_trunc(x.y));
}

vec3 compat_trunc(vec3 x) {
    return vec3(compat_trunc(x.x), compat_trunc(x.y), compat_trunc(x.z));
}

vec4 compat_trunc(vec4 x) {
    return vec4(compat_trunc(x.x), compat_trunc(x.y), compat_trunc(x.z), compat_trunc(x.w));
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

// isnan - Check if value is NaN (not available in GLSL ES 1.00)
bool compat_isnan(float x) {
    return x != x;
}

// isinf - Check if value is infinite (not available in GLSL ES 1.00)
bool compat_isinf(float x) {
    return abs(x) > 1e38;
}

// saturate - Clamp value to [0, 1] range (common in HLSL, not in GLSL)
float saturate(float x) {
    return clamp(x, 0.0, 1.0);
}

vec2 saturate(vec2 x) {
    return clamp(x, 0.0, 1.0);
}

vec3 saturate(vec3 x) {
    return clamp(x, 0.0, 1.0);
}

vec4 saturate(vec4 x) {
    return clamp(x, 0.0, 1.0);
}

// lerp - Linear interpolation (HLSL name for mix)
float lerp(float a, float b, float t) {
    return mix(a, b, t);
}

vec2 lerp(vec2 a, vec2 b, float t) {
    return mix(a, b, t);
}

vec3 lerp(vec3 a, vec3 b, float t) {
    return mix(a, b, t);
}

vec4 lerp(vec4 a, vec4 b, float t) {
    return mix(a, b, t);
}

// ============================================================================
// COMMON NOISE FUNCTIONS
// ============================================================================

// Simple hash function for pseudo-random values
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 2D Value noise
float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // Smoothstep

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ============================================================================
// TONEMAPPING FUNCTIONS
// ============================================================================

// Reinhard tonemapping
vec3 tonemapReinhard(vec3 color) {
    return color / (color + 1.0);
}

// Reinhard extended tonemapping
vec3 tonemapReinhardExtended(vec3 color, float maxWhite) {
    vec3 numerator = color * (1.0 + color / (maxWhite * maxWhite));
    return numerator / (1.0 + color);
}

// ACES filmic tonemapping (approximation)
vec3 tonemapACES(vec3 color) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
}

// Tanh tonemapping using compat function
vec3 tonemapTanh(vec3 color, float intensity) {
    return compat_tanh(color / intensity);
}

vec4 tonemapTanh(vec4 color, float intensity) {
    return compat_tanh(color / intensity);
}
