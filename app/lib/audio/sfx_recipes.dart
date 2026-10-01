part of 'sfx_synth.dart';

Float64List _recipe(SoundId id) => switch (id) {
  SoundId.uiClick => _uiClick(),
  SoundId.cardFlip => _cardFlip(),
  SoundId.fanfare => _fanfare(),
  SoundId.countdownBeep => _beep(880, 0.12, 0),
  SoundId.countdownGo => _beep(1760, 0.5, 0.35),
  SoundId.timeUp => _timeUp(),
  SoundId.whooshLight => _whooshLight(),
  SoundId.whooshHeavy => _whooshHeavy(),
  SoundId.dash => _dash(),
  SoundId.jump => _jump(),
  SoundId.land => _land(),
  SoundId.landBig => _landBig(),
  SoundId.hitLight => _hitLight(),
  SoundId.hitHeavy => _hitHeavy(),
  SoundId.hitCrit => _hitCrit(),
  SoundId.block => _block(),
  SoundId.guardBreak => _guardBreak(),
  SoundId.ko => _ko(),
  SoundId.splash => _splash(),
  SoundId.fallWhistle => _fallWhistle(),
  SoundId.pickup => _pickup(),
  SoundId.trapSnap => _trapSnap(),
  SoundId.bucketSpill => _bucketSpill(),
  SoundId.cluck => _cluck(),
  SoundId.squawk => _squawk(),
  SoundId.crow => _crow(),
  SoundId.rageRoar => _rageRoar(),
  SoundId.flameKick => _flameKick(),
  SoundId.shadowDash => _shadowDash(),
  SoundId.earthBoom => _earthBoom(),
  SoundId.madSquawk => _madSquawk(),
  SoundId.fakeDeath => _fakeDeath(),
  SoundId.surprise => _surprise(),
  SoundId.stomp => _stomp(),
  SoundId.peck => _peck(),
  SoundId.vortex => _vortex(),
  SoundId.vortexBurst => _vortexBurst(),
  SoundId.respawn => _respawn(),
  SoundId.exhausted => _exhausted(),
  SoundId.taiko => _taiko(1),
  SoundId.gong => _gong(),
  SoundId.heartbeat => _heartbeat(),
  SoundId.clockTick => _clockTick(),
  SoundId.crowdOoh => _crowd(1.2, cheer: false, seed: 900),
  SoundId.crowdCheer => _crowd(1.8, cheer: true, seed: 950),
};

Float64List _click(int seed, double tau) =>
    _burst(seed, tau, attack: 0.0003, hp: 2500);

// ---------------------------------------------------------------------------
// Chicken voice

/// One "bok": fast pitch drop through a nasal formant; [s] scales pitch.
Float64List _bok(double s, int seed) {
  final p = _Curve([(0, 640 * s), (0.02, 540 * s), (0.09, 430 * s)]);
  const shift = _Curve([(0, 0.8), (0.018, 1.05), (0.09, 0.9)]);
  const tone = _Tone(0.004, 0.035, 0.08, 1.5);
  double decay(double t) => math.exp(-t / 0.05);
  final v = _voice(0.09, p, _vowelBok, tone, seed, shift: shift, amp: decay);
  return _mix([
    _L(v),
    _L(_burst(seed + 100, 0.003, attack: 0.0004, band: 2800, q: 1.5), 0.3),
  ]);
}

Float64List _cluck() => _mix([_L(_bok(1, 1)), _L(_bok(0.92, 2), 0.8, 0.115)]);

/// Hurt "BAWK!": pitch jumps up then falls, rough and gritty.
Float64List _squawk() {
  const p = _Curve([(0, 900), (0.035, 1400), (0.09, 1250), (0.25, 700)]);
  const shift = _Curve([(0, 0.75), (0.04, 1.1), (0.25, 0.95)]);
  const tone = _Tone(0.006, 0.07, 0.2, 2.5, jitter: 0.03, vib: (23, 0.015));
  return _mix([
    _L(_voice(0.25, p, _vowelAw, tone, 3, shift: shift)),
    _L(_burst(4, 0.006, attack: 0.001, band: 3000, q: 1.2), 0.25, 0.225),
  ]);
}

/// Low, growling crow with sub-harmonic and a rising power swell.
Float64List _rageRoar() {
  const p = _Curve([(0, 165), (0.7, 290), (0.85, 320), (1, 250)]);
  const shift = _Curve([(0, 0.8), (0.7, 1.15), (1.0, 1.0)]);
  const tone = _Tone(
    0.03,
    0.12,
    0.3,
    4,
    jitter: 0.04,
    vib: (7, 0.02),
    sub: 0.5,
    growl: 0.6,
  );
  double swell(double t) => 0.35 + 0.65 * _smooth(t / 0.75);
  return _voice(1, p, _vowelAa, tone, 9, shift: shift, amp: swell);
}

/// Four fast, fuzzy, angry squawks.
Float64List _madSquawk() {
  const shift = _Curve([(0, 0.8), (0.025, 1.12), (0.11, 0.95)]);
  const tone = _Tone(0.004, 0.035, 0.3, 4.5, jitter: 0.05, vib: (31, 0.025));
  _L squawk(int i, double f) {
    final p = _Curve([(0, f), (0.02, f * 1.45), (0.11, f * 0.8)]);
    final v = _voice(0.11, p, _vowelAw, tone, 20 + i, shift: shift);
    return _L(v, i.isEven ? 1 : 0.85, i * 0.125);
  }

  return _mix([
    for (final (i, f) in const [980.0, 1120.0, 900.0, 1180.0].indexed)
      squawk(i, f),
  ]);
}

// ---------------------------------------------------------------------------
// UI / match flow

Float64List _uiClick() {
  const _Modes wood = [
    (1900, 1, 0.006),
    (3150, 0.45, 0.004),
    (5300, 0.2, 0.002),
  ];
  return _mix([_L(_modes(0.03, wood)), _L(_click(1, 0.0012), 0.5)]);
}

Float64List _cardFlip() {
  double env(double t) => _ad(t, 0.0015, 0.011);
  return _mix([
    _L(_noise(0.05, 2, env, band: (t) => 2200 + 3e4 * t, q: 0.9)),
    _L(_burst(3, 0.008, attack: 0.001, band: 3800, q: 1.2), 0.55, 0.032),
  ]);
}

/// Brass-ish note: detuned saws + sub pulse, filter opening with the attack.
Float64List _brass(double f, double dur, {bool hold = false}) {
  final a = _Osc(), b = _Osc(0.37), c = _Osc(0.11), v = _Osc(), filter = _Svf();
  return _gen(dur, (t) {
    final vib = hold ? 0.009 * _smooth((t - 0.12) / 0.15) * v.sine(5.5) : 0.0;
    final fr = f * (1 - 0.03 * math.exp(-t / 0.02)) * (1 + vib);
    final src = a.saw(fr * 1.003) + b.saw(fr * 0.997) + 0.5 * c.square(fr / 2);
    final bright = _smooth(t / 0.03) * (0.6 + 0.4 * math.exp(-t / 0.12));
    final y = filter.lowpass(src, fr * (1 + 5 * bright), 0.9);
    return _drive(0.5 * y, 1.5) * _ar(t, dur, 0.018, hold ? 0.18 : 0.03);
  });
}

Float64List _fanfare() => _mix([
  _L(_brass(523.25, 0.11), 0.85),
  _L(_brass(659.25, 0.11), 0.85, 0.1),
  _L(_brass(783.99, 0.11), 0.85, 0.2),
  _L(_brass(1046.5, 0.58, hold: true), 1, 0.3),
]);

/// Sine beep; [bright] > 0 adds a pulse edge and an octave-down body.
Float64List _beep(double f, double dur, double bright) {
  final o = _Osc(), s = _Osc(), l = _Osc(), lpf = _OnePole();
  return _gen(dur, (t) {
    final edge = bright > 0 ? bright * lpf.lp(s.square(f), 5000) : 0.0;
    final body = bright > 0 ? 0.4 * l.sine(f / 2) : 0.12 * l.sine(f * 2);
    final punch = 0.75 + 0.25 * math.exp(-t / 0.08);
    return (o.sine(f) + edge + body) * punch * _ar(t, dur, 0.003, dur * 0.3);
  });
}

/// Pea whistle: sine with a ~27 Hz pitch/amplitude trill plus breath.
Float64List _whistleBlast(double dur, int seed) {
  final o = _Osc(), trill = _Osc(), rng = _Rng(seed), air = _Svf();
  return _gen(dur, (t) {
    final tr = trill.sine(27);
    final f = 2950 * (1 + 0.035 * tr);
    final s = o.sine(f) * (0.75 + 0.25 * tr) + 0.5 * air.band(rng.bi(), f, 6);
    return s * _ar(t, dur, 0.012, 0.04);
  });
}

Float64List _timeUp() => _mix([
  _L(_whistleBlast(0.14, 11), 0.85),
  _L(_whistleBlast(0.4, 12), 1, 0.2),
]);

// ---------------------------------------------------------------------------
// Movement

Float64List _dash() {
  const band = _Curve([(0, 1800), (0.16, 5500)]);
  return _swoosh(0.16, 24, 0.22, band: band, q: 0.9, hp: 800);
}

/// Rising cartoon "boing": triangle sweep with a decaying spring wobble.
Float64List _jump() {
  final o = _Osc(), w = _Osc();
  return _gen(0.28, (t) {
    final wob = 1 + 0.1 * w.sine(15) * math.exp(-t / 0.12);
    final f = 190 * math.pow(3.4, _clamp01(t / 0.2)) * wob;
    return o.tri(f) * _ad(t, 0.004, 0.1) * _smooth((0.28 - t) / 0.05);
  });
}

Float64List _land() => _mix([
  _L(_thump(0.16, 140, 50, decay: 0.05)),
  _L(_burst(31, 0.025, attack: 0.002, lp: 700), 0.35),
]);

Float64List _landBig() => _mix([
  _L(_thump(0.55, 95, 30, sweep: 0.04, decay: 0.16, drive: 2.5)),
  _L(_burst(32, 0.09, attack: 0.003, lp: 240), 0.55),
  _L(_burst(33, 0.008, lp: 2500), 0.35),
]);

// ---------------------------------------------------------------------------
// Combat

Float64List _block() => _mix([
  _L(_clang(640, 0.45, 0.16)),
  _L(_click(51, 0.003), 0.6),
  _L(_thump(0.08, 260, 140, decay: 0.025), 0.35),
]);

/// Clang plus a scatter of glassy shard pings and a bright hiss.
Float64List _guardBreak() {
  final rng = _Rng(52);
  _L shard() {
    final f = rng.range(2600, 7600), tau = rng.range(0.012, 0.04);
    final at = 0.012 + 0.34 * math.pow(rng.unit(), 1.8);
    return _L(_modes(0.08, [(f, 1, tau)]), rng.range(0.15, 0.4), at);
  }

  return _mix([
    _L(_clang(430, 0.6, 0.22)),
    _L(_thump(0.2, 150, 50, decay: 0.06, drive: 2), 0.5),
    _L(_burst(53, 0.08, attack: 0.002, hp: 3500), 0.35, 0.01),
    for (var i = 0; i < 24; i++) shard(),
  ]);
}

// ---------------------------------------------------------------------------
// Arena / props

/// Low-passed wash with bubbly amplitude flutter, plus rising bubble blips.
Float64List _splash() {
  final rng = _Rng(71), n = _Rng(72);
  final lo = _OnePole(), hi = _OnePole(), am = _OnePole();
  final wash = _gen(0.5, (t) {
    final mod = 0.6 + 0.4 * (am.lp(n.bi(), 25) * 20).clamp(-1.0, 1.0);
    final s = hi.hp(lo.lp(n.bi(), 6500.0 * math.pow(0.1, t / 0.5)), 250);
    return s * _ad(t, 0.003, 0.11) * mod;
  });
  _L bubble() {
    final o = _Osc();
    final f = rng.range(350, 950), dur = rng.range(0.02, 0.045);
    final blip = _gen(
      dur,
      (t) => o.sine(f * (1 + 2.2 * t / dur)) * _hump(t, dur, 0.1),
    );
    return _L(blip, rng.range(0.12, 0.3), 0.03 + 0.4 * rng.unit());
  }

  return _mix([
    _L(wash),
    _L(_burst(73, 0.05, attack: 0.001, band: 900), 0.6),
    for (var i = 0; i < 14; i++) bubble(),
  ]);
}

Float64List _fallWhistle() =>
    _whistle(0.8, const _Curve([(0, 2200), (0.3, 1700), (0.8, 430)]), seed: 62);

Float64List _pickup() => _mix([
  _L(_chime(1318.5, 0.045)),
  _L(_chime(1975.5, 0.045), 1, 0.055),
  _L(_chime(2637, 0.08, detune: 0.004), 1, 0.11),
]);

Float64List _trapSnap() {
  const _Modes jaws = [(1850, 1, 0.05), (3120, 0.7, 0.035), (4630, 0.5, 0.025)];
  return _mix([
    _L(_click(101, 0.003)),
    _L(_click(102, 0.002), 0.7, 0.014),
    _L(_modes(0.2, jaws), 0.55, 0.014),
    _L(_thump(0.08, 190, 90, decay: 0.025), 0.6, 0.014),
  ]);
}

/// Metal bucket clank and bounce, then a wobbling water slosh.
Float64List _bucketSpill() {
  final rng = _Rng(111), bp = _Svf(), am = _OnePole(), lfo = _Osc();
  final slosh = _gen(0.7, (t) {
    final mod = (0.55 + 18 * am.lp(rng.bi(), 12)).clamp(0.1, 1.0);
    final water = bp.band(rng.bi(), 750 + 450 * lfo.sine(6.5), 1.6);
    return water * mod * _hump(t, 0.7, 0.25);
  });
  return _mix([
    _L(_clang(310, 0.5, 0.22)),
    _L(_click(112, 0.003), 0.5),
    _L(_clang(330, 0.5, 0.18), 0.45, 0.1),
    _L(slosh, 0.9, 0.08),
  ]);
}

// ---------------------------------------------------------------------------
// Skills

Float64List _flameKick() {
  const band = _Curve([(0, 300), (0.18, 1600), (0.55, 800)]);
  return _mix([
    _L(_swoosh(0.55, 121, 0.3, band: band, q: 0.9)),
    _L(_swoosh(0.55, 122, 0.35, lp: 200), 0.5),
    _L(_crackle(0.5, 123, 90, (t) => _hump(t, 0.5, 0.3)), 0.55, 0.03),
  ]);
}

/// Reversed-feel swell: cubic rise, abrupt cut, soft landing thump.
Float64List _shadowDash() {
  const d = 0.38;
  double swell(double t) =>
      t < d ? math.pow(t / d, 3).toDouble() : math.exp(-(t - d) / 0.012);
  final o = _Osc();
  const band = _Curve([(0, 180), (d, 750)]);
  return _mix([
    _L(_noise(0.42, 131, swell, band: band.at, q: 1.3)),
    _L(_gen(0.42, (t) => o.sine(55 + 40 * t / d) * swell(t)), 0.5),
    _L(_noise(0.42, 132, (t) => swell(t) * swell(t), hp: 3000), 0.15),
    _L(_thump(0.12, 130, 55, decay: 0.035), 0.55, d - 0.01),
  ]);
}

/// Sub boom, dark wobbling rumble, a crack, and scattered debris.
Float64List _earthBoom() {
  final rng = _Rng(141), r = _Rng(142);
  final lo1 = _OnePole(), lo2 = _OnePole(), am = _OnePole();
  final rumble = _gen(1.0, (t) {
    final wobble = 0.6 + (am.lp(r.bi(), 8) * 25).clamp(-0.4, 0.4);
    final dark = lo2.lp(lo1.lp(r.bi(), 220), 220);
    return dark * _ad(t, 0.006, 0.32) * wobble;
  });
  _L debris(int i) => _L(
    _burst(150 + i, 0.006, lp: 1800),
    rng.range(0.08, 0.25),
    0.08 + 0.7 * rng.unit(),
  );
  return _mix([
    _L(_thump(1.0, 75, 28, sweep: 0.06, decay: 0.33, drive: 3)),
    _L(rumble, 0.75),
    _L(_burst(143, 0.012, lp: 4000), 0.5),
    for (var i = 0; i < 12; i++) debris(i),
  ]);
}

/// Plunger-muted trombone note; the last one wobbles and sags.
Float64List _trombone(double f, double dur, {bool last = false}) {
  final a = _Osc(), b = _Osc(0.2), v = _Osc(), wah = _Svf();
  return _gen(dur, (t) {
    final wobble = last ? _smooth((t - 0.1) / 0.2) * v.sine(5.5) : 0.0;
    final sag = last ? 1 - 0.07 * _smooth((t / dur - 0.6) / 0.4) : 1.0;
    final fr = f * (1 + 0.028 * wobble) * sag;
    final open = last ? 0.55 + 0.45 * wobble : _hump(t, dur, 0.35);
    final src = a.saw(fr) + 0.6 * b.square(fr, 0.35);
    final y = wah.lowpass(src, fr * (1.3 + 6 * open), 2.5);
    return _drive(0.4 * y, 1.8) * _ar(t, dur, 0.025, last ? 0.2 : 0.045);
  });
}

/// "Wah wah wah waaah" (B♭3 A3 A♭3 G3).
Float64List _fakeDeath() => _mix([
  _L(_trombone(233.08, 0.23)),
  _L(_trombone(220.0, 0.23), 1, 0.25),
  _L(_trombone(207.65, 0.23), 1, 0.5),
  _L(_trombone(196.0, 0.66, last: true), 1, 0.75),
]);

/// Cork pop, then a buzzy party-horn blat that unrolls up to pitch.
Float64List _surprise() {
  final o = _Osc(0.25);
  double cork(double t) =>
      o.sine(180 + 600 * math.exp(-t / 0.008)) * _ad(t, 0.0005, 0.012);
  const pitch = _Curve([(0, 250), (0.06, 370), (0.4, 360)]);
  const tone = _Tone(0.012, 0.05, 0.1, 3, jitter: 0.015);
  const _Vowel reed = [(1250, 3, 1), (2600, 4, 0.6)];
  return _mix([
    _L(_gen(0.05, cork)),
    _L(_burst(162, 0.004, attack: 0.0003, lp: 5000), 0.7),
    _L(_voice(0.4, pitch, reed, tone, 161), 0.85, 0.035),
  ]);
}

Float64List _stomp() => _mix([
  _L(_thump(0.32, 170, 42, sweep: 0.015, decay: 0.1, drive: 4)),
  _L(_click(171, 0.0025), 0.55),
  _L(_burst(172, 0.035, attack: 0.001, lp: 900), 0.5),
]);

Float64List _peck() {
  const _Modes tip = [(2300, 1, 0.006), (4100, 0.6, 0.004), (950, 0.5, 0.009)];
  return _mix([_L(_modes(0.04, tip)), _L(_click(181, 0.0015), 0.7)]);
}

/// Wind through two band-passes swept in anti-phase by an accelerating LFO.
Float64List _vortex() {
  final rng = _Rng(191), a = _Svf(), b = _Svf(), rumble = _OnePole();
  const base = _Curve([(0, 450), (1.0, 1400)]);
  var phase = 0.0;
  return _gen(1.0, (t) {
    phase += _tau * (3 + 7 * t) / _sr;
    final c = base.at(t), lfo = math.sin(phase), s = rng.bi();
    final y =
        a.band(s, c * (1 + 0.45 * lfo), 4) +
        0.6 * b.band(s, c * 1.9 * (1 - 0.35 * lfo), 5) +
        rumble.lp(s, 150);
    return y * (0.25 + 0.75 * _smooth(t / 0.8)) * _smooth((1.0 - t) / 0.08);
  });
}

Float64List _vortexBurst() {
  const sweep = _Curve([(0, 7000), (0.4, 250)]);
  return _mix([
    _L(_thump(0.7, 95, 32, sweep: 0.05, decay: 0.2, drive: 3)),
    _L(_noise(0.6, 201, (t) => _ad(t, 0.003, 0.15), lp: sweep.at), 0.85),
    _L(_swoosh(0.35, 202, 0.15, band: const _Curve([(0, 280)]), q: 2), 0.6),
  ]);
}

/// Rising sparkle arpeggio over a shimmering hiss and an upward air sweep.
Float64List _respawn() {
  const notes = [1046.5, 1318.5, 1568.0, 2093.0, 2637.0, 3136.0];
  const air = _Curve([(0, 400), (0.7, 3200)]);
  double shimmer(double t) =>
      _hump(t, 0.75, 0.45) * (0.7 + 0.3 * math.sin(_tau * 11 * t));
  return _mix([
    for (final (i, f) in notes.indexed)
      _L(_chime(f, 0.13, a: 0.012, detune: 0.0035), 0.8 - i * 0.07, i * 0.06),
    _L(_noise(0.75, 91, shimmer, hp: 5000), 0.2),
    _L(_swoosh(0.7, 92, 0.6, band: air, q: 2), 0.3),
  ]);
}

/// Wheezy inhale, then a breathy tired "hah".
Float64List _exhausted() {
  final o = _Osc(), rng = _Rng(82), jit = _OnePole();
  final wheeze = _gen(0.22, (t) {
    final f = 1250 * (1 - 0.1 * t / 0.22) * (1 + 0.6 * jit.lp(rng.bi(), 30));
    return o.sine(f) * _hump(t, 0.22, 0.4);
  });
  const inhale = _Curve([(0, 1900), (0.24, 2300)]);
  const exhale = _Curve([(0, 1400), (0.32, 1000)]);
  const pitch = _Curve([(0, 420), (0.25, 330)]);
  const tone = _Tone(0.03, 0.12, 0.8, 1);
  const _Vowel hah = [(900, 3, 1), (1600, 4, 0.5)];
  return _mix([
    _L(_swoosh(0.24, 83, 0.3, band: inhale, q: 1.5)),
    _L(wheeze, 0.22, 0.01),
    _L(_swoosh(0.32, 84, 0.3, band: exhale, q: 1.2), 0.85, 0.28),
    _L(_voice(0.25, pitch, hah, tone, 85), 0.3, 0.3),
  ]);
}
