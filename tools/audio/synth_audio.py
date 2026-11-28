"""Synthesise LANTERN's audio procedurally (M10). Everything here is
generated from noise and sine waves, so it is CC0 by construction: no
recordings, no third-party samples.

Usage: python3 -I tools/audio/synth_audio.py <out_dir>

Writes 22.05 kHz mono 16-bit WAV files:
  rain_loop.wav    20 s seamless: light rain on a pool, fine hiss plus
                   hundreds of tiny drop plinks of varied pitch and level
  stream_loop.wav  20 s seamless: slow water burble, band-passed noise with
                   wandering resonances and occasional bubble chirps
  firefly.wav      a soft glassy chime (collecting a firefly)
  knock.wav        a dull wooden knock on stone (collision)
  rustle.wav       a wet paper/leaf rustle (a leaf smothers the lantern)
  finale.wav       a slow, soft rising chord (the run is won)
"""
import os
import struct
import sys
import wave

import numpy as np

SR = 22050
rng = np.random.default_rng(2026)


def write(path, x, peak=0.8):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print('wrote', path, f'{len(x) / SR:.1f} s', os.path.getsize(path), 'bytes')


def one_pole_lp(x, fc):
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def bandpass(x, lo, hi):
    """FFT band-pass with soft edges (fine for offline synthesis)."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    X = np.fft.rfft(x)
    w = 1 / (1 + (lo / np.maximum(f, 1)) ** 4) * 1 / (1 + (f / hi) ** 4)
    return np.fft.irfft(X * w, n)


def seamless(x, fade_s=1.0):
    """Crossfade the tail into the head so the loop has no seam."""
    k = int(fade_s * SR)
    head, tail = x[:k].copy(), x[-k:].copy()
    t = np.linspace(0, 1, k)
    x = x[:-k].copy()
    x[:k] = head * t + tail * (1 - t)
    return x


def drop(n, f0, decay):
    t = np.arange(n) / SR
    # A water drop: a short pitch-rising bubble resonance.
    f = f0 * (1 + 0.6 * t / (t[-1] + 1e-9))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / decay)


def rain_loop(seconds=20.0):
    n = int((seconds + 1.0) * SR)
    # Fine hiss: pink-ish noise, high-passed, gently swelling.
    white = rng.standard_normal(n)
    hiss = bandpass(white, 900, 9000)
    hiss *= 0.12 * (1 + 0.15 * np.sin(2 * np.pi * np.arange(n) / SR / 7.3))
    out = hiss
    # Plinks: ~45 drops per second, mostly faint, a few closer and louder.
    count = int(45 * (seconds + 1))
    for _ in range(count):
        at = rng.integers(0, n - 4000)
        f0 = rng.uniform(1300, 4200)
        dec = rng.uniform(0.006, 0.02)
        length = int(dec * 8 * SR)
        amp = rng.pareto(3.0) * 0.06 + 0.01
        out[at:at + length] += amp * drop(length, f0, dec)
    return seamless(out)


def stream_loop(seconds=20.0):
    n = int((seconds + 1.0) * SR)
    white = rng.standard_normal(n)
    # Low burble: noise through a few slowly wandering resonances.
    t = np.arange(n) / SR
    out = np.zeros(n)
    for centre, width, rate in [(260, 120, 0.13), (520, 200, 0.21), (900, 300, 0.17)]:
        band = bandpass(white, centre - width, centre + width)
        env = 0.5 + 0.5 * np.sin(2 * np.pi * rate * t + rng.uniform(0, 6.28))
        out += band * (0.4 + 0.6 * env)
    out = one_pole_lp(out, 2500) * 0.6
    # Occasional bubble chirps.
    for _ in range(int(3 * (seconds + 1))):
        at = rng.integers(0, n - 6000)
        f0 = rng.uniform(300, 900)
        dec = rng.uniform(0.02, 0.05)
        length = int(dec * 6 * SR)
        out[at:at + length] += 0.08 * drop(length, f0, dec)
    return seamless(out)


def firefly():
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    tone = (np.sin(2 * np.pi * 1318.5 * t) * 0.6 + np.sin(2 * np.pi * 1975.5 * t) * 0.3 +
            np.sin(2 * np.pi * 2637 * t) * 0.15)
    env = (1 - np.exp(-t / 0.004)) * np.exp(-t / 0.45)
    return tone * env


def knock():
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 170 * t) * np.exp(-t / 0.06) + 0.5 * np.sin(2 * np.pi * 410 * t) * np.exp(-t / 0.03)
    click = bandpass(rng.standard_normal(n), 800, 4000) * np.exp(-t / 0.004) * 0.6
    return body + click


def rustle():
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    noise = bandpass(rng.standard_normal(n), 1500, 7000)
    # Crinkles: noise gated by a jittery envelope.
    gate = np.repeat(rng.uniform(0.2, 1.0, n // 200 + 1), 200)[:n]
    env = np.sin(np.pi * np.clip(t / t[-1], 0, 1)) ** 1.5
    return noise * gate * env


def finale():
    n = int(4.0 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        start = int(k * 0.35 * SR)
        tt = t[:n - start]
        out[start:] += np.sin(2 * np.pi * f * tt) * (1 - np.exp(-tt / 0.08)) * np.exp(-tt / 1.6) * (0.5 - 0.06 * k)
    return out


def fade_out(x, ms=10):
    """One-shots end on silence, so stopping them cannot click."""
    k = int(ms / 1000 * SR)
    x = x.copy()
    x[-k:] *= np.linspace(1, 0, k)
    return x


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    write(os.path.join(out_dir, 'rain_loop.wav'), rain_loop(), 0.7)
    write(os.path.join(out_dir, 'stream_loop.wav'), stream_loop(), 0.7)
    write(os.path.join(out_dir, 'firefly.wav'), fade_out(firefly()), 0.6)
    write(os.path.join(out_dir, 'knock.wav'), fade_out(knock()), 0.8)
    write(os.path.join(out_dir, 'rustle.wav'), fade_out(rustle()), 0.6)
    write(os.path.join(out_dir, 'finale.wav'), fade_out(finale(), 200), 0.6)


if __name__ == '__main__':
    main(sys.argv[1])
