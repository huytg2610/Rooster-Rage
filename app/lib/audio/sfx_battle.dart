part of 'sfx_synth.dart';

// Fight-weight sounds: layered impacts (sub + crack + crunch + short room
// tail), war drums, gong, heartbeat and a cartoon crowd. Tuned to feel
// tense rather than silly.

/// Short dark "room" tail so impacts don't end dry.
Float64List _room(int seed, double dur, {double lp = 1400, double tau = 0.09}) =>
    _noise(dur, seed, (t) => _ad(t, 0.004, tau), lp: (_) => lp, hp: 120);

Float64List _whooshLight() {
  const band = _Curve([(0, 700), (0.07, 3200), (0.16, 1400)]);
  return _mix([
    _L(_swoosh(0.16, 21, 0.45, band: band, q: 1.6)),
    _L(_swoosh(0.16, 25, 0.5, lp: 380), 0.35),
  ]);
}

Float64List _whooshHeavy() {
  const band = _Curve([(0, 180), (0.16, 1500), (0.32, 420)]);
  return _mix([
    _L(_swoosh(0.32, 22, 0.5, band: band, q: 1.3, lp: 2200)),
    _L(_swoosh(0.32, 23, 0.55, lp: 200), 0.7),
    _L(_thump(0.2, 90, 50, sweep: 0.05, decay: 0.08), 0.35, 0.12),
  ]);
}

/// Snappy body blow: sub punch, bright crack, meaty smack.
Float64List _hitLight() => _mix([
      _L(_thump(0.14, 150, 55, sweep: 0.01, decay: 0.045, drive: 2.5)),
      _L(_burst(41, 0.01, attack: 0.0003, band: 2600, q: 0.7), 0.8),
      _L(_burst(44, 0.03, attack: 0.001, lp: 900), 0.6),
      _L(_room(45, 0.18, tau: 0.05), 0.18),
    ]);

/// Heavy slam: booming sub, crunch, thwack, crack and a room tail.
Float64List _hitHeavy() => _mix([
      _L(_thump(0.42, 110, 36, sweep: 0.03, decay: 0.12, drive: 4)),
      _L(_crackle(0.16, 42, 1400, (t) => _ad(t, 0.001, 0.05), hp: 500), 0.6),
      _L(_burst(43, 0.05, attack: 0.001, band: 650, q: 1.1), 0.75),
      _L(_burst(46, 0.012, attack: 0.0003, band: 3800, q: 0.8), 0.6),
      _L(_room(47, 0.4), 0.3),
    ]);

/// Critical / backstab: heavy slam plus a metallic slash ring.
Float64List _hitCrit() {
  const _Modes shing = [
    (2349, 1, 0.22), (3520, 0.7, 0.16), (4699, 0.5, 0.11), (6272, 0.3, 0.07),
  ];
  return _mix([
    _L(_hitHeavy(), 0.95),
    _L(_swoosh(0.12, 48, 0.2, band: const _Curve([(0, 3000), (0.12, 8000)]), q: 1.2), 0.45),
    _L(_modes(0.5, shing), 0.5, 0.01),
  ]);
}

/// Knockout: detonating low boom, crash, and a falling metallic groan.
Float64List _ko() {
  const _Modes groan = [(98, 1, 0.5), (147, 0.6, 0.4), (233, 0.4, 0.3)];
  return _mix([
    _L(_thump(0.9, 90, 28, sweep: 0.06, decay: 0.3, drive: 5)),
    _L(_noise(0.9, 61, (t) => _ad(t, 0.002, 0.28), hp: 2500), 0.45),
    _L(_crackle(0.3, 62, 1800, (t) => _ad(t, 0.001, 0.09), hp: 400), 0.5),
    _L(_modes(0.9, groan), 0.4, 0.02),
    _L(_room(63, 0.9, lp: 900, tau: 0.25), 0.35),
  ]);
}

/// War drum hit ("DON"): skin fundamental, stick attack, body resonance.
Float64List _taiko(double size) {
  final f0 = 88 / size;
  return _mix([
    _L(_thump(0.7, f0 * 1.6, f0, sweep: 0.03, decay: 0.22, drive: 1.5)),
    _L(_modes(0.6, [(f0 * 1.52, 0.5, 0.12), (f0 * 2.18, 0.3, 0.08)]), 0.4),
    _L(_burst(81, 0.006, attack: 0.0005, band: 1600, q: 0.8), 0.45),
    _L(_room(82, 0.6, lp: 700, tau: 0.16), 0.3),
  ]);
}

/// Temple gong (fight start): beating inharmonic partials, slow bloom.
Float64List _gong() {
  const _Modes partials = [
    (110, 1, 1.4), (111.3, 0.8, 1.3), (163, 0.6, 1.0), (231, 0.5, 0.8),
    (317, 0.35, 0.6), (452, 0.25, 0.45), (613, 0.15, 0.3),
  ];
  return _mix([
    _L(_modes(2.0, partials)),
    _L(_thump(0.5, 120, 50, sweep: 0.04, decay: 0.2), 0.5),
    _L(_noise(1.6, 83, (t) => _hump(t, 1.6, 0.1), band: (_) => 900, q: 2), 0.12),
  ]);
}

/// "Lub-dub" for low health.
Float64List _heartbeat() => _mix([
      _L(_thump(0.2, 70, 40, sweep: 0.02, decay: 0.06, drive: 1.5)),
      _L(_thump(0.2, 62, 36, sweep: 0.02, decay: 0.05, drive: 1.5), 0.7, 0.2),
    ]);

/// Clock tick for the last seconds (woody, dry).
Float64List _clockTick() => _mix([
      _L(_burst(84, 0.004, attack: 0.0002, band: 3200, q: 3)),
      _L(_modes(0.06, const [(1800, 1, 0.012), (2700, 0.5, 0.008)]), 0.5),
    ]);

/// Cartoon crowd: a dozen detuned voices through an "oh" formant, plus
/// breathy murmur. [cheer] adds rising "hey!" swells.
Float64List _crowd(double dur, {required bool cheer, required int seed}) {
  final rng = _Rng(seed);
  final voices = [
    for (var i = 0; i < 12; i++)
      (_Osc(rng.unit()), rng.range(130, 330), rng.range(4, 7), rng.range(0, 0.25)),
  ];
  final f1 = _Svf(), f2 = _Svf(), f3 = _Svf(), air = _Svf(), n = _Rng(seed + 1);
  return _gen(dur, (t) {
    var v = 0.0;
    for (final (o, f, vib, delay) in voices) {
      if (t < delay) continue;
      final lift = cheer ? 1 + 0.25 * _smooth((t - delay) / 0.4) : 1 - 0.12 * t / dur;
      v += o.saw(f * lift * (1 + 0.02 * math.sin(_tau * vib * t)));
    }
    final vowel = f1.band(v, 520, 4) + 0.8 * f2.band(v, 900, 5) + 0.3 * f3.band(v, 2500, 6);
    final murmur = air.band(n.bi(), 700, 0.8) * 0.8;
    final env = cheer ? _ar(t, dur, 0.08, 0.6) : _hump(t, dur, 0.25);
    return (vowel * 0.12 + murmur) * env;
  });
}

/// Strident rooster formants (bright, nasal) — not a human "oh".
const _Vowel _vowelCrow = [(1500, 4, 1), (2900, 6, 0.65), (900, 3, 0.45), (4200, 8, 0.2)];

/// Rooster "Ò-ó-o-ooo": raspy (38 Hz flutter + period doubling), bright
/// formants, a "k" click on each syllable, and a long last note that holds
/// high then falls.
Float64List _crow() {
  const tone = _Tone(0.006, 0.03, 0.22, 3.2,
      jitter: 0.03, vib: (7, 0.015), sub: 0.12, growl: 0.45);
  const tail = _Tone(0.01, 0.12, 0.24, 3.4,
      jitter: 0.035, vib: (6, 0.025), sub: 0.15, growl: 0.5);
  double rasp(double t) => 1 - 0.38 * (0.5 + 0.5 * math.sin(_tau * 38 * t));
  _L syl(double dur, _Curve pitch, _Curve shift, _Tone tn, int seed, double at, double g) =>
      _L(_voice(dur, pitch, _vowelCrow, tn, seed, shift: shift, amp: rasp), g, at);
  _L k(double at, int seed) => _L(_burst(seed, 0.005, attack: 0.0003, band: 2600, q: 1.4), 0.35, at);
  return _mix([
    k(0, 401),
    syl(0.12, const _Curve([(0, 520), (0.12, 650)]), const _Curve([(0, 0.95)]), tone, 11, 0.005, 0.8),
    k(0.15, 402),
    syl(0.1, const _Curve([(0, 640), (0.1, 720)]), const _Curve([(0, 1.0)]), tone, 12, 0.155, 0.75),
    k(0.28, 403),
    syl(0.28, const _Curve([(0, 700), (0.08, 830), (0.28, 810)]),
        const _Curve([(0, 1.0), (0.28, 1.08)]), tone, 13, 0.285, 0.95),
    k(0.6, 404),
    syl(0.8, const _Curve([(0, 780), (0.1, 920), (0.45, 890), (0.8, 470)]),
        const _Curve([(0, 1.08), (0.45, 1.12), (0.8, 0.82)]), tail, 14, 0.605, 1),
  ]);
}
