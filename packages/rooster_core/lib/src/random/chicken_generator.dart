/// Weighted random chicken system (GDD §1A, §11).
///
/// Not fully random: weights account for role balance within the match,
/// what each player played recently, duplicates, and a difficulty curve for
/// new players.
library;

import '../data/chicken_classes.dart';
import '../data/variants.dart';
import '../math/rng.dart';

class PlayerProfile {
  final String playerId;

  /// Matches played so far (drives the difficulty curve).
  final int gamesPlayed;

  /// Most recent first.
  final List<String> recentClasses;

  const PlayerProfile({
    required this.playerId,
    this.gamesPlayed = 0,
    this.recentClasses = const [],
  });
}

class ChickenInstance {
  final String classId;
  final Variant variant;
  final Rarity rarity;

  const ChickenInstance(this.classId, this.variant, this.rarity);

  ChickenClassDef get def => ChickenClasses.byId(classId);

  Map<String, Object> toJson() =>
      {'class': classId, 'variant': variant.name, 'rarity': rarity.name};

  static ChickenInstance fromJson(Map<String, dynamic> j) => ChickenInstance(
        j['class'] as String,
        Variant.values.byName(j['variant'] as String),
        Rarity.values.byName(j['rarity'] as String),
      );
}

class ChickenGenerator {
  // Weight factors — exposed for tests / tuning.
  static const recentPenalty = [0.3, 0.6, 0.85];
  static const duplicatePenalty = 0.12;
  static const sameRolePenalty = 0.45;
  static const newbieGames = 3;
  static const newbieEasyBoost = 1.8;
  static const newbieHardPenalty = 0.45;

  /// Weight of each class for [profile] given classes already assigned in
  /// this match.
  static List<double> weightsFor(PlayerProfile profile, List<String> assigned,
      [List<ChickenClassDef> pool = ChickenClasses.all]) {
    return [
      for (final c in pool) _weight(c, profile, assigned),
    ];
  }

  static double _weight(
      ChickenClassDef c, PlayerProfile p, List<String> assigned) {
    var w = 1.0;
    // Recently played by this player.
    for (var i = 0; i < p.recentClasses.length && i < recentPenalty.length; i++) {
      if (p.recentClasses[i] == c.id) w *= recentPenalty[i];
    }
    // Unique chickens: a class already in the match is excluded while any
    // class is still free (8 classes = 8 slots, so a full room never repeats).
    final dupes = assigned.where((a) => a == c.id).length;
    final allTaken = ChickenClasses.all.every((k) => assigned.contains(k.id));
    if (dupes > 0) {
      if (!allTaken) return 0;
      w *= duplicatePenalty;
    }
    // Role balance (each class currently has a unique role, but keep the
    // rule so future classes sharing a role stay balanced).
    final sameRole =
        assigned.where((a) => ChickenClasses.byId(a).role == c.role).length;
    w *= 1 / (1 + sameRolePenalty * sameRole);
    // Difficulty curve.
    if (p.gamesPlayed < newbieGames) {
      if (c.difficulty == 1) w *= newbieEasyBoost;
      if (c.difficulty == 3) w *= newbieHardPenalty;
    }
    return w;
  }

  /// Assigns one chicken per profile. Order is shuffled first so the first
  /// player doesn't always get first pick of the weights. [fixedClasses]
  /// (parallel to [profiles], null = roll) pins picks from competitive mode;
  /// rolled players never duplicate a pinned class.
  static List<ChickenInstance> generate(List<PlayerProfile> profiles, int seed,
      {List<String?>? fixedClasses}) {
    final rng = Rng(seed);
    final order = List<int>.generate(profiles.length, (i) => i);
    for (var i = order.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final t = order[i];
      order[i] = order[j];
      order[j] = t;
    }
    final fixed = fixedClasses ?? List<String?>.filled(profiles.length, null);
    final assigned = <String>[for (final c in fixed) ?c];
    final out = List<ChickenInstance?>.filled(profiles.length, null);
    for (final idx in order) {
      final pinned = fixed[idx];
      if (pinned != null) {
        out[idx] = ChickenInstance(pinned, rollVariant(rng), rollRarity(rng));
        continue;
      }
      final weights = weightsFor(profiles[idx], assigned);
      var ci = rng.weightedIndex(weights);
      if (ci < 0) ci = rng.nextInt(ChickenClasses.all.length);
      final cls = ChickenClasses.all[ci];
      assigned.add(cls.id);
      out[idx] = ChickenInstance(cls.id, rollVariant(rng), rollRarity(rng));
    }
    return out.cast<ChickenInstance>();
  }

  static Variant rollVariant(Rng rng) => rng.pick(Variant.values);

  static Rarity rollRarity(Rng rng) {
    final i = rng.weightedIndex([for (final r in Rarity.values) r.weight]);
    return Rarity.values[i < 0 ? 0 : i];
  }
}
