import 'package:rooster_core/rooster_core.dart';
import 'package:test/test.dart';

FighterSetup setup(int id, String cls, {double x = 0}) => FighterSetup(
      id: id,
      playerId: 'p$id',
      name: 'P$id',
      slot: id - 1,
      isBot: false,
      classId: cls,
      variant: Variant.water, // no damage/hp modifiers
      rarity: Rarity.common,
    );

MatchSimulation duel(String a, String b) {
  final sim = MatchSimulation(
      const MatchConfig(duration: 60, seed: 7), [setup(1, a), setup(2, b)]);
  // Skip countdown.
  while (sim.phase == MatchPhase.countdown) {
    sim.step();
  }
  return sim;
}

void main() {
  group('GDD stamina multiplier', () {
    test('100% → 1.0, 50% → 0.7, 0% → 0.4', () {
      expect(Fighter.staminaMultiplier(100, 100), closeTo(1.0, 1e-9));
      expect(Fighter.staminaMultiplier(50, 100), closeTo(0.7, 1e-9));
      expect(Fighter.staminaMultiplier(0, 100), closeTo(0.4, 1e-9));
    });

    test('final damage = base * stamina * rage * hit', () {
      expect(Combat.finalDamage(10, 0.7, 1.3, 1.25), closeTo(11.375, 1e-9));
    });
  });

  group('applyHit', () {
    test('armor reduces damage, rage builds on both sides', () {
      final sim = duel('samurai', 'tank');
      final a = sim.byId(1)!, t = sim.byId(2)!;
      a.pos.set(0, 0);
      t.pos.set(1, 0);
      t.facing.set(-1, 0); // facing attacker: no backstab
      a.attackStaminaMul = 1;
      Combat.applyHit(sim, a, t, const AttackSpec(damage: 10, knock: 0, balance: 0, hitstun: 0.1),
          V2(1, 0));
      expect(t.armor, greaterThan(0));
      expect(t.maxHp - t.hp, closeTo(10 * (1 - t.armor), 1e-6));
      expect(a.rage, greaterThan(0));
      expect(t.rage, greaterThan(a.rage));
      expect(t.lastAttacker, a.id);
    });

    test('backstab multiplies damage', () {
      final sim = duel('samurai', 'ninja');
      final a = sim.byId(1)!, t = sim.byId(2)!;
      a.pos.set(0, 0);
      t.pos.set(1, 0);
      t.facing.set(1, 0); // facing away
      a.attackStaminaMul = 1;
      Combat.applyHit(sim, a, t, const AttackSpec(damage: 10, knock: 0, balance: 0, hitstun: 0.1),
          V2(1, 0));
      expect(t.maxHp - t.hp, closeTo(10 * 1.25, 1e-6)); // samurai power 1.0
    });

    test('draining balance to zero stuns and boosts knockback', () {
      final sim = duel('samurai', 'ninja');
      final a = sim.byId(1)!, t = sim.byId(2)!;
      t.facing.set(-1, 0);
      t.pos.set(a.pos.x + 1, a.pos.y);
      Combat.applyHit(sim, a, t,
          const AttackSpec(damage: 1, knock: 4, balance: 500, hitstun: 0.1), V2(1, 0));
      expect(t.state, FState.stunned);
      expect(t.vel.length, greaterThan(4 / t.mass));
    });

    test('invulnerable (dodging) targets are not hit', () {
      final sim = duel('samurai', 'ninja');
      final a = sim.byId(1)!, t = sim.byId(2)!;
      t.invuln = 0.2;
      final hit = Combat.applyHit(
          sim, a, t, const AttackSpec(damage: 10, knock: 0, balance: 0, hitstun: 0), V2(1, 0));
      expect(hit, isFalse);
      expect(t.hp, t.maxHp);
    });
  });

  group('stamina management', () {
    test('spamming light attacks exhausts the chicken', () {
      final sim = duel('berserker', 'tank');
      final f = sim.byId(1)!;
      var exhausted = false;
      for (var i = 0; i < 60 * 8 && !exhausted; i++) {
        sim.setInput(1, 0, 0, false, Btn.light);
        sim.step();
        exhausted = f.state == FState.exhausted;
      }
      expect(exhausted, isTrue);
    });

    test('low stamina lowers damage dealt', () {
      final full = duel('samurai', 'samurai');
      final tired = duel('samurai', 'samurai');
      for (final sim in [full, tired]) {
        final a = sim.byId(1)!, t = sim.byId(2)!;
        t.facing.set(-1, 0);
        a.pos.set(0, 0);
        t.pos.set(1, 0);
        if (identical(sim, tired)) a.stamina = 0;
        a.attackStaminaMul = a.staminaMul;
        Combat.applyHit(sim, a, t, AttackSpec.light(1), V2(1, 0));
      }
      final dFull = full.byId(2)!.maxHp - full.byId(2)!.hp;
      final dTired = tired.byId(2)!.maxHp - tired.byId(2)!.hp;
      expect(dTired / dFull, closeTo(0.4, 1e-6));
    });
  });

  group('guard (K)', () {
    test('blocking still loses HP, just less, and does not flinch', () {
      final open = duel('samurai', 'samurai');
      final guard = duel('samurai', 'samurai');
      for (final sim in [open, guard]) {
        final a = sim.byId(1)!, t = sim.byId(2)!;
        a.pos.set(0, 0);
        t.pos.set(1, 0);
        t.facing.set(-1, 0);
        a.attackStaminaMul = 1;
        if (identical(sim, guard)) t.setState(FState.block);
        Combat.applyHit(sim, a, t, AttackSpec.heavy(1), V2(1, 0));
      }
      final tOpen = open.byId(2)!, tGuard = guard.byId(2)!;
      final lostOpen = tOpen.maxHp - tOpen.hp, lostGuard = tGuard.maxHp - tGuard.hp;
      expect(lostGuard, greaterThan(0));
      expect(lostGuard / lostOpen, closeTo(Tuning.blockDamageMul, 1e-6));
      expect(tGuard.state, FState.block);
      expect(tGuard.vel.length, lessThan(tOpen.vel.length));
      // The shield soaks the raw hit; stamina is untouched.
      expect(tGuard.shield, closeTo(Tuning.shieldMax - lostOpen, 1e-6));
      expect(tGuard.stamina, tGuard.maxStamina);
    });

    test('an empty shield shatters: stun, no guard until it mends a quarter',
        () {
      final sim = duel('ninja', 'samurai');
      final a = sim.byId(1)!, t = sim.byId(2)!;
      t.facing.set(-1, 0);
      t.pos.set(a.pos.x + 1, a.pos.y);
      t.setState(FState.block);
      t.shield = 2;
      Combat.applyHit(sim, a, t, AttackSpec.light(1), V2(1, 0));
      final events = sim.drainEvents();
      expect(t.state, FState.stunned);
      expect(events.first.flags & HitFlag.guardBreak, isNonZero);
      expect(t.shieldBroken, isTrue);

      // Holding K does nothing until the shield is back to a quarter.
      a.pos.set(-6, 0); // out of the way
      var ticks = 0;
      while (t.shieldBroken) {
        sim.setInput(2, 0, 0, false, 0, block: true);
        sim.step();
        ticks++;
        if (t.shieldBroken) expect(t.state, isNot(FState.block));
      }
      final expected = Tuning.shieldRegenDelay +
          Tuning.shieldRaiseMin * t.shieldRegenTime;
      expect(ticks * Tuning.dt, closeTo(expected, 0.05));
      sim.setInput(2, 0, 0, false, 0, block: true);
      sim.step();
      expect(t.state, FState.block);
    });

    test('sturdier chickens mend their shield faster', () {
      double regen(String id) =>
          Tuning.shieldRegenTime / Fighter.guardRatingOf(ChickenClasses.byId(id));
      expect(regen('tank'), lessThan(regen('samurai')));
      expect(regen('samurai'), lessThan(regen('bantam')));
      expect(regen('dongtao'), lessThan(regen('ninja')));
    });

    test('a chipped shield mends after a pause', () {
      final sim = duel('ninja', 'samurai');
      final t = sim.byId(2)!;
      t.shield = 10;
      t.shieldIdle = 0;
      for (var i = 0; i < 60; i++) {
        sim.step(); // 1 s: still inside the regen delay
      }
      expect(t.shield, 10);
      for (var i = 0; i < 120; i++) {
        sim.step();
      }
      expect(t.shield, greaterThan(10));
    });

    test('holding block enters guard, releasing leaves it', () {
      final sim = duel('tank', 'ninja');
      final f = sim.byId(1)!;
      sim.setInput(1, 0, 0, false, 0, block: true);
      sim.step();
      expect(f.state, FState.block);
      sim.setInput(1, 0, 0, false, Btn.light, block: true);
      sim.step();
      expect(f.state, FState.block); // no attacking through the guard
      sim.setInput(1, 0, 0, false, 0);
      sim.step();
      expect(f.state, isNot(FState.block));
    });
  });

  group('rage-gated skills', () {
    test('U does nothing outside rage; rage unlocks it with a fresh cooldown', () {
      final sim = duel('samurai', 'tank');
      final f = sim.byId(1)!;
      expect(Skills.tryStartSkill(sim, f), isFalse);
      f.rage = Tuning.rageMax;
      f.skillCd = 5;
      expect(Skills.tryRage(sim, f), isTrue);
      expect(f.skillCd, 0);
      f.setState(FState.idle);
      expect(Skills.tryStartSkill(sim, f), isTrue);
      expect(f.skillCd,
          closeTo(f.def.skillCooldown * Tuning.rageSkillCooldownMul, 1e-9));
    });

    test('U with a full bar rages and fires the ultimate in one press', () {
      final sim = duel('samurai', 'tank');
      final f = sim.byId(1)!;
      // Empty bar: U does nothing.
      sim.setInput(1, 0, 0, false, Btn.skill);
      sim.step();
      expect(f.rageActive, isFalse);
      expect(f.state, isNot(FState.skill));

      f.rage = Tuning.rageMax;
      sim.setInput(1, 0, 0, false, Btn.skill);
      sim.step();
      expect(f.rageActive, isTrue);
      expect(f.rage, 0);
      expect(f.state, FState.skill); // no roar pause first
      expect(f.rageTimer, lessThanOrEqualTo(Tuning.rageDuration));
      expect(sim.drainEvents().map((e) => e.type), contains(EvType.rage));

      // Still raging: U again is just the skill once its cooldown is over.
      while (f.state != FState.idle && f.state != FState.run) {
        sim.setInput(1, 0, 0, false, 0);
        sim.step();
      }
      f.skillCd = 0;
      sim.setInput(1, 0, 0, false, Btn.skill);
      sim.step();
      expect(f.state, FState.skill);
    });
  });
}
