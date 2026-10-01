/// Combat rules & damage calculation (GDD §5 — Domain layer).
library;

import 'dart:math' as math;

import '../data/chicken_classes.dart';
import '../data/tuning.dart';
import '../math/vec2.dart';
import 'events.dart';
import 'fighter.dart';
import 'match_sim.dart';
import 'skills.dart';

class AttackSpec {
  final double damage; // base damage before the attacker's power
  final double knock; // knockback speed (m/s)
  final double balance; // balance damage
  final double hitstun;
  final int flags; // HitFlag
  final bool canCrit; // consumes Ninja's empowered state
  final double burn; // seconds of burn applied
  final double confuse; // seconds of confusion applied
  final double pop; // vertical pop velocity

  const AttackSpec({
    required this.damage,
    required this.knock,
    required this.balance,
    required this.hitstun,
    this.flags = 0,
    this.canCrit = false,
    this.burn = 0,
    this.confuse = 0,
    this.pop = 0,
  });

  static AttackSpec light(int comboStep) {
    final fin = comboStep >= 3;
    return AttackSpec(
      damage: Tuning.lightDamage * (fin ? Tuning.comboFinisherDamage : 1),
      knock: Tuning.lightKnock * (fin ? Tuning.comboFinisherKnock : 1),
      balance: Tuning.lightBalance * (fin ? Tuning.comboFinisherBalance : 1),
      hitstun: Tuning.lightHitstun * (fin ? 1.4 : 1),
      flags: fin ? HitFlag.finisher : 0,
      canCrit: true,
    );
  }

  static AttackSpec heavy(double charge01) => AttackSpec(
        damage: lerpD(Tuning.heavyDamageMin, Tuning.heavyDamageMax, charge01),
        knock: lerpD(Tuning.heavyKnockMin, Tuning.heavyKnockMax, charge01),
        balance: lerpD(Tuning.heavyBalanceMin, Tuning.heavyBalanceMax, charge01),
        hitstun: Tuning.heavyHitstun,
        flags: HitFlag.heavy,
        canCrit: true,
        pop: 1.5 + 2.0 * charge01,
      );

  static const jumpLand = AttackSpec(
    damage: Tuning.jumpDamage,
    knock: Tuning.jumpKnock,
    balance: Tuning.jumpBalance,
    hitstun: 0.28,
    canCrit: true,
  );

  /// Zero-damage shove (crow, rage roar).
  static AttackSpec shove(double knock, double balance) => AttackSpec(
        damage: 0,
        knock: knock,
        balance: balance,
        hitstun: 0.15,
        flags: HitFlag.shove,
      );
}

class Combat {
  /// GDD §5 formula:
  /// finalDamage = baseDamage * staminaMultiplier * rageMultiplier * hitMultiplier
  static double finalDamage(double baseDamage, double staminaMultiplier,
          double rageMultiplier, double hitMultiplier) =>
      baseDamage * staminaMultiplier * rageMultiplier * hitMultiplier;

  static double rageMultiplier(Fighter f) =>
      f.rageActive ? Tuning.rageDamageMul : 1.0;

  /// Class/state bonuses folded into base damage.
  static double attackerBonus(Fighter f) {
    var m = 1.0;
    if (f.isMad) m *= 1.2; // stacks with rage now that skills need rage
    if (f.def.skill == SkillId.madRooster) {
      // Berserker passive: up to +20% damage as HP drops to 20%.
      final missing = 1 - f.hp / f.maxHp;
      m *= 1 + 0.2 * clampD(missing / 0.8, 0, 1);
    }
    return m;
  }

  static double takenMultiplier(Fighter t) => t.isMad ? 1.25 : 1.0;

  /// True while [t] is committed to an attack (counter-hit window).
  static bool inWindup(Fighter t) => switch (t.state) {
        FState.attack => t.stateTime < Tuning.lightWindup * t.attackTimeScale,
        FState.heavyCharge => true,
        FState.heavyAttack => t.stateTime < Tuning.heavyWindup * t.attackTimeScale,
        FState.skill => t.stateTime < 0.12,
        _ => false,
      };

  /// Applies [spec] from [a] to [t]. [dir] is the knockback direction.
  /// Returns true if the hit connected.
  static bool applyHit(
      MatchSimulation sim, Fighter a, Fighter t, AttackSpec spec, V2 dir) {
    if (!t.alive || t.invuln > 0 || identical(a, t)) return false;
    if (t.state == FState.fakeDead) {
      // Poking a "corpse" wakes the troll up — right into its ambush.
      Skills.trollSurprise(sim, t);
      return true;
    }

    var flags = spec.flags;
    var hitMul = 1.0;
    final toTarget = (t.pos - a.pos).normalized();
    if (spec.damage > 0) {
      if (t.facing.dot(toTarget) > 0.5) {
        hitMul *= Tuning.backstabMul;
        flags |= HitFlag.backstab;
      }
      if (inWindup(t)) {
        hitMul *= Tuning.counterMul;
        flags |= HitFlag.counter;
      }
      if (t.state == FState.stunned) hitMul *= Tuning.stunnedTargetMul;
      if (spec.canCrit && a.empoweredTime > 0) {
        hitMul *= Tuning.empoweredMul;
        flags |= HitFlag.crit;
        a.empoweredTime = 0;
      }
      hitMul = math.min(hitMul, Tuning.maxHitMul);
    }

    final base = spec.damage * a.power * attackerBonus(a);
    var dmg = finalDamage(base, a.attackStaminaMul, rageMultiplier(a), hitMul) *
        (1 - t.armor) *
        takenMultiplier(t);

    // Guard (hold K): still lose HP, just less. The shield soaks the raw
    // hit into its own HP; when that runs out it shatters.
    final blocking = t.state == FState.block;
    var guardBroken = false;
    if (blocking) {
      flags |= HitFlag.blocked;
      t.shield -= dmg;
      t.shieldIdle = 0;
      dmg *= Tuning.blockDamageMul;
      if (t.shield <= 0) {
        t.shield = 0;
        t.shieldBroken = true;
        guardBroken = true;
      }
    }

    if (dmg > 0) {
      t.hp -= dmg;
      a.damageDealt += dmg;
      if (!a.rageActive) a.rage = math.min(Tuning.rageMax, a.rage + dmg * Tuning.rageOnDeal);
      if (!t.rageActive) t.rage = math.min(Tuning.rageMax, t.rage + dmg * Tuning.rageOnTake);
    }
    t.lastAttacker = a.id;
    t.lastAttackerTime = sim.time;

    if (spec.burn > 0) {
      t.burnTime = spec.burn;
      t.burnSource = a.id;
      flags |= HitFlag.burn;
    }
    if (spec.confuse > 0) t.confuseTime = spec.confuse;

    // Balance → stun + knockback scaling (GDD: balance controls both).
    t.balance -= spec.balance * (1 - t.armor * 0.5) * (blocking ? Tuning.blockBalanceMul : 1);
    t.balanceIdle = 0;
    if (guardBroken) flags |= HitFlag.guardBreak;
    final lost = 1 - clampD(t.balance / t.maxBalance, 0, 1);
    var kb = (1 + lost * Tuning.knockFromBalance) / t.mass;
    if (t.state == FState.stunned) kb *= Tuning.knockStunnedMul;
    final armored = t.superArmor;
    if (armored) kb *= 0.45;
    if (blocking && !guardBroken) kb *= Tuning.blockKnockMul;
    t.vel.scale(0.3);
    t.vel.addScaled(dir, spec.knock * kb);
    if (spec.pop > 0 && t.grounded && !armored && !blocking) t.vz = spec.pop;

    sim.emit(SimEvent(EvType.hit,
        a: a.id, b: t.id, x: t.pos.x, y: t.pos.y, v: dmg, flags: flags));

    if (t.hp <= 0) {
      t.hp = 0;
      sim.killFighter(t, a.id, KoCause.hp);
    } else if (guardBroken) {
      t.balance = 0;
      t.setState(FState.stunned, Tuning.guardBreakStun);
      sim.emit(SimEvent(EvType.stun, b: t.id, x: t.pos.x, y: t.pos.y));
    } else if (blocking) {
      // Guard holds: no flinch.
    } else if (t.balance <= 0 && !armored && t.state != FState.stunned) {
      t.balance = 0;
      t.heavyCharge = 0;
      t.setState(FState.stunned, Tuning.stunTime);
      sim.emit(SimEvent(EvType.stun, b: t.id, x: t.pos.x, y: t.pos.y));
    } else if (!armored && spec.hitstun > 0 && t.state != FState.stunned) {
      t.heavyCharge = 0;
      t.setState(FState.hitstun, spec.hitstun);
    }
    if (t.balance < 0) t.balance = 0;
    return true;
  }

  /// Radial area hit around (cx, cy). Returns number of targets hit.
  static int aoe(MatchSimulation sim, Fighter a, double cx, double cy,
      double radius, AttackSpec spec, {bool hitsAir = false}) {
    var n = 0;
    final c = V2(cx, cy);
    for (final t in sim.fighters) {
      if (identical(t, a) || !t.alive) continue;
      if (!hitsAir && t.z > Tuning.airHitHeight) continue;
      final d = t.pos.distanceTo(c);
      if (d > radius + Tuning.fighterRadius) continue;
      final dir = d < 1e-4 ? a.facing.clone() : (t.pos - c).normalized();
      if (applyHit(sim, a, t, spec, dir)) n++;
    }
    return n;
  }

  /// Resolves active light/heavy hitboxes for this tick.
  static void resolveAttacks(MatchSimulation sim) {
    for (final a in sim.fighters) {
      if (!a.alive || a.z > Tuning.airHitHeight) continue;
      final ts = a.attackTimeScale;
      AttackSpec? spec;
      double reach = 0, radius = 0;
      if (a.state == FState.attack) {
        final w = Tuning.lightWindup * ts;
        if (a.stateTime >= w && a.stateTime <= w + Tuning.lightActive * ts) {
          spec = AttackSpec.light(a.comboStep);
          reach = Tuning.lightReach;
          radius = Tuning.lightRadius;
        }
      } else if (a.state == FState.heavyAttack) {
        final w = Tuning.heavyWindup * ts;
        if (a.stateTime >= w && a.stateTime <= w + Tuning.heavyActive * ts) {
          spec = AttackSpec.heavy(a.heavyCharge / Tuning.heavyMaxCharge);
          reach = Tuning.heavyReach;
          radius = Tuning.heavyRadius;
        }
      }
      if (spec == null) continue;
      final hx = a.pos.x + a.facing.x * reach, hy = a.pos.y + a.facing.y * reach;
      final center = V2(hx, hy);
      for (final t in sim.fighters) {
        if (identical(t, a) || !t.alive || a.hitIds.contains(t.id)) continue;
        if (t.z > Tuning.airHitHeight) continue;
        if (t.pos.distanceTo(center) > radius + Tuning.fighterRadius) continue;
        a.hitIds.add(t.id);
        final dir = (a.facing * 0.6 + (t.pos - a.pos).normalized() * 0.4).normalized();
        applyHit(sim, a, t, spec, dir);
      }
      if (!a.attackHitProps) {
        if (sim.props.hitBuckets(sim, hx, hy, radius, a.facing)) a.attackHitProps = true;
      }
    }
  }
}
