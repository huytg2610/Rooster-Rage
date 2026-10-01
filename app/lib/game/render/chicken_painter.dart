/// Procedural chicken renderer: every rooster is drawn with Canvas calls, no
/// sprite assets. Parts and effects live in `chicken_parts.dart`; the
/// Vietnamese breeds (Đông Tảo, Gà Tre, Gà Ác) in `chicken_parts_extra.dart`.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:rooster_core/rooster_core.dart';

part 'chicken_parts.dart';
part 'chicken_parts_extra.dart';

/// Visual identity of one chicken (constant for a match).
class ChickenLook {
  final String classId; // any ChickenClasses id; unknown ids draw as samurai
  final Variant variant; // element tint/accents
  final Rarity rarity; // cosmetic flair
  final Color slotColor; // player color (neck scarf)

  const ChickenLook({
    required this.classId,
    required this.variant,
    required this.rarity,
    required this.slotColor,
  });
}

/// Per-frame pose, derived from network snapshots.
class ChickenPose {
  final FState state;
  final double stateTime; // seconds in current state
  final double stateDur; // duration of timed states (0 if untimed)
  final double time; // global clock seconds (idle bob, flicker)
  final bool faceRight; // sprite faces right when true
  final double speed01; // 0..1 horizontal speed ratio
  final double heavyCharge01; // 0..1 while charging heavy
  final int comboStep; // 1..3 during light attack combo
  final int flags; // FFlag bits
  final double hitFlash; // 0..1 white flash intensity
  final double shield01; // 0..1 guard shield HP (cracks as it drops)

  const ChickenPose({
    required this.state,
    this.stateTime = 0,
    this.stateDur = 0,
    this.time = 0,
    this.faceRight = true,
    this.speed01 = 0,
    this.heavyCharge01 = 0,
    this.comboStep = 1,
    this.flags = 0,
    this.hitFlash = 0,
    this.shield01 = 1,
  });
}

class ChickenPainter {
  /// Nominal chicken height in world pixels (~1 m at 32 px/m).
  static const double height = 40;

  static final _Rig _rig = _Rig();
  static final Paint _layerPaint = Paint()
    ..color = const Color.fromRGBO(0, 0, 0, 0.42);
  static const Rect _layerBounds = Rect.fromLTRB(-48, -72, 48, 12);

  /// Paints the chicken with its FEET at the canvas origin (0,0); the body
  /// extends upward (negative y). Caller already translated for position and
  /// jump height (z) and draws the ground shadow itself.
  static void paint(Canvas canvas, ChickenLook look, ChickenPose pose) {
    final a = _Art.of(look);
    final r = _rig;
    // Per-chicken phase so idle blinks/pecks don't sync across the arena.
    final t = pose.time + a.seed * 7.0;
    _solve(r, a, pose, t);
    _a = a;
    _r = r;
    _pose = pose;
    _t = t;
    _flash = pose.hitFlash.clamp(0.0, 1.0);
    final flags = pose.flags;

    canvas.save();
    if (!pose.faceRight) canvas.scale(-1, 1);
    if (a.scale != 1) canvas.scale(a.scale);
    // Invulnerability blink: the only save layer, and only on dim frames.
    // 12 Hz = exactly two frames per phase on the 24 fps sprite clock.
    final dim = flags & FFlag.invuln != 0 && (pose.time * 12).floor().isEven;
    if (dim) canvas.saveLayer(_layerBounds, _layerPaint);

    canvas.save();
    canvas.translate(r.shake, 0);
    canvas.scale(r.sx, r.sy);
    _backFx(canvas);
    _legs(canvas);

    _enterBody(canvas, r);
    if (flags & FFlag.superArmor != 0 && r.lie == 0) _armorRim(canvas);
    _bodyBack(canvas);
    canvas.restore();

    _neck(canvas);

    _enterBody(canvas, r);
    _bodyFront(canvas);
    canvas.restore();

    canvas.save();
    canvas.translate(r.hx, r.hy);
    canvas.rotate(r.hrot);
    canvas.scale(_hs);
    _head(canvas);
    canvas.restore();

    _enterBody(canvas, r);
    _scarf(canvas);
    canvas.restore();

    _frontFx(canvas);
    canvas.restore();

    if (a.sparks > 0) _sparkles(canvas);
    if (dim) canvas.restore();
    canvas.restore();
    _flash = 0;
  }

  static void _enterBody(Canvas c, _Rig r) {
    c.save();
    c.translate(r.hipX, r.hipY);
    if (r.lean != 0) c.rotate(r.lean);
    if (r.flip != 1) c.scale(1, r.flip);
  }
}

/// Eye expressions; those up to [angry] draw an eyeball (and allow brows).
enum _Eye { open, spiral, panic, tired, angry, blink, happy, squeeze, cross }

/// Mutable pose rig, reused every call to avoid allocation.
///
/// Frames: world (feet at origin) → body (origin at hip, rotated by [lean],
/// vertically scaled by [flip]) → head (centre at [hx],[hy], rotated [hrot]).
/// Wing angles: 0 = folded back, positive = raised.
class _Rig {
  double sx = 1, sy = 1, shake = 0, lean = 0, flip = 1, lie = 0;
  double hipX = -1, hipY = -11, headX = 0, headY = 0, headRot = 0;
  double wing = 0, wingFar = 0, tail = 0;
  double bX = 0, bY = 0, fX = 0, fY = 0, bend = 0, toeB = 0, toeF = 0;
  double hipSpread = 0; // extra hip width for wide-set legs
  _Eye eye = _Eye.open;
  double lookX = 0.4, lookY = 0, beak = 0;
  bool tongue = false, brows = false;

  // Derived by [finish].
  double cs = 1, sn = 0, hx = 0, hy = 0, hrot = 0;
  double hbX = 0, hbY = 0, hfX = 0, hfY = 0, bcx = 0, bcy = 0;

  void reset() {
    sx = sy = flip = 1;
    shake = lean = lie = tail = headX = headY = headRot = lookY = 0;
    hipSpread = 0;
    hipX = -1;
    hipY = -11;
    lookX = 0.4;
    wings(-0.12);
    feet(-3.5, 0, 1.5, 0);
    face(_Eye.open);
  }

  /// Upper-body posture: lean, squash about the feet and hip offset.
  void body({
    double lean = 0,
    double sx = 1,
    double sy = 1,
    double dx = 0,
    double dy = 0,
  }) {
    this.lean = lean;
    this.sx = sx;
    this.sy = sy;
    hipX += dx;
    hipY += dy;
  }

  /// Head offset from its neutral spot (body frame) plus extra tilt.
  void look({double dx = 0, double dy = 0, double rot = 0}) {
    headX += dx;
    headY += dy;
    headRot += rot;
  }

  /// Near and far wing angles; the far wing only shows when raised.
  void wings(double near, [double far = -9]) {
    wing = near;
    wingFar = far;
  }

  /// World-space foot positions (back, front), toe tilt and knee bend.
  void feet(
    double bx,
    double by,
    double fx,
    double fy, {
    double toeB = 0,
    double toeF = 0,
    double bend = 1.2,
  }) {
    bX = bx;
    bY = by;
    fX = fx;
    fY = fy;
    this.toeB = toeB;
    this.toeF = toeF;
    this.bend = bend;
  }

  void face(
    _Eye eye, {
    double beak = 0,
    bool brows = false,
    bool tongue = false,
  }) {
    this.eye = eye;
    this.beak = beak;
    this.brows = brows;
    this.tongue = tongue;
  }

  double wx(double lx, double ly) => hipX + lx * cs - ly * flip * sn;
  double wy(double lx, double ly) => hipY + lx * sn + ly * flip * cs;

  void finish() {
    cs = math.cos(lean);
    sn = math.sin(lean);
    hbX = wx(-3.5 - hipSpread, -1);
    hbY = wy(-3.5 - hipSpread, -1);
    hfX = wx(1.5 + hipSpread, -1);
    hfY = wy(1.5 + hipSpread, -1);
    bcx = wx(-1, -5);
    bcy = wy(-1, -5);
    // Head placement ignores the flip so the dead flop blends smoothly.
    final lx = 5.5 + headX, ly = -19.5 + headY;
    hx = _lerp(hipX + lx * cs - ly * sn, 12, lie);
    hy = _lerp(hipY + lx * sn + ly * cs, -11.2, lie);
    hrot = _lerp(lean + headRot, -1.05, lie);
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
double _ease(double t) => t * t * (3 - 2 * t);
double _c01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Maps a pose to rig parameters. Each state is a small hand-tuned recipe.
void _solve(_Rig r, _Art a, ChickenPose p, double t) {
  r.reset();
  final st = p.stateTime;
  final k = p.stateDur > 0 ? _c01(st / p.stateDur) : 0.0;
  switch (p.state) {
    case FState.idle:
      final b = math.sin(t * 3.2);
      r.body(sx: 1 - b * 0.015, sy: 1 + b * 0.015, dy: b * 0.5);
      r.tail = b * 0.05;
      final pk = (t * 0.23) % 1.0;
      if (pk < 0.09) {
        // Occasional peck at the ground.
        final e = math.sin(pk / 0.09 * math.pi);
        r.look(dx: 3.5 * e, dy: 4.5 * e, rot: 0.45 * e);
        r.lookY = 0.7 * e;
      }
      if ((t * 0.37) % 1.0 < 0.045) r.eye = _Eye.blink;
    case FState.run:
      _run(r, _c01(p.speed01), t);
    case FState.attack:
      _attack(r, p.comboStep, k);
    case FState.heavyCharge:
      final c = _c01(p.heavyCharge01);
      r.body(lean: -0.08 - 0.1 * c, sx: 1.03 + 0.09 * c, sy: 0.96 - 0.14 * c);
      r.shake = math.sin(t * 70) * 0.8 * c;
      r.look(dx: -1.5 - 1.5 * c, dy: 1.5 * c);
      r.wings(0.4 + 0.6 * c, 0.4 + 0.6 * c);
      r.feet(-6, 0, 3.5, 0, bend: 2.4);
      r.face(_Eye.angry, brows: true);
      r.lookX = 1;
    case FState.heavyAttack:
      final w = _c01(k / 0.45), e = _c01((k - 0.45) / 0.18), pull = w * (1 - e);
      r.body(lean: -0.18 * pull + 0.42 * e, sx: 1 + 0.16 * e, sy: 1 - 0.08 * e);
      r.look(dx: 9 * e - 2.5 * pull, dy: 3.5 * e, rot: 0.3 * e);
      r.wings(0.3 + 0.6 * pull + 0.2 * e, 0.1 + 0.6 * pull + 0.2 * e);
      r.feet(-3.5 - 6 * e, 0, 1.5 + 3 * e, 0);
      r.face(_Eye.angry, beak: e, brows: true);
      r.lookX = 1;
    case FState.jump:
      _tuck(r);
      r.wings(
        0.85 + math.sin(t * 28) * 0.3,
        0.95 + math.sin(t * 28 + 0.6) * 0.3,
      );
      r.face(_Eye.open, beak: 0.25);
      r.headRot = -0.12;
      r.tail = 0.25;
      r.lookY = -0.4;
    case FState.dodge:
      _dash(r);
    case FState.recovery:
      final e = 1 - _ease(k);
      r.body(lean: 0.08 * e, sx: 1 + 0.05 * e, sy: 1 - 0.07 * e);
      r.look(dy: 1.5 * e);
      r.wings(0.25 * e - 0.12);
    case FState.hitstun:
      final e = 1 - 0.6 * k;
      r.body(lean: -0.38 * e, dx: -2 * e);
      r.shake = math.sin(st * 60) * 1.2 * (1 - k);
      r.look(dx: -3 * e, dy: -1, rot: -0.35 * e);
      r.face(_Eye.squeeze, beak: 0.8);
      r.wings(0.95 * e, 0.9 * e);
      r.feet(-3.5, 0, 1.5 + 4 * e, -2.5 * e, toeF: -0.4);
      r.tail = 0.3 * e;
    case FState.stunned:
      final w = math.sin(t * 4.5);
      r.body(lean: w * 0.16, sx: 1 + 0.03 * math.sin(t * 9));
      r.look(dx: w * 1.2, rot: math.sin(t * 4.5 + 1.2) * 0.28);
      r.face(_Eye.spiral, beak: 0.3, tongue: true);
      r.wings(-0.35);
      r.feet(-4.5, 0, 2.5, 0);
    case FState.exhausted:
      final b = math.sin(t * 2.2);
      r.body(lean: 0.28, sy: 0.96, dy: 2 + b * 0.6);
      r.look(dx: 1.5, dy: 4 + b * 0.5, rot: 0.3);
      r.face(_Eye.tired, beak: 0.45, tongue: true);
      r.wings(-0.5);
      r.tail = -0.3;
      r.bend = 2.2;
    case FState.skill:
      _skill(r, a.kind, st, t, _c01(p.speed01));
    case FState.crow:
      _shout(r, st, t, rage: false);
    case FState.rageRoar:
      _shout(r, st, t, rage: true);
    case FState.fakeDead || FState.dead:
      // Identical for both so a faking troll can't be read. Quick flop onto
      // the back (vertical flip), feet up with the odd twitch.
      final e = _ease(_c01(st / 0.22));
      final tw = math.max(0.0, math.sin(t * 1.7) - 0.8) * 5;
      r.body(lean: 0.1 * e, dx: -2 * e, dy: -1.5 * e);
      r.lie = e;
      r.flip = 1 - 2 * e;
      r.feet(
        _lerp(-3.5, -7.5, e),
        -25.5 * e - tw,
        _lerp(1.5, 1.0, e),
        -27 * e + tw,
        toeB: -1.9 * e,
        toeF: -1.9 * e,
        bend: 1.2 - 2.2 * e,
      );
      r.face(e > 0.5 ? _Eye.cross : _Eye.squeeze, beak: 0.35, tongue: true);
      r.wings(0.5 * e);
      r.tail = -0.7 * e;
    case FState.block:
      // Guard: crouched, wings raised in front, braced wide.
      final b = math.sin(t * 5) * 0.3;
      r.body(lean: -0.14, sx: 1.05, sy: 0.93, dy: 1.5);
      r.look(dx: -1.5, dy: 2.5, rot: 0.18);
      r.wings(1.0 + b * 0.1, 0.65);
      r.feet(-6.5, 0, 4, 0, bend: 2.2);
      r.face(_Eye.angry, brows: true);
      r.tail = 0.15;
      r.lookX = 1;
    case FState.falling:
      final f = t * 30;
      r.body(lean: -0.12 + math.sin(t * 6) * 0.15);
      r.look(dx: math.sin(t * 25) * 0.8, rot: math.sin(t * 20) * 0.15);
      r.wings(
        0.75 + math.sin(t * 32) * 0.45,
        0.85 + math.sin(t * 32 + 1.4) * 0.45,
      );
      r.feet(
        -4.5 + math.sin(f) * 2.5,
        -1.5 - math.cos(f).abs() * 2,
        2.5 - math.sin(f) * 2.5,
        -1.5 - math.sin(f).abs() * 2,
      );
      r.face(_Eye.panic, beak: 0.85);
      r.lookY = -0.6;
  }
  if (p.flags & FFlag.rage != 0 && r.eye == _Eye.open) r.brows = true;
  // Ninjas always squint through the mask.
  if (a.kind == _kNinja && r.eye == _Eye.open) r.eye = _Eye.angry;
  _breedPose(r, a);
  r.finish();
}

/// Run cycle; leg frequency and stride scale with speed [s] (0..1).
void _run(_Rig r, double s, double t) {
  final ph = t * (2.4 + 2.8 * s) * math.pi * 2;
  final sw = math.sin(ph) * (2.5 + 3.5 * s), lift = 2.0 + 2.5 * s;
  final bUp = math.max(0.0, math.cos(ph)) * lift;
  final fUp = math.max(0.0, -math.cos(ph)) * lift;
  r.feet(
    -3.5 + sw,
    -bUp,
    1.5 - sw,
    -fUp,
    toeB: bUp > 0 ? 0.35 : 0,
    toeF: fUp > 0 ? 0.35 : 0,
  );
  r.body(lean: 0.1 + 0.14 * s, dy: -math.cos(ph * 2).abs() * (0.6 + s));
  r.look(dx: 1.5 * s + math.sin(ph * 2) * 1.3, dy: math.cos(ph * 2) * 0.5);
  r.wings(0.1 + 0.35 * s * (0.5 + 0.5 * math.sin(ph * 2)));
  r.tail = -0.08 * math.sin(ph * 2) - 0.1 * s;
  r.lookX = 0.8;
}

/// Light combo: 1 = peck, 2 = front kick, 3 = hopping flying kick.
void _attack(_Rig r, int step, double k) {
  final w = _c01(k / 0.4), e = _c01((k - 0.4) / 0.22), pull = w * (1 - e);
  r.lookX = 1;
  switch (step) {
    case >= 3:
      final s = _ease(_c01(k / 0.35));
      r.body(lean: -0.35 * s, dy: -5 * s);
      r.feet(-4.5, -5 * s, 1.5 + 11 * s, -8 * s, toeB: 0.9 * s, toeF: -0.5 * s);
      r.wings(0.95 * s, 0.9 * s);
      r.look(dx: -1.5 * s);
      r.face(_Eye.angry, beak: 0.5 * s, brows: true);
    case 2:
      r.body(lean: -0.08 * pull - 0.2 * e);
      r.feet(
        -3.5,
        0,
        1.5 - 2 * pull + 9.5 * e,
        -2 * pull - 5.5 * e,
        toeF: -0.3 * e,
      );
      r.look(dx: -1.5 * pull - 1.5 * e);
      r.wings(0.3 + 0.5 * e);
      r.eye = _Eye.angry;
    default:
      r.body(lean: -0.06 * pull + 0.22 * e);
      r.look(
        dx: -2.5 * pull + 8 * e,
        dy: -0.5 * pull + 3.5 * e,
        rot: -0.15 * pull + 0.35 * e,
      );
      r.wings(0.3 * e);
      r.face(e > 0 ? _Eye.angry : _Eye.open, beak: 0.7 * e);
  }
}

void _tuck(_Rig r) => r.feet(
  r.hipX - 3.2,
  r.hipY + 7,
  r.hipX + 2.8,
  r.hipY + 7.5,
  toeB: 1,
  toeF: 1,
  bend: 2.5,
);

void _dash(_Rig r, [double lean = 0.55, double sx = 1.22, double sy = 0.8]) {
  r.body(lean: lean, sx: sx, sy: sy, dy: 1.5);
  r.look(dx: 2, dy: 2, rot: 0.1);
  r.feet(-9, -1.5, -3, -3, toeB: 0.5, toeF: 0.5);
  r.wings(0.5);
  r.eye = _Eye.angry;
  r.tail = -0.25;
  r.lookX = 1;
}

void _skill(_Rig r, int kind, double st, double t, double speed) {
  switch (kind) {
    case >= _kDongtao:
      _breedSkill(r, kind, st, t, speed);
    case _kSamurai:
      // Flame Kick: crouch, then a flying kick until the dash ends.
      if (st < 0.1) {
        final w = st / 0.1;
        r.body(lean: -0.1 * w, sy: 1 - 0.12 * w);
        r.wings(0.6 * w);
      } else if (st < 0.38) {
        r.body(lean: -0.42, dy: -6);
        r.feet(-3, -7, 13, -10, toeB: 1, toeF: -0.6);
        r.wings(0.9, 0.85);
        r.beak = 0.35;
      }
      r.eye = _Eye.angry;
      r.brows = true;
    case _kNinja:
      _dash(r, 0.62, 1.3, 0.78);
      r.wings(0.25);
    case _kTank:
      // Earth Rooster leap: wings up like fists.
      _tuck(r);
      r.body(sy: 1.05);
      r.wings(1.15 + math.sin(t * 6) * 0.08, 1.1);
      r.face(_Eye.angry, beak: 0.6, brows: true);
      r.headRot = -0.2;
    case _kBerserker:
      _shout(r, st, t, rage: true);
      r.headRot = -0.3;
    default:
      _shout(r, st, t, rage: false);
  }
}

/// Crow (happy, head back) or roar (angry, shaking).
void _shout(_Rig r, double st, double t, {required bool rage}) {
  final e = _ease(_c01(st / 0.12));
  r.look(dx: -1.5 * e, dy: -1.5 * e, rot: (rage ? -0.4 : -0.6) * e);
  r.tail = 0.2 * e;
  if (rage) {
    r.body(lean: -0.12 * e, sx: 1 + 0.08 * e, sy: 1 + 0.08 * e);
    r.shake = math.sin(t * 75) * e;
    r.wings(e, 0.95 * e);
    r.feet(-6, 0, 3.5, 0);
    r.face(_Eye.angry, beak: e, brows: true);
  } else {
    r.body(lean: -0.22 * e, sy: 1 + 0.05 * e);
    r.wings(0.55 * e, 0.3 * e);
    r.face(_Eye.happy, beak: e);
  }
}
