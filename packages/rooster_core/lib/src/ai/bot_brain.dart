/// AISystem (GDD §8): utility-style bot that manages stamina, avoids edges,
/// tries to ring enemies out and uses class skills situationally.
library;

import 'dart:math' as math;

import '../data/arenas.dart';
import '../data/chicken_classes.dart';
import '../data/tuning.dart';
import '../math/rng.dart';
import '../math/vec2.dart';
import '../sim/arena_runtime.dart';
import '../sim/fighter.dart';
import '../sim/input.dart';
import '../sim/match_sim.dart';

class BotBrain {
  final int fighterId;
  final int level; // 0 easy, 1 normal, 2 hard
  final Rng rng;

  int targetId = -1;
  double _retarget = 0;
  double _think = 0;
  double _holdHeavy = 0;
  bool _kiting = false;
  double _strafe = 1;
  double _strafeTimer = 0;
  bool _compensate = false;
  double _blockTime = 0;

  BotBrain(this.fighterId, int level, int seed)
      : level = level.clamp(0, 2),
        rng = Rng(seed);

  double get _reaction => const [0.42, 0.25, 0.13][level];
  double get _aggression => const [0.5, 0.78, 0.95][level];
  double get _dodgeSkill => const [0.2, 0.45, 0.75][level];

  void think(MatchSimulation sim, Fighter me, double dt) {
    final input = me.input;
    input.pressed = 0;
    // Smarter bots counter-steer while confused (the sim inverts input).
    _compensate = me.confuseTime > 0 && level >= 1;
    if (!me.alive) {
      input.clear();
      return;
    }

    _retarget -= dt;
    var target = sim.byId(targetId);
    if (_retarget <= 0 || target == null || !_valid(target)) {
      target = _pickTarget(sim, me);
      targetId = target?.id ?? -1;
      _retarget = rng.range(1.2, 2.4);
    }
    _strafeTimer -= dt;
    if (_strafeTimer <= 0) {
      _strafe = rng.chance(0.5) ? 1 : -1;
      _strafeTimer = rng.range(0.8, 1.8);
    }

    // Hold heavy until the planned release.
    if (me.state == FState.heavyCharge) {
      _holdHeavy -= dt;
      input.heavyHeld = _holdHeavy > 0;
      if (target != null) _steer(input, (target.pos - me.pos).normalized());
      return;
    }
    input.heavyHeld = false;

    // Keep guarding until the planned release.
    if (_blockTime > 0) {
      _blockTime -= dt;
      input.blockHeld = _blockTime > 0 && !me.shieldBroken;
      if (input.blockHeld) {
        if (target != null) _steer(input, (target.pos - me.pos).normalized() * 0.3);
        return;
      }
    }
    input.blockHeld = false;

    final move = V2.zero();
    final dist = target == null ? 99.0 : me.pos.distanceTo(target.pos);
    final staminaRatio = me.stamina / me.maxStamina;
    if (_kiting) {
      if (staminaRatio > 0.6) _kiting = false;
    } else if (staminaRatio < 0.22 && !me.isMad) {
      _kiting = true;
    }

    if (target != null) {
      final toT = (target.pos - me.pos).normalized();
      if (_kiting) {
        move.addScaled(toT, dist < 3 ? -1 : 0);
        move.addScaled(toT.perp, _strafe * 0.8);
      } else {
        // Approach from the arena-center side to shove the target outward.
        final out = target.pos.normalized();
        final approach = level > 0 ? target.pos - out * 0.9 : target.pos.clone();
        final toA = approach - me.pos;
        if (dist > 1.3) {
          move.addScaled(toA.normalized(), 1);
        } else {
          move.addScaled(toT, 0.35);
          move.addScaled(toT.perp, _strafe * 0.35);
        }
      }
    }

    // Hurt: go eat a nearby heal drop unless an enemy is right on top.
    if (me.hp < me.maxHp * 0.5 && (target == null || dist > 1.6)) {
      Food? best;
      var bestD = 7.0 * 7.0;
      for (final f in sim.props.foods) {
        if (f.kind != FoodKind.heal) continue;
        final d = me.pos.distance2To(V2(f.x, f.y));
        if (d < bestD) {
          bestD = d;
          best = f;
        }
      }
      if (best != null) {
        move.setFrom((V2(best.x, best.y) - me.pos).normalized());
      }
    }

    // Edge safety overrides everything else.
    final safe = _safeDir(sim, me);
    var wantJumpGap = false;
    if (safe != null) {
      if (target != null && _jumpReachable(sim, me, target)) {
        wantJumpGap = true;
      } else {
        move.setFrom(safe);
      }
    }
    _steer(input, move);

    _think -= dt;
    if (_think > 0) return;
    _think = _reaction * rng.range(0.7, 1.3);
    if (!me.canAct && me.state != FState.recovery) return;

    if (wantJumpGap && me.stamina > Tuning.jumpStamina) {
      _steer(input, (target!.pos - me.pos).normalized());
      input.pressed |= Btn.jump;
      return;
    }
    // One button: rage + ultimate together (same as players' U).
    if (me.rage >= Tuning.rageMax && !me.rageActive && dist < 3) {
      _steer(input, (target!.pos - me.pos).normalized());
      input.pressed |= Btn.skill;
      return;
    }
    if (_dodgeThreat(sim, me, input)) return;
    if (target == null) return;
    if (_useSkill(sim, me, target, dist)) {
      input.pressed |= Btn.skill;
      return;
    }
    if (me.crowCd <= 0 && _enemiesWithin(sim, me, 2.0) >= 2 && rng.chance(0.25)) {
      input.pressed |= Btn.crow;
      return;
    }
    if (_kiting) return;

    if (dist <= 1.25 && rng.chance(_aggression)) {
      final vulnerable = target.state == FState.stunned ||
          target.state == FState.recovery ||
          target.state == FState.exhausted ||
          target.balance < target.maxBalance * 0.35;
      if (vulnerable && staminaRatio > 0.35 && rng.chance(0.7)) {
        _holdHeavy = rng.range(0.25, 0.4 + 0.25 * level);
        input.heavyHeld = true;
      } else {
        input.pressed |= Btn.light;
      }
    } else if (dist > 1.8 && dist < 2.9 && staminaRatio > 0.4 &&
        rng.chance(0.12 * _aggression) &&
        _landingSafe(sim, me, (target.pos - me.pos).normalized(), 2.7)) {
      input.pressed |= Btn.jump;
    }
  }

  bool _valid(Fighter t) => t.alive && t.state != FState.fakeDead;

  Fighter? _pickTarget(MatchSimulation sim, Fighter me) {
    Fighter? best;
    var bestScore = double.infinity;
    for (final t in sim.fighters) {
      if (identical(t, me) || !_valid(t)) continue;
      var score = me.pos.distanceTo(t.pos) + t.hp / t.maxHp + rng.nextDouble() * 1.5;
      if (t.id == targetId) score -= 1.0;
      // Spread pressure: avoid dog-piling a chicken other bots already chase.
      for (final b in sim.brains.values) {
        if (b.fighterId != me.id && b.targetId == t.id) score += 1.2;
      }
      // Bots exist to entertain humans — lean toward real players.
      if (!sim.brains.containsKey(t.id)) score -= 0.8 + 0.4 * level;
      if (level == 2) {
        final depth = sim.arena.groundDepth(t.pos.x, t.pos.y, sim.time);
        score -= (1 - clampD(depth / 3, 0, 1)) * 2;
      }
      if (score < bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return best;
  }

  /// Direction toward safer ground if we're about to walk off, else null.
  V2? _safeDir(MatchSimulation sim, Fighter me) {
    final t = sim.time + 0.3;
    final ahead = me.pos + me.vel * 0.35;
    final inFan = _inActiveFan(sim, me.pos);
    if (sim.arena.groundDepth(ahead.x, ahead.y, t) > 0.9 && !inFan) return null;
    V2? best;
    var bestD = -double.infinity;
    for (var i = 0; i < 12; i++) {
      final d = V2.fromAngle(i * math.pi / 6);
      final p = me.pos + d * 1.2;
      var depth = sim.arena.groundDepth(p.x, p.y, t);
      if (_inActiveFan(sim, p)) depth -= 1.5;
      if (depth > bestD) {
        bestD = depth;
        best = d;
      }
    }
    return best;
  }

  bool _inActiveFan(MatchSimulation sim, V2 p) {
    for (final prop in sim.arena.props) {
      if (prop.type != PropType.fan) continue;
      if (prop.fanPhase(sim.time) >= 1 && prop.inFanZone(p.x, p.y)) return true;
    }
    return false;
  }

  bool _landingSafe(MatchSimulation sim, Fighter me, V2 dir, double dist) {
    final land = me.pos + dir * dist;
    return sim.arena.isGround(land.x, land.y, sim.time + 0.6, 0.4);
  }

  /// Target is across a gap we can jump (temple platforms).
  bool _jumpReachable(MatchSimulation sim, Fighter me, Fighter target) {
    final a = sim.arena;
    if (a.groundAt(me.pos.x, me.pos.y, sim.time) ==
        a.groundAt(target.pos.x, target.pos.y, sim.time)) {
      return false;
    }
    final dir = (target.pos - me.pos).normalized();
    return me.pos.distanceTo(target.pos) < 5 && _landingSafe(sim, me, dir, 2.7);
  }

  bool _dodgeThreat(MatchSimulation sim, Fighter me, InputState input) {
    if (me.stamina < 10) return false;
    for (final e in sim.fighters) {
      if (identical(e, me) || !e.alive) continue;
      final threatening = e.state == FState.heavyCharge ||
          (e.state == FState.attack && e.stateTime < 0.06) ||
          (e.state == FState.skill && e.stateTime < 0.12);
      if (!threatening) continue;
      final d = me.pos - e.pos;
      if (d.length > 2.4 || e.facing.dot(d.normalized()) < 0.5) continue;
      if (!rng.chance(_dodgeSkill)) return false;
      // Guard instead of dodging when stamina is short (or sometimes anyway).
      if (me.stamina < Tuning.dodgeStamina * 1.5 || rng.chance(0.35)) {
        _blockTime = rng.range(0.35, 0.75);
        input.blockHeld = true;
        return true;
      }
      var dir = d.normalized().perp * _strafe;
      if (!_landingSafe(sim, me, dir, 2.6)) dir = -dir;
      if (!_landingSafe(sim, me, dir, 2.6)) return false;
      _steer(input, dir);
      input.pressed |= Btn.dodge;
      return true;
    }
    return false;
  }

  bool _useSkill(MatchSimulation sim, Fighter me, Fighter target, double dist) {
    // Skills unlock only during rage.
    if (!me.rageActive || me.skillCd > 0 || me.stamina < me.def.skillStamina) return false;
    if (!rng.chance(0.35 + 0.2 * level)) return false;
    final dir = (target.pos - me.pos).normalized();
    return switch (me.def.skill) {
      SkillId.flameKick =>
        dist > 1.4 && dist < 3.8 && _landingSafe(sim, me, dir, 3.2),
      SkillId.shadowDash => dist > 1.8 &&
          dist < 4.5 &&
          target.facing.dot(dir) > -0.3 &&
          _landingSafe(sim, me, dir, 5.0),
      SkillId.earthRooster =>
        _enemiesWithin(sim, me, 2.4) >= 2 || (dist < 1.8 && target.balance < 50),
      SkillId.madRooster => me.hp > me.maxHp * 0.45 && dist < 2.5,
      SkillId.fakeDeath =>
        me.hp < me.maxHp * 0.4 && _enemiesWithin(sim, me, 2.5) >= 1,
      SkillId.stompChain => dist < 2.0,
      SkillId.peckFlurry => dist < 1.3,
      SkillId.darkVortex => dist > 1.2 && dist < 4.2,
    };
  }

  int _enemiesWithin(MatchSimulation sim, Fighter me, double r) {
    var n = 0;
    for (final e in sim.fighters) {
      if (!identical(e, me) && e.alive && e.pos.distanceTo(me.pos) <= r) n++;
    }
    return n;
  }

  void _steer(InputState input, V2 dir) {
    final d = dir.clone()..clampLength(1);
    final s = _compensate ? -1.0 : 1.0;
    input.mx = d.x * s;
    input.my = d.y * s;
  }
}
