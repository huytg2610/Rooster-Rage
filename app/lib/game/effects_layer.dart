import 'dart:math' as math;
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:rooster_core/rooster_core.dart';

import '../ui/theme.dart';
import 'projection.dart';
import 'rooster_game.dart';
import 'text_sprites.dart';

enum _K { dot, feather, star, ring, text, drop, vortex, wave, chevron }

class _P {
  _K kind;
  double x, y, vx, vy, life, max, size, rot, vr, gravity;
  Color color;
  String? text;
  _P(
    this.kind,
    this.x,
    this.y, {
    this.vx = 0,
    this.vy = 0,
    this.max = 0.6,
    this.size = 4,
    this.rot = 0,
    this.vr = 0,
    this.gravity = 0,
    required this.color,
    this.text,
    double delay = 0,
  }) : life = -delay;
}

// Action colours, matching the chicken overlays: warm = attack,
// blue = guard, gold = push.
const _guardC = Color(0xFF4FB8FF);
const _pushC = Color(0xFFFFC21A);

/// Juice: feathers, impact stars, damage numbers, shockwaves, callouts.
class EffectsLayer extends Component with HasGameReference<RoosterGame> {
  EffectsLayer() : super(priority: 20);

  final _ps = <_P>[];
  final _rng = math.Random(7);
  final _fill = Paint();
  final _line = Paint()..style = PaintingStyle.stroke;
  final _labels = TextSprites();

  @override
  void onRemove() {
    _labels.dispose();
    super.onRemove();
  }

  double _r(double a, double b) => a + _rng.nextDouble() * (b - a);

  void onEvent(SimEvent e) {
    final g = game;
    final at = Proj.p(e.x, e.y, 0.6);
    final mine = e.a == g.localId || e.b == g.localId;
    switch (e.type) {
      case EvType.hit:
        final blocked = e.flags & HitFlag.blocked != 0;
        // Crow / rage-roar shove (older hosts: zero damage, unblocked).
        if (e.flags & HitFlag.shove != 0 || (!blocked && e.v <= 0)) {
          _pushed(e, mine);
          return;
        }
        g.flashHit(e.b);
        final victimColor = Color(
          ChickenClasses.byId(g.info(e.b)?.classId ?? 'samurai').color,
        );
        if (blocked) {
          // Guarded: sparks instead of feathers, small chip number.
          final broke = e.flags & HitFlag.guardBreak != 0;
          _burst(at, 6, const Color(0xFF9FD8FF), _K.star, speed: 140);
          _ring(at.translate(0, -6), _guardC, 34);
          if (e.v > 0.4) {
            _add(
              _P(
                _K.text,
                at.dx,
                at.dy - 16,
                vy: -50,
                max: 0.6,
                size: 12,
                color: const Color(0xFF9FD8FF),
                text: e.v.round().toString(),
              ),
            );
          }
          _callout(
            at.translate(0, -38),
            broke ? 'VỠ KHIÊN!' : 'ĐỠ!',
            broke ? RC.red : const Color(0xFF9FD8FF),
            broke ? 20 : 14,
          );
          if (broke) {
            // Shield shards flying off.
            _burst(at.translate(0, -10), 10, _guardC, _K.feather, speed: 230);
            _ring(at.translate(0, -6), RC.red, 50);
          }
          if (broke) g.shake(mine ? 7 : 4);
          return;
        }
        final big =
            e.flags & (HitFlag.heavy | HitFlag.finisher | HitFlag.skill) != 0;
        _burst(
          at,
          big ? 9 : 5,
          victimColor,
          _K.feather,
          speed: big ? 220 : 150,
        );
        _add(
          _P(
            _K.star,
            at.dx,
            at.dy,
            max: 0.18,
            size: big ? 26 : 16,
            color: RC.cream,
          ),
        );
        if (e.v > 0.4) {
          final crit =
              e.flags & (HitFlag.crit | HitFlag.backstab | HitFlag.counter) !=
              0;
          _add(
            _P(
              _K.text,
              at.dx + _r(-8, 8),
              at.dy - 16,
              vy: -60,
              max: 0.8,
              size: crit ? 20 : 15,
              color: crit ? RC.gold : RC.cream,
              text: e.v.round().toString(),
            ),
          );
          final tag = e.flags & HitFlag.crit != 0
              ? 'CHÍ MẠNG!'
              : e.flags & HitFlag.backstab != 0
              ? 'ĐÁNH LÉN!'
              : e.flags & HitFlag.counter != 0
              ? 'PHẢN ĐÒN!'
              : null;
          if (tag != null) _callout(at.translate(0, -40), tag, RC.gold, 14);
        }
        if (big) {
          _ring(at, RC.cream, 60);
          _skid(e, 6);
          g.shake(mine ? 7 : 4);
        } else if (mine) {
          g.shake(2);
        }
      case EvType.ko:
        final c = Proj.p(e.x, e.y, 0.8);
        _burst(c, 16, RC.cream, _K.feather, speed: 260);
        _callout(c.translate(0, -30), 'KO!', RC.red, 30);
        if (e.flags == KoCause.ringOut && g.arena.voidKind == VoidKind.pond) {
          _splash(Proj.p(e.x, e.y));
        }
        g.addFeed(e);
        g.shake(mine ? 9 : 5);
      case EvType.fakeKo:
        final c = Proj.p(e.x, e.y, 0.8);
        _burst(c, 10, RC.cream, _K.feather, speed: 200);
        _callout(
          c.translate(0, -30),
          e.b == g.localId ? 'GIẢ CHẾT...' : 'KO!',
          e.b == g.localId ? const Color(0xFFB05CFF) : RC.red,
          30,
        );
        g.addFeed(e);
      case EvType.stun:
        _callout(at.translate(0, -34), 'CHOÁNG!', RC.gold, 16);
        _burst(at.translate(0, -20), 6, RC.gold, _K.star, speed: 90);
      case EvType.pickup:
        if (e.v.round() == FoodKind.heal.index) {
          _burst(at, 12, RC.hp, _K.star, speed: 140);
          _ring(at, const Color(0xFF6DDC6D), 50);
          _callout(
            at.translate(0, -30),
            '+30% MÁU',
            const Color(0xFF6DDC6D),
            e.a == g.localId ? 18 : 13,
          );
        } else {
          _burst(at, 8, RC.gold, _K.dot, speed: 120);
          if (e.a == g.localId) {
            _callout(at.translate(0, -30), '+THỂ LỰC', RC.gold, 14);
          }
        }
      case EvType.spill:
        _splash(Proj.p(e.x, e.y));
      case EvType.trap:
        _callout(at.translate(0, -30), 'BẬP!', RC.muted, 18);
        _burst(at, 8, const Color(0xFFD9D9D9), _K.dot, speed: 160);
        if (e.b == g.localId) g.shake(6);
      case EvType.skill:
        final skill =
            SkillId.values[e.v.round().clamp(0, SkillId.values.length - 1)];
        final color = switch (skill) {
          SkillId.flameKick => RC.orange,
          SkillId.shadowDash => const Color(0xFF2A2A40),
          SkillId.earthRooster => const Color(0xFFB5832F),
          SkillId.madRooster => RC.red,
          SkillId.fakeDeath => const Color(0xFFB05CFF),
          SkillId.stompChain => const Color(0xFF9E3B1E),
          SkillId.peckFlurry => RC.gold,
          SkillId.darkVortex => const Color(0xFF8A4DFF),
        };
        _burst(at, 12, color, _K.dot, speed: 200);
        if (skill == SkillId.madRooster) {
          _callout(at.translate(0, -40), 'ĐIÊN RỒI!', RC.red, 18);
        }
        if (skill == SkillId.flameKick) _ring(at, RC.orange, 50);
      case EvType.rage:
        _ring(at, RC.rage, 110);
        _ring(at, RC.gold, 70);
        _callout(at.translate(0, -44), 'NỘ!', RC.rage, 26);
        g.shake(mine ? 6 : 3);
      case EvType.crow:
        // The shove lands 0.15 s in; the ground wave shows its exact reach.
        final feet = Proj.p(e.x, e.y);
        final reach = Proj.sx(Tuning.crowRadius);
        _add(
          _P(
            _K.wave,
            feet.dx,
            feet.dy,
            max: 0.45,
            size: reach,
            color: _pushC,
            delay: 0.1,
          ),
        );
        for (var i = 0; i < 8; i++) {
          final ang = i * math.pi / 4 + 0.2;
          final dx = math.cos(ang), dy = math.sin(ang) * Proj.tilt;
          _add(
            _P(
              _K.chevron,
              feet.dx + dx * reach * 0.45,
              feet.dy + dy * reach * 0.45,
              vx: dx * 150,
              vy: dy * 150,
              max: 0.4,
              size: 7,
              rot: math.atan2(dy, dx),
              color: _pushC,
              delay: 0.12,
            ),
          );
        }
        _callout(at.translate(0, -46), 'Ò Ó O!', _pushC, 17);
      case EvType.respawn:
        _burst(Proj.p(e.x, e.y, 0.3), 10, RC.cream, _K.dot, speed: 100);
      case EvType.land:
        final c = Proj.p(e.x, e.y);
        _dust(c, e.v >= 2 ? 16 : (e.v > 1 ? 10 : 7));
        if (e.v >= 2) {
          _ring(c, const Color(0xFFB5832F), 150);
          g.shake(8);
        } else if (e.v > 1) {
          // Đông Tảo stomp.
          _ring(c, const Color(0xFF9E3B1E), 70);
          g.shake(mine ? 4 : 2);
        }
      case EvType.dodge:
        _dust(Proj.p(e.x, e.y), 5);
      case EvType.exhausted:
        _callout(at.translate(0, -36), 'HẾT HƠI!', RC.stamina, 14);
        _burst(at.translate(0, -20), 4, RC.blue, _K.drop, speed: 70);
      case EvType.surprise:
        _ring(at, const Color(0xFFB05CFF), 120);
        _burst(at, 18, const Color(0xFFB05CFF), _K.star, speed: 240);
        _callout(
          at.translate(0, -44),
          'BẤT NGỜ CHƯA!',
          const Color(0xFFE0B0FF),
          18,
        );
        g.shake(5);
      case EvType.vortex:
        final c = Proj.p(e.x, e.y);
        _add(
          _P(
            _K.vortex,
            c.dx,
            c.dy,
            max: e.v.clamp(0.2, 2.0).toDouble(),
            size: Proj.sx(Skills.vortexRadius),
            color: const Color(0xFF8A4DFF),
          ),
        );
      case EvType.healDrop:
        // A heart pops out of the fallen chicken: tell everyone.
        final c = Proj.p(e.x, e.y, 0.3);
        _ring(c, RC.hp, 46);
        _burst(c, 8, RC.hp, _K.star, speed: 120);
        _callout(c.translate(0, -26), '+MÁU', RC.hp, 13);
      case EvType.burst:
        final c = Proj.p(e.x, e.y, 0.3);
        _ring(c, const Color(0xFF8A4DFF), 150);
        _ring(c, const Color(0xFFE0B0FF), 90);
        _burst(c, 20, const Color(0xFF8A4DFF), _K.star, speed: 260);
        g.shake(7);
    }
  }

  /// Unit push direction on screen (attacker → victim), or null.
  Offset? _pushDir(SimEvent e) {
    final a = game.frame?.fighter(e.a);
    if (a == null) return null;
    final dx = e.x - a.x, dy = (e.y - a.y) * Proj.tilt;
    final len = math.sqrt(dx * dx + dy * dy);
    return len < 1e-3 ? null : Offset(dx / len, dy / len);
  }

  /// Shoved (crow / roar): gold chevrons streaming away from the shouter
  /// and dust at the feet — no feathers or damage, so it never reads as a
  /// hit.
  void _pushed(SimEvent e, bool mine) {
    final feet = Proj.p(e.x, e.y);
    final dir = _pushDir(e);
    if (dir != null) {
      for (var i = 0; i < 3; i++) {
        _add(
          _P(
            _K.chevron,
            feet.dx + dir.dx * (6 + i * 9),
            feet.dy - 14 + dir.dy * (6 + i * 9),
            vx: dir.dx * 170,
            vy: dir.dy * 170,
            max: 0.35 + i * 0.05,
            size: 8,
            rot: math.atan2(dir.dy, dir.dx),
            color: _pushC,
          ),
        );
      }
    }
    _skid(e, 5);
    if (mine) {
      _callout(Proj.p(e.x, e.y, 0.6).translate(0, -40), 'ĐẨY!', _pushC, 14);
    }
  }

  /// Dust kicked up behind a chicken sliding from a knockback.
  void _skid(SimEvent e, int n) {
    final feet = Proj.p(e.x, e.y);
    final dir = _pushDir(e) ?? Offset.zero;
    for (var i = 0; i < n; i++) {
      _add(
        _P(
          _K.dot,
          feet.dx - dir.dx * _r(0, 10),
          feet.dy - dir.dy * _r(0, 10),
          vx: -dir.dx * _r(20, 60) + _r(-25, 25),
          vy: -dir.dy * _r(20, 60) - _r(5, 25),
          max: _r(0.3, 0.55),
          size: _r(4, 7),
          color: const Color(0xAAE6CFA8),
        ),
      );
    }
  }

  /// Particle budget drops when the device struggles (keeps fights readable).
  void _add(_P p) {
    final cap = game.fps < 45 ? 140 : 260;
    if (_ps.length < cap || p.kind == _K.text || p.kind == _K.vortex) {
      _ps.add(p);
    }
  }

  void _burst(Offset c, int n, Color color, _K kind, {double speed = 150}) {
    for (var i = 0; i < n; i++) {
      final a = _r(0, math.pi * 2), s = _r(speed * 0.4, speed);
      _add(
        _P(
          kind,
          c.dx,
          c.dy,
          vx: math.cos(a) * s,
          vy: math.sin(a) * s - 60,
          max: _r(0.35, 0.8),
          size: _r(3, 6),
          rot: a,
          vr: _r(-8, 8),
          gravity: kind == _K.feather ? 140 : 380,
          color: color,
        ),
      );
    }
  }

  void _dust(Offset c, int n) {
    for (var i = 0; i < n; i++) {
      final a = _r(0, math.pi * 2), s = _r(30, 110);
      _add(
        _P(
          _K.dot,
          c.dx,
          c.dy,
          vx: math.cos(a) * s,
          vy: math.sin(a) * s * 0.4,
          max: _r(0.3, 0.6),
          size: _r(4, 8),
          color: const Color(0xAAE6CFA8),
        ),
      );
    }
  }

  void _splash(Offset c) {
    for (var i = 0; i < 16; i++) {
      final a = _r(-math.pi, 0), s = _r(80, 240);
      _add(
        _P(
          _K.drop,
          c.dx,
          c.dy,
          vx: math.cos(a) * s * 0.6,
          vy: math.sin(a) * s,
          max: _r(0.4, 0.8),
          size: _r(3, 6),
          gravity: 600,
          color: const Color(0xFF9FD8FF),
        ),
      );
    }
    _ring(c, const Color(0xFF9FD8FF), 60);
  }

  void _ring(Offset c, Color color, double size) =>
      _add(_P(_K.ring, c.dx, c.dy, max: 0.4, size: size, color: color));

  void _callout(Offset c, String text, Color color, double size) => _add(
    _P(
      _K.text,
      c.dx,
      c.dy,
      vy: -40,
      max: 0.9,
      size: size,
      color: color,
      text: text,
    ),
  );

  @override
  void update(double dt) {
    for (final p in _ps) {
      p.life += dt;
      if (p.life < 0) continue; // delayed start
      p.vy += p.gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.vr * dt;
    }
    _ps.removeWhere((p) => p.life >= p.max);
  }

  @override
  void render(Canvas canvas) {
    for (final p in _ps) {
      if (p.life < 0) continue;
      final k = (p.life / p.max).clamp(0.0, 1.0);
      final a = (1 - k);
      switch (p.kind) {
        case _K.dot:
        case _K.drop:
          _fill.color = p.color.withValues(alpha: p.color.a * a);
          canvas.drawCircle(
            Offset(p.x, p.y),
            p.size * (p.kind == _K.drop ? 1 : (1 - k * 0.5)),
            _fill,
          );
        case _K.vortex:
          _vortex(canvas, p, k);
        case _K.wave:
          // Ground shockwave growing to its full reach, then fading.
          final rx = p.size * (0.25 + 0.75 * Curves.easeOut.transform(k));
          final oval = Rect.fromCenter(
            center: Offset(p.x, p.y),
            width: rx * 2,
            height: rx * 2 * Proj.tilt,
          );
          _fill.color = p.color.withValues(alpha: 0.18 * a);
          canvas.drawOval(oval, _fill);
          _line
            ..color = RC.ink.withValues(alpha: 0.5 * a)
            ..strokeWidth = 6;
          canvas.drawOval(oval, _line);
          _line
            ..color = p.color.withValues(alpha: a)
            ..strokeWidth = 3.5;
          canvas.drawOval(oval, _line);
        case _K.chevron:
          _chevron(canvas, p, a);
        case _K.feather:
          _fill.color = p.color.withValues(alpha: a);
          canvas.save();
          canvas.translate(p.x, p.y);
          canvas.rotate(p.rot);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * 2.6,
              height: p.size,
            ),
            _fill,
          );
          if (p.size > 4.2) {
            _line
              ..color = RC.ink.withValues(alpha: a * 0.6)
              ..strokeWidth = 1;
            canvas.drawOval(
              Rect.fromCenter(
                center: Offset.zero,
                width: p.size * 2.6,
                height: p.size,
              ),
              _line,
            );
          }

          canvas.restore();
        case _K.star:
          _fill.color = p.color.withValues(alpha: a);
          _star(canvas, Offset(p.x, p.y), p.size * (0.6 + k), p.rot);
        case _K.ring:
          _line
            ..color = p.color.withValues(alpha: a)
            ..strokeWidth = 4 * a + 1;
          final s = p.size * (0.3 + k);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(p.x, p.y),
              width: s * 2,
              height: s * 2 * Proj.tilt,
            ),
            _line,
          );
        case _K.text:
          final pop = k < 0.15 ? 0.6 + k / 0.15 * 0.6 : 1.2 - (k - 0.15) * 0.25;
          final style = Styles.outlined(p.size, p.color, FontWeight.w900, 2);
          canvas.save();
          canvas.translate(p.x, p.y);
          canvas.scale(pop);
          _labels.paint(canvas, p.text!, style, Offset.zero, opacity: a);
          canvas.restore();
      }
    }
  }

  final _chev = Path();

  /// ">" arrow pointing along [_P.rot].
  void _chevron(Canvas canvas, _P p, double a) {
    final s = p.size;
    _chev
      ..reset()
      ..moveTo(-s * 0.6, -s)
      ..lineTo(s * 0.5, 0)
      ..lineTo(-s * 0.6, s);
    canvas.save();
    canvas.translate(p.x, p.y);
    canvas.rotate(p.rot);
    _line
      ..color = RC.ink.withValues(alpha: 0.7 * a)
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_chev, _line);
    _line
      ..color = p.color.withValues(alpha: a)
      ..strokeWidth = 3;
    canvas.drawPath(_chev, _line);
    _line
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;
    canvas.restore();
  }

  /// Swirling dark vortex: spiral arms rotating inward + dark core.
  void _vortex(Canvas canvas, _P p, double k) {
    final c = Offset(p.x, p.y);
    final fadeIn = (k / 0.15).clamp(0.0, 1.0);
    final spin = p.life * 9;
    _fill.color = const Color(0x552A1545).withValues(alpha: 0.35 * fadeIn);
    canvas.drawOval(
      Rect.fromCenter(
        center: c,
        width: p.size * 2,
        height: p.size * 2 * Proj.tilt,
      ),
      _fill,
    );
    _line.strokeWidth = 3;
    for (var arm = 0; arm < 3; arm++) {
      final path = Path();
      for (var i = 0; i <= 20; i++) {
        final u = i / 20;
        final r = p.size * (1 - u) * (0.9 + 0.1 * math.sin(spin));
        final ang = spin + arm * math.pi * 2 / 3 + u * 4.2;
        final o = c + Offset(math.cos(ang) * r, math.sin(ang) * r * Proj.tilt);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      _line.color = p.color.withValues(alpha: 0.75 * fadeIn);
      canvas.drawPath(path, _line);
    }
    _fill.color = const Color(0xFF1A0E2A).withValues(alpha: 0.8 * fadeIn);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: 22, height: 22 * Proj.tilt),
      _fill,
    );
  }

  void _star(Canvas canvas, Offset c, double r, double rot) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final a = rot + i * math.pi / 5;
      final o = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    path.close();
    canvas.drawPath(path, _fill);
  }
}
