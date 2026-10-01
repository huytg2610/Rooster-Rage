import 'dart:ui';

/// Records static drawings once and replays them every frame.
///
/// Keys should include every visual state of an object (e.g. a bucket
/// upright vs spilled), so a state change just switches to another cached
/// picture — nothing is re-drawn from scratch.
class PictureCache {
  final _pics = <Object, Picture>{};

  int get length => _pics.length;

  Picture get(Object key, void Function(Canvas c) draw) =>
      _pics[key] ??= _record(draw);

  void draw(Canvas canvas, Object key, void Function(Canvas c) draw) =>
      canvas.drawPicture(get(key, draw));

  static Picture _record(void Function(Canvas c) draw) {
    final rec = PictureRecorder();
    draw(Canvas(rec));
    return rec.endRecording();
  }

  /// Drops references; pictures are freed by the GC finalizer (an explicit
  /// dispose could race the wasm renderer's raster thread).
  void dispose() => _pics.clear();
}
