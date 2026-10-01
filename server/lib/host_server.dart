import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:rooster_core/rooster_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// LAN host: serves the Flutter web build and runs the authoritative room
/// over WebSocket at `/ws`.
class HostServer {
  static const maxMessageBytes = 4096;
  static const maxMessagesPerSecond = 120;

  final RoomHost room;
  HttpServer? _http;
  Timer? _ticker;
  final _clock = Stopwatch();

  HostServer(this.room);

  int get port => _http?.port ?? 0;

  Future<void> start({
    required String webDir,
    String address = '0.0.0.0',
    int port = 8080,
  }) async {
    final ws = webSocketHandler((WebSocketChannel ch, String? _) => _WsLink(ch, room).listen(),
        pingInterval: const Duration(seconds: 5));

    Handler staticFiles;
    if (Directory(webDir).existsSync()) {
      staticFiles = createStaticHandler(webDir, defaultDocument: 'index.html');
    } else {
      staticFiles = (_) => Response.notFound(
          'Web build not found at $webDir.\nRun: cd app && flutter build web\n');
    }

    final handler = const Pipeline()
        .addMiddleware(_noCacheShell())
        .addMiddleware(_gzipStatic())
        .addHandler((Request r) => switch (r.url.path) {
              'ws' => ws(r),
              // Lets the web client detect it was served by a LAN host.
              'rr-host' => Response.ok('{"host":true,"v":$protocolVersion}',
                  headers: {'content-type': 'application/json', 'cache-control': 'no-cache'}),
              _ => staticFiles(r),
            });

    _http = await shelf_io.serve(handler, address, port);
    _clock.start();
    var last = _clock.elapsedMicroseconds;
    _ticker = Timer.periodic(const Duration(milliseconds: 4), (_) {
      final now = _clock.elapsedMicroseconds;
      room.advance((now - last) / 1e6);
      last = now;
    });
  }

  Future<void> stop() async {
    _ticker?.cancel();
    await _http?.close(force: true);
  }

  // Compressed static files, keyed by path; invalidated by Last-Modified.
  final _gzCache = <String, (String, List<int>)>{};

  /// gzip for the web bundle (~6 MB of wasm/js → ~2.4 MB on the wire).
  /// shelf_static sets Content-Length, which disables dart:io autoCompress,
  /// so compress here once per file and serve from memory.
  Middleware _gzipStatic() => (inner) => (req) async {
        final res = await inner(req);
        if (req.method != 'GET' || res.statusCode != 200) return res;
        if (!(req.headers['accept-encoding'] ?? '').contains('gzip')) return res;
        if (res.headers.containsKey('content-encoding')) return res;
        final type = res.headers['content-type'] ?? '';
        const compressible = ['javascript', 'wasm', 'json', 'html', 'css', 'font', 'text/'];
        if (!compressible.any(type.contains)) return res;
        final key = req.url.path, tag = res.headers['last-modified'] ?? '';
        var hit = _gzCache[key];
        if (hit == null || hit.$1 != tag) {
          final raw = <int>[];
          await for (final chunk in res.read()) {
            raw.addAll(chunk);
          }
          hit = (tag, gzip.encode(raw));
          _gzCache[key] = hit;
        } else {
          await res.read().drain<void>();
        }
        return res.change(body: hit.$2, headers: {
          'content-encoding': 'gzip',
          'content-length': '${hit.$2.length}',
          'vary': 'accept-encoding',
        });
      };

  /// * App code revalidates on every load (so a rebuilt host is picked up);
  ///   engine files and fonts are cached for a day.
  /// * COOP/COEP make the page cross-origin isolated. Only the opt-in
  ///   multi-threaded skwasm renderer (`?renderer=skwasm-mt`) needs it; the
  ///   default CanvasKit renderer works either way.
  static Middleware _noCacheShell() => (inner) => (req) async {
        final res = await inner(req);
        final p = req.url.path;
        final headers = <String, String>{
          'cross-origin-opener-policy': 'same-origin',
          'cross-origin-embedder-policy': 'require-corp',
        };
        if (p.startsWith('canvaskit/') || p.startsWith('assets/fonts/')) {
          // Engine + fonts only change with a Flutter upgrade.
          headers['cache-control'] = 'public, max-age=86400';
        } else {
          // App code (main.dart.wasm/js, index, bootstrap) must revalidate so
          // phones pick up a new build after the host restarts (304 if same).
          headers['cache-control'] = 'no-cache';
        }
        return res.change(headers: headers);
      };
}

class _WsLink implements HostLink {
  final WebSocketChannel ch;
  final RoomHost room;
  int _windowStart = 0;
  int _windowCount = 0;

  // Broadcasts send the same map to every link — encode it once.
  static Map<String, Object?>? _lastMsg;
  static String? _lastJson;

  _WsLink(this.ch, this.room);

  void listen() {
    ch.stream.listen(
      (data) {
        if (!_allow()) return;
        if (data is List<int>) {
          // Binary hot path: 5-byte input frames.
          if (data.length <= 16) {
            room.messageBytes(this, data is Uint8List ? data : Uint8List.fromList(data));
          }
          return;
        }
        if (data is! String || data.length > HostServer.maxMessageBytes) return;
        Object? msg;
        try {
          msg = jsonDecode(data);
        } on FormatException {
          return;
        }
        if (msg is Map<String, dynamic>) room.message(this, msg);
      },
      onDone: () => room.disconnect(this),
      onError: (_) => room.disconnect(this),
      cancelOnError: true,
    );
  }

  bool _allow() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _windowStart >= 1000) {
      _windowStart = now;
      _windowCount = 0;
    }
    return ++_windowCount <= HostServer.maxMessagesPerSecond;
  }

  @override
  void send(Map<String, Object?> msg) {
    if (!identical(msg, _lastMsg)) {
      _lastMsg = msg;
      _lastJson = jsonEncode(msg);
    }
    ch.sink.add(_lastJson!);
  }

  @override
  void sendBytes(Uint8List bytes) => ch.sink.add(bytes);

  @override
  void close() => ch.sink.close();
}
