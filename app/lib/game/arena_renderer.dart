import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:rooster_core/rooster_core.dart';

import '../ui/theme.dart';
import 'picture_cache.dart';
import 'projection.dart';
import 'rooster_game.dart';

/// Ground layer: void (pond / sky / abyss), ground shapes with a visible
/// side band for depth, puddles, traps, fans, food. Drawn under entities.
class ArenaRenderer extends Component with HasGameReference<RoosterGame> {
  final ArenaDef arena;
  ArenaRenderer(this.arena) : super(priority: 0);

  final _fill = Paint();
  final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = RC.ink;

  // Static art (void decor, ground sides/tops + textures) is recorded once
  // into Pictures; moving platforms replay theirs with a translation. Only
  // small dynamic decals are drawn per frame.
  Picture? _voidPic;
  final _sidePics = <Picture>[];
  final _topPics = <Picture>[];
  final _props = PictureCache(); // traps (per armed state), corn

  static Picture _record(void Function(Canvas) draw) {
    final rec = PictureRecorder();
    draw(Canvas(rec));
    return rec.endRecording();
  }

  void _ensureCache() {
    if (_voidPic != null) return;
    _voidPic = _record((c) => _void(c, 0));
    for (final g in arena.grounds) {
      _sidePics.add(_record((c) => _groundSide(c, g, 0)));
      _topPics.add(_record((c) => _groundTop(c, g, 0)));
    }
  }

  @override
  void render(Canvas canvas) {
    final t = game.renderTime;
    _ensureCache();
    canvas.drawPicture(_voidPic!);
    for (final pics in [_sidePics, _topPics]) {
      for (var i = 0; i < arena.grounds.length; i++) {
        final g = arena.grounds[i];
        if (g.motion == null) {
          canvas.drawPicture(pics[i]);
          continue;
        }
        canvas.save();
        canvas.translate(
          Proj.sx(g.ox(t) - g.ox(0)),
          Proj.sy(g.oy(t) - g.oy(0)),
        );
        canvas.drawPicture(pics[i]);
        canvas.restore();
      }
    }
    _decals(canvas, t);
  }

  @override
  void onRemove() {
    _props.dispose();
    // Pictures are released by GC; disposing them here could race the
    // renderer thread still drawing the last frame.
    _voidPic = null;
    _sidePics.clear();
    _topPics.clear();
    super.onRemove();
  }

  void _void(Canvas canvas, double t) {
    final w = arena.viewHalfW * 3, h = arena.viewHalfH * 3;
    final r = Rect.fromCenter(
      center: Offset.zero,
      width: Proj.sx(w * 2),
      height: Proj.sy(h * 2) * 2,
    );
    _fill.color = Color(arena.voidColor);
    canvas.drawRect(r, _fill);
    switch (arena.voidKind) {
      case VoidKind.pond:
        // Ripples + lily pads.
        _fill.color = const Color(0x33FFFFFF);
        for (var i = 0; i < 26; i++) {
          final a = i * 2.39996;
          final d = 8.5 + (i * 37 % 9);
          final c = Proj.p(math.cos(a) * d, math.sin(a) * d);
          final s = 0.6 + 0.4 * math.sin(t * 1.3 + i);
          canvas.drawOval(
            Rect.fromCenter(center: c, width: 34 * s, height: 10 * s),
            _fill,
          );
        }
        _fill.color = const Color(0xFF4FA35A);
        for (var i = 0; i < 7; i++) {
          final a = i * 0.9 + 0.4;
          final c = Proj.p(math.cos(a) * 9.4, math.sin(a) * 9.4);
          canvas.drawOval(
            Rect.fromCenter(center: c, width: 30, height: 16),
            _fill,
          );
        }
      case VoidKind.sky:
        _fill.color = const Color(0xCCFFFFFF);
        for (var i = 0; i < 9; i++) {
          final x = ((i * 5.3 + t * 0.6) % 36) - 18;
          final y = (i * 3.7 % 16) - 8;
          final c = Proj.p(x, y + (y > 0 ? 5 : -5));
          canvas.drawOval(
            Rect.fromCenter(center: c, width: 90, height: 30),
            _fill,
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: c + const Offset(28, -10),
              width: 60,
              height: 30,
            ),
            _fill,
          );
        }
      case VoidKind.abyss:
        _fill.color = const Color(0x22B89CFF);
        for (var i = 0; i < 30; i++) {
          final a = i * 2.1;
          final d = 5 + (i * 13 % 11);
          final c = Proj.p(
            math.cos(a + t * 0.05) * d,
            math.sin(a + t * 0.05) * d,
          );
          canvas.drawCircle(c, 2 + (i % 3).toDouble(), _fill);
        }
    }
  }

  Path _shapePath(GroundShape g, double t) {
    switch (g) {
      case CircleGround():
        final c = Proj.p(g.centerX(t), g.centerY(t));
        return Path()..addOval(
          Rect.fromCenter(
            center: c,
            width: Proj.sx(g.r * 2),
            height: Proj.sy(g.r * 2),
          ),
        );
      case RectGround():
        final c = Proj.p(g.centerX(t), g.centerY(t));
        return Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: c,
              width: Proj.sx(g.hw * 2),
              height: Proj.sy(g.hh * 2),
            ),
            const Radius.circular(6),
          ),
        );
    }
  }

  /// Extruded silhouette: top face swept down by the ground thickness.
  Path _sidePath(GroundShape g, double t) {
    final drop = Proj.groundThickness * Proj.px;
    final c = Proj.p(g.centerX(t), g.centerY(t));
    switch (g) {
      case CircleGround():
        final w = Proj.sx(g.r * 2), h = Proj.sy(g.r * 2);
        final band = Path()
          ..addRect(Rect.fromLTWH(c.dx - w / 2, c.dy, w, drop));
        return Path.combine(
          PathOperation.union,
          Path.combine(PathOperation.union, _shapePath(g, t), band),
          Path()..addOval(
            Rect.fromCenter(center: c.translate(0, drop), width: w, height: h),
          ),
        );
      case RectGround():
        final w = Proj.sx(g.hw * 2), h = Proj.sy(g.hh * 2);
        return Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c.dx - w / 2, c.dy - h / 2, w, h + drop),
            const Radius.circular(6),
          ),
        );
    }
  }

  void _groundSide(Canvas canvas, GroundShape g, double t) {
    final side = _sidePath(g, t);
    _fill.color = Color(arena.groundEdgeColor);
    canvas.drawPath(side, _fill);
    canvas.drawPath(side, _stroke);
  }

  void _groundTop(Canvas canvas, GroundShape g, double t) {
    final top = _shapePath(g, t);
    _fill.color = Color(arena.groundColor);
    canvas.drawPath(top, _fill);
    // Texture: arena-specific pattern clipped to the top face.
    canvas.save();
    canvas.clipPath(top);
    _texture(canvas, g, t);
    canvas.restore();
    canvas.drawPath(top, _stroke);
  }

  void _texture(Canvas canvas, GroundShape g, double t) {
    final cx = g.centerX(t), cy = g.centerY(t);
    switch (arena.voidKind) {
      case VoidKind.pond:
        // Packed dirt with scattered pebbles + a painted ring.
        _fill.color = const Color(0x22000000);
        for (var i = 0; i < 60; i++) {
          final a = i * 2.39996, d = math.sqrt(i / 60) * 6.8;
          canvas.drawCircle(
            Proj.p(cx + math.cos(a) * d, cy + math.sin(a) * d),
            2.5,
            _fill,
          );
        }
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0x55FFFFFF);
        canvas.drawOval(
          Rect.fromCenter(
            center: Proj.p(cx, cy),
            width: Proj.sx(6),
            height: Proj.sy(6),
          ),
          ring,
        );
      case VoidKind.sky:
        // Roof tiles rows.
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0x44000000);
        for (var y = -6.0; y <= 6; y += 0.8) {
          canvas.drawLine(Proj.p(-9, cy + y), Proj.p(9, cy + y), p);
        }
        for (var y = -6.0; y <= 6; y += 0.8) {
          for (var x = -9.0; x <= 9; x += 1.2) {
            final off = ((y / 0.8).round() % 2) * 0.6;
            canvas.drawLine(
              Proj.p(x + off, cy + y),
              Proj.p(x + off, cy + y + 0.8),
              p,
            );
          }
        }
      case VoidKind.abyss:
        // Stone flagstones.
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0x40000000);
        for (var y = -7.0; y <= 7; y += 1.1) {
          canvas.drawLine(Proj.p(cx - 9, cy + y), Proj.p(cx + 9, cy + y), p);
          for (var x = -9.0; x <= 9; x += 1.4) {
            final off = ((y / 1.1).round() % 2) * 0.7;
            canvas.drawLine(
              Proj.p(cx + x + off, cy + y),
              Proj.p(cx + x + off, cy + y + 1.1),
              p,
            );
          }
        }
    }
  }

  void _decals(Canvas canvas, double t) {
    final props = game.latestProps;
    // Puddles.
    for (final p in props.puddles) {
      _fill.color = Color.fromARGB(
        (120 * (p.ttl / 3).clamp(0.2, 1.0)).round(),
        90,
        180,
        255,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Proj.p(p.x, p.y),
          width: Proj.sx(p.r * 2),
          height: Proj.sy(p.r * 2),
        ),
        _fill,
      );
    }
    var trapI = 0;
    for (final d in arena.props) {
      switch (d.type) {
        case PropType.trap:
          final armed = trapI < props.trapsArmed.length
              ? props.trapsArmed[trapI]
              : true;
          trapI++;
          _props.draw(canvas, (
            'trap',
            d.x,
            d.y,
            armed,
          ), (c) => _trap(c, d, armed));
        case PropType.fan:
          _fan(canvas, d, t);
        default:
          break;
      }
    }
    // One recorded corn / heal, replayed at each pickup with a small bob.
    for (final f in props.foods) {
      final c = Proj.p(f.x, f.y);
      final heal = f.kind == FoodKind.heal;
      canvas.save();
      canvas.translate(c.dx, c.dy + math.sin(t * 4 + f.id) * 2);
      if (heal) {
        // Soft pulsing glow under the heart.
        final g = 0.5 + 0.5 * math.sin(t * 6 + f.id);
        _fill.color = Color.fromRGBO(255, 80, 80, 0.18 + 0.2 * g);
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(0, 1),
            width: 30 + 6 * g,
            height: 12 + 2 * g,
          ),
          _fill,
        );
        _props.draw(canvas, 'heal', _heal);
      } else {
        _props.draw(canvas, 'corn', (cv) => _corn(cv, Offset.zero, 0));
      }
      canvas.restore();
    }
  }

  void _trap(Canvas canvas, PropDef d, bool armed) {
    final c = Proj.p(d.x, d.y);
    final rect = Rect.fromCenter(
      center: c,
      width: Proj.sx(d.radius * 2),
      height: Proj.sy(d.radius * 2),
    );
    _fill.color = const Color(0xFF6B6B6B);
    canvas.drawOval(rect, _fill);
    final teeth = Paint()
      ..color = armed ? const Color(0xFFD9D9D9) : const Color(0xFF8A8A8A)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawOval(rect.deflate(3), teeth);
    if (armed) {
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final o = Offset(
          math.cos(a) * rect.width / 2 * 0.8,
          math.sin(a) * rect.height / 2 * 0.8,
        );
        canvas.drawLine(c + o, c + o * 0.6, teeth);
      }
    }
    canvas.drawOval(rect, _stroke..strokeWidth = 2);
    _stroke.strokeWidth = 3;
  }

  void _fan(Canvas canvas, PropDef d, double t) {
    final phase = d.fanPhase(t);
    final c = Proj.p(d.x, d.y);
    // Zone lines when blowing / warning.
    if (phase > 0) {
      final p = Paint()
        ..strokeWidth = phase == 2 ? 3 : 2
        ..color = phase == 2
            ? const Color(0x99FFFFFF)
            : const Color(0x55FFFFFF);
      for (var i = 0; i < 7; i++) {
        final side = (i / 6 - 0.5) * d.width;
        final along = ((t * (phase == 2 ? 9 : 2) + i * 1.3) % d.length);
        final sx = d.x + -d.dirY * side + d.dirX * along;
        final sy = d.y + d.dirX * side + d.dirY * along;
        canvas.drawLine(
          Proj.p(sx, sy),
          Proj.p(sx + d.dirX * 0.9, sy + d.dirY * 0.9),
          p,
        );
      }
    }
    // Fan body.
    _fill.color = const Color(0xFF3E4A59);
    canvas.drawCircle(c, 18, _fill);
    canvas.drawCircle(c, 18, _stroke);
    final spin =
        t *
        (phase == 2
            ? 18
            : phase == 1
            ? 6
            : 0.5);
    _fill.color = const Color(0xFFBFD4E6);
    for (var i = 0; i < 3; i++) {
      final a = spin + i * 2 * math.pi / 3;
      canvas.drawOval(
        Rect.fromCenter(
          center: c + Offset(math.cos(a) * 8, math.sin(a) * 8),
          width: 14,
          height: 8,
        ),
        _fill,
      );
    }
  }

  /// Heal drop: a red heart with a white cross.
  void _heal(Canvas canvas) {
    _fill.color = const Color(0x33000000);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 18, height: 7),
      _fill,
    );
    final heart = Path()
      ..moveTo(0, -4)
      ..cubicTo(-3, -11, -12, -10, -11, -17)
      ..cubicTo(-10, -23, -3, -23, 0, -18)
      ..cubicTo(3, -23, 10, -23, 11, -17)
      ..cubicTo(12, -10, 3, -11, 0, -4)
      ..close();
    _fill.color = const Color(0xFFE8412C);
    canvas.drawPath(heart, _fill);
    canvas.drawPath(heart, _stroke..strokeWidth = 2);
    _stroke.strokeWidth = 3;
    _fill.color = const Color(0xFFFFFFFF);
    canvas.drawRect(
      Rect.fromCenter(center: const Offset(0, -14), width: 3.2, height: 9),
      _fill,
    );
    canvas.drawRect(
      Rect.fromCenter(center: const Offset(0, -14), width: 9, height: 3.2),
      _fill,
    );
  }

  void _corn(Canvas canvas, Offset c, double t) {
    final bob = math.sin(t * 4) * 2;
    final o = c + Offset(0, -6 + bob);
    _fill.color = const Color(0x33000000);
    canvas.drawOval(Rect.fromCenter(center: c, width: 18, height: 7), _fill);
    _fill.color = const Color(0xFF6DBE45);
    canvas.drawOval(
      Rect.fromCenter(center: o + const Offset(-5, 2), width: 8, height: 18),
      _fill,
    );
    canvas.drawOval(
      Rect.fromCenter(center: o + const Offset(5, 2), width: 8, height: 18),
      _fill,
    );
    _fill.color = const Color(0xFFFFD23A);
    canvas.drawOval(Rect.fromCenter(center: o, width: 10, height: 20), _fill);
    canvas.drawOval(
      Rect.fromCenter(center: o, width: 10, height: 20),
      _stroke..strokeWidth = 2,
    );
    _stroke.strokeWidth = 3;
  }
}
