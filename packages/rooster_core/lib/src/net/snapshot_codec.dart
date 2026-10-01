/// Binary wire format for the hot path (GDD §10 sync at 30 Hz).
///
/// * Snapshots: keyframes carry every field; deltas carry only fields that
///   changed since the previous broadcast (WebSocket/TCP is reliable and
///   ordered, so a delta chain is safe). Periodic keyframes + a keyframe
///   whenever someone (re)joins keep late clients in sync.
/// * Fields are quantized so idle values stop changing: `stateTime` travels
///   as the tick the state began, resources as whole points.
/// * Input: 5 bytes instead of a ~45-byte JSON object.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../data/tuning.dart';
import '../sim/arena_runtime.dart' show FoodKind;
import '../sim/events.dart';
import '../sim/fighter.dart';
import '../sim/match_sim.dart';
import 'bytes.dart';
import 'snapshot.dart';

class Wire {
  static const keyframe = 1;
  static const delta = 2;
  static const input = 0x10;
}

/// Field order and widths of one fighter record.
enum _F {
  x(_W.i16), y(_W.i16), z(_W.i16), vx(_W.i16), vy(_W.i16),
  facing(_W.u8), state(_W.u8), stateStart(_W.u24), stateDur(_W.u16),
  hp(_W.u8), stamina(_W.u8), balance(_W.u8), rage(_W.u8),
  flags(_W.u16), heavy(_W.u8), combo(_W.u8),
  skillCd(_W.u8), crowCd(_W.u8), respawn(_W.u8), rageTimer(_W.u8),
  kos(_W.u8), deaths(_W.u8),
  shield(_W.u8), shieldBroken(_W.u8); // 24 fields = the u24 mask, full

  final _W w;
  const _F(this.w);
}

enum _W { u8, i16, u16, u24 }

void _write(ByteWriter w, _W t, int v) => switch (t) {
      _W.u8 => w.u8(v),
      _W.i16 => w.i16(v),
      _W.u16 => w.u16(v),
      _W.u24 => w.u24(v),
    };

int _read(ByteReader r, _W t) => switch (t) {
      _W.u8 => r.u8(),
      _W.i16 => r.i16(),
      _W.u16 => r.u16(),
      _W.u24 => r.u24(),
    };

const _twoPi = 2 * math.pi;

List<int> _fields(Fighter f, int tick) {
  int c(double v) => (v * 100).round();
  int d(double v) => (v * 10).ceil();
  final a = f.facing.angle % _twoPi;
  return [
    c(f.pos.x), c(f.pos.y), c(f.z), c(f.vel.x), c(f.vel.y),
    (a / _twoPi * 256).round() & 0xFF,
    f.state.index,
    math.max(0, tick - (f.stateTime / Tuning.dt).round()),
    (f.stateDur * 1000).round(),
    f.hp.ceil(), f.stamina.round(), f.balance.round(), f.rage.floor(),
    f.flags,
    (f.heavyCharge / Tuning.heavyMaxCharge * 255).round(),
    f.comboStep,
    d(f.skillCd), d(f.crowCd), d(f.respawnTimer), d(f.rageTimer),
    f.kos, f.deaths,
    (f.shield / Tuning.shieldMax * 100).round(), f.shieldBroken ? 1 : 0,
  ];
}

FighterSnap _toSnap(int id, List<int> v, int tick) => FighterSnap(
      id: id,
      x: v[_F.x.index] / 100,
      y: v[_F.y.index] / 100,
      z: v[_F.z.index] / 100,
      vx: v[_F.vx.index] / 100,
      vy: v[_F.vy.index] / 100,
      facing: v[_F.facing.index] / 256 * _twoPi,
      state: FState.values[v[_F.state.index].clamp(0, FState.values.length - 1)],
      stateTime: math.max(0, tick - v[_F.stateStart.index]) * Tuning.dt,
      stateDur: v[_F.stateDur.index] / 1000,
      hp: v[_F.hp.index].toDouble(),
      stamina: v[_F.stamina.index].toDouble(),
      balance: v[_F.balance.index].toDouble(),
      rage: v[_F.rage.index].toDouble(),
      flags: v[_F.flags.index],
      heavyCharge: v[_F.heavy.index] / 255 * Tuning.heavyMaxCharge,
      comboStep: v[_F.combo.index],
      skillCd: v[_F.skillCd.index] / 10,
      crowCd: v[_F.crowCd.index] / 10,
      respawnTimer: v[_F.respawn.index] / 10,
      rageTimer: v[_F.rageTimer.index] / 10,
      kos: v[_F.kos.index],
      deaths: v[_F.deaths.index],
      shield: v[_F.shield.index] / 100 * Tuning.shieldMax,
      shieldBroken: v[_F.shieldBroken.index] != 0,
    );

Uint8List _propsBytes(MatchSimulation sim) {
  final r = sim.props, w = ByteWriter(64);
  var mask = 0;
  for (var i = 0; i < r.buckets.length && i < 8; i++) {
    if (r.buckets[i].spilled) mask |= 1 << i;
  }
  w.u8(math.min(8, r.buckets.length));
  w.u8(mask);
  mask = 0;
  for (var i = 0; i < r.traps.length && i < 8; i++) {
    if (r.traps[i].armed) mask |= 1 << i;
  }
  w.u8(math.min(8, r.traps.length));
  w.u8(mask);
  w.u8(r.puddles.length);
  for (final p in r.puddles) {
    w.i16((p.x * 100).round());
    w.i16((p.y * 100).round());
    w.u8((p.r * 10).round());
    w.u8((p.ttl * 10).ceil());
  }
  w.u8(r.foods.length);
  for (final f in r.foods) {
    w.u16(f.id);
    w.u8(f.kind.index);
    w.i16((f.x * 100).round());
    w.i16((f.y * 100).round());
  }
  return w.takeBytes();
}

PropsSnap _readProps(ByteReader r) {
  List<bool> bits(int n, int mask) => [for (var i = 0; i < n; i++) mask & (1 << i) != 0];
  final nb = r.u8(), bm = r.u8(), nt = r.u8(), tm = r.u8();
  final puddles = [
    for (var i = r.u8(); i > 0; i--)
      PuddleSnap(r.i16() / 100, r.i16() / 100, r.u8() / 10, r.u8() / 10),
  ];
  final foods = <FoodSnap>[];
  for (var i = r.u8(); i > 0; i--) {
    final id = r.u16();
    final kind = FoodKind.values[r.u8().clamp(0, FoodKind.values.length - 1)];
    foods.add(FoodSnap(id, r.i16() / 100, r.i16() / 100, kind));
  }
  return PropsSnap(bits(nb, bm), bits(nt, tm), puddles, foods);
}

bool _sameBytes(Uint8List? a, Uint8List b) {
  if (a == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Host side: one encoder per match, shared by all links (broadcast).
class SnapshotEncoder {
  /// Keyframe every N snapshots (≈3 s at 30 Hz) as a safety net.
  final int keyEvery;
  final _prev = <int, List<int>>{};
  Uint8List? _prevProps;
  int _sinceKey = 0;
  bool _forceKey = true;

  SnapshotEncoder({this.keyEvery = 90});

  /// Next snapshot will be a keyframe (someone joined / reconnected).
  void forceKeyframe() => _forceKey = true;

  Uint8List encode(MatchSimulation sim, List<SimEvent> events) {
    final key = _forceKey || _sinceKey >= keyEvery;
    _forceKey = false;
    _sinceKey = key ? 0 : _sinceKey + 1;
    final w = ByteWriter(key ? 512 : 256);
    w.u8(key ? Wire.keyframe : Wire.delta);
    w.u24(sim.tick);
    w.u8(sim.phase.index);
    w.u16((sim.remaining * 10).round());
    w.u8((sim.countdownLeft * 10).ceil());

    final countAt = w.length;
    w.u8(0);
    var count = 0;
    for (final f in sim.fighters) {
      final v = _fields(f, sim.tick);
      final old = _prev[f.id];
      if (key || old == null) {
        w.u8(f.id);
        for (final fld in _F.values) {
          _write(w, fld.w, v[fld.index]);
        }
        count++;
      } else {
        var mask = 0;
        for (var i = 0; i < v.length; i++) {
          if (v[i] != old[i]) mask |= 1 << i;
        }
        if (mask != 0) {
          w.u8(f.id);
          w.u24(mask);
          for (final fld in _F.values) {
            if (mask & (1 << fld.index) != 0) _write(w, fld.w, v[fld.index]);
          }
          count++;
        }
      }
      _prev[f.id] = v;
    }
    w.setU8(countAt, count);

    final props = _propsBytes(sim);
    if (key || !_sameBytes(_prevProps, props)) {
      w.u8(1);
      for (final b in props) {
        w.u8(b);
      }
    } else {
      w.u8(0);
    }
    _prevProps = props;

    final n = math.min(events.length, 255);
    w.u8(n);
    for (final e in events.take(n)) {
      w.u8(e.type.index);
      w.i8(e.a);
      w.i8(e.b);
      w.i16((e.x * 100).round());
      w.i16((e.y * 100).round());
      w.i16((e.v * 10).round());
      w.u16(e.flags);
    }
    return w.takeBytes();
  }
}

/// Client side: rebuilds full snapshots from keyframes + deltas.
class SnapshotDecoder {
  final _state = <int, List<int>>{};
  PropsSnap _props = PropsSnap.empty;
  bool _hasKey = false;
  int _lastTick = -1;

  void reset() {
    _state.clear();
    _props = PropsSnap.empty;
    _hasKey = false;
    _lastTick = -1;
  }

  /// Returns null for frames that can't be applied yet (delta before the
  /// first keyframe) or malformed data.
  MatchSnap? decode(Uint8List bytes) {
    try {
      final r = ByteReader(bytes);
      final kind = r.u8();
      if (kind != Wire.keyframe && kind != Wire.delta) return null;
      final key = kind == Wire.keyframe;
      if (!key && !_hasKey) return null;
      final tick = r.u24();
      final phase = MatchPhase.values[r.u8().clamp(0, MatchPhase.values.length - 1)];
      final remaining = r.u16() / 10;
      final countdown = r.u8() / 10;
      if (key) _state.clear();
      for (var n = r.u8(); n > 0; n--) {
        final id = r.u8();
        if (key) {
          _state[id] = [for (final fld in _F.values) _read(r, fld.w)];
        } else {
          final mask = r.u24();
          final v = _state[id];
          if (v == null) return null;
          for (final fld in _F.values) {
            if (mask & (1 << fld.index) != 0) v[fld.index] = _read(r, fld.w);
          }
        }
      }
      if (r.u8() == 1) _props = _readProps(r);
      final events = <SimEvent>[
        for (var n = r.u8(); n > 0; n--)
          SimEvent(
            EvType.values[r.u8().clamp(0, EvType.values.length - 1)],
            a: r.i8(),
            b: r.i8(),
            x: r.i16() / 100,
            y: r.i16() / 100,
            v: r.i16() / 10,
            flags: r.u16(),
          ),
      ];
      _hasKey = true;
      if (tick <= _lastTick && !key) return null;
      _lastTick = tick;
      return MatchSnap(
        tick: tick,
        time: tick * Tuning.dt,
        phase: phase,
        remaining: remaining,
        countdown: countdown,
        fighters: [for (final e in _state.entries) _toSnap(e.key, e.value, tick)],
        props: _props,
        events: events,
      );
    } on Object {
      return null;
    }
  }
}

/// 5-byte player input: type, mx, my (-100..100), held bits, pressed bits.
class InputCodec {
  static const heavyBit = 1, blockBit = 2;

  static Uint8List encode(int mx, int my, bool heavy, bool block, int pressed) {
    final b = Uint8List(5);
    final v = ByteData.sublistView(b);
    b[0] = Wire.input;
    v.setInt8(1, mx.clamp(-100, 100));
    v.setInt8(2, my.clamp(-100, 100));
    b[3] = (heavy ? heavyBit : 0) | (block ? blockBit : 0);
    b[4] = pressed & 0xFF;
    return b;
  }

  static ({double mx, double my, bool heavy, bool block, int pressed})? decode(Uint8List b) {
    if (b.length != 5 || b[0] != Wire.input) return null;
    final v = ByteData.sublistView(b);
    return (
      mx: v.getInt8(1).clamp(-100, 100) / 100,
      my: v.getInt8(2).clamp(-100, 100) / 100,
      heavy: b[3] & heavyBit != 0,
      block: b[3] & blockBit != 0,
      pressed: b[4],
    );
  }
}
