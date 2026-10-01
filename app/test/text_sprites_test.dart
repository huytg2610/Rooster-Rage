import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster_rage/game/projection.dart';
import 'package:rooster_rage/game/text_sprites.dart';

void main() {
  final style = Styles.outlined(20, const Color(0xFFE8412C));

  void frame(void Function(Canvas c) draw) {
    final rec = PictureRecorder();
    draw(Canvas(rec));
    rec.endRecording();
  }

  test('a label is rasterized once, then reused at any scale and fade', () {
    final labels = TextSprites();
    for (var i = 0; i < 60; i++) {
      frame((c) {
        c.scale(0.6 + i / 50);
        labels.paint(
          c,
          'KO!',
          style,
          const Offset(10, 10),
          opacity: 1 - i / 60,
        );
      });
    }
    expect(labels.renders, 1);
    labels.dispose();
  });

  test('labels survive generations while in use; idle ones are re-made', () {
    final labels = TextSprites();
    for (var round = 0; round < 3; round++) {
      frame((c) {
        labels.paint(c, 'BẠN', style, Offset.zero);
        for (var i = 0; i < TextSprites.generation; i++) {
          labels.paint(c, 'r$round-$i', style, Offset.zero);
        }
      });
    }
    // 'BẠN' once + 3 rounds of fresh labels.
    expect(labels.renders, 1 + 3 * TextSprites.generation);
    frame((c) => labels.paint(c, 'r0-0', style, Offset.zero));
    expect(labels.renders, 2 + 3 * TextSprites.generation);
    labels.dispose();
  });

  test('invisible labels draw nothing', () {
    final labels = TextSprites();
    frame((c) => labels.paint(c, 'x', style, Offset.zero, opacity: 0));
    expect(labels.renders, 0);
  });
}
