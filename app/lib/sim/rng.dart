/// Deterministic 32-bit PRNG (xorshift32 with a murmur-style seed scramble).
///
/// Uses only 32-bit masked shifts, xors and a split 16-bit multiply, so it
/// produces identical sequences on native (64-bit ints) and web (JS numbers,
/// 53-bit mantissa). That keeps seeded runs and captures reproducible on both.
class Rng {
  Rng(int seed) : _s = _scramble(seed);

  int _s;

  /// 32-bit multiply, low 32 bits, exact on native and web.
  static int imul(int a, int b) {
    final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
    final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
    final mid = ((ah * bl + al * bh) & 0xFFFF) * 65536;
    return (al * bl + mid) % 4294967296;
  }

  static int _scramble(int seed) {
    var z = (seed ^ 0x9E3779B9) & 0xFFFFFFFF;
    z = imul(z ^ (z >> 16), 0x45D9F3B);
    z = imul(z ^ (z >> 16), 0x45D9F3B);
    z = (z ^ (z >> 16)) & 0xFFFFFFFF;
    return z == 0 ? 0x6D2B79F5 : z;
  }

  int nextU32() {
    var x = _s;
    x = (x ^ ((x * 8192) % 4294967296)) & 0xFFFFFFFF; // x ^= x << 13
    x = (x ^ (x >> 17)) & 0xFFFFFFFF;
    x = (x ^ ((x * 32) % 4294967296)) & 0xFFFFFFFF; // x ^= x << 5
    _s = x;
    return x;
  }

  /// Uniform in [0, 1).
  double next() => nextU32() / 4294967296.0;

  double range(double a, double b) => a + (b - a) * next();

  int intBelow(int n) => (next() * n).floor();

  bool chance(double p) => next() < p;

  /// A child generator with an independent stream.
  Rng fork(int salt) => Rng(nextU32() ^ imul(salt & 0xFFFFFFFF, 0x27D4EB2D));
}
