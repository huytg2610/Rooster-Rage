import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster_core/rooster_core.dart';
import 'package:rooster_rage/app/profile.dart';
import 'package:rooster_rage/controls/input_controller.dart';
import 'package:rooster_rage/game/rooster_game.dart';
import 'package:rooster_rage/net/client_link.dart';
import 'package:rooster_rage/net/session.dart';

/// Feeds a real simulation into a Session through a fake link.
class FakeClientLink implements ClientLink {
  final msgs = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final bin = StreamController<Uint8List>.broadcast(sync: true);
  @override
  Stream<Map<String, dynamic>> get messages => msgs.stream;
  @override
  Stream<Uint8List> get frames => bin.stream;
  @override
  final status = ValueStreamLike(LinkStatus.open);
  @override
  void send(Map<String, Object?> msg) {}
  @override
  void sendBytes(Uint8List bytes) {}
  @override
  Future<void> close() async {}
  void push(Map<String, Object?> m) =>
      msgs.add(jsonDecode(jsonEncode(m)) as Map<String, dynamic>);
}

void main() {
  for (final (arena, survival) in [
    ('village', false),
    ('rooftop', false),
    ('temple', false),
    ('village', true),
  ]) {
    testWidgets(
        'match renders frames without exceptions ($arena${survival ? ', survival' : ''})',
        (tester) async {
      final link = FakeClientLink();
      final session = Session(
        link: link,
        profile: const Profile(pid: 'p1', name: 'Me', gamesPlayed: 3),
        isLocal: true,
      );
      final sim = MatchSimulation(
          MatchConfig(arenaId: arena, seed: 4, survival: survival), [
        for (var i = 1; i <= 8; i++)
          FighterSetup(
            id: i, playerId: i == 1 ? 'p1' : 'b$i', name: 'F$i', slot: i - 1,
            isBot: true, botLevel: 2, classId: ChickenClasses.all[i - 1].id,
            variant: Variant.values[i % 5], rarity: Rarity.values[i % 4]),
      ]);
      link.push(RoomState(
        phase: RoomPhase.match, ownerPid: 'p1', settings: const LobbySettings(),
        players: const [LobbyPlayerDto(pid: 'p1', name: 'Me', slot: 0, connected: true)],
        joinUrls: const [], timer: 0, local: true).toJson());
      link.push({
        't': Msg.match,
        'arena': arena,
        'dur': 180,
        'surv': survival,
        'fighters': [for (final f in sim.fighters) FighterInfo.of(f).toJson()],
        'you': 1,
      });
      final game = RoosterGame(session: session, input: InputController(), showTouchControls: true);
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      final enc = SnapshotEncoder();
      for (var frame = 0; frame < 60 * 12; frame++) {
        sim.step();
        if (sim.tick.isEven) link.bin.add(enc.encode(sim, sim.drainEvents()));
        await tester.pump(const Duration(milliseconds: 16));
        final ex = tester.takeException();
        if (ex != null) fail('frame $frame: $ex');
      }
      expect(game.frame, isNotNull);
      session.dispose();
    });
  }
}
