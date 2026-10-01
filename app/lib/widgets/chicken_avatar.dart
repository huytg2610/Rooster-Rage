import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rooster_core/rooster_core.dart';

import '../game/render/chicken_painter.dart';

/// One shared, throttled clock for every menu avatar.
///
/// Menu idle animations don't need 60 fps: a single 24 fps timer drives
/// repaints (no widget rebuilds) and stops when no avatar is on screen.
class AvatarClock extends ChangeNotifier {
  static final instance = AvatarClock._();
  AvatarClock._();

  static const fps = 24;
  final _sw = Stopwatch()..start();
  Timer? _timer;

  double get time => _sw.elapsedMicroseconds / 1e6;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _timer ??= Timer.periodic(
      const Duration(microseconds: 1000000 ~/ fps),
      (_) => notifyListeners(),
    );
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }
}

/// Animated chicken for menus (lobby, reveal, results, roster).
class ChickenAvatar extends StatelessWidget {
  final ChickenInstance chicken;
  final Color slotColor;
  final double size;
  final FState state;
  final bool faceRight;

  const ChickenAvatar({
    super.key,
    required this.chicken,
    required this.slotColor,
    this.size = 72,
    this.state = FState.idle,
    this.faceRight = true,
  });

  // ChickenLook caches derived colors per instance — reuse them.
  static final _looks = <(String, Variant, Rarity, int), ChickenLook>{};

  static ChickenLook lookFor(ChickenInstance c, Color slot) {
    final key = (c.classId, c.variant, c.rarity, slot.toARGB32());
    if (_looks.length > 128) _looks.clear();
    return _looks[key] ??= ChickenLook(
      classId: c.classId,
      variant: c.variant,
      rarity: c.rarity,
      slotColor: slot,
    );
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _AvatarPainter(lookFor(chicken, slotColor), state, faceRight),
      ),
    ),
  );
}

class _AvatarPainter extends CustomPainter {
  final ChickenLook look;
  final FState state;
  final bool faceRight;

  _AvatarPainter(this.look, this.state, this.faceRight)
    : super(repaint: AvatarClock.instance);

  @override
  void paint(Canvas canvas, Size size) {
    final t = AvatarClock.instance.time;
    final scale = size.height / (ChickenPainter.height * 1.45);
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.9);
    canvas.scale(scale);
    ChickenPainter.paint(
      canvas,
      look,
      ChickenPose(
        state: state,
        stateTime: t % 2,
        stateDur: 2,
        time: t,
        faceRight: faceRight,
        speed01: state == FState.run ? 0.8 : 0,
        heavyCharge01: 0,
        comboStep: 1,
        flags: 0,
        hitFlash: 0,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      !identical(old.look, look) ||
      old.state != state ||
      old.faceRight != faceRight;
}
