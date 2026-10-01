import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:rooster_core/rooster_core.dart';
import 'package:rooster_server/host_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class Client {
  final WebSocketChannel ch;
  final msgs = <Map<String, dynamic>>[];
  final snaps = <MatchSnap>[];
  final _dec = SnapshotDecoder();
  int bytesIn = 0;
  Client(this.ch) {
    ch.stream.listen((d) {
      if (d is String) {
        msgs.add(jsonDecode(d) as Map<String, dynamic>);
      } else {
        final b = d is Uint8List ? d : Uint8List.fromList(d as List<int>);
        bytesIn += b.length;
        final s = _dec.decode(b);
        if (s != null) snaps.add(s);
      }
    });
  }
  void send(Map<String, Object?> m) => ch.sink.add(jsonEncode(m));
  Iterable<Map<String, dynamic>> of(String t) => msgs.where((m) => m['t'] == t);
}

Future<void> waitFor(bool Function() cond, {int ms = 15000}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > ms) throw TimeoutException('timeout');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late HostServer server;
  late Directory web;

  setUp(() async {
    web = await Directory.systemTemp.createTemp('rr_web');
    await File('${web.path}/index.html').writeAsString('<html>rooster</html>');
    server = HostServer(RoomHost(settings: const LobbySettings(bots: 2, duration: 30)));
    await server.start(webDir: web.path, address: '127.0.0.1', port: 0);
  });

  tearDown(() async {
    await server.stop();
    await web.delete(recursive: true);
  });

  test('serves the web build with no-cache shell', () async {
    await File('${web.path}/main.dart.js').writeAsString('x' * 20000);
    final gz = HttpClient()..autoUncompress = false;
    final js = await (await gz.getUrl(Uri.parse('http://127.0.0.1:${server.port}/main.dart.js'))
          ..headers.set('accept-encoding', 'gzip'))
        .close();
    expect(js.headers.value('content-encoding'), 'gzip');
    final zipped = await js.fold<List<int>>([], (a, b) => a..addAll(b));
    expect(utf8.decode(gzip.decode(zipped)), 'x' * 20000);
    expect(zipped.length, lessThan(1000));
    expect(js.headers.value('cache-control'), 'no-cache'); // app code revalidates
    gz.close();
    final http = HttpClient();
    final req = await http.getUrl(Uri.parse('http://127.0.0.1:${server.port}/'));
    final res = await req.close();
    expect(res.statusCode, 200);
    expect(await res.transform(utf8.decoder).join(), contains('rooster'));
    expect(res.headers.value('cache-control'), 'no-cache');
    expect(res.headers.value('cross-origin-opener-policy'), 'same-origin');
    expect(res.headers.value('cross-origin-embedder-policy'), 'require-corp');
    final probe = await (await http.getUrl(Uri.parse('http://127.0.0.1:${server.port}/rr-host'))).close();
    expect(await probe.transform(utf8.decoder).join(), contains('"host":true'));
    http.close();
  });

  test('two LAN clients play a match over WebSocket', () async {
    final uri = Uri.parse('ws://127.0.0.1:${server.port}/ws');
    final a = Client(WebSocketChannel.connect(uri));
    final b = Client(WebSocketChannel.connect(uri));
    await a.ch.ready;
    await b.ch.ready;
    a.send({'t': 'hello', 'pid': 'aaaa', 'name': 'An'});
    await waitFor(() => a.of(Msg.welcome).isNotEmpty);
    b.send({'t': 'hello', 'pid': 'bbbb', 'name': 'Bình'});
    await waitFor(() => b.of(Msg.room).isNotEmpty);
    expect(RoomState.fromJson(b.of(Msg.room).last).players, hasLength(2));

    a.send({'t': 'start'});
    await waitFor(() => b.of(Msg.match).isNotEmpty, ms: 10000);
    final you = b.of(Msg.match).last['you'] as int;
    await waitFor(() => b.snaps.length > 60);

    // ~30 Hz binary snapshots, a few hundred bytes each.
    final snaps = b.snaps;
    final span = snaps.last.time - snaps.first.time;
    expect(snaps.length / span, inInclusiveRange(24, 36));
    expect(b.bytesIn / snaps.length, lessThan(300));

    // Input from client B moves its chicken.
    await waitFor(() => b.snaps.last.phase == MatchPhase.fighting);
    final x0 = b.snaps.last.fighter(you)!.x;
    for (var i = 0; i < 30; i++) {
      b.ch.sink.add(InputCodec.encode(-100, 0, false, false, 0));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    final x1 = b.snaps.last.fighter(you)!.x;
    expect(x1, lessThan(x0 - 0.5));

    // Garbage is ignored, connection survives.
    b.ch.sink.add('not json');
    b.ch.sink.add('x' * 10000);
    b.ch.sink.add(Uint8List.fromList(List.filled(200, 7)));
    final before = b.snaps.length;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(b.snaps.length, greaterThan(before));

    await a.ch.sink.close();
    await b.ch.sink.close();
  }, timeout: const Timeout(Duration(seconds: 40)));
}
