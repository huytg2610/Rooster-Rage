/// Host-authoritative room (GDD §10): lobby → (pick) → reveal → match →
/// results. Transport-agnostic — the LAN server wires WebSockets to it, the
/// offline mode wires an in-memory link. Owns the only [MatchSimulation].
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../data/arenas.dart';
import '../data/chicken_classes.dart';
import '../data/tuning.dart';
import '../data/variants.dart';
import '../math/rng.dart';
import '../random/chicken_generator.dart';
import '../sim/fighter.dart';
import '../sim/match_sim.dart';
import 'protocol.dart';
import 'snapshot_codec.dart';

/// One client connection as seen by the host.
abstract class HostLink {
  /// Control messages (lobby, reveal, results…) as JSON objects.
  void send(Map<String, Object?> msg);

  /// Hot-path binary frames (snapshots). Implementations must not mutate.
  void sendBytes(Uint8List bytes);

  void close();
}

class _Player {
  HostLink? link;
  final String pid;
  String name;
  int slot;
  int games;
  String? pickClass;
  Variant? pickVariant;
  int? fighterId;

  _Player(this.link, this.pid, this.name, this.slot, this.games);

  bool get connected => link != null;
}

class RoomHost {
  static const maxFighters = 8;
  static const pickTime = 20.0;
  static const revealTime = 7.0;
  static const revealTimeCompetitive = 4.0;
  static const endLinger = 2.5;
  static const resultsTimeout = 60.0;

  final bool local;
  final int snapshotEvery;
  List<String> joinUrls;

  RoomPhase phase = RoomPhase.lobby;
  LobbySettings settings;
  final List<_Player> _players = [];
  String? _ownerPid;

  MatchSimulation? sim;
  SnapshotEncoder? _encoder;
  List<FighterInfo> _infos = const [];
  List<Map<String, Object?>> _reveal = const [];
  double _timer = 0;
  double _acc = 0;
  final Rng _rng;
  final Map<String, List<String>> _history = {};

  RoomHost({
    this.local = false,
    this.snapshotEvery = 2,
    this.joinUrls = const [],
    LobbySettings? settings,
    int? seed,
  })  : settings = settings ?? const LobbySettings(),
        _rng = Rng(seed ?? DateTime.now().microsecondsSinceEpoch);

  int get humanCount => _players.length;

  // ---------------------------------------------------------------- links

  void disconnect(HostLink link) {
    final p = _byLink(link);
    if (p == null) return;
    p.link = null;
    if (phase == RoomPhase.lobby) _players.remove(p);
    final fid = p.fighterId;
    if (fid != null && phase == RoomPhase.match) sim?.setBot(fid, true, 1);
    if (_ownerPid == p.pid) {
      final next = _players.where((q) => q.connected);
      _ownerPid = next.isEmpty ? null : next.first.pid;
    }
    _broadcastRoom();
  }

  /// Handles one client message. Malformed input is dropped (validated at
  /// this system boundary so a bad client can't crash the host).
  void message(HostLink link, Map<String, dynamic> msg) {
    try {
      _message(link, msg);
    } on Object {
      // Drop malformed message.
    }
  }

  void _message(HostLink link, Map<String, dynamic> msg) {
    final type = msg['t'];
    if (type == Msg.hello) return _hello(link, msg);
    if (type == Msg.ping) {
      final c = msg['c'];
      if (c is num) link.send({'t': Msg.pong, 'c': c});
      return;
    }
    final p = _byLink(link);
    if (p == null) return;
    final owner = p.pid == _ownerPid;
    switch (type) {
      case Msg.settings when owner && phase == RoomPhase.lobby:
        settings = LobbySettings.fromJson({...settings.toJson(), ...msg});
        settings = settings.copyWith(
          bots: settings.bots.clamp(0, maxFighters - 1),
          duration: settings.duration.clamp(30, 600),
          botLevel: settings.botLevel.clamp(0, 2),
        );
        _broadcastRoom();
      case Msg.start when owner && phase == RoomPhase.lobby:
        _begin();
      case Msg.pick when phase == RoomPhase.picking:
        final cls = msg['class'] as String?;
        // One player per chicken: a class someone else holds is locked.
        final taken = _players.any((q) => !identical(q, p) && q.connected && q.pickClass == cls);
        if (cls != null && !taken && ChickenClasses.all.any((c) => c.id == cls)) {
          p.pickClass = cls;
        }
        final v = msg['variant'] as String?;
        if (v != null) p.pickVariant = Variant.values.asNameMap()[v];
        _broadcastRoom();
      case Msg.rematch when owner && phase == RoomPhase.results:
        _begin();
      case Msg.toLobby when owner && phase == RoomPhase.results:
        _toLobby();
      case Msg.close when owner && !local:
        closeRoom();
    }
  }

  /// Binary frames from a client (currently only 5-byte input).
  void messageBytes(HostLink link, Uint8List data) {
    final input = InputCodec.decode(data);
    if (input == null || phase != RoomPhase.match) return;
    final fid = _byLink(link)?.fighterId;
    if (fid == null) return;
    sim?.setInput(fid, input.mx, input.my, input.heavy, input.pressed, block: input.block);
  }

  void _hello(HostLink link, Map<String, dynamic> msg) {
    final pid = (msg['pid'] as String?)?.trim() ?? '';
    var name = (msg['name'] as String?)?.trim() ?? '';
    if (pid.isEmpty || pid.length > 64) {
      link.send({'t': Msg.error, 'msg': 'ID người chơi không hợp lệ'});
      return;
    }
    if (name.isEmpty) name = 'Gà ${pid.substring(0, math.min(4, pid.length))}';
    if (name.length > 16) name = name.substring(0, 16);
    final games = (msg['games'] as int? ?? 0).clamp(0, 100000);

    var p = _byPid(pid);
    if (p != null) {
      p.link?.close();
      p.link = link;
      p.name = name;
      final fid = p.fighterId;
      if (fid != null && phase == RoomPhase.match) sim?.setBot(fid, false);
    } else {
      if (_players.length >= maxFighters) {
        link.send({'t': Msg.error, 'msg': 'Phòng đã đủ $maxFighters người'});
        return;
      }
      p = _Player(link, pid, name, _freeSlot(), games);
      _players.add(p);
    }
    _ownerPid ??= pid;
    link.send({'t': Msg.welcome, 'pid': pid, 'local': local, 'v': protocolVersion});
    _broadcastRoom();
    // Late joiners / reconnects catch up with the running phase.
    if (phase == RoomPhase.reveal || phase == RoomPhase.picking) {
      if (_reveal.isNotEmpty) link.send(_revealMsg());
    }
    if (phase == RoomPhase.match || phase == RoomPhase.results) {
      link.send(_matchMsg(p));
      _encoder?.forceKeyframe(); // late joiner needs a full snapshot
    }
    if (phase == RoomPhase.results) link.send(_resultsMsg());
  }

  // ---------------------------------------------------------------- flow

  void _begin() {
    for (final p in _players) {
      p.pickClass = null;
      p.pickVariant = null;
      p.fighterId = null;
    }
    _players.removeWhere((p) => !p.connected);
    if (_players.isEmpty) return _toLobby();
    if (settings.mode == GameMode.competitive) {
      phase = RoomPhase.picking;
      _timer = pickTime;
      _reveal = const [];
      _broadcastRoom();
    } else {
      _toReveal();
    }
  }

  /// Builds the roster (humans + bots) and assigns chickens.
  void _toReveal() {
    final humans = _players.where((p) => p.connected).toList();
    final botCount = math.min(settings.bots, maxFighters - humans.length);
    final usedSlots = humans.map((p) => p.slot).toSet();
    final botSlots = [
      for (var s = 0; s < maxFighters; s++)
        if (!usedSlots.contains(s)) s
    ];

    final profiles = <PlayerProfile>[
      for (final p in humans)
        PlayerProfile(
            playerId: p.pid, gamesPlayed: p.games, recentClasses: _history[p.pid] ?? const []),
      for (var i = 0; i < botCount; i++)
        PlayerProfile(playerId: 'bot-$i', gamesPlayed: 99),
    ];
    final rolled = ChickenGenerator.generate(profiles, _rng.nextU32(), fixedClasses: [
      for (final p in humans) p.pickClass,
      for (var i = 0; i < botCount; i++) null,
    ]);

    final entries = <Map<String, Object?>>[];
    for (var i = 0; i < profiles.length; i++) {
      final isBot = i >= humans.length;
      final human = isBot ? null : humans[i];
      var inst = rolled[i];
      if (human?.pickVariant != null) {
        inst = ChickenInstance(inst.classId, human!.pickVariant!, inst.rarity);
      }
      final fid = i + 1;
      human?.fighterId = fid;
      final botIdx = i - humans.length;
      entries.add({
        'fid': fid,
        'pid': profiles[i].playerId,
        'name': isBot ? botNames[botIdx % botNames.length] : human!.name,
        'slot': isBot ? botSlots[botIdx] : human!.slot,
        'bot': isBot,
        ...inst.toJson(),
      });
    }
    _reveal = entries;
    phase = RoomPhase.reveal;
    _timer = settings.mode == GameMode.competitive ? revealTimeCompetitive : revealTime;
    _broadcastRoom();
    _broadcast(_revealMsg());
  }

  void _startMatch() {
    final setups = [
      for (final e in _reveal)
        FighterSetup(
          id: e['fid'] as int,
          playerId: e['pid'] as String,
          name: e['name'] as String,
          slot: e['slot'] as int,
          isBot: e['bot'] as bool,
          botLevel: settings.botLevel,
          classId: e['class'] as String,
          variant: Variant.values.byName(e['variant'] as String),
          rarity: Rarity.values.byName(e['rarity'] as String),
        ),
    ];
    final s = MatchSimulation(
      MatchConfig(
        arenaId: Arenas.byId(settings.arenaId).id,
        duration: settings.duration.toDouble(),
        seed: _rng.nextU32(),
        survival: settings.survival,
      ),
      setups,
    );
    // Humans who left during the reveal are driven by AI.
    for (final p in _players) {
      final fid = p.fighterId;
      if (fid != null && !p.connected) s.setBot(fid, true, 1);
    }
    sim = s;
    _encoder = SnapshotEncoder();
    _infos = [for (final f in s.fighters) FighterInfo.of(f)];
    _acc = 0;
    _timer = 0;
    phase = RoomPhase.match;
    _broadcastRoom();
    for (final p in _players) {
      p.link?.send(_matchMsg(p));
    }
  }

  void _toResults() {
    phase = RoomPhase.results;
    _timer = resultsTimeout;
    final s = sim;
    if (s != null) {
      for (final p in _players) {
        final f = p.fighterId == null ? null : s.byId(p.fighterId!);
        if (f == null) continue;
        p.games++;
        final h = _history.putIfAbsent(p.pid, () => []);
        h.insert(0, f.setup.classId);
        if (h.length > 5) h.removeLast();
      }
    }
    _broadcastRoom();
    _broadcast(_resultsMsg());
  }

  /// Owner closes the LAN room: everyone is told why and disconnected, and
  /// the host resets to an empty lobby (next joiner owns a fresh room).
  void closeRoom([String reason = 'Chủ phòng đã đóng phòng.']) {
    final links = [
      for (final p in _players)
        if (p.link != null) p.link!
    ];
    _players.clear();
    _ownerPid = null;
    phase = RoomPhase.lobby;
    sim = null;
    _reveal = const [];
    _infos = const [];
    _history.clear();
    _timer = 0;
    settings = const LobbySettings();
    for (final l in links) {
      l.send({'t': Msg.closed, 'msg': reason});
      l.close();
    }
  }

  void _toLobby() {
    phase = RoomPhase.lobby;
    sim = null;
    _reveal = const [];
    _players.removeWhere((p) => !p.connected);
    for (final p in _players) {
      p.fighterId = null;
    }
    _broadcastRoom();
  }

  /// Drive the room clock. Call often (server timer / client frame loop).
  void advance(double dt) {
    switch (phase) {
      case RoomPhase.lobby:
        return;
      case RoomPhase.picking:
        _timer -= dt;
        final humans = _players.where((p) => p.connected);
        if (_timer <= 0 || humans.every((p) => p.pickClass != null)) _toReveal();
      case RoomPhase.reveal:
        _timer -= dt;
        if (_timer <= 0) _startMatch();
      case RoomPhase.match:
        final s = sim!;
        _acc = math.min(_acc + dt, 0.25);
        while (_acc >= Tuning.dt) {
          _acc -= Tuning.dt;
          s.step();
          if (s.tick % snapshotEvery == 0) {
            final bytes = _encoder!.encode(s, s.drainEvents());
            for (final p in _players) {
              p.link?.sendBytes(bytes);
            }
          }
        }
        if (s.phase == MatchPhase.ended) {
          _timer += dt;
          if (_timer >= endLinger) _toResults();
        }
      case RoomPhase.results:
        _timer -= dt;
        if (_timer <= 0) _toLobby();
    }
  }

  // ---------------------------------------------------------------- messages

  Map<String, Object?> _revealMsg() => {
        't': Msg.reveal,
        'entries': _reveal,
        'dur': _timer,
      };

  Map<String, Object?> _matchMsg(_Player p) => {
        't': Msg.match,
        'arena': sim?.arena.id ?? settings.arenaId,
        'dur': settings.duration,
        'surv': sim?.config.survival ?? settings.survival,
        'fighters': [for (final i in _infos) i.toJson()],
        'you': p.fighterId,
      };

  Map<String, Object?> _resultsMsg() => {
        't': Msg.results,
        'results': [for (final r in sim?.results() ?? const []) r.toJson()],
      };

  RoomState get state => RoomState(
        phase: phase,
        ownerPid: _ownerPid,
        settings: settings,
        players: [
          for (final p in _players)
            LobbyPlayerDto(
              pid: p.pid,
              name: p.name,
              slot: p.slot,
              connected: p.connected,
              picked: p.pickClass,
              pickedVariant: p.pickVariant?.name,
            )
        ],
        joinUrls: joinUrls,
        timer: _timer,
        local: local,
      );

  void _broadcastRoom() => _broadcast(state.toJson());

  void _broadcast(Map<String, Object?> msg) {
    for (final p in _players) {
      p.link?.send(msg);
    }
  }

  // ---------------------------------------------------------------- helpers

  _Player? _byLink(HostLink l) {
    for (final p in _players) {
      if (identical(p.link, l)) return p;
    }
    return null;
  }

  _Player? _byPid(String pid) {
    for (final p in _players) {
      if (p.pid == pid) return p;
    }
    return null;
  }

  int _freeSlot() {
    final used = _players.map((p) => p.slot).toSet();
    for (var s = 0; s < maxFighters; s++) {
      if (!used.contains(s)) return s;
    }
    return 0;
  }

}
