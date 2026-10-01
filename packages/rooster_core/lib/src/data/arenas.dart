/// Arena definitions (GDD §14). Pure data + time-based queries, so the client
/// can reproduce moving platforms / fans from the synced match time alone.
library;

import 'dart:math' as math;

/// Sinusoidal oscillation: offset(t) = (ax, ay) * sin(2πt/period + phase).
class Motion {
  final double ax, ay, period, phase;
  const Motion(this.ax, this.ay, this.period, [this.phase = 0]);

  double _s(double t) => math.sin(2 * math.pi * t / period + phase);
  double dx(double t) => ax * _s(t);
  double dy(double t) => ay * _s(t);
}

sealed class GroundShape {
  final Motion? motion;
  const GroundShape(this.motion);

  double ox(double t) => motion?.dx(t) ?? 0;
  double oy(double t) => motion?.dy(t) ?? 0;

  /// True if (x, y) is on this shape at time [t], shrunk by [margin].
  bool contains(double x, double y, double t, [double margin = 0]);

  /// Distance from (x, y) to the shape edge (positive inside).
  double edgeDistance(double x, double y, double t);

  double centerX(double t);
  double centerY(double t);
}

class CircleGround extends GroundShape {
  final double cx, cy, r;
  const CircleGround(this.cx, this.cy, this.r, [super.motion]);

  @override
  double centerX(double t) => cx + ox(t);
  @override
  double centerY(double t) => cy + oy(t);

  @override
  bool contains(double x, double y, double t, [double margin = 0]) =>
      edgeDistance(x, y, t) >= margin;

  @override
  double edgeDistance(double x, double y, double t) {
    final dx = x - centerX(t), dy = y - centerY(t);
    return r - math.sqrt(dx * dx + dy * dy);
  }
}

class RectGround extends GroundShape {
  final double cx, cy, hw, hh;
  const RectGround(this.cx, this.cy, this.hw, this.hh, [super.motion]);

  @override
  double centerX(double t) => cx + ox(t);
  @override
  double centerY(double t) => cy + oy(t);

  @override
  bool contains(double x, double y, double t, [double margin = 0]) =>
      edgeDistance(x, y, t) >= margin;

  @override
  double edgeDistance(double x, double y, double t) {
    final dx = (x - centerX(t)).abs(), dy = (y - centerY(t)).abs();
    return math.min(hw - dx, hh - dy);
  }
}

class WallSeg {
  final double ax, ay, bx, by;
  const WallSeg(this.ax, this.ay, this.bx, this.by);
}

enum PropType { bucket, trap, food, fan, pillar }

class PropDef {
  final PropType type;
  final double x, y;
  final double radius;
  // Fan only: blow direction, zone length/width, cycle timing, force.
  final double dirX, dirY, length, width, period, onTime, phase, force;

  const PropDef(
    this.type,
    this.x,
    this.y, {
    this.radius = 0.5,
    this.dirX = 0,
    this.dirY = 0,
    this.length = 0,
    this.width = 0,
    this.period = 1,
    this.onTime = 0,
    this.phase = 0,
    this.force = 0,
  });

  /// Fans: 0 = off, 1 = spinning up (warning), 2 = blowing.
  int fanPhase(double t) {
    if (type != PropType.fan) return 0;
    final c = ((t + phase) % period + period) % period;
    if (c < onTime) return 2;
    if (c > period - 0.9) return 1;
    return 0;
  }

  /// Fans: whether (px, py) is inside the blow zone.
  bool inFanZone(double px, double py) {
    if (type != PropType.fan) return false;
    final rx = px - x, ry = py - y;
    final along = rx * dirX + ry * dirY;
    final side = (rx * -dirY + ry * dirX).abs();
    return along >= 0 && along <= length && side <= width / 2;
  }
}

enum VoidKind { pond, sky, abyss }

class ArenaDef {
  final String id;
  final String nameVi;
  final String descVi;
  final List<GroundShape> grounds;
  final List<WallSeg> walls;
  final List<PropDef> props;
  final List<(double, double)> spawns;
  final double viewHalfW, viewHalfH;
  final VoidKind voidKind;
  final int groundColor, groundEdgeColor, voidColor;

  const ArenaDef({
    required this.id,
    required this.nameVi,
    required this.descVi,
    required this.grounds,
    required this.walls,
    required this.props,
    required this.spawns,
    required this.viewHalfW,
    required this.viewHalfH,
    required this.voidKind,
    required this.groundColor,
    required this.groundEdgeColor,
    required this.voidColor,
  });

  /// Index of the ground shape under (x, y) at time t, or -1 (= void).
  int groundAt(double x, double y, double t) {
    for (var i = 0; i < grounds.length; i++) {
      if (grounds[i].contains(x, y, t)) return i;
    }
    return -1;
  }

  bool isGround(double x, double y, double t, [double margin = 0]) {
    for (final g in grounds) {
      if (g.contains(x, y, t, margin)) return true;
    }
    return false;
  }

  /// Largest edge distance over all shapes (how deep inside ground we are).
  double groundDepth(double x, double y, double t) {
    var best = -double.infinity;
    for (final g in grounds) {
      final d = g.edgeDistance(x, y, t);
      if (d > best) best = d;
    }
    return best;
  }
}

List<WallSeg> _arcWalls(double r, double fromDeg, double toDeg, int segs) {
  final out = <WallSeg>[];
  for (var i = 0; i < segs; i++) {
    final a0 = (fromDeg + (toDeg - fromDeg) * i / segs) * math.pi / 180;
    final a1 = (fromDeg + (toDeg - fromDeg) * (i + 1) / segs) * math.pi / 180;
    out.add(WallSeg(math.cos(a0) * r, math.sin(a0) * r, math.cos(a1) * r,
        math.sin(a1) * r));
  }
  return out;
}

List<(double, double)> _ring(double r, int n, double startDeg) => [
      for (var i = 0; i < n; i++)
        (
          math.cos((startDeg + 360 / n * i) * math.pi / 180) * r,
          math.sin((startDeg + 360 / n * i) * math.pi / 180) * r,
        ),
    ];

class Arenas {
  static final village = ArenaDef(
    id: 'village',
    nameVi: 'Sân Đình Làng',
    descVi: 'Sân đất giữa ao. Rào tre chắn bớt, 4 khe hở dẫn xuống ao.',
    grounds: const [CircleGround(0, 0, 7.2)],
    walls: [
      for (var q = 0; q < 4; q++) ..._arcWalls(7.2, q * 90 + 14, q * 90 + 76, 5),
    ],
    props: const [
      PropDef(PropType.bucket, -3.6, -1.6, radius: 0.42),
      PropDef(PropType.bucket, 3.6, 1.8, radius: 0.42),
      PropDef(PropType.trap, 1.8, -3.4, radius: 0.5),
      PropDef(PropType.trap, -2.0, 3.4, radius: 0.5),
      PropDef(PropType.food, 0, 0),
      PropDef(PropType.food, 5.3, 0),
      PropDef(PropType.food, -5.3, 0),
      PropDef(PropType.food, 0, 5.3),
      PropDef(PropType.food, 0, -5.3),
    ],
    spawns: _ring(4.3, 8, 22.5),
    viewHalfW: 8.4,
    viewHalfH: 8.4,
    voidKind: VoidKind.pond,
    groundColor: 0xFFD9A066,
    groundEdgeColor: 0xFF8F5B2E,
    voidColor: 0xFF3E8FB0,
  );

  static final rooftop = ArenaDef(
    id: 'rooftop',
    nameVi: 'Mái Nhà Phố',
    descVi: 'Không rào chắn. Quạt gió thổi bay gà ra mép mái.',
    grounds: const [RectGround(0, 0, 7.6, 4.6)],
    walls: const [],
    props: const [
      PropDef(PropType.pillar, -2.5, 0, radius: 0.6),
      PropDef(PropType.pillar, 2.5, 0, radius: 0.6),
      PropDef(PropType.fan, -4.5, -4.6,
          dirX: 0, dirY: 1, length: 9.2, width: 2.4,
          period: 7, onTime: 2.6, phase: 0, force: 15),
      PropDef(PropType.fan, 4.5, 4.6,
          dirX: 0, dirY: -1, length: 9.2, width: 2.4,
          period: 7, onTime: 2.6, phase: 3.5, force: 15),
      PropDef(PropType.food, 0, -3),
      PropDef(PropType.food, 0, 3),
      PropDef(PropType.food, -6.2, 0),
      PropDef(PropType.food, 6.2, 0),
    ],
    spawns: const [
      (-5.5, -2.5), (5.5, 2.5), (-5.5, 2.5), (5.5, -2.5),
      (0, -3.2), (0, 3.2), (-3, 2.8), (3, -2.8),
    ],
    viewHalfW: 8.8,
    viewHalfH: 5.8,
    voidKind: VoidKind.sky,
    groundColor: 0xFFB5523B,
    groundEdgeColor: 0xFF6E2A1C,
    voidColor: 0xFF9ED8F5,
  );

  static final temple = ArenaDef(
    id: 'temple',
    nameVi: 'Đấu Trường Chùa Cổ',
    descVi: 'Sàn đá giữa vực. Hai bệ đá hai bên trôi lên xuống — phải nhảy qua.',
    grounds: const [
      CircleGround(0, 0, 4.2),
      RectGround(0, -5.2, 1.7, 1.3),
      RectGround(0, 5.2, 1.7, 1.3),
      RectGround(-6.8, 0, 1.8, 1.6, Motion(0, 2.4, 6.5)),
      RectGround(6.8, 0, 1.8, 1.6, Motion(0, 2.4, 6.5, math.pi)),
    ],
    walls: const [],
    props: const [
      PropDef(PropType.pillar, -1.7, -1.5, radius: 0.45),
      PropDef(PropType.pillar, 1.7, 1.5, radius: 0.45),
      PropDef(PropType.food, 0, 0),
      PropDef(PropType.food, 0, -5.6),
      PropDef(PropType.food, 0, 5.6),
    ],
    spawns: [..._ring(2.7, 6, 0), (0, -5.4), (0, 5.4)],
    viewHalfW: 9.2,
    viewHalfH: 7.0,
    voidKind: VoidKind.abyss,
    groundColor: 0xFFA7A29A,
    groundEdgeColor: 0xFF5B5750,
    voidColor: 0xFF1C1A2B,
  );

  static final all = <ArenaDef>[village, rooftop, temple];

  static ArenaDef byId(String id) =>
      all.firstWhere((a) => a.id == id, orElse: () => village);
}
