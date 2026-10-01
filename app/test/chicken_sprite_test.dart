import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster_core/rooster_core.dart';
import 'package:rooster_rage/game/render/chicken_painter.dart';
import 'package:rooster_rage/game/render/chicken_sprite.dart';

void main() {
  const look = ChickenLook(
    classId: 'samurai',
    variant: Variant.fire,
    rarity: Rarity.common,
    slotColor: Color(0xFFE8412C),
  );

  void frames(ChickenSprite s, double from, double to, FState state) {
    final rec = PictureRecorder();
    final canvas = Canvas(rec);
    // 120 Hz display.
    for (var t = from; t < to; t += 1 / 120) {
      s.paint(
        canvas,
        look,
        ChickenPose(state: state, time: t, stateTime: t - from, speed01: 0.7),
      );
    }
    rec.endRecording();
  }

  test('re-records at the animation clock, not the display rate', () {
    final s = ChickenSprite();
    frames(s, 10, 11, FState.run);
    // One second at 120 Hz = 120 frames, ~24 recordings.
    expect(s.recordings, inInclusiveRange(24, 26));
    s.dispose();
  });

  test('animation clock halves on slow displays, with hysteresis', () {
    addTearDown(() => ChickenSprite.fps = 24);
    ChickenSprite.adapt(60);
    expect(ChickenSprite.fps, 24);
    ChickenSprite.adapt(30);
    expect(ChickenSprite.fps, 12);
    ChickenSprite.adapt(45); // in the dead band: stays
    expect(ChickenSprite.fps, 12);
    ChickenSprite.adapt(55);
    expect(ChickenSprite.fps, 24);
  });

  test('a state change re-records immediately', () {
    final s = ChickenSprite();
    final rec = PictureRecorder();
    final canvas = Canvas(rec);
    s.paint(canvas, look, const ChickenPose(state: FState.idle, time: 5));
    s.paint(canvas, look, const ChickenPose(state: FState.idle, time: 5.001));
    expect(s.recordings, 1);
    s.paint(canvas, look, const ChickenPose(state: FState.block, time: 5.002));
    expect(s.recordings, 2);
    rec.endRecording();
    s.dispose();
  });

  test('every state and flag combination draws', () {
    final s = ChickenSprite();
    for (final st in FState.values) {
      for (final flags in [0, FFlag.rage, FFlag.invuln | FFlag.burning]) {
        frames(s, 3, 3.2, st);
        final rec = PictureRecorder();
        s.paint(
          Canvas(rec),
          look,
          ChickenPose(
            state: st,
            time: 4,
            stateTime: 0.1,
            stateDur: 0.3,
            flags: flags,
            hitFlash: 0.5,
            heavyCharge01: 0.6,
          ),
        );
        rec.endRecording();
      }
    }
    s.dispose();
  });
}
