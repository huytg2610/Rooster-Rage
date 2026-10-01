import 'sound_ids.dart';

/// Silent backend for platforms without Web Audio (native audio comes later).
class SoundFx {
  SoundFx._();

  static final SoundFx instance = SoundFx._();

  /// When true, [play] is a no-op.
  bool muted = false;

  /// Master volume, 0..1.
  double volume = 0.8;

  /// Music on/off (sound effects unaffected).
  bool musicMuted = false;

  void unlock() {}

  void playMusic(MusicTrack track) {}

  void stopMusic() {}

  void prepareMusic(MusicTrack track) {}

  void play(SoundId id, {double volume = 1, double rate = 1, double pan = 0}) {}
}
