import 'dart:math' as math;

/// Small mutable 2D vector used by the simulation.
///
/// Kept dependency-free (instead of vector_math) so the core stays a tiny,
/// portable pure-Dart package shared by server, web and mobile.
class V2 {
  double x;
  double y;

  V2(this.x, this.y);
  V2.zero()
      : x = 0,
        y = 0;
  factory V2.fromAngle(double a, [double len = 1]) =>
      V2(math.cos(a) * len, math.sin(a) * len);

  V2 clone() => V2(x, y);

  double get length => math.sqrt(x * x + y * y);
  double get length2 => x * x + y * y;
  double get angle => math.atan2(y, x);
  bool get isZero => x == 0 && y == 0;

  void set(double nx, double ny) {
    x = nx;
    y = ny;
  }

  void setFrom(V2 o) {
    x = o.x;
    y = o.y;
  }

  void add(V2 o) {
    x += o.x;
    y += o.y;
  }

  void sub(V2 o) {
    x -= o.x;
    y -= o.y;
  }

  void addScaled(V2 o, double s) {
    x += o.x * s;
    y += o.y * s;
  }

  void scale(double s) {
    x *= s;
    y *= s;
  }

  /// Normalizes in place; leaves zero vectors untouched.
  void normalize() {
    final l = length;
    if (l > 1e-9) {
      x /= l;
      y /= l;
    }
  }

  /// Clamps length to [max] in place.
  void clampLength(double max) {
    final l = length;
    if (l > max && l > 1e-9) {
      final s = max / l;
      x *= s;
      y *= s;
    }
  }

  V2 normalized() {
    final l = length;
    return l < 1e-9 ? V2(0, 0) : V2(x / l, y / l);
  }

  double dot(V2 o) => x * o.x + y * o.y;
  double cross(V2 o) => x * o.y - y * o.x;
  double distanceTo(V2 o) {
    final dx = x - o.x, dy = y - o.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double distance2To(V2 o) {
    final dx = x - o.x, dy = y - o.y;
    return dx * dx + dy * dy;
  }

  V2 operator +(V2 o) => V2(x + o.x, y + o.y);
  V2 operator -(V2 o) => V2(x - o.x, y - o.y);
  V2 operator *(double s) => V2(x * s, y * s);
  V2 operator -() => V2(-x, -y);

  /// Perpendicular (rotated +90°).
  V2 get perp => V2(-y, x);

  @override
  String toString() => 'V2(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

double lerpD(double a, double b, double t) => a + (b - a) * t;

/// Shortest-path angle interpolation.
double lerpAngle(double a, double b, double t) {
  var d = (b - a) % (2 * math.pi);
  if (d > math.pi) d -= 2 * math.pi;
  if (d < -math.pi) d += 2 * math.pi;
  return a + d * t;
}
