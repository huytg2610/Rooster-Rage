// Headless bot-vs-bot balance report.
//   dart run tool/balance_report.dart [matches] [arena]
import 'package:rooster_core/rooster_core.dart';

void main(List<String> args) {
  final matches = args.isNotEmpty ? int.parse(args[0]) : 40;
  final arena = args.length > 1 ? args[1] : 'village';
  final classes = ChickenClasses.all.map((c) => c.id).toList();
  final kos = <String, int>{}, deaths = <String, int>{}, wins = <String, int>{};
  final dmg = <String, double>{}, games = <String, int>{};
  var ringOuts = 0, hpKos = 0;

  for (var m = 0; m < matches; m++) {
    final rng = Rng(m + 1);
    final sim = MatchSimulation(MatchConfig(arenaId: arena, duration: 180, seed: m + 1), [
      for (var i = 1; i <= 6; i++)
        FighterSetup(
          id: i,
          playerId: 'b$i',
          name: 'B$i',
          slot: i - 1,
          isBot: true,
          botLevel: 1 + (i % 2),
          classId: classes[(i + m) % classes.length],
          variant: rng.pick(Variant.values),
          rarity: Rarity.common,
        ),
    ]);
    while (sim.phase != MatchPhase.ended) {
      sim.step();
      for (final e in sim.drainEvents()) {
        if (e.type != EvType.ko) continue;
        e.flags == KoCause.ringOut ? ringOuts++ : hpKos++;
      }
    }
    final res = sim.results();
    for (final f in sim.fighters) {
      final c = f.setup.classId;
      games[c] = (games[c] ?? 0) + 1;
      kos[c] = (kos[c] ?? 0) + f.kos;
      deaths[c] = (deaths[c] ?? 0) + f.deaths;
      dmg[c] = (dmg[c] ?? 0) + f.damageDealt;
    }
    final winner = sim.byId(res.first.id)!.setup.classId;
    wins[winner] = (wins[winner] ?? 0) + 1;
  }

  print('$matches matches on $arena, 6 bots, 180s');
  print('KOs: ${ringOuts + hpKos} total — ring-out $ringOuts, HP $hpKos '
      '(${((ringOuts + hpKos) / matches).toStringAsFixed(1)}/match)');
  print('class      games  KO/g  death/g  dmg/g  wins');
  for (final c in classes) {
    final g = games[c] ?? 1;
    print('${c.padRight(10)} ${g.toString().padLeft(5)}  '
        '${((kos[c] ?? 0) / g).toStringAsFixed(2).padLeft(4)}  '
        '${((deaths[c] ?? 0) / g).toStringAsFixed(2).padLeft(7)}  '
        '${((dmg[c] ?? 0) / g).toStringAsFixed(0).padLeft(5)}  '
        '${(wins[c] ?? 0).toString().padLeft(4)}');
  }
}
