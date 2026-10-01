import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:rooster_core/rooster_core.dart';

import '../net/snapshot_buffer.dart';
import '../ui/theme.dart';
import 'picture_cache.dart';
import 'projection.dart';
import 'render/chicken_painter.dart';
import 'render/chicken_sprite.dart';
import 'rooster_game.dart';

/// Y-sorted world objects: chickens, fences, pillars, buckets.
class EntityLayer extends Component with HasGameReference<RoosterGame> {
  final ArenaDef arena;
  final bool underGround; // draws chickens falling off the far edge
  EntityLayer(this.arena, {this.underGround = false})
    : super(priority: underGround ? -1 : 10);

  final _fill = Paint();
  final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..color = RC.ink;
  final _looks = <int, ChickenLook>{};
  final _sprites = <int, ChickenSprite>{};
  // Fences / pillars / buckets never change except bucket spill state.
  final _static = PictureCache();

  @override
  void onRemove() {
    _static.dispose();
    for (final s in _sprites.values) {
      s.dispose();
    }
    _sprites.clear();
    super.onRemove();
  }

  final _faceRight = <int, bool>{};

  @override
  void render(Canvas canvas) {
    final frame = game.frame;
    if (frame == null) return;
    if (!underGround) ChickenSprite.adapt(game.fps);
    final items = <(double, void Function())>[];
    for (final f in frame.fighters) {
      final falling = f.s.state == FState.falling;
      final behind = falling && f.y < 0;
      if (underGround != behind) continue;
      if (!underGround) {
        items.add((f.y, () => _chicken(canvas, f)));
      } else {
        _chicken(canvas, f);
      }
    }
    if (underGround) return;

    for (final (i, w) in arena.walls.indexed) {
      items.add((
        (w.ay + w.by) / 2,
        () => _static.draw(canvas, ('fence', i), (c) => _fence(c, w)),
      ));
    }
    var bucketI = 0;
    for (final (pi, d) in arena.props.indexed) {
      if (d.type == PropType.pillar) {
        items.add((
          d.y,
          () => _static.draw(canvas, ('pillar', pi), (c) => _pillar(c, d)),
        ));
      } else if (d.type == PropType.bucket) {
        final i = bucketI++;
        final spilled =
            i < game.latestProps.bucketsSpilled.length &&
            game.latestProps.bucketsSpilled[i];
        items.add((
          d.y,
          () => _static.draw(canvas, (
            'bucket',
            pi,
            spilled,
          ), (c) => _bucket(c, d, spilled)),
        ));
      }
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final it in items) {
      it.$2();
    }
  }

  ChickenLook _look(FighterView f) => _looks.putIfAbsent(
    f.id,
    () => ChickenLook(
      classId: f.info.classId,
      variant: f.info.variant,
      rarity: f.info.rarity,
      slotColor: Color(slotColors[f.info.slot % slotColors.length]),
    ),
  );

  void _chicken(Canvas canvas, FighterView f) {
    final s = f.s;
    var alpha = 1.0;
    var scale = 1.0;
    var sink = 0.0;
    // Survival: a faking troll's corpse fades like a real one (to others).
    final fakeOut = s.state == FState.fakeDead &&
        s.has(FFlag.out) &&
        f.id != game.localId;
    if (s.state == FState.dead || fakeOut) {
      final left = fakeOut ? Tuning.respawnTime - f.stateTime : s.respawnTimer;
      if (left < 0.4) alpha = (left / 0.4).clamp(0.0, 1.0);
      if (alpha <= 0) return;
    } else if (s.state == FState.falling) {
      final k = (f.stateTime / Tuning.fallTime).clamp(0.0, 1.0);
      scale = 1 - 0.55 * k;
      sink = k * k * 90;
      alpha = 1 - k * 0.7;
    }

    final ground = Proj.p(f.x, f.y);
    if (s.state != FState.falling) {
      final shadowW = 30 * (1 - (f.z / 3).clamp(0.0, 0.5));
      _fill.color = const Color(0x44000000);
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: shadowW, height: shadowW * 0.4),
        _fill,
      );
      if (f.id == game.localId) {
        // Own chicken ring.
        final ring = _ring
          ..color = Color(slotColors[f.info.slot % slotColors.length]);
        canvas.drawOval(
          Rect.fromCenter(center: ground, width: 42, height: 17),
          ring,
        );
      }
    }

    final cos = math.cos(f.facing);
    final prev = _faceRight[f.id] ?? true;
    final right = cos.abs() < 0.2 ? prev : cos > 0;
    _faceRight[f.id] = right;

    final speed = math.sqrt(s.vx * s.vx + s.vy * s.vy);
    final pose = ChickenPose(
      state: s.state,
      stateTime: f.stateTime,
      stateDur: s.stateDur,
      time: game.clock,
      faceRight: right,
      speed01: (speed / 6).clamp(0.0, 1.0),
      heavyCharge01: (s.heavyCharge / Tuning.heavyMaxCharge).clamp(0.0, 1.0),
      comboStep: s.comboStep,
      flags: s.flags,
      hitFlash: game.hitFlash(f.id),
      shield01: s.shield / Tuning.shieldMax,
    );

    canvas.save();
    canvas.translate(ground.dx, ground.dy - f.z * Proj.px + sink);
    if (scale != 1) canvas.scale(scale);
    if (alpha < 1) {
      // Bounded: an unbounded layer is a full-screen offscreen texture per
      // fading chicken (heavy GPU memory on phones).
      canvas.saveLayer(
        _fadeBounds,
        _fade..color = Color.fromRGBO(255, 255, 255, alpha),
      );
    }
    _sprites
        .putIfAbsent(f.id, ChickenSprite.new)
        .paint(canvas, _look(f), pose);
    if (alpha < 1) canvas.restore();
    canvas.restore();
  }

  static final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  static final _fade = Paint();
  static const _fadeBounds = Rect.fromLTRB(-90, -120, 90, 40);
  static final _post = Paint()
    ..color = const Color(0xFF9C7A3C)
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round;
  static final _rail = Paint()
    ..color = const Color(0xFFC9A05A)
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round;
  static final _outline = Paint()
    ..color = RC.ink
    ..strokeWidth = 7
    ..strokeCap = StrokeCap.round;

  void _fence(Canvas canvas, WallSeg w) {
    final a0 = Proj.p(w.ax, w.ay), b0 = Proj.p(w.bx, w.by);
    const h = 22.0;
    final post = _post, rail = _rail, outline = _outline;
    for (final y in [h * 0.4, h * 0.85]) {
      canvas.drawLine(a0.translate(0, -y), b0.translate(0, -y), outline);
      canvas.drawLine(a0.translate(0, -y), b0.translate(0, -y), rail);
    }
    for (final p in [a0, Offset.lerp(a0, b0, 0.5)!, b0]) {
      canvas.drawLine(p, p.translate(0, -h), outline);
      canvas.drawLine(p, p.translate(0, -h), post);
    }
  }

  void _pillar(Canvas canvas, PropDef d) {
    final c = Proj.p(d.x, d.y);
    final w = Proj.sx(d.radius * 2);
    final h = arena.voidKind == VoidKind.sky ? 46.0 : 58.0;
    final body = Rect.fromLTWH(c.dx - w / 2, c.dy - h, w, h);
    _fill.color = const Color(0x44000000);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: w * 1.3, height: w * 0.5),
      _fill,
    );
    _fill.color = arena.voidKind == VoidKind.sky
        ? const Color(0xFF8E4A36)
        : const Color(0xFF8C8577);
    canvas.drawRect(body, _fill);
    _fill.color = const Color(0x22FFFFFF);
    canvas.drawRect(Rect.fromLTWH(body.left + 3, body.top, w * 0.25, h), _fill);
    canvas.drawRect(body, _stroke);
    final cap = Rect.fromCenter(
      center: body.topCenter,
      width: w * 1.2,
      height: w * 0.45,
    );
    _fill.color = arena.voidKind == VoidKind.sky
        ? const Color(0xFF5E2E22)
        : const Color(0xFFB0A898);
    canvas.drawOval(cap, _fill);
    canvas.drawOval(cap, _stroke);
  }

  void _bucket(Canvas canvas, PropDef d, bool spilled) {
    final c = Proj.p(d.x, d.y);
    final w = Proj.sx(d.radius * 2);
    _fill.color = const Color(0x44000000);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: w * 1.2, height: w * 0.45),
      _fill,
    );
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (spilled) canvas.rotate(math.pi / 2.2);
    final body = Path()
      ..moveTo(-w / 2, -w * 1.05)
      ..lineTo(w / 2, -w * 1.05)
      ..lineTo(w * 0.4, 0)
      ..lineTo(-w * 0.4, 0)
      ..close();
    _fill.color = const Color(0xFF7A8A99);
    canvas.drawPath(body, _fill);
    _fill.color = const Color(0xFF5E6B77);
    canvas.drawRect(Rect.fromLTWH(-w * 0.47, -w * 0.75, w * 0.94, 3), _fill);
    canvas.drawRect(Rect.fromLTWH(-w * 0.43, -w * 0.3, w * 0.86, 3), _fill);
    canvas.drawPath(body, _stroke);
    if (!spilled) {
      _fill.color = const Color(0xFF4AA3E8);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, -w * 1.05),
          width: w,
          height: w * 0.35,
        ),
        _fill,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, -w * 1.05),
          width: w,
          height: w * 0.35,
        ),
        _stroke,
      );
    }
    canvas.restore();
  }
}
