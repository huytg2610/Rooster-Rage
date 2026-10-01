import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWasm;

import 'chicken_painter.dart';

/// Cached drawing ("sprite") of one on-screen chicken.
///
/// [ChickenPainter] builds ~35 Paths and 60-100 draw calls per chicken.
/// Doing that every display frame (120 Hz on many phones) churned ~37K
/// paths/s. Here the pose runs on an animation clock of [fps]: the
/// chicken is re-recorded into a [Picture] only when its quantized pose
/// changes, and every other frame replays that picture. Position, jump
/// height, scale and fade stay per-frame (applied by the caller), so motion
/// stays smooth — only limbs/face/effects step at [fps].
///
/// Measured (8 chickens, same match, sprite on vs off): paths built per
/// frame 260 → 95, frame CPU -9% at full speed and -13% (p95 -22%) with a
/// 4x-throttled CPU. Skia still rasterizes the replayed vectors every frame;
/// a bitmap sprite would avoid that, but CanvasKit's Picture.toImageSync
/// reads pixels back from the GPU, far too slow to do 200 times a second.
class ChickenSprite {
  /// Animation clock. Drops to 12 when the display can't keep up, so a slow
  /// phone re-records (and Skia re-tessellates) half as often.
  static double fps = 24;

  /// Picks the animation clock from the smoothed render rate, with
  /// hysteresis so it doesn't flip back and forth.
  static void adapt(double renderFps) {
    if (fps > 12 && renderFps < 38) {
      fps = 12;
    } else if (fps < 24 && renderFps > 50) {
      fps = 24;
    }
  }

  Picture? _pic;
  Picture? _prev;
  Object? _key;

  /// Number of recordings so far (tests / diagnostics).
  int recordings = 0;

  void paint(Canvas canvas, ChickenLook look, ChickenPose pose) {
    final tf = (pose.time * fps).floor();
    final flash = (pose.hitFlash.clamp(0.0, 1.0) * 3).ceil();
    final speed = (pose.speed01.clamp(0.0, 1.0) * 8).round();
    final charge = (pose.heavyCharge01.clamp(0.0, 1.0) * 16).round();
    final shield = (pose.shield01.clamp(0.0, 1.0) * 6).ceil();
    final key = (
      look,
      pose.state,
      tf,
      pose.comboStep,
      pose.flags,
      pose.faceRight,
      flash,
      speed,
      charge,
      shield,
    );
    var pic = _pic;
    if (pic == null || key != _key) {
      pic = _record(look, pose, tf, flash, speed, charge, shield);
      // Free the picture from two recordings ago: the last one may still
      // be referenced by the frame being rasterized. skwasm (opt-in wasm
      // builds) must never free by hand — its GC finalizer handles it.
      if (!kIsWasm) _prev?.dispose();
      _prev = _pic;
      _pic = pic;
      _key = key;
    }
    canvas.drawPicture(pic);
  }

  Picture _record(
    ChickenLook look,
    ChickenPose pose,
    int tf,
    int flash,
    int speed,
    int charge,
    int shield,
  ) {
    recordings++;
    final tq = tf / fps;
    // Shift stateTime onto the same clock so both step together.
    final st = pose.stateTime - (pose.time - tq);
    final rec = PictureRecorder();
    ChickenPainter.paint(
      Canvas(rec),
      look,
      ChickenPose(
        state: pose.state,
        stateTime: st < 0 ? 0 : st,
        stateDur: pose.stateDur,
        time: tq,
        faceRight: pose.faceRight,
        speed01: speed / 8,
        heavyCharge01: charge / 16,
        comboStep: pose.comboStep,
        flags: pose.flags,
        hitFlash: flash / 3,
        shield01: shield / 6,
      ),
    );
    return rec.endRecording();
  }

  void dispose() {
    if (!kIsWasm) {
      _prev?.dispose();
      _pic?.dispose();
    }
    _prev = _pic = null;
    _key = null;
  }
}
