import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster_rage/audio/sfx_synth.dart';
import 'package:rooster_rage/audio/sound_fx.dart';

void main() {
  group('SfxSynth', () {
    final rendered = <SoundId, Float32List>{};
    var elapsedMs = 0;

    setUpAll(() {
      final sw = Stopwatch()..start();
      for (final id in SoundId.values) {
        rendered[id] = SfxSynth.render(id);
      }
      elapsedMs = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('Synthesized ${SoundId.values.length} sounds in $elapsedMs ms');
    });

    for (final id in SoundId.values) {
      test('${id.name} renders a sane, audible buffer', () {
        final s = rendered[id]!;
        expect(s, isNotEmpty);
        var peak = 0.0;
        for (final v in s) {
          expect(v.isFinite, isTrue);
          expect(v, inInclusiveRange(-1.0, 1.0));
          if (v.abs() > peak) peak = v.abs();
        }
        expect(peak, greaterThan(0.2));
        expect(s.length / SfxSynth.sampleRate, lessThanOrEqualTo(2.0));
      });
    }

    test('synthesis of every sound is fast', () {
      expect(elapsedMs, lessThan(2000));
    });

    test('rendering is deterministic', () {
      expect(SfxSynth.render(SoundId.splash), rendered[SoundId.splash]);
      expect(SfxSynth.render(SoundId.crow), rendered[SoundId.crow]);
    });

    test('peck is short and earthBoom is long', () {
      expect(
        rendered[SoundId.peck]!.length / SfxSynth.sampleRate,
        lessThan(0.05),
      );
      expect(
        rendered[SoundId.earthBoom]!.length / SfxSynth.sampleRate,
        greaterThan(0.6),
      );
    });
  });

  group('SoundFx (stub)', () {
    test('API calls never throw', () {
      final fx = SoundFx.instance;
      expect(identical(fx, SoundFx.instance), isTrue);
      expect(fx.volume, 0.8);
      expect(fx.muted, isFalse);
      fx.unlock();
      for (final id in SoundId.values) {
        fx.play(id);
        fx.play(id, volume: 0.5, rate: 1.3, pan: -1);
      }
      fx.muted = true;
      fx.play(SoundId.crow);
      fx.muted = false;
      fx.volume = 0.3;
      fx.play(SoundId.peck, volume: 2, rate: 0.8, pan: 1);
      fx.volume = 0.8;
    });
  });

  group('battle music', () {
    for (final track in MusicTrack.values) {
      test('$track is a clean, seamless loop', () {
        final sw = Stopwatch()..start();
        final m = SfxSynth.renderMusic(track);
        final secs = m.length / SfxSynth.sampleRate;
        // ignore: avoid_print
        print('$track: ${secs.toStringAsFixed(2)} s rendered in ${sw.elapsedMilliseconds} ms');
        expect(secs, inInclusiveRange(10, 16)); // 8 bars at 140/160 BPM
        var peak = 0.0;
        for (final v in m) {
          expect(v.isFinite, isTrue);
          if (v.abs() > peak) peak = v.abs();
        }
        expect(peak, inInclusiveRange(0.5, 1.0));
        // No jump at the loop seam.
        expect((m.first - m.last).abs(), lessThan(0.25));
      });
    }
  });
}
