import 'package:rooster_core/rooster_core.dart';
import 'package:test/test.dart';

void main() {
  test('xorshift is deterministic', () {
    final a = Rng(42), b = Rng(42);
    for (var i = 0; i < 100; i++) {
      expect(a.nextU32(), b.nextU32());
    }
  });

  test('every chicken in a full 8-player room is unique', () {
    expect(ChickenClasses.all, hasLength(8));
    for (var seed = 1; seed <= 300; seed++) {
      final out = ChickenGenerator.generate(
          [for (var i = 0; i < 8; i++) PlayerProfile(playerId: 'p$i', gamesPlayed: i * 3)], seed);
      expect(out.map((c) => c.classId).toSet(), hasLength(8), reason: 'seed $seed');
    }
  });

  test('pinned picks are honored and never duplicated by rolls', () {
    for (var seed = 1; seed <= 100; seed++) {
      final out = ChickenGenerator.generate(
          [for (var i = 0; i < 6; i++) PlayerProfile(playerId: 'p$i')], seed,
          fixedClasses: ['troll', null, 'ninja', null, null, null]);
      expect(out[0].classId, 'troll');
      expect(out[2].classId, 'ninja');
      expect(out.map((c) => c.classId).toSet(), hasLength(6));
    }
  });

  test('recently played class is less likely', () {
    var repeats = 0;
    for (var seed = 1; seed <= 1000; seed++) {
      final out = ChickenGenerator.generate(
          [const PlayerProfile(playerId: 'a', gamesPlayed: 10, recentClasses: ['ninja'])], seed);
      if (out.single.classId == 'ninja') repeats++;
    }
    // Uniform would be ~200/1000; the 0.3 penalty should land well below.
    expect(repeats, lessThan(120));
  });

  test('new players get easier classes more often', () {
    var easyNew = 0, easyVet = 0;
    for (var seed = 1; seed <= 1000; seed++) {
      final n = ChickenGenerator.generate([const PlayerProfile(playerId: 'n')], seed).single;
      final v = ChickenGenerator.generate(
          [const PlayerProfile(playerId: 'v', gamesPlayed: 50)], seed).single;
      if (n.def.difficulty == 1) easyNew++;
      if (v.def.difficulty == 1) easyVet++;
    }
    expect(easyNew, greaterThan(easyVet));
  });

  test('8 players all receive a chicken; rarity roll is weighted', () {
    final out = ChickenGenerator.generate(
        [for (var i = 0; i < 8; i++) PlayerProfile(playerId: 'p$i')], 99);
    expect(out, hasLength(8));
    var legendary = 0;
    final rng = Rng(5);
    for (var i = 0; i < 5000; i++) {
      if (ChickenGenerator.rollRarity(rng) == Rarity.legendary) legendary++;
    }
    expect(legendary / 5000, closeTo(0.02, 0.01));
  });
}
