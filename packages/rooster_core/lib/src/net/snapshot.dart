/// Decoded match snapshot model (host → clients, 30 Hz). Wire format lives
/// in snapshot_codec.dart.
library;

import '../data/tuning.dart';
import '../sim/arena_runtime.dart' show FoodKind;
import '../sim/events.dart';
import '../sim/fighter.dart';
import '../sim/match_sim.dart';

class FighterSnap {
  final int id;
  final double x, y, z, vx, vy, facing;
  final FState state;
  final double stateTime, stateDur;
  final double hp, stamina, balance, rage;
  final int flags;
  final double heavyCharge;
  final int comboStep;
  final double skillCd, crowCd, respawnTimer, rageTimer;
  final int kos, deaths;
  final double shield; // guard HP
  final bool shieldBroken; // shattered, mending back to a quarter

  const FighterSnap({
    required this.id,
    required this.x,
    required this.y,
    required this.z,
    required this.vx,
    required this.vy,
    required this.facing,
    required this.state,
    required this.stateTime,
    required this.stateDur,
    required this.hp,
    required this.stamina,
    required this.balance,
    required this.rage,
    required this.flags,
    required this.heavyCharge,
    required this.comboStep,
    required this.skillCd,
    required this.crowCd,
    required this.respawnTimer,
    required this.rageTimer,
    required this.kos,
    required this.deaths,
    this.shield = Tuning.shieldMax,
    this.shieldBroken = false,
  });

  bool has(int flag) => flags & flag != 0;

}

class PuddleSnap {
  final double x, y, r, ttl;
  const PuddleSnap(this.x, this.y, this.r, this.ttl);
}

class FoodSnap {
  final int id;
  final double x, y;
  final FoodKind kind;
  const FoodSnap(this.id, this.x, this.y, [this.kind = FoodKind.corn]);
}

class PropsSnap {
  final List<bool> bucketsSpilled;
  final List<bool> trapsArmed;
  final List<PuddleSnap> puddles;
  final List<FoodSnap> foods;

  const PropsSnap(this.bucketsSpilled, this.trapsArmed, this.puddles, this.foods);

  static const empty = PropsSnap([], [], [], []);

}

class MatchSnap {
  final int tick;
  final double time;
  final MatchPhase phase;
  final double remaining;
  final double countdown;
  final List<FighterSnap> fighters;
  final PropsSnap props;
  final List<SimEvent> events;

  const MatchSnap({
    required this.tick,
    required this.time,
    required this.phase,
    required this.remaining,
    required this.countdown,
    required this.fighters,
    required this.props,
    required this.events,
  });

  FighterSnap? fighter(int id) {
    for (final f in fighters) {
      if (f.id == id) return f;
    }
    return null;
  }

}
