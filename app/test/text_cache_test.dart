import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster_rage/game/projection.dart';

void main() {
  final style = Styles.outlined(12, const Color(0xFFFFFFFF));

  void fill(TextCache cache, String prefix, int n) {
    for (var i = 0; i < n; i++) {
      cache.get('$prefix$i', style);
    }
  }

  test('hits return the same painter', () {
    final cache = TextCache();
    expect(identical(cache.get('a', style), cache.get('a', style)), isTrue);
  });

  test('a painter used every generation survives rotations', () {
    final cache = TextCache();
    final a = cache.get('a', style);
    for (var round = 0; round < 3; round++) {
      fill(cache, 'r$round-', TextCache.generation);
      expect(identical(cache.get('a', style), a), isTrue);
      expect(a.debugDisposed, isFalse);
    }
  });

  test('snapScale lands on few 1/8-octave steps', () {
    expect(TextCache.snapScale(1), closeTo(1, 1e-9));
    expect(TextCache.snapScale(1.03), closeTo(1, 1e-9));
    expect(TextCache.snapScale(1.07), closeTo(1.0905, 1e-3));
    expect(TextCache.snapScale(2), closeTo(2, 1e-9));
    // A smooth zoom from 1x to 2x hits only 9 distinct text sizes.
    final sizes = {
      for (var z = 1.0; z <= 2.0; z += 0.001)
        TextCache.snapScale(z).toStringAsFixed(6),
    };
    expect(sizes.length, 9);
  });

  test('a painter unused for two generations is disposed', () {
    final cache = TextCache();
    final a = cache.get('a', style);
    fill(cache, 'x', TextCache.generation); // 'a' moves to the old generation
    expect(a.debugDisposed, isFalse);
    fill(cache, 'y', TextCache.generation); // old generation freed
    expect(a.debugDisposed, isTrue);
    final again = cache.get('a', style);
    expect(identical(again, a), isFalse);
    expect(again.debugDisposed, isFalse);
  });
}
