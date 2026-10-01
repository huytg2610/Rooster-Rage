import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show FontWeight, TextStyle;
import 'package:rooster_core/rooster_core.dart';

import '../ui/theme.dart';
import 'projection.dart';
import 'rooster_game.dart';
import 'text_sprites.dart';

/// Name tags + mini bars above every chicken (always on top of the world).
class OverheadLayer extends Component with HasGameReference<RoosterGame> {
  OverheadLayer() : super(priority: 30);

  final _labels = TextSprites();

  @override
  void onRemove() {
    _labels.dispose();
    super.onRemove();
  }

  final _fill = Paint();

  @override
  void render(Canvas canvas) {
    final frame = game.frame;
    if (frame == null) return;
    for (final f in frame.fighters) {
      final s = f.s;
      final head = Proj.p(f.x, f.y, f.z) + const Offset(0, -50);
      final color = Color(slotColors[f.info.slot % slotColors.length]);
      // A fake-dead troll must look exactly like a real corpse to others.
      final fake = s.state == FState.fakeDead && f.id != game.localId;
      final ownFake = s.state == FState.fakeDead && f.id == game.localId;
      if (s.has(FFlag.out) && !ownFake) {
        // Survival: knocked out for good. A faking troll mimics the corpse
        // timer so others can't tell.
        final left = s.state == FState.fakeDead
            ? Tuning.respawnTime - f.stateTime
            : s.respawnTimer;
        if (left > 0.4) {
          _labels.paint(
            canvas,
            'LOẠI',
            _style(11, RC.red),
            Proj.p(f.x, f.y) + const Offset(0, -30),
          );
        }
        continue;
      }
      if (s.state == FState.dead || fake) {
        final left = fake
            ? Tuning.respawnFor(s.deaths + 1) - f.stateTime
            : s.respawnTimer;
        if (left > 0.2) {
          _labels.paint(
            canvas,
            'hồi sinh ${left.ceil()}',
            _style(10, RC.muted),
            Proj.p(f.x, f.y) + const Offset(0, -30),
          );
        }
        continue;
      }
      if (s.state == FState.falling) continue;
      final mine = f.id == game.localId;
      _labels.paint(
        canvas,
        mine ? 'BẠN' : f.info.name,
        _style(mine ? 12 : 10, color),
        head,
        vAnchor: 1,
      );
      const w = 38.0, h = 5.0;
      final r = Rect.fromLTWH(head.dx - w / 2, head.dy + 2, w, h);
      _fill.color = const Color(0xCC1B100A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.inflate(1.5), const Radius.circular(3)),
        _fill,
      );
      _fill.color = RC.hp;
      canvas.drawRect(
        Rect.fromLTWH(r.left, r.top, w * (s.hp / f.info.maxHp).clamp(0, 1), h),
        _fill,
      );
      // Balance sliver: shows how close to being stunned they are.
      _fill.color = RC.balance;
      canvas.drawRect(
        Rect.fromLTWH(
          r.left,
          r.bottom,
          w * (s.balance / f.info.maxBalance).clamp(0, 1),
          2,
        ),
        _fill,
      );
      if (s.shieldBroken) {
        _brokenShield(canvas, Offset(r.left - 7, r.center.dy));
      }
      if (s.rage >= Tuning.rageMax || s.has(FFlag.rage)) {
        _fill.color = RC.rage;
        canvas.drawCircle(Offset(r.right + 6, r.center.dy), 3.5, _fill);
      }
    }
  }

  final _badge = Path()
    ..moveTo(-4, -4.5)
    ..lineTo(4, -4.5)
    ..lineTo(4, 0)
    ..quadraticBezierTo(4, 3.5, 0, 5.5)
    ..quadraticBezierTo(-4, 3.5, -4, 0)
    ..close();
  final _crack = Path()
    ..moveTo(1.5, -4.5)
    ..lineTo(-0.5, -1)
    ..lineTo(1, 1)
    ..lineTo(-1, 4);
  final _ink = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = RC.ink;

  /// Grey cracked shield: this chicken can't guard right now.
  void _brokenShield(Canvas canvas, Offset c) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    _fill.color = const Color(0xFF8A96A0);
    canvas.drawPath(_badge, _fill);
    canvas.drawPath(_badge, _ink);
    canvas.drawPath(_crack, _ink);
    canvas.restore();
  }

  // No blur on the tag shadow: blurred text shadows are costly per frame.
  TextStyle _style(double size, Color c) =>
      Styles.outlined(size, c, FontWeight.w900, 1.2);
}
