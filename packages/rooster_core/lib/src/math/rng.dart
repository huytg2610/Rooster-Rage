/// Deterministic xorshift32 PRNG.
///
/// Uses only shifts/xors masked to 32 bits so it produces identical
/// sequences on the Dart VM (64-bit ints) and on the web (JS numbers).
class Rng {
  int _s;

  Rng(int seed) : _s = _init(seed);

  /// Scrambles the seed (murmur3 fmix32) so small/sequential seeds don't
  /// produce correlated first outputs.
  static int _init(int seed) {
    var h = (seed ^ 0x9E3779B9) & 0xFFFFFFFF;
    h ^= h >> 16;
    h = _mul32(h, 0x85EBCA6B);
    h ^= h >> 13;
    h = _mul32(h, 0xC2B2AE35);
    h ^= h >> 16;
    return h == 0 ? 0x9E3779B9 : h;
  }

  /// 32-bit multiply that stays exact on the web (< 2^53 intermediates).
  static int _mul32(int a, int b) {
    final lo = (a & 0xFFFF) * b;
    final hi = (((a >> 16) & 0xFFFF) * b) & 0xFFFF;
    return (lo + hi * 0x10000) & 0xFFFFFFFF;
  }

  int nextU32() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _s = x & 0xFFFFFFFF;
    return _s;
  }

  /// Uniform in [0, 1).
  double nextDouble() => nextU32() / 4294967296.0;

  /// Uniform int in [0, max).
  int nextInt(int max) => (nextDouble() * max).floor();

  double range(double a, double b) => a + (b - a) * nextDouble();

  bool chance(double p) => nextDouble() < p;

  T pick<T>(List<T> list) => list[nextInt(list.length)];

  /// Picks an index proportionally to [weights]. Returns -1 if all are zero.
  int weightedIndex(List<double> weights) {
    var total = 0.0;
    for (final w in weights) {
      if (w > 0) total += w;
    }
    if (total <= 0) return -1;
    var r = nextDouble() * total;
    for (var i = 0; i < weights.length; i++) {
      final w = weights[i];
      if (w <= 0) continue;
      if (r < w) return i;
      r -= w;
    }
    return weights.lastIndexWhere((w) => w > 0);
  }
}
