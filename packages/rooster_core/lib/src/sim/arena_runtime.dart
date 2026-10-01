/// Runtime state of arena props: water buckets, puddles, traps, food.
library;

import 'dart:math' as math;

import '../data/arenas.dart';
import '../data/tuning.dart';
import '../math/vec2.dart';
import 'events.dart';
import 'fighter.dart';
import 'match_sim.dart';

class BucketState {
  final int prop;
  bool spilled = false;
  double timer = 0;
  BucketState(this.prop);
}

class TrapState {
  final int prop;
  bool armed = true;
  double timer = 0;
  TrapState(this.prop);
}

class Puddle {
  final double x, y, r;
  double ttl;
  Puddle(this.x, this.y, this.r, this.ttl);
}

enum FoodKind {
  corn, // spawns on food spots: stamina + a little HP
  heal, // dropped by a fallen chicken: 30% of the eater's max HP
}

class Food {
  final int id;
  final int spot; // food-spot prop index, -1 for drops
  final double x, y;
  final FoodKind kind;
  double ttl; // drops expire
  Food(this.id, this.spot, this.x, this.y,
      {this.kind = FoodKind.corn, this.ttl = double.infinity});
}

class ArenaRuntime {
  static const bucketRespawn = 15.0;
  static const puddleTtl = 10.0;
  static const puddleRadius = 1.7;
  static const trapRearm = 8.0;
  static const trapDamage = 6.0;
  static const trapStun = 1.0;
  static const foodInterval = 7.0;
  static const maxFood = 2;

  final ArenaDef def;
  final List<BucketState> buckets = [];
  final List<TrapState> traps = [];
  final List<Puddle> puddles = [];
  final List<Food> foods = [];
  final List<int> _foodSpots = [];
  double _foodTimer = 3.0;
  int _nextFoodId = 1;

  ArenaRuntime(this.def) {
    for (var i = 0; i < def.props.length; i++) {
      switch (def.props[i].type) {
        case PropType.bucket:
          buckets.add(BucketState(i));
        case PropType.trap:
          traps.add(TrapState(i));
        case PropType.food:
          _foodSpots.add(i);
        case PropType.fan:
        case PropType.pillar:
          break;
      }
    }
  }

  void update(MatchSimulation sim, double dt) {
    for (final b in buckets) {
      if (b.spilled && (b.timer -= dt) <= 0) b.spilled = false;
    }
    for (final t in traps) {
      if (!t.armed && (t.timer -= dt) <= 0) t.armed = true;
    }
    puddles.removeWhere((p) => (p.ttl -= dt) <= 0);
    foods.removeWhere((f) => f.kind == FoodKind.heal && (f.ttl -= dt) <= 0);
    final corn = foods.where((f) => f.kind == FoodKind.corn).length;
    if (_foodSpots.isNotEmpty && corn < maxFood) {
      _foodTimer -= dt;
      if (_foodTimer <= 0) {
        _foodTimer = foodInterval;
        final free = _foodSpots.where((s) => !foods.any((f) => f.spot == s)).toList();
        if (free.isNotEmpty) {
          final spot = sim.rng.pick(free);
          final p = def.props[spot];
          foods.add(Food(_nextFoodId++, spot, p.x, p.y));
        }
      }
    }
  }

  /// Heal left by a fallen chicken ([from] = its id, for the drop fx).
  void dropHeal(MatchSimulation sim, double x, double y, [int from = -1]) {
    if (sim.phase != MatchPhase.fighting) return;
    foods.add(Food(_nextFoodId++, -1, x, y,
        kind: FoodKind.heal, ttl: Tuning.healDropTtl));
    sim.emit(SimEvent(EvType.healDrop, b: from, x: x, y: y));
  }

  bool slipperyAt(double x, double y) {
    for (final p in puddles) {
      final dx = x - p.x, dy = y - p.y;
      if (dx * dx + dy * dy < p.r * p.r) return true;
    }
    return false;
  }

  /// Solid circular obstacles: pillars and upright buckets.
  Iterable<(double, double, double, int)> obstacles() sync* {
    for (var i = 0; i < def.props.length; i++) {
      final p = def.props[i];
      if (p.type == PropType.pillar) yield (p.x, p.y, p.radius, -1);
    }
    for (var i = 0; i < buckets.length; i++) {
      final b = buckets[i];
      if (!b.spilled) {
        final p = def.props[b.prop];
        yield (p.x, p.y, p.radius, i);
      }
    }
  }

  /// Attack hitbox vs buckets. Returns true if any bucket spilled.
  bool hitBuckets(MatchSimulation sim, double x, double y, double r, V2 dir) {
    var any = false;
    for (var i = 0; i < buckets.length; i++) {
      final b = buckets[i];
      if (b.spilled) continue;
      final p = def.props[b.prop];
      final dx = p.x - x, dy = p.y - y;
      if (dx * dx + dy * dy < math.pow(r + p.radius, 2)) {
        spill(sim, i, dir.x, dir.y);
        any = true;
      }
    }
    return any;
  }

  void spill(MatchSimulation sim, int i, double dx, double dy) {
    final b = buckets[i];
    if (b.spilled) return;
    final p = def.props[b.prop];
    b.spilled = true;
    b.timer = bucketRespawn;
    final d = V2(dx, dy).normalized();
    puddles.add(Puddle(p.x + d.x * 1.1, p.y + d.y * 1.1, puddleRadius, puddleTtl));
    sim.emit(SimEvent(EvType.spill, a: i, x: p.x, y: p.y));
  }

  /// Food pickups and traps for grounded fighters.
  void interact(MatchSimulation sim) {
    for (final f in sim.fighters) {
      if (!f.alive || !f.grounded) continue;
      for (var i = foods.length - 1; i >= 0; i--) {
        final food = foods[i];
        if (f.pos.distance2To(V2(food.x, food.y)) >= 0.36) continue;
        if (food.kind == FoodKind.heal) {
          if (f.hp >= f.maxHp) continue; // full chickens leave it be
          f.hp = math.min(f.maxHp, f.hp + f.maxHp * Tuning.healDropFraction);
        } else {
          f.stamina = math.min(f.maxStamina, f.stamina + 30);
          f.hp = math.min(f.maxHp, f.hp + 8);
          if (!f.rageActive) f.rage = math.min(Tuning.rageMax, f.rage + 5);
        }
        foods.removeAt(i);
        sim.emit(SimEvent(EvType.pickup,
            a: f.id, b: food.id, x: food.x, y: food.y, v: food.kind.index.toDouble()));
      }
      if (f.invuln > 0 || f.state == FState.fakeDead) continue;
      for (var i = 0; i < traps.length; i++) {
        final t = traps[i];
        if (!t.armed) continue;
        final p = def.props[t.prop];
        if (f.pos.distance2To(V2(p.x, p.y)) > p.radius * p.radius) continue;
        t.armed = false;
        t.timer = trapRearm;
        f.hp -= trapDamage * (1 - f.armor);
        sim.emit(SimEvent(EvType.trap, a: i, b: f.id, x: p.x, y: p.y));
        if (f.hp <= 0) {
          f.hp = 0;
          sim.killFighter(f, -1, KoCause.hp);
        } else if (!f.superArmor) {
          f.vel.set(0, 0);
          f.heavyCharge = 0;
          f.setState(FState.stunned, trapStun);
        }
      }
    }
  }
}
