#version 460 core
// Spike: high-quality upscale of the internal-res scene image to native res.
// Catmull-Rom bicubic (9 bilinear taps) + contrast-adaptive sharpen + TPDF dither.
#include <flutter/runtime_effect.glsl>

uniform vec2 uOutSize;     // output size in physical px
uniform vec2 uInSize;      // source texture size in px
uniform float uSharpen;    // 0..1
uniform float uFrame;      // for dither animation
uniform float uGrain;      // sensor-noise strength (M8), 0 = none
uniform sampler2D uSrc;

out vec4 fragColor;

vec3 catmullRom(vec2 uv) {
  vec2 samplePos = uv * uInSize;
  vec2 tc1 = floor(samplePos - 0.5) + 0.5;
  vec2 f = samplePos - tc1;
  vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
  vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
  vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
  vec2 w3 = f * f * (-0.5 + 0.5 * f);
  vec2 w12 = w1 + w2;
  vec2 off12 = w2 / w12;
  vec2 tc0 = (tc1 - 1.0) / uInSize;
  vec2 tc3 = (tc1 + 2.0) / uInSize;
  vec2 tc12 = (tc1 + off12) / uInSize;
  vec3 r = vec3(0.0);
  r += texture(uSrc, vec2(tc0.x, tc0.y)).rgb * w0.x * w0.y;
  r += texture(uSrc, vec2(tc12.x, tc0.y)).rgb * w12.x * w0.y;
  r += texture(uSrc, vec2(tc3.x, tc0.y)).rgb * w3.x * w0.y;
  r += texture(uSrc, vec2(tc0.x, tc12.y)).rgb * w0.x * w12.y;
  r += texture(uSrc, vec2(tc12.x, tc12.y)).rgb * w12.x * w12.y;
  r += texture(uSrc, vec2(tc3.x, tc12.y)).rgb * w3.x * w12.y;
  r += texture(uSrc, vec2(tc0.x, tc3.y)).rgb * w0.x * w3.y;
  r += texture(uSrc, vec2(tc12.x, tc3.y)).rgb * w12.x * w3.y;
  r += texture(uSrc, vec2(tc3.x, tc3.y)).rgb * w3.x * w3.y;
  return max(r, vec3(0.0));
}

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 uv = fc / uOutSize;
  vec3 c = catmullRom(uv);
  // Contrast-adaptive sharpen on the source grid (RCAS-like, cheap).
  vec2 px = 1.0 / uInSize;
  vec3 n = texture(uSrc, uv + vec2(0.0, -px.y)).rgb;
  vec3 s = texture(uSrc, uv + vec2(0.0, px.y)).rgb;
  vec3 e = texture(uSrc, uv + vec2(px.x, 0.0)).rgb;
  vec3 w = texture(uSrc, uv + vec2(-px.x, 0.0)).rgb;
  vec3 mn = min(min(n, s), min(e, w));
  vec3 mx = max(max(n, s), max(e, w));
  vec3 amp = clamp(min(mn, 1.0 - mx) / max(mx, vec3(1e-4)), 0.0, 1.0);
  // M8 round 33: a phone's noise reduction smears fine detail in the
  // shadows (critics: "pin-sharp, noise-free render with an even grain
  // layer on top"). Dark areas blend toward a small local blur and are
  // not sharpened; lit areas keep their detail.
  float lum0 = dot(c, vec3(0.2126, 0.7152, 0.0722));
  float nr = (1.0 - smoothstep(0.035, 0.2, lum0)) * 0.75;
  if (nr > 0.0) {
    vec3 d1 = texture(uSrc, uv + px * vec2(1.5, 1.5)).rgb;
    vec3 d2 = texture(uSrc, uv + px * vec2(-1.5, 1.5)).rgb;
    vec3 d3 = texture(uSrc, uv + px * vec2(1.5, -1.5)).rgb;
    vec3 d4 = texture(uSrc, uv + px * vec2(-1.5, -1.5)).rgb;
    vec3 blur = (2.0 * c + n + s + e + w + d1 + d2 + d3 + d4) / 10.0;
    c = mix(c, blur, nr);
  }
  float k = uSharpen * 0.2 * sqrt(dot(amp, vec3(0.333))) * (1.0 - nr);
  c = clamp(c + (4.0 * c - (n + s + e + w)) * k, 0.0, 1.0);
  // M8: phone sensor noise after its noise reduction, on the display image.
  // Strongest in the dark mid-tones, nearly clean in the blacks and fading
  // in the highlights (critics measured the dusk references at about 0.6
  // levels RMS in near-black and 2.4-2.8 in dark mid-tones; the engine's
  // flat linear grain gave about 4 everywhere and buried the ripples).
  // Mostly luma with a little colour; one grain per source pixel, the
  // slightly soft clumps noise reduction leaves.
  if (uGrain > 0.0) {
    vec2 gp = floor(uv * uInSize) + uFrame * 7.13;
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    // Round 33: between rounds 31 and 32 (critics split on the near-black).
    float wgt = mix(0.4, 1.0, smoothstep(0.015, 0.11, l)) * (1.0 - 0.75 * smoothstep(0.3, 0.8, l));
    float gl = hash(gp) + hash(gp + 31.7) - 1.0;
    // Round 34: chroma noise in soft clumps about two source pixels
    // across (bilinear between hashed cells), the colour mottling a phone
    // leaves after noise reduction; critics found the round-33 grain about
    // half to a third of the references' and nearly colourless.
    vec2 cp = uv * uInSize * 0.5 + uFrame * 3.71;
    vec2 ci = floor(cp), cf = fract(cp);
    cf = cf * cf * (3.0 - 2.0 * cf);
    vec3 c00 = vec3(hash(ci + 3.1), hash(ci + 5.9), hash(ci + 8.3));
    vec3 c10 = vec3(hash(ci + vec2(1.0, 0.0) + 3.1), hash(ci + vec2(1.0, 0.0) + 5.9), hash(ci + vec2(1.0, 0.0) + 8.3));
    vec3 c01 = vec3(hash(ci + vec2(0.0, 1.0) + 3.1), hash(ci + vec2(0.0, 1.0) + 5.9), hash(ci + vec2(0.0, 1.0) + 8.3));
    vec3 c11 = vec3(hash(ci + vec2(1.0, 1.0) + 3.1), hash(ci + vec2(1.0, 1.0) + 5.9), hash(ci + vec2(1.0, 1.0) + 8.3));
    vec3 gc = mix(mix(c00, c10, cf.x), mix(c01, c11, cf.x), cf.y) - 0.5;
    gc -= dot(gc, vec3(0.333));  // colour only
    c += (gl * 0.055 + gc * 0.06) * (uGrain * wgt);
  }
  // TPDF dither, +/- 1 LSB of 8-bit, so dark gradients never band.
  float d = hash(fc + uFrame) + hash(fc * 1.37 + 17.0 + uFrame) - 1.0;
  c += d / 255.0;
  fragColor = vec4(c, 1.0);
}
