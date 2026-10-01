part of 'sfx_synth.dart';

// Procedural battle music: Vietnamese war-drum (trống trận) groove over a
// pulsing bass and a dissonant minor-second pad. Rendered as an exact
// 8-bar loop; hits near the end wrap around to the start, and continuous
// oscillators use whole cycles per loop, so it loops without a seam.

Float32List _music(MusicTrack track) {
  final fin = track == MusicTrack.finale;
  final bpm = fin ? 160.0 : 140.0;
  final step = 60 / bpm / 4; // one 16th
  const bars = 8, perBar = 16;
  final n = (bars * perBar * step * _sr).round();
  final loopSec = n / _sr;
  final out = Float64List(n);

  void add(Float64List sig, double at, double gain) {
    final o = (at * _sr).round();
    final g = gain / math.max(_peak(sig, sig.length), 1e-9);
    for (var i = 0; i < sig.length; i++) {
      out[(o + i) % n] += sig[i] * g;
    }
  }

  double t(int bar, int s) => (bar * perBar + s) * step;

  // One-shot sources, rendered once.
  final don = _taiko(1), tom = _taiko(0.7);
  final ka = _mix([
    _L(_burst(301, 0.008, attack: 0.0003, band: 2400, q: 1.2)),
    _L(_modes(0.08, const [(880, 1, 0.02), (1310, 0.5, 0.012)]), 0.5),
  ]);
  final hat = _burst(302, 0.014, attack: 0.0002, hp: 6500);
  final key = fin ? 1 : 0; // finale sits a semitone higher

  // Drums.
  final donSteps = fin ? const [0, 3, 6, 8, 10, 11, 14] : const [0, 6, 8, 11];
  for (var b = 0; b < bars; b++) {
    final fill = fin ? b.isOdd : (b == 3 || b == 7);
    for (final s in donSteps) {
      if (fill && s >= 12) continue;
      add(don, t(b, s), s == 0 ? 1.0 : 0.8);
    }
    add(ka, t(b, 4), 0.5);
    add(ka, t(b, 12), 0.5);
    add(ka, t(b, 14), 0.2);
    if (fill) {
      for (var s = 12; s < 16; s++) {
        add(tom, t(b, s), 0.55 + 0.1 * (s - 12));
      }
    }
    if (fin) {
      for (var s = 0; s < perBar; s++) {
        add(hat, t(b, s), s.isEven ? 0.2 : 0.1);
      }
    }
  }

  // Bass: driving 8ths (16ths in the finale) around D.
  const riff = [0, 0, 0, 3, 0, 0, -2, 0, 0, 0, 0, 5, 3, 3, -2, -2];
  final noteSteps = fin ? 1 : 2;
  final noteLen = noteSteps * step;
  for (var i = 0; i < bars * perBar ~/ noteSteps; i++) {
    final semi = riff[(i ~/ (fin ? 2 : 1)) % riff.length] + key;
    final f = 73.42 * math.pow(2, semi / 12);
    final o = _Osc(), lp = _Svf();
    final note = _gen(noteLen * 1.6, (x) {
      final cut = 250 + 900 * math.exp(-x / 0.05);
      return _drive(lp.lowpass(o.saw(f), cut, 1.2) * _ad(x, 0.003, 0.09), 2);
    });
    add(note, i * noteLen, i % 4 == 0 ? 0.6 : 0.45);
  }

  // Stabs: short minor chords on bar downbeats (every bar in the finale).
  for (var b = 0; b < bars; b += fin ? 1 : 2) {
    final root = 293.66 * math.pow(2, key / 12);
    final chord = [root, root * 1.1892, root * 1.4983]; // minor triad
    final oscs = [for (final _ in chord) _Osc()];
    final lp = _Svf();
    final stab = _gen(0.4, (x) {
      var v = 0.0;
      for (var k = 0; k < chord.length; k++) {
        v += oscs[k].saw(chord[k] * (1 + 0.003 * k));
      }
      return lp.lowpass(v, 900 + 1800 * math.exp(-x / 0.06)) * _ad(x, 0.004, 0.14);
    });
    add(stab, t(b, 0), 0.32);
  }
  if (fin) {
    // Rising noise swell into the loop point.
    add(_noise(2 * perBar * step, 303, (x) => math.pow(x / (2 * perBar * step), 2).toDouble(),
        band: (x) => 800 + 5000 * x / (2 * perBar * step), q: 1.5), t(6, 0), 0.25);
  }

  // Tension pad: minor second, whole cycles per loop so it never clicks.
  double whole(double f) => (f * loopSec).roundToDouble() / loopSec;
  final pa = _Osc(), pb = _Osc(), plp = _Svf();
  final fa = whole(146.83 * math.pow(2, key / 12)), fb = whole(155.56 * math.pow(2, key / 12));
  final swell = whole(2 / loopSec);
  // Two passes: the first warms the filter so its state matches at the seam.
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 0; i < n; i++) {
      final x = i / _sr;
      final lfo = 0.5 - 0.5 * math.cos(_tau * swell * x);
      final v = plp.lowpass(pa.saw(fa) + pb.saw(fb), 500 + 700 * lfo, 0.9);
      if (pass == 1) out[i] += v * (0.05 + 0.05 * lfo) * (fin ? 1.3 : 1);
    }
  }

  // Master: gentle saturation, normalize.
  final peak = math.max(_peak(out, n), 1e-9);
  final res = Float32List(n);
  for (var i = 0; i < n; i++) {
    res[i] = (_drive(out[i] / peak, 1.3) * 0.85).clamp(-1.0, 1.0);
  }
  return res;
}
