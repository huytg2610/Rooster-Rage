// Renders every sound effect to build/sfx_preview/<name>.wav and prints
// per-sound stats. Run from app/: dart run tool/export_sfx.dart
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rooster_rage/audio/sfx_synth.dart';
import 'package:rooster_rage/audio/sound_ids.dart';

const _envelopeIds = {
  SoundId.cluck,
  SoundId.squawk,
  SoundId.crow,
  SoundId.madSquawk,
  SoundId.rageRoar,
  SoundId.fakeDeath,
};

void main() {
  const sr = SfxSynth.sampleRate;
  final appDir = File.fromUri(Platform.script).parent.parent;
  final outDir = Directory('${appDir.path}/build/sfx_preview')
    ..createSync(recursive: true);

  print(
    '${'sound'.padRight(14)}${'ms'.padLeft(6)}${'peak'.padLeft(7)}'
    '${'rms dB'.padLeft(8)}${'centroid'.padLeft(10)}${'pwr-cent'.padLeft(10)}',
  );
  final envelopes = <String>[];
  final total = Stopwatch()..start();
  for (final track in MusicTrack.values) {
    // Two loop passes back to back, so the seam can be heard.
    final m = SfxSynth.renderMusic(track);
    final twice = Float32List(m.length * 2)
      ..setAll(0, m)
      ..setAll(m.length, m);
    File('${outDir.path}/music_${track.name}.wav').writeAsBytesSync(_wav(twice, sr));
  }
  for (final id in SoundId.values) {
    final s = SfxSynth.render(id);
    File('${outDir.path}/${id.name}.wav').writeAsBytesSync(_wav(s, sr));

    var peak = 0.0, sq = 0.0;
    for (final v in s) {
      peak = math.max(peak, v.abs());
      sq += v * v;
    }
    final rms = math.sqrt(sq / s.length);
    print(
      '${id.name.padRight(14)}'
      '${(s.length * 1000 / sr).toStringAsFixed(0).padLeft(6)}'
      '${peak.toStringAsFixed(2).padLeft(7)}'
      '${(20 * math.log(rms) / math.ln10).toStringAsFixed(1).padLeft(8)}'
      '${'${_centroid(s, sr, 1).round()} Hz'.padLeft(10)}'
      '${'${_centroid(s, sr, 2).round()} Hz'.padLeft(10)}',
    );
    if (_envelopeIds.contains(id)) envelopes.add(_envelope(id.name, s, sr));
  }
  print('\nTotal (render + stats + write): ${total.elapsedMilliseconds} ms');
  print('\nRMS envelope (25 ms bins, " " < -40 dB .. "@" = 0 dB) and pitch:');
  envelopes.forEach(print);
  print('\nWrote ${SoundId.values.length} files to ${outDir.path}');
}

Uint8List _wav(Float32List s, int sr) {
  final data = ByteData(44 + s.length * 2);
  void tag(int at, String t) {
    for (var i = 0; i < 4; i++) {
      data.setUint8(at + i, t.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  data.setUint32(4, 36 + s.length * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sr, Endian.little)
    ..setUint32(28, sr * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, s.length * 2, Endian.little);
  for (var i = 0; i < s.length; i++) {
    final v = (s[i].clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Mean frequency over Hann-windowed 1024-point frames, weighted by
/// magnitude ([power] 1) or energy ([power] 2).
double _centroid(Float32List s, int sr, int power) {
  const n = 1024;
  var num = 0.0, den = 0.0;
  for (var start = 0; start < s.length; start += n ~/ 2) {
    final re = Float64List(n), im = Float64List(n);
    for (var i = 0; i < n && start + i < s.length; i++) {
      re[i] = s[start + i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)));
    }
    _fft(re, im);
    for (var k = 1; k < n ~/ 2; k++) {
      final e = re[k] * re[k] + im[k] * im[k];
      final mag = power == 2 ? e : math.sqrt(e);
      num += mag * k * sr / n;
      den += mag;
    }
  }
  return den == 0 ? 0 : num / den;
}

void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i], ti = im[i];
      re[i] = re[j];
      im[i] = im[j];
      re[j] = tr;
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    for (var i = 0; i < n; i += len) {
      for (var k = 0; k < len ~/ 2; k++) {
        final wr = math.cos(ang * k), wi = math.sin(ang * k);
        final a = i + k, b = a + len ~/ 2;
        final xr = re[b] * wr - im[b] * wi, xi = re[b] * wi + im[b] * wr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
      }
    }
  }
}

String _envelope(String name, Float32List s, int sr) {
  final bin = (0.025 * sr).round();
  final bars = StringBuffer('${name.padRight(10)}|');
  for (var start = 0; start < s.length; start += bin) {
    var sq = 0.0;
    final end = math.min(start + bin, s.length);
    for (var i = start; i < end; i++) {
      sq += s[i] * s[i];
    }
    final db = 20 * math.log(math.sqrt(sq / (end - start)) + 1e-9) / math.ln10;
    const glyphs = ' .:-=+*#%@';
    final level = ((db + 40) / 40 * (glyphs.length - 1)).round();
    bars.write(glyphs[level.clamp(0, glyphs.length - 1)]);
  }
  bars.write('|\n${''.padRight(10)} f0 Hz @50ms:');
  for (var start = 0; start + 1024 <= s.length; start += (0.05 * sr).round()) {
    bars.write(' ${_pitch(s, start, sr)}');
  }
  return bars.toString();
}

/// Crude autocorrelation pitch estimate (150..2000 Hz) of a 1024-sample frame.
String _pitch(Float32List s, int start, int sr) {
  const n = 1024;
  var energy = 0.0;
  for (var i = 0; i < n; i++) {
    energy += s[start + i] * s[start + i];
  }
  if (energy < 1e-3) return '-';
  var best = 0.0, bestLag = 0;
  for (var lag = sr ~/ 2000; lag <= sr ~/ 150; lag++) {
    var c = 0.0;
    for (var i = 0; i + lag < n; i++) {
      c += s[start + i] * s[start + i + lag];
    }
    c /= n - lag;
    if (c > best) {
      best = c;
      bestLag = lag;
    }
  }
  return bestLag == 0 ? '?' : '${(sr / bestLag).round()}';
}
