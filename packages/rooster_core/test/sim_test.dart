
import 'package:rooster_core/rooster_core.dart';
import 'package:test/test.dart';

FighterSetup setup(int id, String cls, {bool bot = false}) => FighterSetup(
      id: id,
      playerId: 'p$id',
      name: 'P$id',
      slot: id - 1,
      isBot: bot,
      botLevel: 2,
      classId: cls,
      variant: Variant.fire,
      rarity: Rarity.rare,
    );

void skipCountdown(MatchSimulation sim) {
  while (sim.phase == MatchPhase.countdown) {
    sim.step();
  }
}

void main() {
  test('chickens cannot act during the countdown', () {
    final sim = MatchSimulation(const MatchConfig(seed: 3), [setup(1, 'samurai')]);
    final start = sim.byId(1)!.pos.clone();
    for (var i = 0; i < 60; i++) {
      sim.setInput(1, 1, 0, false, Btn.light);
      sim.step();
    }
    expect(sim.byId(1)!.pos.distanceTo(start), lessThan(1e-6));
    expect(sim.byId(1)!.state, FState.idle);
  });

  test('walking out of a village fence gap falls into the pond → KO credited', () {
    final sim = MatchSimulation(
        const MatchConfig(seed: 3), [setup(1, 'samurai'), setup(2, 'ninja')]);
    skipCountdown(sim);
    final victim = sim.byId(2)!;
    victim.pos.set(6.5, 0); // gap centered at 0°
    victim.lastAttacker = 1;
    victim.lastAttackerTime = sim.time;
    for (var i = 0; i < 120; i++) {
      sim.setInput(2, 1, 0, false, 0);
      sim.step();
    }
    final kos = sim.drainEvents().where((e) => e.type == EvType.ko).toList();
    expect(kos, hasLength(1));
    expect(kos.single.b, 2);
    expect(kos.single.a, 1);
    expect(kos.single.flags, KoCause.ringOut);
    expect(sim.byId(1)!.kos, 1);
    expect(victim.deaths, 1);
  });

  test('a fall is credited to the last hitter, however long ago', () {
    final sim = MatchSimulation(
        const MatchConfig(seed: 3), [setup(1, 'samurai'), setup(2, 'ninja')]);
    skipCountdown(sim);
    final victim = sim.byId(2)!;
    victim.pos.set(6.5, 0);
    victim.lastAttacker = 1;
    victim.lastAttackerTime = sim.time - 60; // a minute ago
    for (var i = 0; i < 120; i++) {
      sim.setInput(2, 1, 0, false, 0);
      sim.step();
    }
    final ko = sim.drainEvents().singleWhere((e) => e.type == EvType.ko);
    expect(ko.a, 1);
    expect(sim.byId(1)!.kos, 1);
  });

  test('a fall nobody caused credits no one', () {
    final sim = MatchSimulation(
        const MatchConfig(seed: 3), [setup(1, 'samurai'), setup(2, 'ninja')]);
    skipCountdown(sim);
    final victim = sim.byId(2)!;
    victim.pos.set(6.5, 0);
    for (var i = 0; i < 120; i++) {
      sim.setInput(2, 1, 0, false, 0);
      sim.step();
    }
    final ko = sim.drainEvents().singleWhere((e) => e.type == EvType.ko);
    expect(ko.a, -1);
    expect(sim.byId(1)!.kos, 0);
  });

  test('dash goes (and faces) where the stick points, from the first tick', () {
    final sim = MatchSimulation(
        const MatchConfig(seed: 3), [setup(1, 'samurai'), setup(2, 'ninja')]);
    skipCountdown(sim);
    final f = sim.byId(1)!;
    for (var i = 0; i < 20; i++) {
      sim.setInput(1, 0, 1, false, 0); // run down
      sim.step();
    }
    sim.setInput(1, 0, -1, false, Btn.dodge); // turn up + dash, same tick
    sim.step();
    expect(f.state, FState.dodge);
    expect(f.dashDir.y, closeTo(-1, 1e-9));
    expect(f.facing.y, closeTo(-1, 1e-9));
    expect(f.vel.y, lessThan(-Tuning.dodgeSpeed * 0.9));
  });

  group('fast button switching', () {
    MatchSimulation duo() {
      final sim = MatchSimulation(const MatchConfig(seed: 3),
          [setup(1, 'samurai'), setup(2, 'ninja')]);
      skipCountdown(sim);
      sim.byId(2)!.pos.set(-5, 0); // out of reach
      return sim;
    }

    void run(MatchSimulation sim, int ticks, [int pressed = 0]) {
      for (var i = 0; i < ticks; i++) {
        sim.setInput(1, 0, 0, false, i == 0 ? pressed : 0);
        sim.step();
      }
    }

    test('the latest press wins; an older one never fires late', () {
      final sim = duo();
      final f = sim.byId(1)!;
      f.setState(FState.hitstun, 0.5);
      run(sim, 3, Btn.dodge); // pressed while unable to act...
      for (var i = 0; i < 5; i++) {
        run(sim, 6, Btn.light); // ...then mashing J
      }
      run(sim, 6);
      expect(f.state, isNot(FState.dodge));
      expect(f.comboStep, greaterThan(0)); // the J press acted
    });

    test('dash cancels light-attack recovery at once', () {
      final sim = duo();
      final f = sim.byId(1)!;
      run(sim, 1, Btn.light);
      while (f.state != FState.recovery) {
        run(sim, 1);
      }
      run(sim, 1, Btn.dodge);
      expect(f.state, FState.dodge);
    });

    test('heavy recovery only cancels in its second half', () {
      final sim = duo();
      final f = sim.byId(1)!;
      f.setState(FState.heavyAttack);
      while (f.state != FState.recovery) {
        run(sim, 1);
      }
      run(sim, 1, Btn.dodge);
      expect(f.state, FState.recovery); // buffered, not yet
      var ticks = 0;
      while (f.state == FState.recovery) {
        run(sim, 1);
        ticks++;
      }
      expect(f.state, FState.dodge);
      expect(ticks * Tuning.dt, lessThan(Tuning.heavyRecovery * 0.6));
    });

    test('U without rage is no free way out of recovery', () {
      final sim = duo();
      final f = sim.byId(1)!;
      run(sim, 1, Btn.light);
      while (f.state != FState.recovery) {
        run(sim, 1);
      }
      run(sim, 1, Btn.skill);
      expect(f.state, FState.recovery);
    });
  });

  group('heal drops & respawn', () {
    MatchSimulation duo() {
      final sim = MatchSimulation(const MatchConfig(seed: 3),
          [setup(1, 'samurai'), setup(2, 'ninja')]);
      skipCountdown(sim);
      return sim;
    }

    test('a KO drops a heal that restores 30% to a hurt chicken', () {
      final sim = duo();
      final a = sim.byId(1)!, v = sim.byId(2)!;
      v.pos.set(2, 0);
      a.pos.set(1, 0);
      sim.killFighter(v, 1, KoCause.hp);
      final heal = sim.props.foods.singleWhere((f) => f.kind == FoodKind.heal);
      // Popped out from under the corpse, away from the killer.
      expect(heal.x, greaterThan(2.6));
      expect(sim.drainEvents().map((e) => e.type), contains(EvType.healDrop));

      a.hp = a.maxHp * 0.5;
      a.pos.set(heal.x, heal.y);
      sim.props.interact(sim);
      expect(a.hp, closeTo(a.maxHp * 0.8, 1e-6));
      expect(sim.props.foods.where((f) => f.kind == FoodKind.heal), isEmpty);
      final pick = sim.drainEvents().lastWhere((e) => e.type == EvType.pickup);
      expect(pick.v, FoodKind.heal.index);
    });

    test('a full-HP chicken leaves the heal; it expires', () {
      final sim = duo();
      final a = sim.byId(1)!, v = sim.byId(2)!;
      v.pos.set(2, 0);
      sim.killFighter(v, 1, KoCause.hp);
      final heal = sim.props.foods.singleWhere((f) => f.kind == FoodKind.heal);
      a.pos.set(heal.x, heal.y);
      sim.props.interact(sim);
      expect(sim.props.foods.where((f) => f.kind == FoodKind.heal), hasLength(1));
      a.pos.set(-3, 0);
      for (var i = 0; i < (Tuning.healDropTtl * 60).ceil() + 2; i++) {
        sim.step();
      }
      expect(sim.props.foods.where((f) => f.kind == FoodKind.heal), isEmpty);
    });

    test('a ring-out drops its heal back on safe ground', () {
      final sim = duo();
      final v = sim.byId(2)!;
      v.pos.set(6.5, 0); // gap → pond
      for (var i = 0; i < 120 && v.state != FState.dead; i++) {
        sim.setInput(2, 1, 0, false, 0);
        sim.step();
      }
      expect(v.state, FState.dead);
      final heal = sim.props.foods.singleWhere((f) => f.kind == FoodKind.heal);
      expect(sim.arena.isGround(heal.x, heal.y, sim.time, 0.3), isTrue);
    });

    test('each death waits longer to respawn, capped', () {
      expect(Tuning.respawnFor(1), Tuning.respawnTime);
      expect(Tuning.respawnFor(2), Tuning.respawnTime + Tuning.respawnPerDeath);
      expect(Tuning.respawnFor(50), Tuning.respawnMax);
      final sim = duo();
      final v = sim.byId(2)!;
      for (var d = 1; d <= 3; d++) {
        sim.killFighter(v, 1, KoCause.hp);
        expect(v.respawnTimer, Tuning.respawnFor(d));
        while (v.state == FState.dead) {
          sim.step();
        }
      }
    });
  });

  group('survival mode (no respawn)', () {
    MatchSimulation trio() {
      final sim = MatchSimulation(
          const MatchConfig(seed: 3, survival: true),
          [setup(1, 'samurai'), setup(2, 'ninja'), setup(3, 'tank')]);
      skipCountdown(sim);
      return sim;
    }

    test('a KO eliminates for good', () {
      final sim = trio();
      final v = sim.byId(2)!;
      sim.killFighter(v, 1, KoCause.hp);
      for (var i = 0; i < 60 * 10; i++) {
        sim.step();
      }
      expect(v.state, FState.dead);
      expect(v.eliminated, isTrue);
      expect(v.flags & FFlag.out, isNonZero);
      expect(sim.phase, MatchPhase.fighting); // two still standing
    });

    test('the last chicken standing ends the match and ranks first', () {
      final sim = trio();
      sim.killFighter(sim.byId(2)!, 1, KoCause.hp);
      for (var i = 0; i < 30; i++) {
        sim.step();
      }
      sim.killFighter(sim.byId(3)!, -1, KoCause.ringOut);
      sim.step();
      expect(sim.phase, MatchPhase.ended);
      final r = {for (final x in sim.results()) x.id: x.rank};
      expect(r[1], 1); // survivor
      expect(r[3], 2); // knocked out last
      expect(r[2], 3); // knocked out first
    });

    test('lobby setting travels to the match config', () {
      final s = LobbySettings.fromJson(
          const LobbySettings(survival: true).toJson());
      expect(s.survival, isTrue);
      expect(LobbySettings.fromJson(const {}).survival, isFalse);
    });

    test('normal mode still respawns', () {
      final sim = MatchSimulation(
          const MatchConfig(seed: 3), [setup(1, 'samurai'), setup(2, 'ninja')]);
      skipCountdown(sim);
      final v = sim.byId(2)!;
      sim.killFighter(v, 1, KoCause.hp);
      for (var i = 0; i < 60 * 5; i++) {
        sim.step();
      }
      expect(v.alive, isTrue);
      expect(v.eliminated, isFalse);
    });
  });

  test('fences block walking out between gaps', () {
    final sim = MatchSimulation(const MatchConfig(seed: 3), [setup(1, 'tank')]);
    skipCountdown(sim);
    final f = sim.byId(1)!;
    f.pos.set(5, 5); // 45° — middle of a fence arc
    for (var i = 0; i < 180; i++) {
      sim.setInput(1, 0.7, 0.7, false, 0);
      sim.step();
    }
    expect(f.alive, isTrue);
    expect(f.pos.length, lessThan(7.2));
  });

  test('dead fighters respawn with invulnerability', () {
    final sim = MatchSimulation(const MatchConfig(seed: 3), [setup(1, 'tank'), setup(2, 'ninja')]);
    skipCountdown(sim);
    final f = sim.byId(2)!;
    sim.killFighter(f, 1, KoCause.hp);
    expect(f.state, FState.dead);
    for (var i = 0; i < (Tuning.respawnTime * 60).ceil() + 2; i++) {
      sim.step();
    }
    expect(f.alive, isTrue);
    expect(f.hp, f.maxHp);
    expect(f.invuln, greaterThan(0));
  });

  test('temple moving platforms carry chickens standing on them', () {
    final sim = MatchSimulation(const MatchConfig(arenaId: 'temple', seed: 3), [setup(1, 'tank')]);
    skipCountdown(sim);
    final f = sim.byId(1)!;
    final g = sim.arena.grounds[3];
    f.pos.set(g.centerX(sim.time), g.centerY(sim.time));
    for (var i = 0; i < 90; i++) {
      sim.step();
    }
    expect(f.alive, isTrue);
    expect(f.pos.y, closeTo(g.centerY(sim.time), 0.05));
  });

  for (final arena in ['village', 'rooftop', 'temple']) {
    test('8-bot smoke match on $arena runs to the end and produces KOs', () {
      final classes = ChickenClasses.all.map((c) => c.id).toList();
      final sim = MatchSimulation(MatchConfig(arenaId: arena, duration: 90, seed: 11), [
        for (var i = 1; i <= 8; i++) setup(i, classes[i % classes.length], bot: true),
      ]);
      var kos = 0;
      var guard = 0;
      while (sim.phase != MatchPhase.ended && guard++ < 60 * 120) {
        sim.step();
        kos += sim.drainEvents().where((e) => e.type == EvType.ko).length;
        for (final f in sim.fighters) {
          expect(f.pos.x.isFinite && f.pos.y.isFinite, isTrue);
        }
      }
      expect(sim.phase, MatchPhase.ended);
      expect(kos, greaterThan(0));
      final results = sim.results();
      expect(results.first.rank, 1);
      expect(results.map((r) => r.id).toSet(), hasLength(8));
    });
  }

  test('binary snapshots: keyframe + delta chain rebuilds the state', () {
    final sim = MatchSimulation(
        const MatchConfig(seed: 5), [setup(1, 'samurai', bot: true), setup(2, 'troll', bot: true)]);
    final enc = SnapshotEncoder(), dec = SnapshotDecoder();
    MatchSnap? snap;
    for (var i = 0; i < 400; i++) {
      sim.step();
      if (sim.tick.isEven) snap = dec.decode(enc.encode(sim, sim.drainEvents()));
    }
    final f = sim.byId(1)!;
    final s = snap!.fighter(1)!;
    expect(s.x, closeTo(f.pos.x, 0.01));
    expect(s.y, closeTo(f.pos.y, 0.01));
    expect(s.hp, closeTo(f.hp, 1));
    expect(s.state, f.state);
    expect(s.stateTime, closeTo(f.stateTime, Tuning.dt * 1.5));
    expect(snap.tick, sim.tick);
  });

  test('bots chase and hit an idle human (regression: props mistaken for fans)', () {
    final sim = MatchSimulation(const MatchConfig(duration: 30, seed: 3), [
      setup(1, 'samurai'),
      setup(2, 'samurai', bot: true),
    ]);
    for (final p in sim.arena.props.where((p) => p.type != PropType.fan)) {
      expect(p.inFanZone(p.x, p.y), isFalse);
    }
    var hitsOnHuman = 0;
    while (sim.phase != MatchPhase.ended) {
      sim.step();
      hitsOnHuman += sim.drainEvents().where((e) => e.type == EvType.hit && e.b == 1).length;
    }
    expect(hitsOnHuman, greaterThan(5));
  });
}
