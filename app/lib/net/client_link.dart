import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:rooster_core/rooster_core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum LinkStatus { connecting, open, reconnecting, closed }

/// Client side of the host connection (GDD §10: client sends input,
/// receives authoritative state).
abstract class ClientLink {
  /// Control messages (JSON).
  Stream<Map<String, dynamic>> get messages;

  /// Hot-path binary frames (snapshots).
  Stream<Uint8List> get frames;

  ValueStreamLike<LinkStatus> get status;
  void send(Map<String, Object?> msg);

  /// Binary frames to the host (5-byte input).
  void sendBytes(Uint8List bytes);

  Future<void> close();
}

/// Minimal "current value + changes" holder (avoids an rxdart dependency).
class ValueStreamLike<T> {
  T _value;
  final _ctrl = StreamController<T>.broadcast();
  ValueStreamLike(this._value);
  T get value => _value;
  Stream<T> get changes => _ctrl.stream;
  void set(T v) {
    if (v == _value) return;
    _value = v;
    _ctrl.add(v);
  }

  void dispose() => _ctrl.close();
}

/// Offline play: runs the authoritative [RoomHost] in-process. Control
/// messages still go through a JSON round-trip and snapshots through the
/// binary codec, so offline and LAN behave the same.
class LocalLink implements ClientLink {
  final RoomHost host;
  late final _HostSide _side = _HostSide(this);
  final _inbox = StreamController<Map<String, dynamic>>.broadcast();
  final _frames = StreamController<Uint8List>.broadcast();
  @override
  final status = ValueStreamLike(LinkStatus.open);
  Timer? _timer;
  final _clock = Stopwatch()..start();
  int _last = 0;

  LocalLink({LobbySettings settings = const LobbySettings(bots: 3)})
    : host = RoomHost(local: true, snapshotEvery: 1, settings: settings) {
    _timer = Timer.periodic(const Duration(milliseconds: 8), (_) {
      final now = _clock.elapsedMicroseconds;
      host.advance((now - _last) / 1e6);
      _last = now;
    });
  }

  @override
  Stream<Map<String, dynamic>> get messages => _inbox.stream;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  void send(Map<String, Object?> msg) =>
      host.message(_side, jsonDecode(jsonEncode(msg)) as Map<String, dynamic>);

  @override
  void sendBytes(Uint8List bytes) =>
      host.messageBytes(_side, Uint8List.fromList(bytes));

  void _deliverBytes(Uint8List bytes) {
    if (_frames.isClosed) return;
    scheduleMicrotask(() {
      if (!_frames.isClosed) _frames.add(bytes);
    });
  }

  void _deliver(Map<String, Object?> msg) {
    if (_inbox.isClosed) return;
    final copy = jsonDecode(jsonEncode(msg)) as Map<String, dynamic>;
    // Deliver asynchronously like a socket would.
    scheduleMicrotask(() {
      if (!_inbox.isClosed) _inbox.add(copy);
    });
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    host.disconnect(_side);
    status.set(LinkStatus.closed);
    await _inbox.close();
    await _frames.close();
  }
}

class _HostSide implements HostLink {
  final LocalLink owner;
  _HostSide(this.owner);
  @override
  void send(Map<String, Object?> msg) => owner._deliver(msg);
  @override
  void sendBytes(Uint8List bytes) => owner._deliverBytes(bytes);
  @override
  void close() {}
}

/// LAN play over WebSocket with automatic reconnect (phones drop WiFi or
/// lock the screen). [onReconnect] re-sends the hello so the host reattaches
/// us to our chicken.
class WsLink implements ClientLink {
  final Uri uri;
  final void Function() onReconnect;
  final _inbox = StreamController<Map<String, dynamic>>.broadcast();
  final _frames = StreamController<Uint8List>.broadcast();
  @override
  final status = ValueStreamLike(LinkStatus.connecting);
  WebSocketChannel? _ch;
  bool _closing = false;
  int _attempt = 0;
  final List<String> _queued = []; // sent before the first open

  WsLink(this.uri, {required this.onReconnect}) {
    _connect();
  }

  @override
  Stream<Map<String, dynamic>> get messages => _inbox.stream;

  @override
  Stream<Uint8List> get frames => _frames.stream;

  Future<void> _connect() async {
    try {
      final ch = WebSocketChannel.connect(uri);
      await ch.ready.timeout(const Duration(seconds: 5));
      if (_closing) {
        await ch.sink.close();
        return;
      }
      _ch = ch;
      final wasReconnect = _attempt > 0;
      _attempt = 0;
      status.set(LinkStatus.open);
      if (wasReconnect) {
        _queued.clear();
        onReconnect();
      } else {
        _queued.forEach(ch.sink.add);
        _queued.clear();
      }
      ch.stream.listen(
        (data) {
          if (data is Uint8List) return _frames.add(data);
          if (data is ByteBuffer) return _frames.add(data.asUint8List());
          if (data is List<int>) return _frames.add(Uint8List.fromList(data));
          if (data is! String) return;
          try {
            final m = jsonDecode(data);
            if (m is Map<String, dynamic>) _inbox.add(m);
          } on FormatException {
            // ignore malformed frame
          }
        },
        onDone: _lost,
        onError: (_) => _lost(),
        cancelOnError: true,
      );
    } on Object {
      _lost();
    }
  }

  void _lost() {
    _ch = null;
    if (_closing) return;
    if (_attempt >= 8) {
      status.set(LinkStatus.closed);
      return;
    }
    _attempt++;
    status.set(LinkStatus.reconnecting);
    Future.delayed(Duration(milliseconds: 400 * _attempt), () {
      if (!_closing) _connect();
    });
  }

  @override
  void send(Map<String, Object?> msg) {
    final ch = _ch;
    if (ch == null) {
      if (status.value == LinkStatus.connecting && _queued.length < 16) {
        _queued.add(jsonEncode(msg));
      }
      return;
    }
    ch.sink.add(jsonEncode(msg));
  }

  @override
  void sendBytes(Uint8List bytes) => _ch?.sink.add(bytes);

  @override
  Future<void> close() async {
    _closing = true;
    status.set(LinkStatus.closed);
    await _ch?.sink.close();
    await _inbox.close();
    await _frames.close();
  }
}
