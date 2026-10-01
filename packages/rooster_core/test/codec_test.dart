import 'dart:convert';
import 'dart:typed_data';

import 'package:rooster_core/rooster_core.dart';
import 'package:test/test.dart';

MatchSimulation eightBots() => MatchSimulation(const MatchConfig(seed: 21), [
      for (var i = 1; i <= 8; i++)
        FighterSetup(
          id: i,
          playerId: 'b$i',
          name: 'B$i',
          slot: i - 1,
          isBot: true,
          classId: ChickenClasses.all[i - 1].id,
          variant: Variant.fire,
          rarity: Rarity.common,
        ),
    ]);

void main() {
  test('8 fighters: keyframe < 400 B, deltas much smaller', () {
    final sim = eightBots();
    final enc = SnapshotEncoder();
    final sizes = <int>[];
    for (var i = 0; i < 60 * 20; i++) {
      sim.step();
      if (sim.tick.isEven) sizes.add(enc.encode(sim, sim.drainEvents()).length);
    }
    final key = sizes.first;
    final deltas = sizes.skip(1).toList()..sort();
    final median = deltas[deltas.length ~/ 2];
    // ignore: avoid_print
    print('keyframe $key B, delta median $median B, p95 ${deltas[(deltas.length * 0.95).floor()]} B');
    expect(key, lessThan(400));
    expect(median, lessThan(key * 0.7));
  });

  test('shield, its cooldown and heal drops survive the wire', () {
    final sim = eightBots();
    while (sim.phase == MatchPhase.countdown) {
      sim.step();
    }
    final f = sim.byId(3)!;
    f.shield = Tuning.shieldMax * 0.4;
    f.shieldBroken = true;
    sim.props.dropHeal(sim, 1.5, -2);
    final enc = SnapshotEncoder(), dec = SnapshotDecoder();
    final snap = dec.decode(enc.encode(sim, sim.drainEvents()))!;
    final s = snap.fighter(3)!;
    expect(s.shield, closeTo(f.shield, Tuning.shieldMax / 100));
    expect(s.shieldBroken, isTrue);
    final heal = snap.props.foods.singleWhere((x) => x.kind == FoodKind.heal);
    expect(heal.x, closeTo(1.5, 0.01));
    expect(heal.y, closeTo(-2, 0.01));
  });

  test('delta before the first keyframe is ignored; keyframe resyncs a late client', () {
    final sim = eightBots();
    final enc = SnapshotEncoder();
    final early = SnapshotDecoder(), late = SnapshotDecoder();
    for (var i = 0; i < 300; i++) {
      sim.step();
      if (!sim.tick.isEven) continue;
      final bytes = enc.encode(sim, sim.drainEvents());
      early.decode(bytes);
      if (i > 200) {
        final s = late.decode(bytes);
        if (bytes.first == Wire.delta) expect(s, isNull); // no base yet
      }
    }
    enc.forceKeyframe();
    sim.step();
    final bytes = enc.encode(sim, sim.drainEvents());
    expect(bytes.first, Wire.keyframe);
    final a = early.decode(bytes)!, b = late.decode(bytes)!;
    for (final f in a.fighters) {
      expect(b.fighter(f.id)!.x, f.x);
    }
  });

  test('malformed frames decode to null instead of throwing', () {
    final dec = SnapshotDecoder();
    expect(dec.decode(Uint8List(0)), isNull);
    expect(dec.decode(Uint8List.fromList([Wire.keyframe, 1, 2])), isNull);
    expect(dec.decode(Uint8List.fromList(List.filled(40, 255))), isNull);
  });

  test('input is 5 bytes and round-trips', () {
    final b = InputCodec.encode(-100, 55, true, true, Btn.light | Btn.skill);
    expect(b.length, 5);
    final d = InputCodec.decode(b)!;
    expect(d.mx, -1);
    expect(d.my, closeTo(0.55, 1e-9));
    expect(d.heavy && d.block, isTrue);
    expect(d.pressed, Btn.light | Btn.skill);
    expect(InputCodec.decode(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
  });

  test('binary snapshot is far smaller than the old JSON form', () {
    final sim = eightBots();
    for (var i = 0; i < 400; i++) {
      sim.step();
    }
    final bin = SnapshotEncoder().encode(sim, const []).length;
    // Equivalent JSON (old format) size estimate: 23 ints per fighter.
    final json = jsonEncode({
      'f': [for (final f in sim.fighters) List.filled(23, (f.pos.x * 100).round())]
    }).length;
    expect(bin, lessThan(json / 2));
  });
}
