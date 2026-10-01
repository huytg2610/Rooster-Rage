// LAN host load test: K WebSocket clients send 60 Hz input, we measure
// snapshot arrival jitter, payload size and host tick rate.
//   dart run tool/load_test.dart [clients] [seconds]
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rooster_core/rooster_core.dart';
import 'package:rooster_server/host_server.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<void> main(List<String> args) async {
  final clients = args.isNotEmpty ? int.parse(args[0]) : 4;
  final seconds = args.length > 1 ? int.parse(args[1]) : 8;
  final web = await Directory.systemTemp.createTemp('rr_load');
  final server = HostServer(RoomHost(
      settings: LobbySettings(bots: math.max(0, 8 - clients), duration: 120)));
  await server.start(webDir: web.path, address: '127.0.0.1', port: 0);
  final uri = Uri.parse('ws://127.0.0.1:${server.port}/ws');

  final arrivals = List.generate(clients, (_) => <int>[]);
  final ticks = List.generate(clients, (_) => <int>[]);
  var bytes = 0, snaps = 0;
  final chans = <WebSocketChannel>[];
  final clock = Stopwatch()..start();
  for (var i = 0; i < clients; i++) {
    final ch = WebSocketChannel.connect(uri);
    await ch.ready;
    chans.add(ch);
    final dec = SnapshotDecoder();
    ch.stream.listen((d) {
      if (d is String) return;
      final b = d is Uint8List ? d : Uint8List.fromList(d as List<int>);
      final snap = dec.decode(b);
      if (snap == null) return;
      arrivals[i].add(clock.elapsedMicroseconds);
      ticks[i].add(snap.tick);
      bytes += b.length;
      snaps++;
    });
    ch.sink.add(jsonEncode({'t': 'hello', 'pid': 'load$i', 'name': 'L$i'}));
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  chans.first.sink.add(jsonEncode({'t': 'start'}));
  // Measure during the fight: reveal + countdown first.
  await Future<void>.delayed(Duration(
      milliseconds: ((RoomHost.revealTime + Tuning.countdown + 0.5) * 1000).round()));
  for (final a in arrivals) {
    a.clear();
  }
  for (final t in ticks) {
    t.clear();
  }
  bytes = 0;
  snaps = 0;

  final rng = math.Random(1);
  final inputTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
    for (final ch in chans) {
      ch.sink.add(InputCodec.encode(rng.nextInt(201) - 100, rng.nextInt(201) - 100, false,
          false, rng.nextInt(20) == 0 ? Btn.light : 0));
    }
  });
  await Future<void>.delayed(Duration(seconds: seconds));
  inputTimer.cancel();

  final gaps = <double>[];
  for (final a in arrivals) {
    for (var i = 1; i < a.length; i++) {
      gaps.add((a[i] - a[i - 1]) / 1000);
    }
  }
  gaps.sort();
  double pct(double p) => gaps.isEmpty ? 0 : gaps[(gaps.length * p).floor().clamp(0, gaps.length - 1)];
  final t0 = ticks.first;
  final tickRate = t0.length < 2 ? 0 : (t0.last - t0.first) / seconds;
  print('clients=$clients  snapshots/client/s=${(snaps / clients / seconds).toStringAsFixed(1)}'
      '  host ticks/s=${tickRate.toStringAsFixed(1)}  avg snapshot=${snaps == 0 ? 0 : bytes ~/ snaps} B'
      '  downlink/client=${(bytes / clients / seconds / 1024).toStringAsFixed(1)} KB/s');
  print('arrival gap ms: p50=${pct(0.5).toStringAsFixed(1)} p95=${pct(0.95).toStringAsFixed(1)}'
      ' p99=${pct(0.99).toStringAsFixed(1)} max=${gaps.isEmpty ? 0 : gaps.last.toStringAsFixed(1)}');
  for (final ch in chans) {
    await ch.sink.close();
  }
  await server.stop();
  await web.delete(recursive: true);
  exit(0);
}
