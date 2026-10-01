part of 'chicken_painter.dart';

// Body parts, face and effect overlays for [ChickenPainter]. Constant shapes
// are parsed once into cached Paths; dynamic ones reuse [_p]. Fills are lerped
// toward white by the current hit flash instead of using a save layer.

const _kSamurai = 0, _kNinja = 1, _kTank = 2, _kBerserker = 3, _kTroll = 4;

const Color _inkC = Color(0xFF2B1B12);
const Color _white = Color(0xFFFFFFFF);
const Color _red = Color(0xFFE8302E);
const Color _bandRed = Color(0xFFD81E3A);
const Color _maskC = Color(0xFF15151C);
const Color _yellow = Color(0xFFFFE14D);
const Color _fire = Color(0xFFFF5A1F);
const Color _gold = Color(0xFFFFC21A);
const Color _steel = Color(0xFFAEB8C3);
const Color _steelDark = Color(0xFF6C7682);
const Color _blush = Color(0x77FF5C8A);
// Action colour language (also used by the effects layer): warm = attack,
// blue = guard, gold = push (crow).
const Color _atkC = Color(0xFFFF7A1A);
const Color _atkGlow = Color(0x88FFB347);
const Color _heavyC = Color(0xFFFF3B1F);
const Color _guardC = Color(0xFF4FB8FF);
const Color _pushC = Color(0xFFFFC21A);
const double _ol = 1.6; // visible outline width
const double _hr = 10.5; // head radius (head-local units)
const double _hs = 1.1; // head scale: big head, small body

final Paint _fillP = Paint()..isAntiAlias = true;
final Paint _strokeP = Paint()
  ..isAntiAlias = true
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;
final Path _p = Path();
final Path _p2 = Path();

// Per-call draw context, set by [ChickenPainter.paint]. Painting is
// synchronous, so one shared context is safe and allocation-free.
late _Art _a;
late _Rig _r;
late ChickenPose _pose;
double _t = 0;
double _flash = 0;

/// Per-look derived palette, cached per [ChickenLook] instance.
class _Art {
  _Art(ChickenLook l) {
    kind = switch (l.classId) {
      'ninja' => _kNinja,
      'tank' => _kTank,
      'berserker' => _kBerserker,
      'troll' => _kTroll,
      'dongtao' => _kDongtao,
      'bantam' => _kBantam,
      'silkie' => _kSilkie,
      _ => _kSamurai,
    };
    final ninja = kind == _kNinja;
    final raw = Color(ChickenClasses.byId(l.classId).color);
    // Lift the near-blacks a touch so masks and outlines still read.
    base = switch (kind) {
      _kNinja => Color.lerp(raw, _white, 0.1)!,
      _kSilkie => Color.lerp(raw, const Color(0xFF5A4B70), 0.25)!,
      _ => raw,
    };
    dark = Color.lerp(base, const Color(0xFF1A0E08), ninja ? 0.35 : 0.2)!;
    light = Color.lerp(base, const Color(0xFFFFF1D0), ninja ? 0.3 : 0.45)!;
    wing = ninja ? Color.lerp(base, const Color(0xFF9A9AB8), 0.35)! : dark;
    accent = Color(l.variant.color);
    kickFire = Color.lerp(accent, _fire, 0.5)!;
    slot = l.slotColor;
    slotDark = Color.lerp(slot, _inkC, 0.18)!;
    spark = Color(l.rarity.color);
    sparks = const [0, 3, 4, 5][l.rarity.index];
    crown = l.rarity == Rarity.legendary;
    seed = (slot.toARGB32() % 1009) / 1009.0 + l.classId.length * 0.137;
    eyeY = kind == _kTank ? 4.0 : 0;
    beakY = kind == _kTank ? 2.6 : 0;
    body = switch (kind) {
      _kTank => _rc(-1, -5.5, 21, 16),
      _kDongtao => _rc(-1, -5.8, 22, 17),
      _kBantam => _rc(-0.5, -5, 15.5, 13.5),
      _kSilkie => _rc(-1, -5, 17, 13.5),
      _ => _rc(-1, -5, 18, 14),
    };
    scale = kind == _kBantam ? 0.85 : 1.0;
    lid = switch (kind) {
      _kDongtao => 0.3,
      _kBantam => 0.4,
      _ => 0.0,
    };
    legW = switch (kind) {
      _kDongtao => 5.4,
      _kSilkie => 2.3,
      _ => 1.9,
    };
    toeW = kind == _kDongtao ? 2.8 : legW;
    legOl = kind == _kDongtao ? 1.4 : 1.3;
    legC = const Color(0xFFF9A41C);
    legBackC = const Color(0xFFD9800F);
    beakUp = const Color(0xFFFFBE1F);
    beakLo = const Color(0xFFF0900F);
    wattle = _red;
    if (kind >= _kDongtao) _breedArt(this);
  }

  late final int kind, sparks;
  late final Color base, dark, accent, kickFire;
  late final Color slot, slotDark, spark;
  late final bool crown;
  late final double seed, eyeY, beakY, scale, lid;
  late final Rect body;
  // Breeds override these in [_breedArt].
  late double legW, toeW, legOl;
  late Color light, wing, legC, legBackC, beakUp, beakLo, wattle;

  static final Expando<_Art> _cache = Expando<_Art>();

  static _Art of(ChickenLook l) => _cache[l] ??= _Art(l);
}

// ---- primitives ------------------------------------------------------------

Color _tint(Color c) => _flash <= 0 ? c : Color.lerp(c, _white, _flash)!;
Paint _fill(Color c) => _fillP..color = _tint(c);
Paint _ink(double w) => _strokeP
  ..color = _inkC
  ..strokeWidth = w;
Paint _pen(Color c, double w) => _strokeP
  ..color = _tint(c)
  ..strokeWidth = w;
Paint _fx(Color c) => _fillP..color = c;
Paint _fxLine(Color c, double w) => _strokeP
  ..color = c
  ..strokeWidth = w;

Rect _rc(double x, double y, double w, double h) =>
    Rect.fromCenter(center: Offset(x, y), width: w, height: h);
Rect _circ(double x, double y, double r) =>
    Rect.fromCircle(center: Offset(x, y), radius: r);

/// Outline-then-fill so overlapping sub-shapes merge into one silhouette.
void _solid(Canvas c, Path p, Color col) {
  c.drawPath(p, _ink(_ol * 2));
  c.drawPath(p, _fill(col));
}

void _ball(Canvas c, double x, double y, double r, Color col) {
  final o = Offset(x, y);
  c.drawCircle(o, r, _ink(_ol * 2));
  c.drawCircle(o, r, _fill(col));
}

/// Outlined stroke (legs, bands, scarves).
void _duo(Canvas c, Path p, Color col, double w, [double ol = _ol]) {
  c.drawPath(p, _ink(w + ol * 2));
  c.drawPath(p, _pen(col, w));
}

/// Union of circles given as flat (x, y, r) triples.
void _bumps(Canvas c, List<double> d, Color col) {
  for (var i = 0; i < d.length; i += 3) {
    c.drawCircle(Offset(d[i], d[i + 1]), d[i + 2], _ink(_ol * 2));
  }
  for (var i = 0; i < d.length; i += 3) {
    c.drawCircle(Offset(d[i], d[i + 1]), d[i + 2], _fill(col));
  }
}

/// Parses a tiny absolute SVG-style path ("M x y L x y Q .. C .. Z"), once.
Path _svg(String d) {
  final t = d.split(' ');
  final p = Path();
  var i = 0;
  double n() => double.parse(t[i++]);
  while (i < t.length) {
    switch (t[i++]) {
      case 'M':
        p.moveTo(n(), n());
      case 'L':
        p.lineTo(n(), n());
      case 'Q':
        p.quadraticBezierTo(n(), n(), n(), n());
      case 'C':
        p.cubicTo(n(), n(), n(), n(), n(), n());
      case 'Z':
        p.close();
    }
  }
  return p;
}

/// Leaf/feather from (x0,y0) to (x1,y1) bowed around control (cx,cy).
Path _leaf(
  Path p,
  double x0,
  double y0,
  double cx,
  double cy,
  double x1,
  double y1,
  double w,
) {
  final dx = x1 - x0, dy = y1 - y0;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1e-3) return p;
  final nx = -dy / len * w, ny = dx / len * w;
  return p
    ..moveTo(x0, y0)
    ..quadraticBezierTo(cx + nx, cy + ny, x1, y1)
    ..quadraticBezierTo(cx - nx, cy - ny, x0, y0)
    ..close();
}

/// Strip of a circle between y1 and y2 (headbands, masks).
Path _band(double r, double y1, double y2) {
  final x1 = math.sqrt(r * r - y1 * y1), x2 = math.sqrt(r * r - y2 * y2);
  final rad = Radius.circular(r);
  return Path()
    ..moveTo(-x1, y1)
    ..lineTo(x1, y1)
    ..arcToPoint(Offset(x2, y2), radius: rad)
    ..lineTo(-x2, y2)
    ..arcToPoint(Offset(-x1, y1), radius: rad)
    ..close();
}

/// Tail feathers in the tail frame: (feather, accent tip) pairs.
final List<Path> _tailShapes = _tailSet(const [
  [1.0, 2.0, -7.0, -3.0, -11.0, 5.0, 4.2],
  [1.0, 0.0, -9.0, -13.0, -15.0, -2.0, 4.6],
  [1.0, -1.0, -4.0, -21.0, -15.0, -14.0, 5.2],
]);

/// Builds (feather, tip) paths from (x0, y0, cx, cy, x1, y1, w) rows.
List<Path> _tailSet(List<List<double>> spec) {
  final out = <Path>[];
  const t0 = 0.58, u = 1 - t0;
  for (final f in spec) {
    final (x0, y0, cx, cy, x1, y1) = (f[0], f[1], f[2], f[3], f[4], f[5]);
    out.add(_leaf(Path(), x0, y0, cx, cy, x1, y1, f[6]));
    // Tip follows the same centre curve (de Casteljau split at t0).
    final px = u * u * x0 + 2 * t0 * u * cx + t0 * t0 * x1;
    final py = u * u * y0 + 2 * t0 * u * cy + t0 * t0 * y1;
    final qx = cx + (x1 - cx) * t0, qy = cy + (y1 - cy) * t0;
    out.add(_leaf(Path(), px, py, qx, qy, x1, y1, f[6] * 0.6));
  }
  return out;
}

final Path _starShape = () {
  final p = Path()..moveTo(0, -3);
  for (var j = 1; j < 10; j++) {
    final a = j * math.pi / 5 - math.pi / 2, rr = j.isEven ? 3.0 : 1.3;
    p.lineTo(math.cos(a) * rr, math.sin(a) * rr);
  }
  return p..close();
}();

final _wingShape = _svg(
  'M 2.5 -1.5 C 0 -6.2 -9 -6.2 -13.2 -1 Q -12.8 1.6 -10.2 1.3 '
  'Q -10 3.8 -7.1 3.1 Q -6 5.3 -3 4.3 C -0.5 4.6 2.5 2 2.5 -1.5 Z',
);
final _wingLine = _svg('M -3.2 1.6 L -6.4 1');
final _jawUp = _svg('M -0.6 -3.4 Q 5.2 -3.6 8.8 -0.2 Q 4.2 1 -0.2 0.6 Z');
final _jawLo = _svg('M -0.2 0.2 L 6.6 0.8 Q 3.2 3.8 0.2 2.9 Z');
final _tongue = _svg('M 2.2 1.2 L 2.6 5.6 Q 3.9 7.4 5 5.4 L 4.8 1.2 Z');
final _spikes = _svg(
  'M -9 -3 L -15.5 -6 L -10 -8 L -12.5 -13.5 L -6 -10.5 L -5.5 -17.5 '
  'L -1.5 -11.5 L 1.5 -19 L 3.5 -11 L 8.5 -15 L 7 -7 Z',
);
final _scar = _svg(
  'M -6.5 -3.5 L -2 5 M -5.9 -0.6 L -3.7 -1.6 M -4.4 2.4 '
  'L -2.2 1.4',
);
final _crownShape = _svg(
  'M -5 0 L -5.4 -5.5 L -2.6 -2.6 L 0 -6.6 '
  'L 2.6 -2.6 L 5.4 -5.5 L 5 0 Z',
);
final _hatShape = _svg('M -4.4 0 L 0 -11 L 4.4 0 Q 0 1.8 -4.4 0 Z');
final _hatStripes = _svg('M -2.9 -3.6 L 2.9 -3.6 M -1.5 -7.2 L 1.5 -7.2');
final _blade = _svg('M -5 -9 L 7 3');
final _hilt = _svg('M -6.5 -10.5 L -12 -17');
final _question = _svg(
  'M -1.9 -2.2 C -1.9 -5.2 2.4 -5.2 2.2 -2.4 '
  'C 2 -0.6 0 -0.8 0 1.2',
);
final _drop = _svg('M 0 -3.2 Q 2.4 0.2 0 1.6 Q -2.4 0.2 0 -3.2 Z');
final _glintShape = _svg(
  'M 0 -1 Q 0.2 -0.2 1 0 Q 0.2 0.2 0 1 '
  'Q -0.2 0.2 -1 0 Q -0.2 -0.2 0 -1 Z',
);
final _samuraiBand = _band(_hr + 0.4, -7.6, -4.0);
final _ninjaMask = _band(_hr + 0.4, -6.8, 1.4);

const _combStd = [-4.4, -8.8, 2.9, -0.9, -11.1, 3.4, 2.9, -9.8, 2.9];
const _combTank = [-2.6, -14.2, 2.3, 0.6, -15.8, 2.6, 3.8, -14.4, 2.2];
const _combTroll = [-7.6, -6.4, 2.7, -4.9, -9.6, 2.9, -1.2, -11.0, 2.9];
const _wattle = [9.3, 0.0, 2.3, 11.2, -0.9, 1.8];

// ---- body ------------------------------------------------------------------

void _legs(Canvas c) {
  _leg(c, false);
  _leg(c, true);
}

void _leg(Canvas c, bool front) {
  final a = _a, r = _r;
  final hx = front ? r.hfX : r.hbX, hy = front ? r.hfY : r.hbY;
  final fx = front ? r.fX : r.bX, fy = front ? r.fY : r.bY;
  final toe = front ? r.toeF : r.toeB;
  final dx = fx - hx, dy = fy - hy;
  final len = math.sqrt(dx * dx + dy * dy) + 1e-6;
  // Knee bows backward (perpendicular to hip→foot); three toes fan out.
  final kx = (hx + fx) / 2 - dy / len * r.bend;
  final ky = (hy + fy) / 2 + dx / len * r.bend;
  final cs = math.cos(toe), sn = math.sin(toe);
  _p
    ..reset()
    ..moveTo(hx, hy)
    ..lineTo(kx, ky)
    ..lineTo(fx, fy);
  _p2
    ..reset()
    ..moveTo(fx + 3.8 * cs - 0.2 * sn, fy + 3.8 * sn + 0.2 * cs)
    ..lineTo(fx, fy)
    ..lineTo(fx + 2.6 * cs - 1.5 * sn, fy + 2.6 * sn + 1.5 * cs)
    ..moveTo(fx, fy)
    ..lineTo(fx - 2.2 * cs - 0.3 * sn, fy - 2.2 * sn + 0.3 * cs);
  // Both outlines first so leg and toes merge into one silhouette.
  final col = front ? a.legC : a.legBackC;
  c.drawPath(_p, _ink(a.legW + a.legOl * 2));
  c.drawPath(_p2, _ink(a.toeW + a.legOl * 2));
  c.drawPath(_p, _pen(col, a.legW));
  c.drawPath(_p2, _pen(col, a.toeW));
  if (a.kind >= _kDongtao) _breedLeg(c, hx, hy, kx, ky, fx, fy);
}

void _neck(Canvas c) {
  final r = _r;
  _p
    ..reset()
    ..moveTo(r.wx(3, -9), r.wy(3, -9))
    ..lineTo(r.hx, r.hy);
  _duo(c, _p, _a.base, 8);
}

void _armorRim(Canvas c) {
  final p = _fxLine(const Color(0x99FFCC33), _ol * 2 + 4);
  c.drawOval(_a.body.inflate(0.5), p);
  c.drawCircle(Offset(5.5 + _r.headX, -19.5 + _r.headY), _hr * _hs, p);
}

/// Far wing, tail feathers and (samurai) katana, behind the body.
void _bodyBack(Canvas c) {
  final a = _a, r = _r;
  if (r.wingFar > 0.2) _wing(c, -2.5, -9, r.wingFar - 0.1, a.dark);
  c.save();
  c.translate(-8, -7);
  c.rotate(r.tail);
  if (a.kind >= _kDongtao) {
    _breedTail(c);
  } else {
    _tail(c, _tailShapes, a.dark, a.base);
  }
  c.restore();
  if (a.kind != _kSamurai) return;
  _duo(c, _blade, const Color(0xFFDDE3EA), 2.2);
  _duo(c, _hilt, const Color(0xFF2E2A5A), 2.8);
  _ball(c, -6, -10, 1.9, _gold);
}

void _tail(Canvas c, List<Path> set, Color side, Color main) {
  for (var i = 0; i < 3; i++) {
    _solid(c, set[i * 2], i == 2 ? main : side);
    c.drawPath(set[i * 2 + 1], _fill(_a.accent));
  }
}

void _bodyFront(Canvas c) {
  final a = _a, tank = a.kind == _kTank;
  if (a.kind == _kSilkie) {
    _fluffBody(c);
  } else {
    c.drawOval(a.body, _ink(_ol * 2));
    c.drawOval(a.body, _fill(a.base));
    final bx = a.body.center.dx + a.body.width * 0.26;
    c.drawOval(_rc(bx, -2.6, 8, 7), _fill(a.light));
  }
  if (a.kind >= _kDongtao) _breedChest(c);
  if (tank) {
    final plate = RRect.fromLTRBXY(1.2, -10, 9.6, 0.5, 3.5, 3.5);
    c.drawRRect(plate, _ink(_ol * 2));
    c.drawRRect(plate, _fill(_steel));
    c.drawCircle(const Offset(3.4, -7.8), 0.9, _fill(_steelDark));
    c.drawCircle(const Offset(7.4, -7.8), 0.9, _fill(_steelDark));
  }
  if (!_wingUp) _nearWing(c);
  if (_pose.flags & FFlag.burning == 0) return;
  _flame(c, -8, -10, 7 + 1.8 * math.sin(_t * 17), 3, _fire);
  _flame(c, -1.5, -3.5, 6 + 1.5 * math.sin(_t * 21 + 2), 2.6, _fire);
}

/// A raised near wing sits in front of the scarf tails (drawn in [_scarf]).
bool get _wingUp => _r.wing > 0.45;

void _nearWing(Canvas c) => _wing(c, -0.5, -8, _r.wing, _a.wing);

void _wing(Canvas c, double px, double py, double ang, Color col) {
  c.save();
  c.translate(px, py);
  c.rotate(ang);
  _solid(c, _wingShape, col);
  c.drawPath(_wingLine, _ink(1.1));
  c.restore();
}

/// Player-colour neckerchief (long trailing tails for the ninja).
void _scarf(Canvas c) {
  final a = _a, speed = _pose.speed01;
  final fl = math.sin(_t * (8 + 6 * speed));
  final len = a.kind == _kNinja ? 13.0 + 3 * speed : 5.5 + 2 * speed;
  final m1 = -3 - len * 0.5, e1 = -3 - len;
  final m2 = -3 - len * 0.45, e2 = -2.5 - len * 0.85;
  _p.reset();
  _leaf(_p, -3, -11, m1, -12.5 + fl * 1.5, e1, -11.5 + fl * 2.5, 3.2);
  _leaf(_p, -3, -10.5, m2, -8.5 - fl, e2, -6 - fl * 1.5, 2.8);
  _solid(c, _p, a.slotDark);
  _p
    ..reset()
    ..moveTo(-3, -11.5)
    ..quadraticBezierTo(3, -7, 10, -9.8);
  _duo(c, _p, a.slot, 3.6);
  _ball(c, -3, -11, 2.0, a.slot);
  if (_wingUp) _nearWing(c);
}

// ---- head ------------------------------------------------------------------

void _head(Canvas c) {
  final a = _a, kind = a.kind, flags = _pose.flags, t = _t;
  final fl = math.sin(t * (7 + 5 * _pose.speed01));
  // Behind the skull: comb and headband tails.
  switch (kind) {
    case _kTank:
      _bumps(c, _combTank, _red);
    case _kBerserker:
      _solid(c, _spikes, const Color(0xFF7E1710));
    case _kTroll:
      _bumps(c, _combTroll, _red);
    case >= _kDongtao:
      _breedComb(c);
    default:
      _bumps(c, _combStd, _red);
  }
  if (kind == _kSamurai) {
    _p.reset();
    _leaf(_p, -9.5, -5, -14, -7 + fl, -19, -8.5 + fl * 2.2, 3.4);
    _leaf(_p, -9.5, -4, -13.5, -2.5 - fl, -17.5, -0.5 - fl * 1.8, 3.0);
    _solid(c, _p, _bandRed);
  }
  _ball(c, 0, 0, _hr, a.base);
  if (kind >= _kDongtao) {
    _breedFace(c);
  } else if (kind != _kNinja) {
    c.drawOval(_rc(1, 4.2 + a.eyeY * 0.4, 4.8, 2.6), _fill(_blush));
  }
  switch (kind) {
    case _kSamurai:
      _solid(c, _samuraiBand, _bandRed);
      _ball(c, -10, -5.6, 1.9, _bandRed);
    case _kNinja:
      _solid(c, _ninjaMask, _maskC);
    case _kBerserker:
      c.drawPath(_scar, _pen(const Color(0xFFF7C6B5), 1.3));
  }
  _eyes(c);
  if (kind == _kTank) _helmet(c);
  _beak(c);
  if (kind == _kTroll) _partyHat(c, fl);
  if (a.crown) _crown(c);

  // Head-anchored effects.
  if (flags & FFlag.empowered != 0) {
    final s = 2.6 + math.sin(t * 10) * 0.9;
    _glint(c, 17.5, -2.8 + a.beakY, s, const Color(0xFFB05CFF));
  }
  if (flags & FFlag.burning != 0) {
    _flame(c, -4, -9, 7 + 1.8 * math.sin(t * 19 + 1), 3, _fire);
  }
  switch (_pose.state) {
    case FState.stunned:
      _stars(c);
    case FState.exhausted || FState.falling:
      _sweat(c);
    case FState.crow:
      _waves(c, rage: false);
    case FState.rageRoar:
      _waves(c, rage: true);
    case FState.skill when kind == _kBerserker:
      _waves(c, rage: true);
    case FState.skill when kind == _kBantam:
      _peckBurst(c);
    default:
  }
  if (flags & FFlag.confused != 0) _confused(c);
}

void _eyes(Canvas c) {
  final a = _a, r = _r, troll = a.kind == _kTroll;
  final nx = troll ? 2.0 : 2.6, ny = -2.6 + a.eyeY, nr = troll ? 4.4 : 3.5;
  final fx = troll ? 8.4 : 8.0, fy = (troll ? -1.6 : -3.0) + a.eyeY;
  final fr = troll ? 2.1 : 2.7;
  _eye(c, nx, ny, nr, true);
  _eye(c, fx, fy, fr, false);
  final eyeball = r.eye.index <= _Eye.angry.index;
  if (!r.brows && eyeball && _breedBrows(c, nx, ny, nr, fx, fy, fr)) return;
  final brows =
      (r.brows || a.kind == _kBerserker) &&
      a.kind != _kTank &&
      a.kind != _kNinja &&
      eyeball;
  if (!brows) return;
  _p
    ..reset()
    ..moveTo(nx - nr * 1.1, ny - nr * 1.45)
    ..lineTo(nx + nr * 0.95, ny - nr * 0.75)
    ..moveTo(fx - fr * 0.9, fy - fr * 0.8)
    ..lineTo(fx + fr * 1.1, fy - fr * 1.5);
  c.drawPath(_p, _ink(2.3));
}

void _eye(Canvas c, double x, double y, double r, bool near) {
  final mode = _r.eye, mad = _pose.flags & FFlag.mad != 0;
  final silkie = _a.kind == _kSilkie;
  if (mode.index > _Eye.angry.index) {
    // Line-only expressions: blink, ^ ^, > <, X X.
    final d = near ? 1.0 : -1.0, s = math.max(r * 0.95, 2.8);
    _p.reset();
    switch (mode) {
      case _Eye.blink:
        _p
          ..moveTo(x - r, y + 0.3)
          ..quadraticBezierTo(x, y + r * 0.8, x + r, y + 0.3);
      case _Eye.happy:
        _p
          ..moveTo(x - r, y + r * 0.4)
          ..quadraticBezierTo(x, y - r * 1.2, x + r, y + r * 0.4);
      case _Eye.squeeze:
        _p
          ..moveTo(x - r * 0.8 * d, y - r * 0.75)
          ..lineTo(x + r * 0.7 * d, y)
          ..lineTo(x - r * 0.8 * d, y + r * 0.75);
      default:
        _p
          ..moveTo(x - s, y - s)
          ..lineTo(x + s, y + s)
          ..moveTo(x + s, y - s)
          ..lineTo(x - s, y + s);
    }
    c.drawPath(_p, _ink(mode == _Eye.cross ? 2.6 : 2.2));
    return;
  }
  final rr = mode == _Eye.panic ? r * 1.15 : r;
  final o = Offset(x, y);
  if (mad) c.drawCircle(o, rr * 1.9, _fx(const Color(0x55FF2A1A)));
  if (silkie && !mad) c.drawCircle(o, rr * 1.8, _fx(const Color(0x66B05CFF)));
  c.drawCircle(o, rr, _ink(2.4));
  c.drawCircle(o, rr, _fill(_white));
  if (mode == _Eye.spiral) {
    _p
      ..reset()
      ..moveTo(x, y);
    for (var i = 1; i <= 16; i++) {
      final ang = _t * 9 + i * 0.75, dist = rr * 0.85 * i / 16;
      _p.lineTo(x + math.cos(ang) * dist, y + math.sin(ang) * dist);
    }
    c.drawPath(_p, _ink(1.1));
    return;
  }
  final pr = mode == _Eye.panic ? r * 0.3 : r * 0.55;
  final px = x + (0.12 + _r.lookX * 0.28) * rr;
  final py = y + _r.lookY * 0.3 * rr + (mode == _Eye.tired ? rr * 0.25 : 0);
  final pupil = mad
      ? const Color(0xFFE0140A)
      : (silkie ? const Color(0xFF9B3CFF) : _inkC);
  c.drawCircle(Offset(px, py), pr, _fill(pupil));
  final glare = Offset(px - pr * 0.35, py - pr * 0.4);
  c.drawCircle(glare, pr * 0.36, _fill(_white));
  final breedLid = mode == _Eye.open ? _a.lid : 0.0;
  if (mode != _Eye.tired && mode != _Eye.angry && breedLid == 0) return;
  // Eyelid: a chord of the eyeball — flat (tired, breed lids) or slanted
  // inward (angry).
  final tired = mode == _Eye.tired;
  var a0 = tired ? math.pi : (near ? math.pi + 0.5 : math.pi - 0.15);
  var sweep = tired ? math.pi : math.pi - 0.35;
  if (breedLid > 0) {
    final b = math.asin(1 - 2 * breedLid);
    a0 = math.pi + b;
    sweep = math.pi - 2 * b;
  }
  final a1 = a0 + sweep;
  final lid = _a.kind == _kNinja ? _maskC : _a.base;
  c.drawArc(_circ(x, y, rr + 0.4), a0, sweep, false, _fill(lid));
  final p0 = Offset(x + math.cos(a0) * rr, y + math.sin(a0) * rr);
  final p1 = Offset(x + math.cos(a1) * rr, y + math.sin(a1) * rr);
  c.drawLine(p0, p1, _ink(1.7));
}

void _beak(Canvas c) {
  const hx = 8.6;
  final hy = 1.4 + _a.beakY, open = _r.beak;
  final lo = open * 0.75, up = -open * 0.22;
  // Wattle hangs from the lower jaw.
  c.save();
  c.translate(0, hy + 4.2 + open * 2.4);
  _bumps(c, _wattle, _a.wattle);
  c.restore();
  if (open > 0.05) {
    final uc = math.cos(up), us = math.sin(up);
    final lc = math.cos(lo), ls = math.sin(lo);
    _p
      ..reset()
      ..moveTo(hx, hy + 0.3)
      ..lineTo(hx + 8.4 * uc + 0.2 * us, hy + 8.4 * us - 0.2 * uc)
      ..lineTo(hx + 6.4 * lc - 0.8 * ls, hy + 6.4 * ls + 0.8 * lc)
      ..close();
    _solid(c, _p, const Color(0xFF8A1424));
  }
  c.save();
  c.translate(hx, hy);
  c.rotate(lo);
  _solid(c, _jawLo, _a.beakLo);
  if (_a.kind == _kTroll || _r.tongue) {
    _solid(c, _tongue, const Color(0xFFFF6F91));
  }
  c.rotate(up - lo);
  _solid(c, _jawUp, _a.beakUp);
  c.drawCircle(const Offset(2.4, -1.9), 0.55, _fill(_inkC));
  c.restore();
}

void _helmet(Canvas c) {
  final dome = _circ(0.5, -3.2, 11.4);
  c.drawArc(dome, math.pi, math.pi, false, _ink(_ol * 2));
  c.drawArc(dome, math.pi, math.pi, false, _fill(_steel));
  final shine = _pen(const Color(0xFFEAF0F5), 1.7);
  c.drawArc(_circ(0.5, -3.2, 8), math.pi + 0.55, 0.9, false, shine);
  final rim = RRect.fromLTRBXY(-12.2, -5.0, 13.8, -1.4, 1.7, 1.7);
  c.drawRRect(rim, _ink(_ol * 2));
  c.drawRRect(rim, _fill(_steelDark));
  c.drawCircle(const Offset(5.5, -9.5), 0.9, _fill(_steelDark));
  c.drawCircle(const Offset(8.8, -6.8), 0.9, _fill(_steelDark));
}

void _partyHat(Canvas c, double fl) {
  c.save();
  c.translate(2.5, -9.6);
  c.rotate(0.35 + fl * 0.05);
  _solid(c, _hatShape, const Color(0xFFFF4FA3));
  c.drawPath(_hatStripes, _pen(_yellow, 1.6));
  _ball(c, 0, -11, 1.9, _yellow);
  c.restore();
}

void _crown(Canvas c) {
  final (x, y) = switch (_a.kind) {
    _kTank => (0.5, -14.2),
    _kTroll || _kBantam => (-4.5, -11.0),
    _kSilkie => (0.5, -15.5),
    _ => (-0.8, -12.2),
  };
  c.save();
  c.translate(x, y);
  c.rotate(-0.18);
  _solid(c, _crownShape, _gold);
  c.drawCircle(const Offset(0, -1.4), 1.0, _fill(_red));
  c.restore();
}

// ---- effects ---------------------------------------------------------------

void _backFx(Canvas c) {
  final a = _a, r = _r, p = _pose;
  if (p.flags & FFlag.rage != 0) _rageAura(c);
  final k = p.stateDur > 0 ? p.stateTime / p.stateDur : 0.0;
  switch (p.state) {
    case FState.heavyCharge:
      _chargeRing(c, _c01(p.heavyCharge01));
    case FState.block:
      _guardRing(c);
    case FState.dodge:
      _speedLines(c, 1);
    case FState.heavyAttack when k > 0.45:
      _speedLines(c, 0.7);
    case FState.skill when a.kind == _kNinja:
      // Shadow Dash afterimages.
      final ghost = Color.lerp(a.base, a.accent, 0.35)!;
      for (var i = 1; i <= 2; i++) {
        final dx = -13.0 * i, paint = _fx(ghost.withValues(alpha: 0.3 / i));
        c.drawOval(_rc(r.bcx + dx, r.bcy, 18, 14), paint);
        c.drawCircle(Offset(r.hx + dx, r.hy), _hr * _hs, paint);
      }
      _speedLines(c, 1);
    case FState.skill when a.kind == _kSamurai && p.stateTime >= 0.1:
      _speedLines(c, 0.8);
    case FState.skill when a.kind >= _kDongtao:
      _breedFx(c, front: false);
    default:
  }
}

void _frontFx(Canvas c) {
  final a = _a, r = _r, p = _pose, st = p.stateTime;
  switch (p.state) {
    case FState.hitstun:
      _feathers(c);
    case FState.attack:
      _lightSlash(c);
    case FState.heavyCharge when p.heavyCharge01 >= 0.9:
      _alert(c);
    case FState.heavyAttack:
      final k = p.stateDur > 0 ? st / p.stateDur : 0.0;
      final e = _c01((k - 0.45) / 0.18);
      if (e <= 0) return;
      final fade = 1 - _c01((k - 0.7) / 0.3);
      _slash(c, _circ(8, -22, 26), -1.4, 2.3 * e, fade, heavy: true);
    case FState.skill when a.kind == _kSamurai && st >= 0.1 && st < 0.38:
      // Flame on the kicking foot, trailing backward.
      c.save();
      c.translate(r.fX + 1.5, r.fY);
      c.rotate(-math.pi / 2 - 0.25);
      _flame(c, 0, 0, 15 + 2.5 * math.sin(_t * 30), 5.5, a.kickFire);
      c.restore();
    case FState.skill when a.kind >= _kDongtao:
      _breedFx(c, front: true);
    case FState.block:
      _shield(c);
    default:
  }
}

/// Outlined flame with a yellow core, rising from (x, y).
void _flame(Canvas c, double x, double y, double h, double w, Color col) {
  for (var i = 0; i < 2; i++) {
    final core = i == 1;
    final ww = core ? w * 0.5 : w, hh = core ? h * 0.58 : h;
    final yy = core ? y - 0.4 : y, top = yy - hh;
    final x1 = x - ww * 1.2, x2 = x - ww * 0.5;
    final x3 = x + ww * 0.35, x4 = x + ww * 1.2;
    _p
      ..reset()
      ..moveTo(x, yy)
      ..cubicTo(x1, yy - hh * 0.15, x2, yy - hh * 0.65, x + ww * 0.25, top)
      ..cubicTo(x3, yy - hh * 0.6, x4, yy - hh * 0.2, x, yy)
      ..close();
    if (!core) c.drawPath(_p, _ink(_ol * 1.6));
    c.drawPath(_p, _fx(core ? const Color(0xFFFFE45C) : col));
  }
}

void _rageAura(Canvas c) {
  final r = _r, t = _t;
  final cx = (r.bcx + r.hx) / 2, cy = (r.bcy + r.hy) / 2;
  final pulse = 0.5 + 0.5 * math.sin(t * 9);
  _p.reset();
  for (var i = 0; i < 28; i++) {
    final ang = i * math.pi / 14;
    final spike = 26.0 + 3 * math.sin(t * 13 + i);
    final rad = (i.isEven ? spike : 19.0) + pulse * 1.5;
    final x = cx + math.cos(ang) * rad * 0.85, y = cy + math.sin(ang) * rad;
    if (i == 0) {
      _p.moveTo(x, y);
    } else {
      _p.lineTo(x, y);
    }
  }
  _p.close();
  c.drawPath(_p, _fx(Color.fromRGBO(255, 90, 20, 0.28 + 0.14 * pulse)));
  final edge = Color.fromRGBO(255, 60, 10, 0.45 + 0.25 * pulse);
  c.drawPath(_p, _fxLine(edge, 1.4));
  c.drawOval(_rc(cx, cy, 30, 36), _fx(const Color(0x33FF2A14)));
}

void _chargeRing(Canvas c, double charge) {
  // Warm like every attack (not the element colour, which can be blue and
  // read as a guard): gold while charging, red when full.
  final accent = Color.lerp(_pushC, _heavyC, charge)!, rx = 21 - 6 * charge;
  final ring = accent.withValues(alpha: 0.3 + 0.6 * charge);
  c.drawOval(_rc(0, -1, rx * 2, rx * 0.8), _fxLine(ring, 1.5 + 2 * charge));
  if (charge <= 0.35) return;
  final g = (charge - 0.35) / 0.65 * (0.75 + 0.25 * math.sin(_t * 30));
  c.drawOval(_rc(0, -21, 36, 42), _fx(accent.withValues(alpha: 0.28 * g)));
}

void _speedLines(Canvas c, double s) {
  final paint = _fxLine(Color.fromRGBO(43, 27, 18, 0.45 * s), 1.5);
  for (var i = 0; i < 4; i++) {
    final ph = (_t * 5 + i * 0.29) % 1.0;
    final y = -9.0 - i * 7.5, x0 = -14.0 - ph * 8;
    final len = (i.isEven ? 12 : 7) * (1 - ph * 0.5);
    c.drawLine(Offset(x0, y), Offset(x0 - len, y), paint);
  }
}

/// Light combo slash: 1 = beak swipe at head height, 2 = low kick arc,
/// 3 = big flying-kick arc. Sweeps during the strike, then fades.
void _lightSlash(Canvas c) {
  final p = _pose, r = _r;
  final k = p.stateDur > 0 ? _c01(p.stateTime / p.stateDur) : 0.0;
  final fade = 1 - _c01((k - 0.62) / 0.3);
  switch (p.comboStep) {
    case >= 3:
      final s = _ease(_c01(k / 0.35));
      if (s <= 0) return;
      _slash(c, _circ(6, -15, 21), -1.5, 2.6 * s, fade, heavy: true);
    case 2:
      final e = _c01((k - 0.4) / 0.22);
      if (e <= 0) return;
      _slash(c, _circ(r.hipX + 6, r.hipY + 2, 17), -0.7, 2.0 * e, fade);
    default:
      final e = _c01((k - 0.4) / 0.22);
      if (e <= 0) return;
      _slash(c, _circ(r.hx + 7, r.hy + 3, 17), -1.35, 2.1 * e, fade);
  }
}

/// Crescent swoosh: soft glow, hot core, white edge.
void _slash(
  Canvas c,
  Rect rect,
  double start,
  double sweep,
  double fade, {
  bool heavy = false,
}) {
  if (fade <= 0 || sweep <= 0) return;
  final glow = heavy ? const Color(0x99FF6A2A) : _atkGlow;
  final hot = heavy ? _heavyC : _atkC;
  final w = heavy ? 1.4 : 1.2;
  c.drawArc(
    rect,
    start,
    sweep,
    false,
    _fxLine(glow.withValues(alpha: glow.a * fade), 9 * w),
  );
  c.drawArc(
    rect,
    start,
    sweep,
    false,
    _fxLine(hot.withValues(alpha: fade), 4.5 * w),
  );
  final tip = sweep * 0.55;
  c.drawArc(
    rect,
    start + sweep - tip,
    tip,
    false,
    _fxLine(_white.withValues(alpha: 0.9 * fade), 1.8 * w),
  );
}

/// Flashing "!" over the head: the heavy is fully charged — get away.
void _alert(Canvas c) {
  final r = _r;
  if ((_t * 10).floor().isOdd) return;
  final x = r.hx, y = r.hy - 26;
  final bar = RRect.fromRectAndRadius(
    _rc(x, y - 3, 4.4, 10),
    const Radius.circular(2.2),
  );
  c.drawRRect(bar.inflate(1.6), _fx(_inkC));
  c.drawRRect(bar, _fx(_heavyC));
  c.drawCircle(Offset(x, y + 5), 3.8, _fx(_inkC));
  c.drawCircle(Offset(x, y + 5), 2.3, _fx(_heavyC));
}

/// Guard: a blue heater shield in front of the chest. It pales and
/// cracks as its HP drops, and flickers when about to shatter.
void _shield(Canvas c) {
  final hp = _c01(_pose.shield01);
  final danger = hp < 0.25;
  final pulse = danger
      ? ((_t * 16).floor().isEven ? 1.0 : 0.55)
      : 0.8 + 0.2 * math.sin(_t * 10);
  final col = Color.lerp(const Color(0xFFB8C4CC), _guardC, hp)!;
  c.save();
  c.translate(14, -20);
  c.rotate(-0.12);
  _p
    ..reset()
    ..moveTo(-9, -12)
    ..quadraticBezierTo(0, -15, 9, -12)
    ..cubicTo(9, 0, 6, 8, 0, 13)
    ..cubicTo(-6, 8, -9, 0, -9, -12)
    ..close();
  c.drawPath(_p, _fxLine(_inkC, 3.4));
  c.drawPath(_p, _fx(col.withValues(alpha: 0.55 * pulse)));
  c.drawPath(_p, _fxLine(_white.withValues(alpha: 0.9), 1.4));
  // Emblem: a white bar down the middle and across.
  final mark = _fxLine(_white.withValues(alpha: 0.75 * pulse), 1.6);
  c.drawLine(const Offset(0, -9), const Offset(0, 8), mark);
  c.drawLine(const Offset(-5.5, -4), const Offset(5.5, -4), mark);
  // Cracks: one below 2/3 HP, a web below 1/3.
  if (hp < 0.66) {
    final crack = _fxLine(_inkC, 1.3);
    _p2
      ..reset()
      ..moveTo(6, -11)
      ..lineTo(2, -6)
      ..lineTo(4, -2)
      ..lineTo(-1, 3);
    if (hp < 0.33) {
      _p2
        ..moveTo(-8, -6)
        ..lineTo(-3, -3)
        ..lineTo(-4, 2)
        ..moveTo(2, -6)
        ..lineTo(-3, -3)
        ..moveTo(4, -2)
        ..lineTo(7, 3);
    }
    c.drawPath(_p2, crack);
  }
  c.restore();
}

/// Blue ring on the ground while guarding (readable from far away).
void _guardRing(Canvas c) {
  final pulse = 0.75 + 0.25 * math.sin(_t * 10);
  final oval = _rc(0, -1, 40, 15);
  c.drawOval(oval, _fx(_guardC.withValues(alpha: 0.16)));
  c.drawOval(oval, _fxLine(_guardC.withValues(alpha: 0.85 * pulse), 2.2));
}

/// Feathers knocked loose on hit, flying out and falling.
void _feathers(Canvas c) {
  final r = _r, st = _pose.stateTime, dur = _pose.stateDur;
  final alpha = 1 - _c01(st / (dur > 0 ? dur : 0.3));
  if (alpha <= 0) return;
  final d = 12 + st * 60;
  for (var i = 0; i < 4; i++) {
    final ang = const [-2.95, -2.3, -0.85, -0.2][i];
    final x = r.bcx + math.cos(ang) * d * 1.1;
    final y = r.bcy - 2 + math.sin(ang) * d * 0.7 + st * st * 60;
    final rot = i * 1.3 + st * 14;
    final dx = math.cos(rot) * 2.8, dy = math.sin(rot) * 2.8;
    _p.reset();
    _leaf(_p, x - dx, y - dy, x, y, x + dx, y + dy, 2.6);
    c.drawPath(_p, _fxLine(_inkC.withValues(alpha: alpha), 2.2));
    c.drawPath(_p, _fx(_a.base.withValues(alpha: alpha)));
  }
}

/// Sound-wave arcs in front of the beak (head frame).
void _waves(Canvas c, {required bool rage}) {
  // Push = gold (crow); the rage roar keeps its red.
  final col = rage ? _heavyC : _pushC;
  for (var i = 0; i < 4; i++) {
    final ph = (_pose.stateTime * (rage ? 3.4 : 3.0) + i / 4) % 1.0;
    final rect = _circ(14, _a.beakY, 5 + ph * 22);
    final alpha = (1 - ph) * 0.95;
    c.drawArc(
      rect,
      -0.9,
      1.8,
      false,
      _fxLine(_inkC.withValues(alpha: alpha * 0.6), 5),
    );
    c.drawArc(rect, -0.9, 1.8, false, _fxLine(col.withValues(alpha: alpha), 3));
  }
}

/// Dizzy stars orbiting above the head.
void _stars(Canvas c) {
  for (var i = 0; i < 3; i++) {
    final ang = _t * 4 + i * 2.094;
    c.save();
    c.translate(math.cos(ang) * 11, -17 + math.sin(ang) * 3.2);
    c.rotate(ang * 0.5);
    c.drawPath(_starShape, _ink(2.2));
    c.drawPath(_starShape, _fill(const Color(0xFFFFD83A)));
    c.restore();
  }
}

/// Two "?" marks orbiting above the head.
void _confused(Canvas c) {
  for (var i = 0; i < 2; i++) {
    final ang = _t * 3 + i * math.pi;
    final col = i == 0 ? _yellow : const Color(0xFF7FE3FF);
    c.save();
    c.translate(math.cos(ang) * 8, -20 + math.sin(ang) * 2.2);
    _duo(c, _question, col, 1.7, 1.2);
    _ball(c, 0, 3.6, 1.0, col);
    c.restore();
  }
}

void _sweat(Canvas c) {
  for (var i = 0; i < 2; i++) {
    final ph = (_t * 1.3 + i * 0.5) % 1.0, al = 1 - ph;
    c.save();
    c.translate(-6.5 - i * 3.5, -9.0 + i * 5 + ph * 5);
    c.drawPath(_drop, _fxLine(_inkC.withValues(alpha: al), 2.4));
    c.drawPath(_drop, _fx(const Color(0xFF8FD3FF).withValues(alpha: al)));
    c.restore();
  }
}

/// Four-point sparkle.
void _glint(Canvas c, double x, double y, double s, Color col) {
  c.save();
  c.translate(x, y);
  c.scale(s);
  c.drawPath(_glintShape, _fxLine(const Color(0x992B1B12), 1.2 / s));
  c.drawPath(_glintShape, _fx(col));
  c.drawCircle(Offset.zero, 0.22, _fx(_white));
  c.restore();
}

/// Rarity sparkles orbiting the chicken, twinkling in and out.
void _sparkles(Canvas c) {
  final n = _a.sparks;
  for (var i = 0; i < n; i++) {
    final tw = math.sin(_t * 3 + i * 2.1);
    if (tw <= 0) continue;
    final ang = (_t * 0.35 + i / n) * math.pi * 2;
    final x = math.cos(ang) * 19, y = -22 + math.sin(ang) * 21;
    _glint(c, x, y, 1.3 + tw * 1.9, _a.spark);
  }
}
