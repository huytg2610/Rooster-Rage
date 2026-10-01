import 'dart:math' as math;
import 'dart:typed_data';

import 'sound_ids.dart';

part 'sfx_battle.dart';
part 'sfx_music.dart';
part 'sfx_recipes.dart';

/// Procedural cartoon sound effects rendered to mono float samples.
///
/// Pure Dart with no platform dependencies, and deterministic: a given
/// [SoundId] always renders to the same samples.
abstract final class SfxSynth {
  static const int sampleRate = 22050;

  /// Hard cap on rendered length.
  static const double maxSeconds = 2.0;

  /// Peak level every sound is normalized to.
  static const double peakLevel = 0.9;

  /// Renders [id] as peak-normalized mono samples at [sampleRate].
  static Float32List render(SoundId id) => _finish(_recipe(id));

  /// Renders a seamless background-music loop (not length-capped).
  static Float32List renderMusic(MusicTrack track) => _music(track);
}

const double _sr = SfxSynth.sampleRate * 1.0;
const double _tau = 2 * math.pi;

// ---------------------------------------------------------------------------
// Unit generators

/// xorshift32; identical sequences on VM, JS and Wasm.
final class _Rng {
  _Rng(int seed) : _s = ((seed + 1) * 0x9E3779B1) & 0xFFFFFFFF {
    if (_s == 0) _s = 0x6D2B79F5;
  }

  int _s;

  /// Uniform in [0, 1).
  double unit() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _s = x;
    return x / 4294967296.0;
  }

  /// Uniform in [-1, 1).
  double bi() => 2 * unit() - 1;

  double range(double lo, double hi) => lo + (hi - lo) * unit();
}

/// Phase-accumulating oscillator; saw and pulse are PolyBLEP band-limited.
final class _Osc {
  _Osc([this.phase = 0]);

  double phase;

  double _tick(double f) {
    final p = phase;
    phase += f / _sr;
    if (phase >= 1 || phase < 0) phase -= phase.floorToDouble();
    return p;
  }

  double sine(double f) => math.sin(_tau * _tick(f));

  double tri(double f) {
    final p = _tick(f);
    return p < 0.5 ? 4 * p - 1 : 3 - 4 * p;
  }

  double saw(double f) {
    final dt = f.abs() / _sr;
    final p = _tick(f);
    return 2 * p - 1 - _blep(p, dt);
  }

  /// Zero-mean pulse with duty cycle [width].
  double square(double f, [double width = 0.5]) {
    final dt = f.abs() / _sr;
    final p = _tick(f);
    final q = p < width ? p - width + 1 : p - width;
    final naive = p < width ? 1.0 : -1.0;
    return naive + _blep(p, dt) - _blep(q, dt) - (2 * width - 1);
  }
}

double _blep(double t, double dt) {
  if (t < dt) {
    final x = t / dt;
    return x + x - x * x - 1;
  }
  if (t > 1 - dt) {
    final x = (t - 1) / dt;
    return x * x + x + x + 1;
  }
  return 0;
}

/// One-pole filter. Use an instance for either [lp] or [hp], not both.
final class _OnePole {
  double _y = 0, _fc = -1, _a = 0;

  double lp(double x, double fc) {
    if (fc != _fc) {
      _fc = fc;
      _a = math.exp(-_tau * fc / _sr);
    }
    return _y = x + _a * (_y - x);
  }

  double hp(double x, double fc) => x - lp(x, fc);
}

/// Topology-preserving state-variable filter (2-pole, stable under sweeps).
final class _Svf {
  double _ic1 = 0, _ic2 = 0, _fc = -1, _q = -1;
  double _k = 1, _a1 = 0, _a2 = 0, _a3 = 0, _bp = 0, _lp = 0;

  void _run(double x, double fc, double q) {
    if (fc != _fc || q != _q) {
      _fc = fc;
      _q = q;
      final g = math.tan(math.pi * fc.clamp(10.0, _sr * 0.45) / _sr);
      _k = 1 / q;
      _a1 = 1 / (1 + g * (g + _k));
      _a2 = g * _a1;
      _a3 = g * _a2;
    }
    final v3 = x - _ic2;
    _bp = _a1 * _ic1 + _a2 * v3;
    _lp = _ic2 + _a2 * _ic1 + _a3 * v3;
    _ic1 = 2 * _bp - _ic1;
    _ic2 = 2 * _lp - _ic2;
  }

  double lowpass(double x, double fc, [double q = 0.707]) {
    _run(x, fc, q);
    return _lp;
  }

  /// Band-pass (resonator) with unity gain at [fc].
  double band(double x, double fc, [double q = 1]) {
    _run(x, fc, q);
    return _k * _bp;
  }
}

/// Piecewise contour through `(seconds, value)` points with geometric
/// interpolation (natural for pitch, cutoff and ratio sweeps).
final class _Curve {
  const _Curve(this.pts);

  final List<(double, double)> pts;

  double at(double t) {
    var (t0, v0) = pts.first;
    if (t <= t0) return v0;
    for (var i = 1; i < pts.length; i++) {
      final (t1, v1) = pts[i];
      if (t < t1) return v0 * math.pow(v1 / v0, (t - t0) / (t1 - t0));
      (t0, v0) = (t1, v1);
    }
    return v0;
  }
}

// ---------------------------------------------------------------------------
// Envelopes and shaping

double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

double _smooth(double x) {
  final u = _clamp01(x);
  return u * u * (3 - 2 * u);
}

/// Linear attack over [a] s, then exponential decay with time constant [tau].
double _ad(double t, double a, double tau) =>
    t < a ? t / a : math.exp(-(t - a) / tau);

/// Smooth attack [a] and release [r] around a sustain lasting [dur] in total.
double _ar(double t, double dur, double a, double r) =>
    _smooth(t / a) * _smooth((dur - t) / r);

/// Swell to 1 at fraction [peak] of [dur], then fade to 0.
double _hump(double t, double dur, double peak) {
  final u = t / dur;
  return u < peak ? _smooth(u / peak) : _smooth((1 - u) / (1 - peak));
}

/// Soft clip with gain [k]; ±1 maps to ±1.
double _drive(double x, double k) => k <= 0 ? x : _tanh(k * x) / _tanh(k);

double _tanh(double v) => 1 - 2 / (math.exp(2 * v) + 1);

// ---------------------------------------------------------------------------
// Buffers

Float64List _gen(double dur, double Function(double t) f) {
  final out = Float64List((dur * _sr).round());
  for (var i = 0; i < out.length; i++) {
    out[i] = f(i / _sr);
  }
  return out;
}

/// A [_mix] layer: [sig] peak-normalized, scaled by [gain], starting [at] s.
final class _L {
  const _L(this.sig, [this.gain = 1, this.at = 0]);

  final Float64List sig;
  final double gain;
  final double at;
}

/// Sums layers; each gets a short fade-out so truncated tails never click.
Float64List _mix(List<_L> layers) {
  var n = 0;
  for (final l in layers) {
    n = math.max(n, (l.at * _sr).round() + l.sig.length);
  }
  final out = Float64List(n);
  for (final l in layers) {
    final o = (l.at * _sr).round();
    final len = l.sig.length;
    final g = l.gain / math.max(_peak(l.sig, len), 1e-9);
    final fadeFrom = len - math.min((0.005 * _sr).round(), len ~/ 4);
    for (var i = 0; i < len; i++) {
      final fade = i < fadeFrom ? 1.0 : (len - i) / (len - fadeFrom);
      out[o + i] += l.sig[i] * g * fade;
    }
  }
  return out;
}

double _peak(Float64List x, int n, [int from = 0]) {
  var p = 0.0;
  for (var i = from; i < n; i++) {
    final a = x[i].abs();
    if (a > p) p = a;
  }
  return p;
}

/// Trims the silent tail, fades out, peak-normalizes and converts.
Float32List _finish(Float64List x) {
  var n = math.min(x.length, (SfxSynth.maxSeconds * _sr).floor());
  for (var i = 0; i < n; i++) {
    if (!x[i].isFinite) x[i] = 0;
  }
  final peak = _peak(x, n);
  if (peak < 1e-9) return Float32List(math.max(n, 1));
  while (n > 1 && x[n - 1].abs() < peak * 0.002) {
    n--;
  }
  final tail = _peak(x, n, math.max(0, n - (0.02 * _sr).round()));
  final fadeSec = tail > peak * 0.03 ? 0.04 : 0.008;
  final fade = math.min((fadeSec * _sr).round(), n ~/ 4);
  for (var k = 0; k < fade; k++) {
    x[n - 1 - k] *= k / fade;
  }
  final g = SfxSynth.peakLevel / peak;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = (x[i] * g).clamp(-1.0, 1.0);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Building blocks

/// White noise shaped by [env]; optionally band-passed around [band] (Hz),
/// then low-passed at [lp] (Hz) and high-passed at [hp] (Hz).
Float64List _noise(
  double dur,
  int seed,
  double Function(double t) env, {
  double Function(double t)? band,
  double q = 1,
  double Function(double t)? lp,
  double hp = 0,
}) {
  final rng = _Rng(seed), bp = _Svf(), lo = _OnePole(), hi = _OnePole();
  return _gen(dur, (t) {
    var s = rng.bi();
    if (band != null) s = bp.band(s, band(t), q);
    if (lp != null) s = lo.lp(s, lp(t));
    if (hp > 0) s = hi.hp(s, hp);
    return s * env(t);
  });
}

/// Percussive noise: [attack] then exponential decay [tau]; filters in Hz.
Float64List _burst(
  int seed,
  double tau, {
  double attack = 0.0005,
  double? band,
  double q = 1,
  double? lp,
  double hp = 0,
}) => _noise(
  attack + 6 * tau,
  seed,
  (t) => _ad(t, attack, tau),
  band: band == null ? null : (_) => band,
  q: q,
  lp: lp == null ? null : (_) => lp,
  hp: hp,
);

/// Noise swell peaking at fraction [peak] of [dur], optionally band-passed
/// along [band].
Float64List _swoosh(
  double dur,
  int seed,
  double peak, {
  _Curve? band,
  double q = 1,
  double? lp,
  double hp = 0,
}) => _noise(
  dur,
  seed,
  (t) => _hump(t, dur, peak),
  band: band?.at,
  q: q,
  lp: lp == null ? null : (_) => lp,
  hp: hp,
);

/// Sine partials `(Hz, amplitude, decay tau)`.
typedef _Modes = List<(double, double, double)>;

/// Sum of decaying partials, faded out over the last quarter of [dur].
Float64List _modes(double dur, _Modes modes) => _gen(dur, (t) {
  var s = 0.0;
  for (final (f, a, tau) in modes) {
    s += a * math.sin(_tau * f * t) * math.exp(-t / tau);
  }
  return s * _clamp01(t / 0.0005) * _smooth((dur - t) / (0.25 * dur));
});

/// Sine kick falling from [f0] to [f1] Hz (time constant [sweep]).
Float64List _thump(
  double dur,
  double f0,
  double f1, {
  double sweep = 0.02,
  double decay = 0.08,
  double drive = 0,
}) {
  final o = _Osc(0.25);
  return _gen(dur, (t) {
    final f = f1 + (f0 - f1) * math.exp(-t / sweep);
    final s = _drive(o.sine(f) * _ad(t, 0.001, decay), drive);
    return s * _smooth((dur - t) / (0.25 * dur));
  });
}

/// Sparse random pops ([rate] per second), high-passed at [hp] Hz.
Float64List _crackle(
  double dur,
  int seed,
  double rate,
  double Function(double t) env, {
  double hp = 1500,
}) {
  final rng = _Rng(seed), f = _OnePole();
  var burst = 0.0;
  return _gen(dur, (t) {
    if (rng.unit() < rate / _sr) burst = rng.range(0.3, 1);
    burst *= 0.93;
    return f.hp(rng.bi() * burst, hp) * env(t);
  });
}

/// Inharmonic metal partials with a beating pair on the fundamental.
Float64List _clang(double f0, double dur, double decay) => _modes(dur, [
  (f0, 1, decay),
  (f0 * 1.006, 0.6, decay),
  (f0 * 2.32, 0.7, decay * 0.7),
  (f0 * 3.87, 0.5, decay * 0.45),
  (f0 * 5.21, 0.35, decay * 0.3),
  (f0 * 6.93, 0.2, decay * 0.2),
]);

/// Two slightly detuned sines: attack [a], decay [tau].
Float64List _chime(
  double f,
  double tau, {
  double a = 0.002,
  double detune = 0,
}) {
  final x = _Osc(), y = _Osc(0.5);
  final hi = f * (1 + detune), lo = f * (1 - detune);
  return _gen(a + 5 * tau, (t) => (x.sine(hi) + y.sine(lo)) * _ad(t, a, tau));
}

/// Pure whistle along [pitch] with vibrato and an airy breath band.
Float64List _whistle(
  double dur,
  _Curve pitch, {
  double vibRate = 6,
  double vibDepth = 0.012,
  double air = 0.3,
  int seed = 1,
}) {
  final o = _Osc(), v = _Osc(), breath = _Svf(), rng = _Rng(seed);
  return _gen(dur, (t) {
    final f = pitch.at(t) * (1 + vibDepth * v.sine(vibRate));
    return (o.sine(f) + air * breath.band(rng.bi(), f, 8)) *
        _ar(t, dur, 0.02, 0.08);
  });
}

// ---------------------------------------------------------------------------
// Voice

/// Formant set `(Hz, Q, gain)`.
typedef _Vowel = List<(double, double, double)>;

/// Voice character: `_Tone(attack, release, breath, drive)` in seconds,
/// noise mix and soft-clip gain (1 = warm, 3 = gritty, 5 = fuzz). [vib] is
/// `(Hz, depth)`; [jitter] is random pitch wander; [sub] and [growl] add a
/// sub-harmonic tone and period-doubling roughness.
final class _Tone {
  const _Tone(
    this.attack,
    this.release,
    this.breath,
    this.drive, {
    this.jitter = 0.01,
    this.vib = (0, 0),
    this.sub = 0,
    this.growl = 0,
  });

  final double attack, release, breath, drive, jitter, sub, growl;
  final (double, double) vib;
}

/// Vocal model: saw + pulse glottal source (vibrato, jitter, breath,
/// sub-harmonic, growl) through a parallel formant bank scaled over time by
/// [shift]; normalized before the soft clip so drive reads the same for every
/// voice.
Float64List _voice(
  double dur,
  _Curve pitch,
  _Vowel formants,
  _Tone tone,
  int seed, {
  _Curve? shift,
  double Function(double t)? amp,
}) {
  final saw = _Osc(), pulse = _Osc(), half = _Osc(), vib = _Osc();
  final rng = _Rng(seed), jit = _OnePole(), body = _OnePole();
  final bank = [for (final _ in formants) _Svf()];
  final (vibHz, vibDepth) = tone.vib;
  final raw = _gen(dur, (t) {
    final wobble =
        vibDepth * vib.sine(vibHz) + tone.jitter * 25 * jit.lp(rng.bi(), 25);
    final f = pitch.at(t) * (1 + wobble);
    final hs = half.sine(f / 2);
    var src = 0.6 * saw.saw(f) + 0.4 * pulse.square(f, 0.3);
    if (tone.growl > 0) src *= 1 + tone.growl * hs;
    src += tone.sub * hs + tone.breath * rng.bi();
    final k = shift == null ? 1.0 : shift.at(t);
    var y = 0.25 * body.lp(src, 900);
    for (var i = 0; i < formants.length; i++) {
      final (ff, q, g) = formants[i];
      y += g * bank[i].band(src, ff * k, q);
    }
    return y;
  });
  final norm = 1 / math.max(_peak(raw, raw.length), 1e-9);
  for (var i = 0; i < raw.length; i++) {
    final t = i / _sr;
    final env = _ar(t, dur, tone.attack, tone.release);
    final a = amp == null ? env : env * amp(t);
    raw[i] = _drive(raw[i] * norm, tone.drive) * a;
  }
  return raw;
}

const _Vowel _vowelBok = [(1150, 5, 1), (2400, 7, 0.45), (650, 3, 0.55)];
const _Vowel _vowelAw = [(1300, 5, 1), (2500, 6, 0.7), (800, 3, 0.45)];
const _Vowel _vowelAa = [(700, 3, 1), (1150, 4, 0.8), (2500, 5, 0.45)];
