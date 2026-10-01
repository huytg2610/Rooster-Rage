import 'dart:collection';
import 'dart:math' as math;

import 'package:rooster_core/rooster_core.dart';

/// Interpolated per-frame view of one chicken.
class FighterView {
  final FighterInfo info;
  final double x, y, z, facing;
  final FighterSnap s; // discrete fields (state, flags, resources)
  final double stateTime;

  const FighterView(
    this.info,
    this.x,
    this.y,
    this.z,
    this.facing,
    this.s,
    this.stateTime,
  );

  int get id => info.id;
}

class RenderFrame {
  final double time;
  final MatchSnap latest;
  final List<FighterView> fighters;
  final List<SimEvent> events; // fired this frame

  const RenderFrame(this.time, this.latest, this.fighters, this.events);

  FighterView? fighter(int? id) {
    if (id == null) return null;
    for (final f in fighters) {
      if (f.id == id) return f;
    }
    return null;
  }
}

/// Snapshot interpolation with adaptive jitter buffering.
///
/// The link is a WebSocket (TCP): nothing is lost, but phone WiFi (power
/// saving, contention) holds packets back and delivers them in bursts.
///
/// * Server clock offset = best (least delayed) `snap.time - arrival` seen
///   in the last [offsetWindow] seconds, so late bursts don't drag the clock
///   while a host clock jump is still picked up within seconds.
/// * Lateness = offset − arrival; the render delay covers the worst
///   lateness of the last [lateWindow] seconds. It rises at once and eases
///   back down slowly, so a spike every couple of seconds keeps the buffer
///   deep instead of starving it each time.
/// * When the buffer runs dry, remote chickens extrapolate briefly instead
///   of freezing; the local chicken is extrapolated from the newest state
///   and smoothed so corrections don't pop (GDD: client prediction).
class SnapshotBuffer {
  static const double offsetWindow = 6;
  static const double lateWindow = 4;

  final double minDelay;
  final List<MatchSnap> _snaps = [];
  final List<(double, SimEvent)> _pending = [];
  final _clock = Stopwatch()..start();
  final _arrivals = ListQueue<(double, double)>(); // (local time, offset)
  double? _offset; // server time - local time (best case)
  double _latePeak = 0; // eased worst recent lateness (s)
  double _interval = 1 / 30; // EWMA of snapshot spacing (server time)
  double? _renderTime;
  double? _ownX, _ownY;
  int _starved = 0;
  bool _dry = false;
  Map<int, FighterInfo> infos = const {};
  int? localId;

  /// Local clock in seconds (injectable for tests).
  final double Function()? clock;

  SnapshotBuffer({required this.minDelay, this.clock});

  bool get hasData => _snaps.isNotEmpty;
  MatchSnap? get latest => _snaps.isEmpty ? null : _snaps.last;

  /// Current interpolation delay (s).
  double get delay =>
      (_interval * 1.15 + _latePeak + 0.008).clamp(minDelay, 0.25).toDouble();

  /// Recent lateness spikes (s) — "jitter" in the stats overlay.
  double get jitter => _latePeak;

  /// Times the buffer ran dry (a snapshot came too late to interpolate)
  /// since the last read.
  int takeStarved() {
    final n = _starved;
    _starved = 0;
    return n;
  }

  double get _now => clock?.call() ?? _clock.elapsedMicroseconds / 1e6;

  void reset(Map<int, FighterInfo> infos, int? localId) {
    this.infos = infos;
    this.localId = localId;
    _snaps.clear();
    _pending.clear();
    _renderTime = null;
    _offset = null;
    _arrivals.clear();
    _latePeak = 0;
    _dry = false;
    _ownX = _ownY = null;
  }

  void add(MatchSnap s) {
    if (_snaps.isNotEmpty && s.tick <= _snaps.last.tick) return;
    final now = _now;
    _arrivals.add((now, s.time - now));
    while (now - _arrivals.first.$1 > offsetWindow) {
      _arrivals.removeFirst();
    }
    var best = -double.infinity, worst = double.infinity;
    for (final (t, o) in _arrivals) {
      if (o > best) best = o;
      if (now - t <= lateWindow && o < worst) worst = o;
    }
    _offset = best;
    final late = best - worst;
    // Up at once, down gently (~2 s to halve at 30 Hz).
    _latePeak = late > _latePeak
        ? late
        : _latePeak + (late - _latePeak) * 0.012;
    if (_snaps.isNotEmpty) {
      final gap = s.time - _snaps.last.time;
      if (gap > 0 && gap < 0.5) _interval = _interval * 0.9 + gap * 0.1;
    }
    _snaps.add(s);
    if (_snaps.length > 40) _snaps.removeAt(0);
    for (final e in s.events) {
      _pending.add((s.time, e));
    }
  }

  RenderFrame? update(double dt) {
    if (_snaps.isEmpty || infos.isEmpty || _offset == null) return null;
    final newest = _snaps.last;
    final serverNow = _now + _offset!;
    final target = serverNow - delay;
    var rt = _renderTime ?? target;
    rt += dt;
    if ((rt - target).abs() > 0.3) {
      rt = target;
    } else {
      rt += (target - rt) * math.min(1.0, 6 * dt);
    }
    _renderTime = rt;
    final dry = rt > newest.time;
    if (dry && !_dry) _starved++;
    _dry = dry;

    // Bracketing snapshots.
    var a = _snaps.first, b = _snaps.first;
    for (var i = _snaps.length - 1; i >= 0; i--) {
      if (_snaps[i].time <= rt) {
        a = _snaps[i];
        b = i + 1 < _snaps.length ? _snaps[i + 1] : _snaps[i];
        break;
      }
    }
    final span = b.time - a.time;
    final alpha = span > 1e-6 ? ((rt - a.time) / span).clamp(0.0, 1.0) : 0.0;
    // Starved: extrapolate from the newest state for up to 100 ms.
    final extra = identical(a, b) ? (rt - a.time).clamp(0.0, 0.1) : 0.0;

    final views = <FighterView>[];
    for (final fa in a.fighters) {
      final info = infos[fa.id];
      if (info == null) continue;
      if (fa.id == localId) {
        views.add(_own(newest.fighter(fa.id) ?? fa, info, serverNow, dt));
        continue;
      }
      final fb = b.fighter(fa.id) ?? fa;
      // Don't interpolate across teleports (respawn).
      final teleport = (fb.x - fa.x).abs() + (fb.y - fa.y).abs() > 3;
      final t = teleport ? 0.0 : alpha;
      final moving = fa.state != FState.dead && fa.state != FState.falling;
      final ex = moving ? extra : 0.0;
      views.add(
        FighterView(
          info,
          lerpD(fa.x, fb.x, t) + fa.vx * ex,
          lerpD(fa.y, fb.y, t) + fa.vy * ex,
          lerpD(fa.z, fb.z, t),
          lerpAngle(fa.facing, fb.facing, t),
          fa,
          fa.stateTime + (rt - a.time),
        ),
      );
    }

    final fired = <SimEvent>[];
    while (_pending.isNotEmpty && _pending.first.$1 <= rt + 0.001) {
      fired.add(_pending.removeAt(0).$2);
    }
    return RenderFrame(rt, newest, views, fired);
  }

  FighterView _own(
    FighterSnap f,
    FighterInfo info,
    double serverNow,
    double dt,
  ) {
    final age = (serverNow - _snaps.last.time).clamp(0.0, 0.1);
    final still = f.state == FState.dead || f.state == FState.falling;
    final tx = f.x + (still ? 0 : f.vx * age),
        ty = f.y + (still ? 0 : f.vy * age);
    var x = _ownX ?? tx, y = _ownY ?? ty;
    if ((tx - x).abs() + (ty - y).abs() > 1.5) {
      x = tx; // respawn / big correction: snap
      y = ty;
    } else {
      final k = 1 - math.exp(-18 * dt);
      x += (tx - x) * k;
      y += (ty - y) * k;
    }
    _ownX = x;
    _ownY = y;
    return FighterView(info, x, y, f.z, f.facing, f, f.stateTime + age);
  }
}
