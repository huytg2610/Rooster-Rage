import 'dart:convert';
import 'dart:typed_data';

import 'package:rooster_core/rooster_core.dart';
import 'package:test/test.dart';

class FakeLink implements HostLink {
  final List<Map<String, dynamic>> inbox = [];
  final List<Uint8List> frames = [];
  final decoder = SnapshotDecoder();
  final List<MatchSnap> snaps = [];
  bool closed = false;

  @override
  void sendBytes(Uint8List bytes) {
    frames.add(bytes);
    final s = decoder.decode(bytes);
    if (s != null) snaps.add(s);
  }

  @override
  void send(Map<String, Object?> msg) =>
      inbox.add(jsonDecode(jsonEncode(msg)) as Map<String, dynamic>);

  @override
  void close() => closed = true;

  Iterable<Map<String, dynamic>> of(String t) => inbox.where((m) => m['t'] == t);
  Map<String, dynamic> last(String t) => of(t).last;
}

void run(RoomHost host, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    host.advance(1 / 60);
  }
}

void main() {
  test('first player owns the room; others cannot start', () {
    final host = RoomHost(seed: 1);
    final a = FakeLink(), b = FakeLink();
    host.message(a, {'t': 'hello', 'pid': 'aaa', 'name': 'An'});
    host.message(b, {'t': 'hello', 'pid': 'bbb', 'name': 'Bình'});
    final room = RoomState.fromJson(b.last(Msg.room));
    expect(room.ownerPid, 'aaa');
    expect(room.players.map((p) => p.slot), [0, 1]);
    host.message(b, {'t': 'start'});
    expect(host.phase, RoomPhase.lobby);
  });

  test('party flow: lobby → reveal → match (snapshots, input) → results → rematch', () {
    final host = RoomHost(seed: 2, settings: const LobbySettings(duration: 30, bots: 2));
    final a = FakeLink(), b = FakeLink();
    host.message(a, {'t': 'hello', 'pid': 'aaa', 'name': 'An'});
    host.message(b, {'t': 'hello', 'pid': 'bbb', 'name': 'Bình'});
    host.message(a, {'t': 'start'});
    expect(host.phase, RoomPhase.reveal);
    final reveal = b.last(Msg.reveal)['entries'] as List;
    expect(reveal, hasLength(4));

    run(host, RoomHost.revealTime + 0.1);
    expect(host.phase, RoomPhase.match);
    final match = b.last(Msg.match);
    expect(match['you'], isNotNull);
    expect((match['fighters'] as List), hasLength(4));

    // Move right for a second after the countdown.
    run(host, Tuning.countdown + 0.1);
    final you = match['you'] as int;
    final before = b.snaps.last.fighter(you)!;
    for (var i = 0; i < 30; i++) {
      host.messageBytes(b, InputCodec.encode(100, 0, false, false, 0));
      run(host, 1 / 60);
    }
    final after = b.snaps.last.fighter(you)!;
    expect(after.x, greaterThan(before.x));
    expect(b.snaps.length, greaterThan(100));
    // Mostly deltas after the first keyframe.
    expect(b.frames.first.first, Wire.keyframe);
    expect(b.frames.where((f) => f.first == Wire.delta).length, greaterThan(90));

    run(host, 30 + RoomHost.endLinger + 0.5);
    expect(host.phase, RoomPhase.results);
    expect((a.last(Msg.results)['results'] as List), hasLength(4));

    host.message(a, {'t': 'rematch'});
    expect(host.phase, RoomPhase.reveal);
  });

  test('disconnect mid-match hands the chicken to a bot; reconnect restores it', () {
    final host = RoomHost(seed: 3, settings: const LobbySettings(bots: 1));
    final a = FakeLink(), b = FakeLink();
    host.message(a, {'t': 'hello', 'pid': 'aaa', 'name': 'An'});
    host.message(b, {'t': 'hello', 'pid': 'bbb', 'name': 'Bình'});
    host.message(a, {'t': 'start'});
    run(host, RoomHost.revealTime + 0.1);
    final fid = b.last(Msg.match)['you'] as int;
    host.disconnect(b);
    expect(host.sim!.brains.containsKey(fid), isTrue);
    final b2 = FakeLink();
    host.message(b2, {'t': 'hello', 'pid': 'bbb', 'name': 'Bình'});
    expect(host.sim!.brains.containsKey(fid), isFalse);
    expect(b2.last(Msg.match)['you'], fid);
  });

  test('competitive: picks are honored', () {
    final host = RoomHost(
        seed: 4, settings: const LobbySettings(mode: GameMode.competitive, bots: 0));
    final a = FakeLink();
    host.message(a, {'t': 'hello', 'pid': 'aaa', 'name': 'An'});
    host.message(a, {'t': 'start'});
    expect(host.phase, RoomPhase.picking);
    host.message(a, {'t': 'pick', 'class': 'troll', 'variant': 'thunder'});
    run(host, 0.1);
    expect(host.phase, RoomPhase.reveal);
    final e = (a.last(Msg.reveal)['entries'] as List).single as Map;
    expect(e['class'], 'troll');
    expect(e['variant'], 'thunder');
  });

  test('malformed messages are ignored and room caps at 8', () {
    final host = RoomHost(seed: 5);
    final links = [for (var i = 0; i < 9; i++) FakeLink()];
    for (var i = 0; i < 9; i++) {
      host.message(links[i], {'t': 'hello', 'pid': 'p$i', 'name': 'N$i'});
    }
    expect(host.humanCount, 8);
    expect(links[8].of(Msg.error), isNotEmpty);
    host.message(links[0], {'t': 'settings', 'dur': 'oops'});
    host.messageBytes(links[0], Uint8List.fromList([Wire.input, 1, 2]));
    host.messageBytes(links[0], Uint8List(0));
    expect(host.settings.duration, 180);
  });

  test('owner closes the LAN room: everyone kicked, host resets', () {
    final host = RoomHost(seed: 6, settings: const LobbySettings(bots: 1));
    final a = FakeLink(), b = FakeLink(), c = FakeLink();
    host.message(a, {'t': 'hello', 'pid': 'aaa', 'name': 'An'});
    host.message(b, {'t': 'hello', 'pid': 'bbb', 'name': 'Bình'});
    host.message(a, {'t': 'start'});
    run(host, RoomHost.revealTime + 0.5);
    expect(host.phase, RoomPhase.match);

    host.message(b, {'t': 'close'}); // not the owner
    expect(host.phase, RoomPhase.match);
    expect(b.closed, isFalse);

    host.message(a, {'t': 'close'});
    for (final l in [a, b]) {
      expect(l.last(Msg.closed)['msg'], isNotEmpty);
      expect(l.closed, isTrue);
    }
    expect(host.phase, RoomPhase.lobby);
    expect(host.humanCount, 0);
    expect(host.sim, isNull);

    // A new joiner gets a fresh room and owns it.
    host.message(c, {'t': 'hello', 'pid': 'ccc', 'name': 'Chi'});
    expect(RoomState.fromJson(c.last(Msg.room)).ownerPid, 'ccc');
  });

  test('ping is echoed; offline rooms cannot be closed remotely', () {
    final host = RoomHost(seed: 7, local: true);
    final a = FakeLink();
    host.message(a, {'t': 'ping', 'c': 1234});
    expect(a.last(Msg.pong)['c'], 1234);
    host.message(a, {'t': 'hello', 'pid': 'aaa', 'name': 'An'});
    host.message(a, {'t': 'close'});
    expect(a.closed, isFalse);
    expect(host.humanCount, 1);
  });

  test('competitive: a class picked by someone else is locked', () {
    final host = RoomHost(
        seed: 8, settings: const LobbySettings(mode: GameMode.competitive, bots: 2));
    final a = FakeLink(), b = FakeLink();
    host.message(a, {'t': 'hello', 'pid': 'aaa', 'name': 'An'});
    host.message(b, {'t': 'hello', 'pid': 'bbb', 'name': 'Bình'});
    host.message(a, {'t': 'start'});
    host.message(a, {'t': 'pick', 'class': 'silkie'});
    host.message(b, {'t': 'pick', 'class': 'silkie'}); // taken → ignored
    final room = RoomState.fromJson(b.last(Msg.room));
    expect(room.players.firstWhere((p) => p.pid == 'bbb').picked, isNull);
    host.message(b, {'t': 'pick', 'class': 'bantam'});
    run(host, 0.1);
    final classes = [for (final e in (a.last(Msg.reveal)['entries'] as List)) (e as Map)['class']];
    expect(classes.toSet(), hasLength(4));
    expect(classes, containsAll(['silkie', 'bantam']));
  });
}
