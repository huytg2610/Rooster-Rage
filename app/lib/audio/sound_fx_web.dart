import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'sfx_synth.dart';
import 'sound_ids.dart';

/// Web Audio backend. Every call is best-effort: failures (autoplay policy,
/// missing APIs) are swallowed so audio can never break the game.
///
/// Graph: voice source → gain → [stereo panner] → master gain → compressor
/// → destination.
class SoundFx {
  SoundFx._();

  static final SoundFx instance = SoundFx._();

  static const int maxVoices = 24;

  /// Minimum spacing between two starts of the same sound, in seconds.
  static const double minRetrigger = 0.03;

  static const double _headroom = 0.7;
  static const int _warmBudgetMs = 8;

  bool _muted = false;
  double _volume = 0.8;

  // Background music: one looping source at a time, crossfaded.
  static const double musicLevel = 0.42;
  bool _musicMuted = false;
  web.GainNode? _musicBus;
  web.AudioBufferSourceNode? _musicSrc;
  web.GainNode? _musicFade;
  MusicTrack? _musicTrack;
  final Map<MusicTrack, web.AudioBuffer> _musicBuffers = {};

  web.AudioContext? _ctx;
  web.GainNode? _master;
  bool _unavailable = false;
  bool _canPan = true;

  final List<web.AudioBuffer?> _buffers = List.filled(
    SoundId.values.length,
    null,
  );
  final Float64List _durations = Float64List(SoundId.values.length);
  final List<bool> _broken = List.filled(SoundId.values.length, false);
  final Float64List _lastStart = Float64List(SoundId.values.length)
    ..fillRange(0, SoundId.values.length, -1);
  final List<_Voice> _voices = [];
  final Stopwatch _clock = Stopwatch()..start();
  int _lastResumeMs = -1000;
  int _warmNext = 0;
  Timer? _warmTimer;

  /// When true, [play] is a no-op and the master bus is silenced.
  bool get muted => _muted;
  set muted(bool value) {
    _muted = value;
    _applyMaster();
  }

  /// Music on/off (sound effects unaffected).
  bool get musicMuted => _musicMuted;
  set musicMuted(bool value) {
    _musicMuted = value;
    final ctx = _ctx, bus = _musicBus;
    if (ctx == null || bus == null) return;
    try {
      bus.gain.setTargetAtTime(value ? 0 : musicLevel, ctx.currentTime, 0.05);
    } on Object {
      // Audio is best-effort.
    }
  }

  /// Starts (or crossfades to) a looping track. Rendering happens on first
  /// use of each track (~tens of ms), so callers may pre-warm with
  /// [prepareMusic] at a quiet moment (e.g. the reveal screen).
  void playMusic(MusicTrack track) {
    final ctx = _ctx, bus = _musicBus;
    if (ctx == null || bus == null || track == _musicTrack) return;
    try {
      final buffer = _musicBuffer(track, ctx);
      if (buffer == null) return;
      _fadeOutMusic(ctx, 0.8);
      final src = ctx.createBufferSource()
        ..buffer = buffer
        ..loop = true;
      final fade = ctx.createGain();
      fade.gain.value = 0;
      fade.gain.setTargetAtTime(1, ctx.currentTime, 0.25);
      src.connect(fade);
      fade.connect(bus);
      src.start();
      _musicSrc = src;
      _musicFade = fade;
      _musicTrack = track;
    } on Object {
      // Audio is best-effort.
    }
  }

  void stopMusic() {
    final ctx = _ctx;
    if (ctx == null) return;
    _fadeOutMusic(ctx, 0.6);
    _musicTrack = null;
  }

  /// Renders a track's buffer ahead of time (no-op if already cached).
  void prepareMusic(MusicTrack track) {
    final ctx = _ctx;
    if (ctx != null) _musicBuffer(track, ctx);
  }

  void _fadeOutMusic(web.AudioContext ctx, double seconds) {
    final src = _musicSrc, fade = _musicFade;
    _musicSrc = null;
    _musicFade = null;
    if (src == null || fade == null) return;
    try {
      fade.gain.setTargetAtTime(0, ctx.currentTime, seconds / 4);
      src.stop(ctx.currentTime + seconds);
    } on Object {
      // Already stopped.
    }
  }

  web.AudioBuffer? _musicBuffer(MusicTrack track, web.AudioContext ctx) {
    final cached = _musicBuffers[track];
    if (cached != null) return cached;
    try {
      final samples = SfxSynth.renderMusic(track);
      final buffer = ctx.createBuffer(1, samples.length, SfxSynth.sampleRate);
      buffer.copyToChannel(samples.toJS, 0);
      return _musicBuffers[track] = buffer;
    } on Object {
      return null;
    }
  }

  /// Master volume, 0..1.
  double get volume => _volume;
  set volume(double value) {
    if (!value.isFinite) return;
    _volume = value.clamp(0.0, 1.0);
    _applyMaster();
  }

  /// Creates or resumes the audio context; call from a user gesture. Cheap
  /// and idempotent, so calling it on every tap is fine.
  void unlock() {
    if (_unavailable) return;
    try {
      final ctx = _ctx ?? _createContext();
      if (ctx == null) return;
      if (ctx.state != 'running') {
        ctx.resume().toDart.ignore();
        _primeSilence(ctx);
      }
      _scheduleWarm();
    } on Object {
      // Audio is best-effort.
    }
  }

  /// Fire-and-forget. [rate] scales playback speed and pitch; [pan] is
  /// -1 (left) .. 1 (right).
  void play(SoundId id, {double volume = 1, double rate = 1, double pan = 0}) {
    final ctx = _ctx;
    final master = _master;
    if (_muted || ctx == null || master == null) return;
    if (!(volume > 0)) return;
    try {
      if (ctx.state != 'running') {
        _tryResume(ctx);
        return;
      }
      final now = ctx.currentTime;
      final i = id.index;
      if (now - _lastStart[i] < minRetrigger) return;
      final buffer = _bufferFor(id, ctx);
      if (buffer == null) return;
      _lastStart[i] = now;

      _voices.removeWhere((v) => v.end <= now);
      if (_voices.length >= maxVoices) _stealVoice(now);

      final r = rate.isFinite ? rate.clamp(0.25, 4.0) : 1.0;
      final source = ctx.createBufferSource()..buffer = buffer;
      source.playbackRate.value = r;
      final gain = ctx.createGain();
      gain.gain.value = volume.clamp(0.0, 2.0);
      source.connect(gain);
      _route(ctx, gain, pan, master);
      source.start();
      _voices.add(_Voice(source, gain, now + _durations[i] / r));
    } on Object {
      // Audio is best-effort.
    }
  }

  web.AudioContext? _createContext() {
    try {
      final ctx = web.AudioContext();
      final master = ctx.createGain();
      final limiter = ctx.createDynamicsCompressor();
      limiter.threshold.value = -6;
      limiter.knee.value = 6;
      limiter.ratio.value = 12;
      limiter.attack.value = 0.002;
      limiter.release.value = 0.15;
      master.connect(limiter);
      limiter.connect(ctx.destination);
      master.gain.value = _masterTarget;
      final music = ctx.createGain();
      music.gain.value = _musicMuted ? 0 : musicLevel;
      music.connect(master);
      _musicBus = music;
      _ctx = ctx;
      _master = master;
      return ctx;
    } on Object {
      _unavailable = true;
      return null;
    }
  }

  double get _masterTarget => _muted ? 0 : _volume * _headroom;

  void _applyMaster() {
    final ctx = _ctx;
    final master = _master;
    if (ctx == null || master == null) return;
    try {
      master.gain.setTargetAtTime(_masterTarget, ctx.currentTime, 0.015);
    } on Object {
      // Audio is best-effort.
    }
  }

  /// Older iOS only unlocks output once a buffer is started inside a gesture.
  void _primeSilence(web.AudioContext ctx) {
    try {
      final source = ctx.createBufferSource()
        ..buffer = ctx.createBuffer(1, 1, SfxSynth.sampleRate);
      source.connect(ctx.destination);
      source.start();
    } on Object {
      // Audio is best-effort.
    }
  }

  /// Contexts can be suspended by the browser (tab switch, iOS interruption);
  /// after the first gesture they may be resumed without one.
  void _tryResume(web.AudioContext ctx) {
    final ms = _clock.elapsedMilliseconds;
    if (ms - _lastResumeMs < 500) return;
    _lastResumeMs = ms;
    ctx.resume().toDart.ignore();
  }

  void _route(
    web.AudioContext ctx,
    web.GainNode gain,
    double pan,
    web.GainNode master,
  ) {
    if (_canPan && pan.isFinite && pan != 0) {
      try {
        final panner = ctx.createStereoPanner();
        panner.pan.value = pan.clamp(-1.0, 1.0);
        gain.connect(panner);
        panner.connect(master);
        return;
      } on Object {
        _canPan = false;
      }
    }
    gain.connect(master);
  }

  void _stealVoice(double now) {
    var victim = 0;
    for (var i = 1; i < _voices.length; i++) {
      if (_voices[i].end < _voices[victim].end) victim = i;
    }
    final v = _voices.removeAt(victim);
    try {
      v.gain.gain.setTargetAtTime(0, now, 0.008);
      v.source.stop(now + 0.04);
    } on Object {
      // Already stopped.
    }
  }

  web.AudioBuffer? _bufferFor(SoundId id, web.AudioContext ctx) {
    final i = id.index;
    final cached = _buffers[i];
    if (cached != null || _broken[i]) return cached;
    try {
      final samples = SfxSynth.render(id);
      final buffer = ctx.createBuffer(1, samples.length, SfxSynth.sampleRate);
      buffer.copyToChannel(samples.toJS, 0);
      _durations[i] = samples.length / SfxSynth.sampleRate;
      return _buffers[i] = buffer;
    } on Object {
      _broken[i] = true;
      return null;
    }
  }

  /// Renders the remaining buffers a few at a time between frames so the
  /// first play of any sound is instant without a startup hitch.
  void _scheduleWarm() {
    if (_warmTimer != null || _warmNext >= SoundId.values.length) return;
    _warmTimer = Timer(const Duration(milliseconds: 20), _warmStep);
  }

  void _warmStep() {
    _warmTimer = null;
    final ctx = _ctx;
    if (ctx == null) return;
    final sw = Stopwatch()..start();
    while (_warmNext < SoundId.values.length &&
        sw.elapsedMilliseconds < _warmBudgetMs) {
      _bufferFor(SoundId.values[_warmNext++], ctx);
    }
    _scheduleWarm();
  }
}

final class _Voice {
  _Voice(this.source, this.gain, this.end);

  final web.AudioBufferSourceNode source;
  final web.GainNode gain;
  final double end;
}
