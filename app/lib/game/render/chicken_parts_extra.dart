part of 'chicken_painter.dart';

// Vietnamese breeds, hooked into the shared parts in chicken_parts.dart:
//  - Đông Tảo (dongtao): bulky mahogany bruiser on huge scaly red legs.
//  - Gà Tre (bantam): small, proud golden rooster with a glossy green tail.
//  - Gà Ác (silkie): fluffy black mystic with a pom-pom crest.

const _kDongtao = 5, _kBantam = 6, _kSilkie = 7;

const Color _hex = Color(0xFFC58BFF); // silkie magic purple

const _combPea = [-2.8, -10.2, 1.9, -0.3, -10.9, 2.1, 2.3, -10.3, 1.9];
const _silkieCrest = [
  -5.2, -7.6, 3.4, -1.8, -10.4, 4.0, 2.6, -10.6, 3.8, //
  5.8, -8.2, 3.0, 0.2, -13.4, 3.2,
];
const _silkieTail = [
  -2.5, -4.0, 3.8, -5.8, -1.0, 3.2, //
  -1.2, 0.5, 3.3, -5.0, -6.8, 3.0,
];

final _combSingle = _svg(
  'M -7 -7 Q -9.5 -13.5 -4.5 -10.5 Q -4 -17.5 -0.5 -11.5 '
  'Q 1.5 -19 3.5 -11.5 Q 7 -17 6.3 -10.5 Q 10.5 -12.5 7 -6.5 Z',
);
final _bantamTail = _tailSet(const [
  [1.0, 1.5, -9.0, -9.0, -16.0, -1.0, 4.2],
  [1.0, 0.0, -7.0, -21.0, -19.0, -13.0, 4.6],
  [1.0, -1.0, -2.0, -27.0, -17.0, -24.0, 5.0],
]);
final _bantamSheen = _svg('M 0.6 -8.2 Q -2.2 -20.8 -9 -24');
final Path _hackles = () {
  final p = Path();
  _leaf(p, 3, -12.5, 0.5, -8.5, -2, -4, 2.3);
  _leaf(p, 0.5, -12.5, -3, -9.5, -6, -5, 2.3);
  return _leaf(p, -2, -12, -5.5, -10, -8.5, -6.5, 2.1);
}();
final _cape = _svg(
  'M 3.5 -12 Q -3 -14.5 -9.5 -9.5 Q -11.5 -5.5 -10.5 -1.5 '
  'Q -9 -3 -7.5 -1.2 Q -6 -3.2 -4.5 -1.6 Q -3.5 -6 3.5 -12 Z',
);
final _fluffCurls = _svg(
  'M 3 -1.5 Q 5 -2.5 5.5 0 M -6.5 -2 Q -4.5 -3.5 -3.5 -1.5 '
  'M -1 -9 Q 1 -10 2 -8',
);
final _crestCurls = _svg(
  'M -3 -11 Q -1.5 -12.5 0 -11 M 2.5 -8.5 Q 4 -9.8 5.5 -8.4',
);

/// Silkie fluff: puffs ringing the body ellipse, as (x, y, r) triples.
final List<double> _fluffRing = [
  for (var i = 0; i < 11; i++) ...[
    -1 + 7.4 * math.cos(i * math.pi * 2 / 11 + 0.3),
    -5 + 5.6 * math.sin(i * math.pi * 2 / 11 + 0.3),
    3.3,
  ],
];

/// Breed palette/geometry overrides on top of the defaults.
void _breedArt(_Art a) {
  switch (a.kind) {
    case _kDongtao:
      a.light = const Color(0xFF6E2616); // dark breast
      a.legC = const Color(0xFFE5493A);
      a.legBackC = const Color(0xFFB9372B);
      a.legW = 7.0;
      a.toeW = 3.2;
    case _kBantam:
      a.light = const Color(0xFFFFD98A);
      a.legC = const Color(0xFFFFC928);
      a.legBackC = const Color(0xFFD99F18);
    default:
      a.wing = const Color(0xFF524862);
      a.legC = const Color(0xFF6C7593);
      a.legBackC = const Color(0xFF525A75);
      a.beakUp = const Color(0xFF5E6788);
      a.beakLo = const Color(0xFF474E6B);
      a.wattle = const Color(0xFF6A2850);
  }
}

// ---- poses -----------------------------------------------------------------

/// Breed posture tweaks layered over the shared state recipes.
void _breedPose(_Rig r, _Art a) {
  final q = 1 - r.lie;
  switch (a.kind) {
    case _kDongtao:
      // Low, stocky stance on wide-set legs.
      r.hipY += 1.0 * q;
      r.hipSpread = 2.2 * q;
      r.bX -= 2.2 * q;
      r.fX += 2.2 * q;
      r.lean += 0.04 * q;
      r.headY += 1.0 * q;
    case _kBantam:
      // Proud: chest out, head high, tail up.
      r.lean -= 0.08 * q;
      r.headY -= 1.4 * q;
      r.tail += 0.15 * q;
    default:
  }
}

void _breedSkill(_Rig r, int kind, double st, double t, double speed) {
  switch (kind) {
    case _kDongtao:
      _stomp(r, st, t);
    case _kBantam:
      _flurry(r, st, t, speed);
    default:
      _cast(r, st, t);
  }
}

/// Index of the current stomp (0..2) and time since it landed (<0: rising).
(int, double) _stompPhase(double st) {
  final i = math.min(2, math.max(0, (st / 0.3).floor()));
  return (i, st - (0.15 + 0.3 * i));
}

/// Stomp Chain: three near-leg slams at 0.15 / 0.45 / 0.75 s, each landing
/// a little further forward.
void _stomp(_Rig r, double st, double t) {
  final (i, u) = _stompPhase(st);
  final s = _c01((u + 0.15) / 0.15);
  // Slow raise, fast slam, then a squashy body bob on impact.
  final lift = u < 0 ? (s < 0.75 ? _ease(s / 0.75) : (1 - s) / 0.25) : 0.0;
  final hit = u >= 0 ? math.pow(1 - _c01(u / 0.15), 2).toDouble() : 0.0;
  final step = 1.5 * i, ux = 3.0 * lift, uy = -13.0 * lift;
  r.feet(
    -3.5,
    0,
    2.0 + step + ux,
    uy,
    toeF: 0.5 * lift,
    bend: 1.2 + 3.0 * lift,
  );
  r.body(
    lean: -0.16 * lift + 0.1 * hit,
    sx: 1 + 0.1 * hit,
    sy: 1 - 0.13 * hit,
    dy: -1.5 * lift + 2 * hit,
  );
  r.look(dx: 1.5 * hit - lift, dy: 2.5 * hit, rot: 0.15 * hit - 0.08 * lift);
  r.wings(0.35 + 0.55 * lift + 0.3 * hit, 0.3 + 0.5 * lift);
  r.face(_Eye.angry, beak: 0.5 * hit, brows: true);
  r.shake = math.sin(t * 80) * 1.3 * hit;
}

/// 0..1 forward reach of the peck cycle (~12 pecks a second).
double _peckPhase(double st) =>
    math.pow(0.5 - 0.5 * math.cos(st * 12 * math.pi * 2), 1.5).toDouble();

/// Peck Flurry: rapid darting pecks and flapping; legs keep running.
void _flurry(_Rig r, double st, double t, double speed) {
  if (speed > 0.05) _run(r, speed, t);
  final e = _peckPhase(st);
  r.body(lean: 0.14 + 0.16 * e);
  r.look(dx: -2 + 9 * e, dy: 1 + 3.5 * e, rot: 0.35 * e);
  r.wings(0.55 + 0.35 * math.sin(t * 42), 0.55 + 0.35 * math.sin(t * 42 + 1.2));
  r.face(_Eye.angry, beak: e > 0.55 ? 0.65 : 0.1, brows: true);
  r.lookX = 1;
}

/// Dark Vortex: hovering channel pose, wings raised, eyes blazing.
void _cast(_Rig r, double st, double t) {
  final e = _ease(_c01(st / 0.2)), bob = math.sin(t * 5) * 0.7;
  r.body(lean: -0.12 * e, sy: 1 + 0.04 * e, dy: (-2.5 + bob) * e);
  r.look(dx: -e, dy: -e, rot: -0.25 * e);
  r.wings(1.1 * e + 0.1 * math.sin(t * 9), 1.05 * e);
  r.face(_Eye.open, beak: 0.35 * e);
  final fy = (-2.5 + bob) * e;
  r.feet(-4.5, fy, 2.5, fy, toeB: 0.6 * e, toeF: 0.6 * e);
  r.tail = 0.2 * e;
}

// ---- parts -----------------------------------------------------------------

void _breedLeg(
  Canvas c,
  double hx,
  double hy,
  double kx,
  double ky,
  double fx,
  double fy,
) {
  if (_a.kind == _kDongtao) {
    // Scaly bands across the huge shanks, plus a glossy highlight.
    _p.reset();
    _scaleTicks(kx, ky, fx, fy, const [0.18, 0.36, 0.54, 0.72, 0.88]);
    _scaleTicks(hx, hy, kx, ky, const [0.5, 0.75]);
    c.drawPath(_p, _pen(const Color(0xFF8E2219), 1.0));
    _p
      ..reset()
      ..moveTo(kx + 1.6, ky + 1)
      ..lineTo(fx + 1.4, fy - 2.5);
    c.drawPath(_p, _pen(const Color(0x88FFB4A0), 1.3));
  } else if (_a.kind == _kSilkie) {
    // Feathered "trousers".
    final mx = kx + (fx - kx) * 0.4, my = ky + (fy - ky) * 0.4;
    _ball(c, kx - 1.2, ky, 2.0, _a.base);
    _ball(c, mx - 1.5, my, 1.5, _a.base);
  }
}

void _scaleTicks(double x0, double y0, double x1, double y1, List<double> at) {
  final dx = x1 - x0, dy = y1 - y0;
  final len = math.sqrt(dx * dx + dy * dy) + 1e-6;
  final ux = dx / len, uy = dy / len, hw = _a.legW * 0.42;
  for (final s in at) {
    final mx = x0 + dx * s, my = y0 + dy * s;
    _p
      ..moveTo(mx + uy * hw, my - ux * hw)
      ..quadraticBezierTo(mx + ux, my + uy, mx - uy * hw, my + ux * hw);
  }
}

void _breedTail(Canvas c) {
  final a = _a;
  switch (a.kind) {
    case _kDongtao:
      c.scale(0.8);
      _tail(c, _tailShapes, a.dark, a.base);
    case _kBantam:
      _tail(c, _bantamTail, const Color(0xFF1E3329), const Color(0xFF14231C));
      c.drawPath(_bantamSheen, _pen(const Color(0xFF3DBB78), 1.3));
    default:
      _bumps(c, _silkieTail, a.base);
      _ball(c, -6.6, -8.4, 2.0, a.accent);
  }
}

void _fluffBody(Canvas c) {
  final a = _a;
  c.drawOval(a.body, _ink(_ol * 2));
  _bumps(c, _fluffRing, a.base);
  c.drawOval(a.body, _fill(a.base));
  c.drawPath(_fluffCurls, _pen(const Color(0xFF6E6285), 1.2));
}

/// Bantam hackle mane / silkie star cape, over the body.
void _breedChest(Canvas c) {
  switch (_a.kind) {
    case _kBantam:
      _solid(c, _hackles, const Color(0xFFFFCF55));
    case _kSilkie:
      _solid(c, _cape, const Color(0xFF4B2A88));
      for (final (x, y) in const [(-7.5, -6.0), (-3.8, -9.6)]) {
        c.save();
        c.translate(x, y);
        c.scale(0.5);
        c.drawPath(_starShape, _fill(const Color(0xFFE2C4FF)));
        c.restore();
      }
    default:
  }
}

void _breedComb(Canvas c) {
  switch (_a.kind) {
    case _kDongtao:
      _bumps(c, _combPea, _red);
    case _kBantam:
      _solid(c, _combSingle, const Color(0xFFFF2D2D));
    default: // silkie: the pom-pom crest is drawn over the skull instead
  }
}

void _breedFace(Canvas c) {
  switch (_a.kind) {
    case _kDongtao:
      // Bare red face.
      c.drawOval(_rc(5.3, 0.3, 12.5, 10.5), _fill(const Color(0xFFDB4A3C)));
    case _kBantam:
      c.drawOval(_rc(1, 4.2, 4.8, 2.6), _fill(_blush));
    default:
      // Silkie: blue-black skin, turquoise earlobe and a pom-pom crest.
      c.drawOval(_rc(6, -0.6, 11.5, 9.5), _fill(const Color(0xFF34466E)));
      final lobe = _rc(-2.4, 3.4, 3.4, 4.4);
      c.drawOval(lobe, _ink(_ol * 1.6));
      c.drawOval(lobe, _fill(const Color(0xFF3FE0D0)));
      _bumps(c, _silkieCrest, const Color(0xFF62567A));
      c.drawPath(_crestCurls, _pen(const Color(0xFF9282AD), 1.2));
  }
}

/// Resting brows for the breeds; returns false to use the default logic.
bool _breedBrows(
  Canvas c,
  double nx,
  double ny,
  double nr,
  double fx,
  double fy,
  double fr,
) {
  switch (_a.kind) {
    case _kDongtao:
      // Stern: heavy and nearly flat.
      _p
        ..reset()
        ..moveTo(nx - nr * 1.15, ny - nr * 1.05)
        ..lineTo(nx + nr * 1.0, ny - nr * 0.85)
        ..moveTo(fx - fr * 0.9, fy - fr * 0.95)
        ..lineTo(fx + fr * 1.15, fy - fr * 1.15);
      c.drawPath(_p, _ink(2.8));
      return true;
    case _kBantam:
      // Cocky: one brow cocked high over the near eye.
      _p
        ..reset()
        ..moveTo(nx - nr, ny - nr * 1.3)
        ..quadraticBezierTo(nx, ny - nr * 2.1, nx + nr * 1.05, ny - nr * 1.45);
      c.drawPath(_p, _ink(2.0));
      return true;
    default:
      return false;
  }
}

// ---- effects ---------------------------------------------------------------

/// Impact burst at the beak tip on each flurry peck (head frame).
void _peckBurst(Canvas c) {
  final e = _peckPhase(_pose.stateTime);
  if (e < 0.7) return;
  final k = (e - 0.7) / 0.3, y = 1.2 + _a.beakY;
  _p.reset();
  for (var i = 0; i < 5; i++) {
    final ang = -0.9 + i * 0.45, r1 = 2.2 + 3.2 * k;
    final cs = math.cos(ang), sn = math.sin(ang);
    _p
      ..moveTo(19 + cs * 2.2, y + sn * 2.2)
      ..lineTo(19 + cs * r1, y + sn * r1);
  }
  _duo(c, _p, _yellow, 1.3, 1.0);
}

/// Skill effects: stomp shockwaves/dust and the silkie's channel glow.
void _breedFx(Canvas c, {required bool front}) {
  final st = _pose.stateTime;
  switch (_a.kind) {
    case _kDongtao:
      final (i, since) = _stompPhase(st);
      final u = since / 0.22;
      if (u < 0 || u > 1) return;
      final x = _r.fX, al = 1 - u;
      if (!front) {
        final ring = Color.fromRGBO(140, 90, 40, 0.7 * al);
        final rect = _rc(x, 0, 10 + 30 * u, 3.5 + 9 * u);
        c.drawOval(rect, _fxLine(ring, 0.6 + 2.4 * al));
        return;
      }
      // Dust puffs kicked out to both sides.
      for (var j = 0; j < 4; j++) {
        final side = j.isEven ? 1.0 : -1.0, far = j < 2 ? 0.0 : 1.0;
        final o = Offset(
          x + side * (4 + 12 * u + 4 * far),
          -2 - 4 * u - 2.5 * far,
        );
        final rad = (2.8 + 3.2 * u) * (1 - 0.3 * far);
        c.drawCircle(o, rad, _fxLine(_inkC.withValues(alpha: 0.5 * al), 1.6));
        c.drawCircle(o, rad, _fx(Color.fromRGBO(236, 222, 190, al)));
      }
    case _kSilkie:
      final e = _ease(_c01(st / 0.2));
      if (e <= 0) return;
      final pulse = 0.5 + 0.5 * math.sin(_t * 10);
      if (!front) {
        final glow = Color.fromRGBO(150, 70, 255, (0.14 + 0.12 * pulse) * e);
        c.drawOval(_rc(0, -22, 42 + 5 * pulse, 48 + 5 * pulse), _fx(glow));
        final ring = Color.fromRGBO(176, 92, 255, 0.55 * e);
        c.drawOval(_rc(0, -1, 34, 11), _fxLine(ring, 1.8));
        return;
      }
      // Motes spiralling up around the caster.
      for (var i = 0; i < 5; i++) {
        final ph = (_t * 0.9 + i / 5) % 1.0, ang = _t * 3 + i * 1.3;
        final x = math.cos(ang) * (18 - 6 * ph);
        final y = -4 - 34 * ph + math.sin(ang) * 3;
        final s = (0.4 + 1.6 * math.sin(ph * math.pi)) * e;
        _glint(c, x, y, s, _hex);
      }
    default:
  }
}
