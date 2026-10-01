import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWasm;
import 'package:flutter/painting.dart';

/// 2.5D oblique projection: world meters → world pixels. Y is squashed so
/// the arena reads as seen from above at an angle; z (jump) lifts upward.
class Proj {
  static const px = 32.0; // pixels per meter
  static const tilt = 0.72; // y squash
  static const groundThickness =
      0.55; // meters of visible "side" under ground edges

  static Offset p(double x, double y, [double z = 0]) =>
      Offset(x * px, y * px * tilt - z * px);

  static double sx(double x) => x * px;
  static double sy(double y) => y * px * tilt;
}

/// Shared outlined text styles, memoized so per-frame HUD / name tags /
/// callouts reuse the same instances (cheap identity lookups in [TextCache]
/// instead of hashing a fresh TextStyle with shadows every draw).
class Styles {
  static final _memo = <(double, int, int, double), TextStyle>{};

  static TextStyle outlined(
    double size,
    Color color, [
    FontWeight weight = FontWeight.w900,
    double shadow = 1.5,
  ]) {
    final key = (size, color.toARGB32(), weight.value, shadow);
    if (_memo.length > 512) _memo.clear();
    return _memo[key] ??= TextStyle(
      fontFamily: 'Roboto',
      fontWeight: weight,
      fontSize: size,
      color: color,
      shadows: [
        Shadow(
          color: Color.fromARGB((color.a * 255).round(), 0x1B, 0x10, 0x0A),
          offset: Offset(shadow, shadow),
        ),
      ],
    );
  }
}

/// TextPainter cache for per-frame labels (name tags, numbers), keyed by
/// style identity then text. Use [Styles] so styles are shared instances.
///
/// Two generations: when the current one fills up it becomes the old one,
/// and the previous old generation is disposed. Hits in the old generation
/// move back to the current one, so a painter is only freed after a full
/// generation without use — never within the frame that drew it. Left to
/// the GC, dropped paragraphs piled up to ~300 MB of CanvasKit heap in a
/// busy match (enough to kill a phone tab).
class TextCache {
  static const int generation = 300;

  var _cur = HashMap<TextStyle, HashMap<String, TextPainter>>.identity();
  var _old = HashMap<TextStyle, HashMap<String, TextPainter>>.identity();
  int _count = 0;

  TextPainter get(String text, TextStyle style) {
    final hit = _cur[style]?[text];
    if (hit != null) return hit;
    if (_count >= generation) _rotate();
    _count++;
    final m = _cur.putIfAbsent(style, HashMap.new);
    final old = _old[style]?.remove(text);
    if (old != null) return m[text] = old;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return m[text] = tp;
  }

  void _rotate() {
    // skwasm (wasm builds, opt-in) must not free paragraphs by hand: its
    // raster worker may still read them. The GC finalizer handles it there.
    if (!kIsWasm) {
      for (final m in _old.values) {
        for (final tp in m.values) {
          tp.dispose();
        }
      }
    }
    _old = _cur;
    _cur = HashMap.identity();
    _count = 0;
  }

  /// Paints centered at [c] (vertical anchor 0 = top, 0.5 = middle, 1 = bottom).
  ///
  /// Pass [scale] — the canvas's current zoom (camera zoom × any pop
  /// animation) — for text drawn under a changing transform. The text is
  /// then snapped to [snapScale] steps so Skia reuses its cached glyphs:
  /// with the camera easing every frame, every frame hit a new text size and
  /// Skia re-rasterized glyphs (~30% of frame CPU on a throttled phone).
  void paint(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset c, [
    double vAnchor = 0.5,
    double? scale,
  ]) {
    final tp = get(text, style);
    final anchor = Offset(tp.width / 2, tp.height * vAnchor);
    if (scale == null || !(scale > 0)) {
      tp.paint(canvas, c - anchor);
      return;
    }
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(snapScale(scale) / scale);
    tp.paint(canvas, -anchor);
    canvas.restore();
  }

  /// Nearest 1/8-octave step (~9%): few distinct glyph sizes, and a size
  /// change of that much is hard to notice mid-zoom.
  static double snapScale(double s) =>
      math.pow(2, (math.log(s) / math.ln2 * 8).round() / 8).toDouble();
}
