import 'dart:collection';
import 'dart:ui' hide TextStyle;

import 'package:flutter/foundation.dart' show kIsWasm;
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

/// World-space labels (callouts, name tags) drawn from cached bitmaps.
///
/// Text under the camera's easing zoom plus pop animations lands on new
/// glyph sizes all the time, and Skia kept re-rasterizing glyphs into its
/// atlas (FreeType + atlas uploads were ~30% of frame CPU in a throttled
/// phone profile). Each label is rendered once to an image at [res]× and
/// then drawn as a textured quad at any scale. Opacity rides on the paint,
/// so fades need no extra variants.
class TextSprites {
  TextSprites({this.res = 4});

  /// Raster scale (image pixels per logical pixel). 4 stays sharp up to the
  /// max camera zoom on a 2× screen.
  final double res;

  static const int generation = 120;
  static const double _pad = 3; // room for the outline shadow

  var _cur = HashMap<TextStyle, HashMap<String, _Label>>.identity();
  var _old = HashMap<TextStyle, HashMap<String, _Label>>.identity();
  int _count = 0;
  final _paint = Paint()..filterQuality = FilterQuality.medium;

  /// Labels rasterized so far (tests / diagnostics).
  int renders = 0;

  /// Paints centered at [c] (vertical anchor 0 = top, 0.5 = middle,
  /// 1 = bottom) in the canvas's current transform.
  void paint(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset c, {
    double vAnchor = 0.5,
    double opacity = 1,
  }) {
    if (!(opacity > 0)) return;
    final l = _get(text, style);
    final dst = Rect.fromLTWH(
      c.dx - l.w / 2 - _pad,
      c.dy - l.h * vAnchor - _pad,
      l.w + _pad * 2,
      l.h + _pad * 2,
    );
    _paint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    canvas.drawImageRect(l.image, l.src, dst, _paint);
  }

  _Label _get(String text, TextStyle style) {
    final hit = _cur[style]?[text];
    if (hit != null) return hit;
    if (_count >= generation) _rotate();
    _count++;
    final m = _cur.putIfAbsent(style, HashMap.new);
    final old = _old[style]?.remove(text);
    if (old != null) return m[text] = old;
    return m[text] = _render(text, style);
  }

  _Label _render(String text, TextStyle style) {
    renders++;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final rec = PictureRecorder();
    tp.paint(Canvas(rec)..scale(res), const Offset(_pad, _pad));
    final pic = rec.endRecording();
    final image = pic.toImageSync(
      ((tp.width + _pad * 2) * res).ceil(),
      ((tp.height + _pad * 2) * res).ceil(),
    );
    final label = _Label(image, tp.width, tp.height);
    if (!kIsWasm) {
      pic.dispose();
      tp.dispose();
    }
    return label;
  }

  // Frees the previous old generation; images still in use were moved back
  // to the current one, so nothing drawn this frame is freed. skwasm
  // (opt-in wasm builds) frees via its GC finalizer instead.
  void _rotate() {
    if (!kIsWasm) {
      for (final m in _old.values) {
        for (final l in m.values) {
          l.image.dispose();
        }
      }
    }
    _old = _cur;
    _cur = HashMap.identity();
    _count = 0;
  }

  void dispose() {
    _rotate();
    _rotate();
  }
}

class _Label {
  _Label(this.image, this.w, this.h)
    : src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );

  final Image image;
  final double w, h;
  final Rect src;
}
