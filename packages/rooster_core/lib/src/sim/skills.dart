/// Class skills + universal Rage / Crow (GDD §2 skill slots, §4 classes).
library;

import 'dart:math' as math;

import '../data/chicken_classes.dart';
import '../data/tuning.dart';
import '../math/vec2.dart';
import 'combat.dart';
import 'events.dart';
import 'fighter.dart';
import 'input.dart';
import 'match_sim.dart';

class Skills {
  // Flame Kick
  static const _fkWindup = 0.1, _fkDashEnd = 0.36, _fkEnd = 0.44, _fkSpeed = 12.0;
  static const flameKick = AttackSpec(
      damage: 14, knock: 9, balance: 35, hitstun: 0.35,
      flags: HitFlag.skill, burn: 3);

  // Shadow Dash
  static const _sdTime = 0.28, _sdSpeed = 18.0;
  static const shadowDash = AttackSpec(
      damage: 9, knock: 3.5, balance: 15, hitstun: 0.25, flags: HitFlag.skill);

  // Earth Rooster
  static const earthRooster = AttackSpec(
      damage: 11, knock: 6.5, balance: 45, hitstun: 0.4,
      flags: HitFlag.skill, pop: 3);
  static const earthRadius = 2.4;

  // Mad Rooster
  static const madDuration = 4.0, madDrain = 3.0;

  // Fake Death
  static const fakeMax = 3.0, fakeHeal = 5.0;
  static const surprise = AttackSpec(
      damage: 10, knock: 8, balance: 25, hitstun: 0.3,
      flags: HitFlag.skill, confuse: Tuning.confuseTime);
  static const surpriseRadius = 2.0;

  // Stomp Chain (Đông Tảo): 3 heavy stomps forward.
  static const stompTimes = [0.15, 0.45, 0.75];
  static const stompEnd = 0.9, stompRadius = 1.3, stompReach = 0.9;
  static const stomp = AttackSpec(
      damage: 6, knock: 4.5, balance: 16, hitstun: 0.22,
      flags: HitFlag.skill, pop: 1.5);

  // Peck Flurry (Gà Tre): 6 quick pecks, can keep moving.
  static const peckCount = 6, peckEvery = 0.15, peckEnd = 1.0;
  static const peck = AttackSpec(
      damage: 3, knock: 1.5, balance: 8, hitstun: 0.12, flags: HitFlag.skill);
  static const peckLast = AttackSpec(
      damage: 4, knock: 5.5, balance: 14, hitstun: 0.25, flags: HitFlag.skill);

  // Dark Vortex (Gà Ác): pull into a point ahead, then explode outward.
  static const vortexAhead = 2.4, vortexRadius = 3.0, vortexPull = 4.8;
  static const vortexStart = 0.15, vortexBurstAt = 1.0, vortexEnd = 1.25;
  static const vortexBurstRadius = 2.2;
  static const vortexBurst = AttackSpec(
      damage: 11, knock: 9.5, balance: 35, hitstun: 0.3, flags: HitFlag.skill);

  /// Class skills are the rage "ultimate window": usable only while rage
  /// is active, on a shortened cooldown.
  static bool tryStartSkill(MatchSimulation sim, Fighter f) {
    if (!f.rageActive || f.skillCd > 0) return false;
    final d = f.def;
    f.attackStaminaMul = f.staminaMul;
    f.spendStamina(d.skillStamina);
    f.skillCd = d.skillCooldown * Tuning.rageSkillCooldownMul;
    f.hitIds.clear();
    f.dashDir.setFrom(f.facing);
    switch (d.skill) {
      case SkillId.flameKick:
        f.setState(FState.skill, _fkEnd);
      case SkillId.shadowDash:
        f.setState(FState.skill, _sdTime);
        f.invuln = math.max(f.invuln, _sdTime);
      case SkillId.earthRooster:
        f.setState(FState.skill, 2.0);
        f.vz = 8.5;
        f.vel.setFrom(f.facing * 3.0);
      case SkillId.madRooster:
        f.setState(FState.skill, 0.4);
        f.madTime = madDuration + 0.4;
      case SkillId.fakeDeath:
        f.setState(FState.fakeDead, fakeMax);
        f.vel.set(0, 0);
        sim.emit(SimEvent(EvType.fakeKo, b: f.id, x: f.pos.x, y: f.pos.y));
      case SkillId.stompChain:
        f.setState(FState.skill, stompEnd);
      case SkillId.peckFlurry:
        f.setState(FState.skill, peckEnd);
      case SkillId.darkVortex:
        f.setState(FState.skill, vortexEnd);
        f.vel.set(0, 0);
        f.skillPoint.setFrom(f.pos + f.facing * vortexAhead);
        sim.emit(SimEvent(EvType.vortex,
            a: f.id, x: f.skillPoint.x, y: f.skillPoint.y,
            v: vortexBurstAt - vortexStart));
    }
    sim.emit(SimEvent(EvType.skill,
        a: f.id, x: f.pos.x, y: f.pos.y, v: d.skill.index.toDouble()));
    return true;
  }

  /// Per-tick skill logic while in [FState.skill] / [FState.fakeDead].
  static void update(MatchSimulation sim, Fighter f, double dt) {
    if (f.state == FState.fakeDead) {
      f.hp = math.min(f.maxHp, f.hp + fakeHeal * dt);
      final wants = f.bufferedPress & (Btn.light | Btn.skill) != 0;
      if (f.stateTime >= fakeMax || (f.stateTime > 0.6 && wants)) {
        f.bufferedPress = 0;
        trollSurprise(sim, f);
      }
      return;
    }
    switch (f.def.skill) {
      case SkillId.flameKick:
        if (f.stateTime < _fkWindup) {
          f.vel.scale(0.5);
        } else if (f.stateTime < _fkDashEnd) {
          f.vel.setFrom(f.dashDir * _fkSpeed);
          _sweep(sim, f, 0.5, 0.7, flameKick, sideways: false);
        } else {
          f.vel.scale(0.8);
        }
        if (f.stateTime >= _fkEnd) _toRecovery(f, 0.25);
      case SkillId.shadowDash:
        f.vel.setFrom(f.dashDir * _sdSpeed);
        _sweep(sim, f, 0, 0.8, shadowDash, sideways: true);
        if (f.stateTime >= _sdTime) {
          f.vel.scale(0.25);
          f.empoweredTime = 1.8;
          _toRecovery(f, 0.12);
        }
      case SkillId.earthRooster:
        if (f.stateTime > 0.1 && f.grounded) {
          Combat.aoe(sim, f, f.pos.x, f.pos.y, earthRadius, earthRooster);
          sim.emit(SimEvent(EvType.land, a: f.id, x: f.pos.x, y: f.pos.y, v: 2));
          f.vel.set(0, 0);
          _toRecovery(f, 0.35);
        } else if (f.stateTime >= f.stateDur) {
          _toRecovery(f, 0.2);
        }
      case SkillId.madRooster:
        f.vel.scale(0.6);
        if (f.stateTime >= f.stateDur) f.setState(FState.idle);
      case SkillId.fakeDeath:
        f.setState(FState.idle);
      case SkillId.stompChain:
        _stompChain(sim, f);
      case SkillId.peckFlurry:
        _peckFlurry(sim, f);
      case SkillId.darkVortex:
        _darkVortex(sim, f, dt);
    }
  }

  static void _stompChain(MatchSimulation sim, Fighter f) {
    f.vel.setFrom(f.dashDir * 1.4); // lumbering advance
    if (f.skillStep < stompTimes.length && f.stateTime >= stompTimes[f.skillStep]) {
      f.skillStep++;
      final c = f.pos + f.dashDir * stompReach;
      Combat.aoe(sim, f, c.x, c.y, stompRadius, stomp);
      sim.emit(SimEvent(EvType.land, a: f.id, x: c.x, y: c.y, v: 1.5));
    }
    if (f.stateTime >= f.stateDur) _toRecovery(f, 0.25);
  }

  static void _peckFlurry(MatchSimulation sim, Fighter f) {
    // Keep walking (60%) and steering while pecking.
    final inDir = V2(f.input.mx, f.input.my)..clampLength(1);
    f.vel.setFrom(inDir * (f.moveSpeed * 0.6));
    if (inDir.length2 > 0.04) {
      final a = lerpAngle(f.facing.angle, inDir.angle, 0.15);
      f.facing.set(math.cos(a), math.sin(a));
    }
    final due = 0.08 + f.skillStep * peckEvery;
    if (f.skillStep < peckCount && f.stateTime >= due) {
      f.skillStep++;
      final last = f.skillStep == peckCount;
      final c = f.pos + f.facing * 0.75;
      for (final t in sim.fighters) {
        if (identical(t, f) || !t.alive || t.z > Tuning.airHitHeight) continue;
        if (t.pos.distanceTo(c) > 0.62 + Tuning.fighterRadius) continue;
        final dir = (f.facing * 0.7 + (t.pos - f.pos).normalized() * 0.3).normalized();
        Combat.applyHit(sim, f, t, last ? peckLast : peck, dir);
      }
    }
    if (f.stateTime >= f.stateDur) _toRecovery(f, 0.15);
  }

  static void _darkVortex(MatchSimulation sim, Fighter f, double dt) {
    f.vel.scale(0.3); // rooted while channeling
    final p = f.skillPoint;
    final t0 = f.stateTime;
    if (t0 >= vortexStart && t0 < vortexBurstAt) {
      for (final t in sim.fighters) {
        if (identical(t, f) || !t.alive || t.invuln > 0) continue;
        if (t.state == FState.fakeDead) continue;
        final d = p - t.pos;
        final dist = d.length;
        if (dist > vortexRadius || dist < 0.15) continue;
        // Suck toward the center; rage super armor resists.
        final pull = vortexPull * (t.rageActive ? 0.4 : 1) / t.mass;
        final want = d.normalized() * pull;
        final k = math.min(1.0, 10 * dt);
        t.vel.x += (want.x - t.vel.x) * k;
        t.vel.y += (want.y - t.vel.y) * k;
      }
    }
    if (!f.effectFired && t0 >= vortexBurstAt) {
      f.effectFired = true;
      Combat.aoe(sim, f, p.x, p.y, vortexBurstRadius, vortexBurst);
      sim.emit(SimEvent(EvType.burst, a: f.id, x: p.x, y: p.y));
    }
    if (t0 >= f.stateDur) _toRecovery(f, 0.2);
  }

  static void trollSurprise(MatchSimulation sim, Fighter f) {
    if (f.state != FState.fakeDead) return;
    // Leave fakeDead before the blast so two trolls can't chain forever.
    _toRecovery(f, 0.2);
    f.invuln = math.max(f.invuln, 0.3);
    f.attackStaminaMul = f.staminaMul;
    sim.emit(SimEvent(EvType.surprise, a: f.id, x: f.pos.x, y: f.pos.y));
    Combat.aoe(sim, f, f.pos.x, f.pos.y, surpriseRadius, surprise);
  }

  static bool tryRage(MatchSimulation sim, Fighter f) {
    if (f.rage < Tuning.rageMax || f.rageActive) return false;
    f.rage = 0;
    f.rageTimer = Tuning.rageDuration + Tuning.rageRoarTime;
    f.skillCd = 0; // skill ready the moment rage kicks in
    f.setState(FState.rageRoar, Tuning.rageRoarTime);
    f.vel.set(0, 0);
    sim.emit(SimEvent(EvType.rage, a: f.id, x: f.pos.x, y: f.pos.y));
    return true;
  }

  /// The U button: rage and the ultimate in one press. With a full bar and
  /// no rage running, rage kicks in — its roar shove lands at once instead
  /// of after a roar pause — and the class skill fires straight away.
  /// While raging it is just the skill (after its short cooldown).
  static bool tryRageSkill(MatchSimulation sim, Fighter f) {
    if (!f.rageActive) {
      if (!tryRage(sim, f)) return false;
      f.rageTimer -= Tuning.rageRoarTime; // no roar pause to cover
      Combat.aoe(sim, f, f.pos.x, f.pos.y, Tuning.rageRoarRadius,
          AttackSpec.shove(Tuning.rageRoarKnock, 10));
    }
    return tryStartSkill(sim, f);
  }

  static bool tryCrow(MatchSimulation sim, Fighter f) {
    if (f.crowCd > 0) return false;
    f.crowCd = Tuning.crowCooldown;
    f.setState(FState.crow, Tuning.crowTime);
    f.vel.scale(0.3);
    sim.emit(SimEvent(EvType.crow, a: f.id, x: f.pos.x, y: f.pos.y));
    return true;
  }

  /// Fires the shove of crow / rage roar once, early in the animation.
  static void updateShout(MatchSimulation sim, Fighter f) {
    f.vel.scale(0.8);
    if (!f.effectFired && f.stateTime >= 0.15) {
      f.effectFired = true;
      if (f.state == FState.crow) {
        f.rage = math.min(Tuning.rageMax, f.rage + Tuning.crowRage);
        Combat.aoe(sim, f, f.pos.x, f.pos.y, Tuning.crowRadius,
            AttackSpec.shove(Tuning.crowKnock, Tuning.crowBalance));
      } else {
        Combat.aoe(sim, f, f.pos.x, f.pos.y, Tuning.rageRoarRadius,
            AttackSpec.shove(Tuning.rageRoarKnock, 10));
      }
    }
    if (f.stateTime >= f.stateDur) f.setState(FState.idle);
  }

  /// Hits each fighter once along a dash.
  static void _sweep(MatchSimulation sim, Fighter f, double ahead, double r,
      AttackSpec spec, {required bool sideways}) {
    final cx = f.pos.x + f.dashDir.x * ahead, cy = f.pos.y + f.dashDir.y * ahead;
    for (final t in sim.fighters) {
      if (identical(t, f) || !t.alive || f.hitIds.contains(t.id)) continue;
      if (t.z > Tuning.airHitHeight) continue;
      final dx = t.pos.x - cx, dy = t.pos.y - cy;
      if (dx * dx + dy * dy > math.pow(r + Tuning.fighterRadius, 2)) continue;
      f.hitIds.add(t.id);
      var dir = f.dashDir.clone();
      if (sideways) {
        final side = f.dashDir.perp;
        dir = side.dot(t.pos - f.pos) >= 0 ? side : -side;
      }
      Combat.applyHit(sim, f, t, spec, dir);
    }
  }

  static void _toRecovery(Fighter f, double dur) {
    f.recoveringFrom = f.state;
    f.setState(FState.recovery, dur);
  }
}
