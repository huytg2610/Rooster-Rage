/// Per-fighter state machine: timers, resources, input → actions (GDD §9).
library;

import 'dart:math' as math;

import '../data/tuning.dart';
import '../math/vec2.dart';
import 'combat.dart';
import 'events.dart';
import 'fighter.dart';
import 'input.dart';
import 'match_sim.dart';
import 'skills.dart';

class FighterLogic {
  static void update(MatchSimulation sim, Fighter f, double dt,
      {required bool allowActions}) {
    _timers(sim, f, dt);
    if (!f.alive) return;
    f.stateTime += dt;

    final input = f.input;
    if (!allowActions) input.clear();
    if (f.confuseTime > 0) {
      input.mx = -input.mx;
      input.my = -input.my;
    }
    if (input.pressed != 0) {
      // Latest press wins: quickly switching buttons does the last one,
      // and an old buffered press can't fire late because newer presses
      // kept refreshing its timer.
      f.bufferedPress = input.pressed;
      f.bufferTime = Tuning.inputBuffer;
    } else if (f.bufferTime > 0) {
      f.bufferTime -= dt;
      if (f.bufferTime <= 0) f.bufferedPress = 0;
    }

    final ts = f.attackTimeScale;
    switch (f.state) {
      case FState.idle:
      case FState.run:
        if (!_tryActions(sim, f)) {
          final moving = input.mx * input.mx + input.my * input.my > 0.04;
          final s = moving ? FState.run : FState.idle;
          if (s != f.state) f.setState(s);
        }
      case FState.attack:
        final end = (Tuning.lightWindup + Tuning.lightActive) * ts;
        if (f.stateTime >= end) _toRecovery(f, Tuning.lightRecovery * ts);
      case FState.heavyCharge:
        f.heavyCharge = math.min(Tuning.heavyMaxCharge, f.heavyCharge + dt);
        if (f.bufferedPress & Btn.dodge != 0) {
          f.heavyCharge = 0;
          _startDodge(sim, f);
        } else if (!input.heavyHeld) {
          final c = f.heavyCharge / Tuning.heavyMaxCharge;
          _beginAttack(f);
          f.spendStamina(lerpD(Tuning.heavyStaminaMin, Tuning.heavyStaminaMax, c),
              attack: true);
          f.setState(FState.heavyAttack);
          f.vel.addScaled(f.facing, 2.0 + 3.0 * c);
        }
      case FState.heavyAttack:
        final end = (Tuning.heavyWindup + Tuning.heavyActive) * ts;
        if (f.stateTime >= end) _toRecovery(f, Tuning.heavyRecovery * ts);
      case FState.recovery:
        final fromLight = f.recoveringFrom == FState.attack;
        if (fromLight && f.bufferedPress & Btn.light != 0 && f.comboStep < 3) {
          f.bufferedPress &= ~Btn.light;
          _startLight(sim, f);
        } else if (_canCancelRecovery(f) && _cancelRecovery(sim, f)) {
          // Dodge / guard / ultimate cut the recovery short.
        } else if (f.stateTime >= f.stateDur) {
          f.comboStep = 0;
          f.setState(FState.idle);
          _tryActions(sim, f);
        }
      case FState.jump:
        if (f.stateTime > 0.05 && f.grounded) {
          f.attackStaminaMul = f.staminaMul;
          final ahead = f.facing * 0.35;
          Combat.aoe(sim, f, f.pos.x + ahead.x, f.pos.y + ahead.y,
              Tuning.jumpRadius, AttackSpec.jumpLand);
          sim.emit(SimEvent(EvType.land, a: f.id, x: f.pos.x, y: f.pos.y, v: 1));
          f.vel.scale(0.3);
          _toRecovery(f, Tuning.landRecovery);
        }
      case FState.dodge:
        f.vel.setFrom(f.dashDir * Tuning.dodgeSpeed);
        if (f.stateTime >= Tuning.dodgeTime) {
          f.vel.scale(0.35);
          _toRecovery(f, Tuning.dodgeRecovery);
        }
      case FState.hitstun:
      case FState.exhausted:
        if (f.stateTime >= f.stateDur) f.setState(FState.idle);
      case FState.stunned:
        if (f.stateTime >= f.stateDur) {
          f.balance = f.maxBalance;
          f.setState(FState.idle);
        }
      case FState.skill:
      case FState.fakeDead:
        Skills.update(sim, f, dt);
      case FState.crow:
      case FState.rageRoar:
        Skills.updateShout(sim, f);
      case FState.block:
        // Hold to guard; dodge or rage cancel it.
        final cancel =
            f.bufferedPress & (Btn.dodge | Btn.rage | Btn.skill) != 0;
        if (!input.blockHeld || cancel || f.shieldBroken) {
          f.setState(FState.idle);
          _tryActions(sim, f);
        }
      case FState.falling:
      case FState.dead:
        break;
    }
    f.heavyWasHeld = input.heavyHeld;
    _updateFacing(f, input);
  }

  /// Desired ground velocity from input for the current state (m/s).
  static V2 desiredVelocity(Fighter f) {
    final factor = switch (f.state) {
      FState.idle || FState.run => 1.0,
      FState.heavyCharge => Tuning.heavyChargeMove,
      FState.block => Tuning.blockMove,
      FState.exhausted => Tuning.exhaustedMove,
      FState.attack => 0.3,
      FState.recovery => f.recoveringFrom == FState.attack ? 0.4 : 0.2,
      FState.crow || FState.rageRoar => 0.15,
      _ => -1.0, // no control
    };
    if (factor < 0) return V2(double.nan, 0);
    final v = V2(f.input.mx, f.input.my)..clampLength(1);
    var speed = f.moveSpeed * factor;
    if (f.rageActive) speed *= Tuning.rageSpeedMul;
    if (f.isMad) speed *= 1.1;
    return v..scale(speed);
  }

  static void _timers(MatchSimulation sim, Fighter f, double dt) {
    if (f.skillCd > 0) f.skillCd = math.max(0, f.skillCd - dt);
    if (f.crowCd > 0) f.crowCd = math.max(0, f.crowCd - dt);
    if (f.invuln > 0) f.invuln = math.max(0, f.invuln - dt);
    if (f.rageTimer > 0) f.rageTimer = math.max(0, f.rageTimer - dt);
    if (f.confuseTime > 0) f.confuseTime = math.max(0, f.confuseTime - dt);
    if (f.empoweredTime > 0) f.empoweredTime = math.max(0, f.empoweredTime - dt);
    if (!f.alive) return;
    if (f.madTime > 0) {
      f.madTime = math.max(0, f.madTime - dt);
      f.hp = math.max(1, f.hp - Skills.madDrain * dt);
    }
    if (f.burnTime > 0) {
      f.burnTime = math.max(0, f.burnTime - dt);
      f.hp -= Tuning.burnDps * dt;
      if (f.hp <= 0) {
        f.hp = 0;
        sim.killFighter(f, f.burnSource, KoCause.hp);
        return;
      }
    }
    // Stamina regen — the core "don't spam" resource.
    f.staminaIdle += dt;
    final spending = f.state == FState.heavyCharge || f.state == FState.block;
    if (f.staminaIdle > Tuning.staminaRegenDelay && !spending) {
      final mul = f.staminaRegenMul * (f.rageActive ? 2 : 1);
      f.stamina = math.min(f.maxStamina, f.stamina + Tuning.staminaRegen * mul * dt);
    }
    // Guard shield mends after a pause, at the chicken's guard rating; a
    // shattered one can be raised again once it is back to a quarter.
    f.shieldIdle += dt;
    if (f.shieldIdle > Tuning.shieldRegenDelay && f.shield < Tuning.shieldMax) {
      f.shield = math.min(Tuning.shieldMax,
          f.shield + Tuning.shieldMax / f.shieldRegenTime * dt);
    }
    if (f.shieldBroken && f.shield >= Tuning.shieldMax * Tuning.shieldRaiseMin) {
      f.shieldBroken = false;
    }
    f.balanceIdle += dt;
    if (f.balanceIdle > Tuning.balanceRegenDelay && f.state != FState.stunned) {
      f.balance = math.min(
          f.maxBalance, f.balance + Tuning.balanceRegen * f.balanceRegenMul * dt);
    }
  }

  /// Tries buffered actions in priority order. Returns true if one started.
  static bool _tryActions(MatchSimulation sim, Fighter f) {
    if (f.stamina <= 0.01 && !f.isMad) {
      f.setState(FState.exhausted, Tuning.exhaustedTime);
      f.bufferedPress = 0;
      sim.emit(SimEvent(EvType.exhausted, a: f.id, x: f.pos.x, y: f.pos.y));
      return true;
    }
    final b = f.bufferedPress;
    bool take(int bit) {
      f.bufferedPress &= ~bit;
      return true;
    }

    if (b & Btn.rage != 0) {
      f.bufferedPress &= ~Btn.rage;
      if (Skills.tryRage(sim, f)) return true;
    }
    if (b & Btn.dodge != 0) {
      _startDodge(sim, f);
      return take(Btn.dodge);
    }
    // Guard has priority over attacks while K / THỦ is held (and the
    // shield isn't shattered).
    if (f.input.blockHeld && !f.shieldBroken) {
      f.heavyCharge = 0;
      f.setState(FState.block);
      return true;
    }
    if (b & Btn.skill != 0) {
      _autoAim(sim, f, 4.5);
      if (Skills.tryRageSkill(sim, f)) return take(Btn.skill);
      f.bufferedPress &= ~Btn.skill;
    }
    if (b & Btn.crow != 0) {
      f.bufferedPress &= ~Btn.crow;
      if (Skills.tryCrow(sim, f)) return true;
    }
    if (b & Btn.jump != 0) {
      _startJump(sim, f);
      return take(Btn.jump);
    }
    if (b & Btn.light != 0) {
      f.comboStep = 0;
      _startLight(sim, f);
      return take(Btn.light);
    }
    if (f.input.heavyHeld && f.stamina > 1) {
      _autoAim(sim, f, 2.4);
      f.heavyCharge = 0;
      f.setState(FState.heavyCharge);
      return true;
    }
    return false;
  }

  static void _beginAttack(Fighter f) {
    f.attackStaminaMul = f.staminaMul;
    f.hitIds.clear();
    f.attackHitProps = false;
  }

  static void _startLight(MatchSimulation sim, Fighter f) {
    _autoAim(sim, f, 2.2);
    _beginAttack(f);
    f.comboStep += 1;
    f.spendStamina(Tuning.lightStamina, attack: true);
    f.setState(FState.attack);
    f.vel.addScaled(f.facing, 1.2);
  }

  static void _startJump(MatchSimulation sim, Fighter f) {
    _autoAim(sim, f, 3.2);
    _beginAttack(f);
    f.spendStamina(Tuning.jumpStamina, attack: true);
    f.vz = Tuning.jumpVz;
    f.vel.setFrom(f.facing * Tuning.jumpForward);
    f.setState(FState.jump);
  }

  /// Recovery after a light attack can be cancelled at once; after a heavy
  /// (or a jump landing) only in its second half, so whiffing a heavy
  /// still leaves an opening. Dash recovery never (no dash chains).
  static bool _canCancelRecovery(Fighter f) {
    final from = f.recoveringFrom;
    if (from == FState.dodge) return false;
    if (from == FState.attack) return true;
    return f.stateTime >= f.stateDur * 0.5;
  }

  static bool _cancelRecovery(MatchSimulation sim, Fighter f) {
    final b = f.bufferedPress;
    // Only for actions that will actually start — a U press without rage
    // must not be a free way out of recovery.
    final rageReady = f.rage >= Tuning.rageMax && !f.rageActive;
    final skillReady = f.rageActive ? f.skillCd <= 0 : rageReady;
    final wants = b & Btn.dodge != 0 ||
        (f.input.blockHeld && !f.shieldBroken) ||
        (b & Btn.skill != 0 && skillReady) ||
        (b & Btn.rage != 0 && rageReady);
    if (!wants) return false;
    if (f.stamina <= 0.01 && !f.isMad) return false;
    f.comboStep = 0;
    f.setState(FState.idle);
    return _tryActions(sim, f);
  }

  static void _startDodge(MatchSimulation sim, Fighter f) {
    // Dash where the stick points (turning to face it, so it never looks
    // like a backstep); with no direction held it's a hop back.
    final inDir = V2(f.input.mx, f.input.my);
    if (inDir.length2 > 0.04) {
      f.dashDir.setFrom(inDir.normalized());
      f.facing.setFrom(f.dashDir);
    } else {
      f.dashDir.setFrom(f.facing * -1);
    }
    // Full dash speed from the first tick — no leftover run momentum.
    f.vel.setFrom(f.dashDir * Tuning.dodgeSpeed);
    f.spendStamina(Tuning.dodgeStamina);
    f.invuln = math.max(f.invuln, Tuning.dodgeIFrames);
    f.setState(FState.dodge);
    sim.emit(SimEvent(EvType.dodge, a: f.id, x: f.pos.x, y: f.pos.y));
  }

  static void _toRecovery(Fighter f, double dur) {
    f.recoveringFrom = f.state;
    f.setState(FState.recovery, dur);
  }

  /// Mobile aim assist: snap facing to the nearest enemy inside a cone.
  static void _autoAim(MatchSimulation sim, Fighter f, double range) {
    final inDir = V2(f.input.mx, f.input.my);
    final aim = inDir.length2 > 0.04 ? inDir.normalized() : f.facing.clone();
    Fighter? best;
    var bestScore = double.infinity;
    for (final t in sim.fighters) {
      if (identical(t, f) || !t.alive || t.state == FState.fakeDead) continue;
      final d = t.pos - f.pos;
      final dist = d.length;
      if (dist > range || dist < 1e-4) continue;
      final cos = d.dot(aim) / dist;
      if (cos < 0.34) continue; // ~70° half-cone
      final score = dist * (2 - cos);
      if (score < bestScore) {
        bestScore = score;
        best = t;
      }
    }
    if (best != null) {
      f.facing.setFrom((best.pos - f.pos).normalized());
    } else {
      f.facing.setFrom(aim);
    }
  }

  static void _updateFacing(Fighter f, InputState input) {
    final turnable = f.state == FState.idle ||
        f.state == FState.run ||
        f.state == FState.heavyCharge ||
        f.state == FState.block ||
        f.state == FState.exhausted;
    if (!turnable) return;
    if (input.mx * input.mx + input.my * input.my < 0.04) return;
    final target = V2(input.mx, input.my).normalized();
    if (f.state == FState.heavyCharge || f.state == FState.block) {
      final a = lerpAngle(f.facing.angle, target.angle, 0.12);
      f.facing.set(math.cos(a), math.sin(a));
    } else {
      f.facing.setFrom(target);
    }
  }
}
