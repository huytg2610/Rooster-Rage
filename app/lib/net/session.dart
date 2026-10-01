import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rooster_core/rooster_core.dart';

import '../app/profile.dart';
import 'client_link.dart';
import 'snapshot_buffer.dart';

class RevealEntry {
  final int fighterId;
  final String pid;
  final String name;
  final int slot;
  final bool bot;
  final ChickenInstance chicken;

  const RevealEntry(
    this.fighterId,
    this.pid,
    this.name,
    this.slot,
    this.bot,
    this.chicken,
  );

  static RevealEntry fromJson(Map<String, dynamic> j) => RevealEntry(
    j['fid'] as int,
    j['pid'] as String,
    j['name'] as String,
    j['slot'] as int,
    j['bot'] as bool,
    ChickenInstance.fromJson(j),
  );
}

class MatchInfo {
  final ArenaDef arena;
  final int duration;
  final Map<int, FighterInfo> fighters;
  final int? you;
  final bool survival; // no respawn: last chicken standing wins

  const MatchInfo(
    this.arena,
    this.duration,
    this.fighters,
    this.you, {
    this.survival = false,
  });
}

/// One connection to a room (offline or LAN). UI listens for phase/lobby
/// changes; the game pulls interpolated frames from [buffer] every frame.
class Session extends ChangeNotifier {
  final ClientLink link;
  final bool isLocal;
  Profile profile;
  final void Function(Profile)? onProfileChanged;

  RoomState? room;
  String? error;

  /// Set when the owner closed the LAN room (we were kicked).
  String? closedReason;

  /// True if this client closed the room (owner) — no "kicked" notice.
  bool closedByMe = false;

  /// Round-trip time to the host (ms), from ping/pong.
  double? rttMs;
  Timer? _pingTimer;
  final _pingClock = Stopwatch()..start();
  List<RevealEntry> reveal = const [];
  double revealDuration = 0;
  MatchInfo? match;
  List<FighterResult>? results;
  final SnapshotBuffer buffer;
  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<Uint8List>? _framesSub;
  final _decoder = SnapshotDecoder();
  StreamSubscription<LinkStatus>? _statusSub;

  Session({
    required this.link,
    required this.profile,
    required this.isLocal,
    this.onProfileChanged,
  }) : buffer = SnapshotBuffer(minDelay: isLocal ? 1 / 40 : 0.05) {
    _sub = link.messages.listen(_onMessage);
    // Hot path: binary snapshots straight into the jitter buffer (no rebuilds).
    _framesSub = link.frames.listen((bytes) {
      final snap = _decoder.decode(bytes);
      if (snap != null) buffer.add(snap);
    });
    _statusSub = link.status.changes.listen((_) => notifyListeners());
    hello();
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      link.send({'t': Msg.ping, 'c': _pingClock.elapsedMilliseconds});
    });
  }

  LinkStatus get linkStatus => link.status.value;
  RoomPhase get phase => room?.phase ?? RoomPhase.lobby;
  bool get isOwner => room?.ownerPid == profile.pid;
  String get myPid => profile.pid;

  void hello() => link.send({
    't': Msg.hello,
    'pid': profile.pid,
    'name': profile.name,
    'games': profile.gamesPlayed,
    'v': protocolVersion,
  });

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case Msg.welcome:
        error = null;
      case Msg.room:
        final prev = room?.phase;
        room = RoomState.fromJson(m);
        if (room!.phase == RoomPhase.lobby && prev != RoomPhase.lobby) {
          results = null;
          match = null;
        }
      case Msg.reveal:
        reveal = [
          for (final e in (m['entries'] as List).cast<Map>())
            RevealEntry.fromJson(e.cast<String, dynamic>()),
        ];
        revealDuration = (m['dur'] as num).toDouble();
        results = null;
      case Msg.match:
        final infos = <int, FighterInfo>{
          for (final f in (m['fighters'] as List).cast<Map>())
            (f['id'] as int): FighterInfo.fromJson(f.cast<String, dynamic>()),
        };
        final you = m['you'] as int?;
        match = MatchInfo(
          Arenas.byId(m['arena'] as String),
          m['dur'] as int,
          infos,
          you,
          survival: m['surv'] as bool? ?? false,
        );
        buffer.reset(infos, you);
        _decoder.reset();
        results = null;
      case Msg.results:
        results = [
          for (final r in (m['results'] as List).cast<Map>())
            FighterResult.fromJson(r.cast<String, dynamic>()),
        ];
        if (match?.you != null) {
          profile = profile.copyWith(gamesPlayed: profile.gamesPlayed + 1);
          onProfileChanged?.call(profile);
        }
      case Msg.pong:
        final c = m['c'];
        if (c is num) {
          final rtt = (_pingClock.elapsedMilliseconds - c).toDouble();
          rttMs = rttMs == null ? rtt : rttMs! * 0.7 + rtt * 0.3;
        }
        return; // no rebuild needed
      case Msg.closed:
        closedReason = m['msg'] as String? ?? 'Phòng đã đóng.';
        _pingTimer?.cancel();
        link.close(); // don't auto-reconnect into a fresh room
      case Msg.error:
        error = m['msg'] as String?;
      default:
        return;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ commands

  void updateSettings(LobbySettings s) =>
      link.send({'t': Msg.settings, ...s.toJson()});
  void start() => link.send({'t': Msg.start});
  void pick(String classId, Variant variant) =>
      link.send({'t': Msg.pick, 'class': classId, 'variant': variant.name});
  void rematch() => link.send({'t': Msg.rematch});
  void backToLobby() => link.send({'t': Msg.toLobby});

  /// Owner only (LAN): close the room and kick everyone.
  void closeRoom() {
    closedByMe = true;
    link.send({'t': Msg.close});
  }

  int _lastMx = 999, _lastMy = 999;
  bool _lastHeavy = false;
  bool _lastBlock = false;
  final _sendClock = Stopwatch()..start();

  /// Sends a 5-byte binary input frame when something changes, on
  /// presses, or as a 1 s keepalive. The stick is quantized to 5% steps so
  /// finger jitter doesn't flood the host (TCP keeps the last state anyway).
  void sendInput(
    double mx,
    double my,
    bool heavy,
    int pressed, {
    bool block = false,
  }) {
    if (phase != RoomPhase.match || match?.you == null) return;
    int q(double v) => ((v * 20).round() * 5).clamp(-100, 100);
    final ix = q(mx), iy = q(my);
    final changed =
        ix != _lastMx ||
        iy != _lastMy ||
        heavy != _lastHeavy ||
        block != _lastBlock;
    if (!changed && pressed == 0 && _sendClock.elapsedMilliseconds < 1000) {
      return;
    }
    // Rate-limit pure stick motion to ~30 Hz; presses/holds go out at once.
    if (changed &&
        pressed == 0 &&
        heavy == _lastHeavy &&
        block == _lastBlock &&
        _sendClock.elapsedMilliseconds < 33) {
      return;
    }
    _lastMx = ix;
    _lastMy = iy;
    _lastHeavy = heavy;
    _lastBlock = block;
    _sendClock.reset();
    link.sendBytes(InputCodec.encode(ix, iy, heavy, block, pressed));
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _sub?.cancel();
    _framesSub?.cancel();
    _statusSub?.cancel();
    link.close();
    super.dispose();
  }
}
