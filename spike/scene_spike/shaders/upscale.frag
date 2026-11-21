#version 460 core
// Spike: high-quality upscale of the internal-res scene image to native res.
// Catmull-Rom bicubic (9 bilinear taps) + contrast-adaptive sharpen + TPDF dither.
#include <flutter/runtime_effect.glsl>

uniform vec2 uOutSize;     // output size in physical px
uniform vec2 uInSize;      // source texture size in px
uniform float uSharpen;    // 0..1
uniform float uFrame;      // for dither animation
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
  float k = uSharpen * 0.2 * sqrt(dot(amp, vec3(0.333)));
  c = clamp(c + (4.0 * c - (n + s + e + w)) * k, 0.0, 1.0);
  // TPDF dither, +/- 1 LSB of 8-bit, so dark gradients never band.
  float d = hash(fc + uFrame) + hash(fc * 1.37 + 17.0 + uFrame) - 1.0;
  c += d / 255.0;
  fragColor = vec4(c, 1.0);
}
