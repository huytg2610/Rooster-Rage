/// Authoritative match simulation (fixed 60 Hz). Runs on the host only;
/// clients receive snapshots. Pure Dart so it runs on server, web and mobile.
library;

import '../ai/bot_brain.dart';
import '../data/arenas.dart';
import '../data/tuning.dart';
import '../math/rng.dart';
import '../math/vec2.dart';
import 'arena_runtime.dart';
import 'combat.dart';
import 'events.dart';
import 'fighter.dart';
import 'fighter_logic.dart';
import 'physics.dart';

enum MatchPhase { countdown, fighting, ended }

class MatchConfig {
  final String arenaId;
  final double duration;
  final int seed;

  /// Survival rules: a KO eliminates (no respawn); the last chicken
  /// standing wins, or the match ends on time.
  final bool survival;

  const MatchConfig({
    this.arenaId = 'village',
    this.duration = 180,
    this.seed = 1,
    this.survival = false,
  });
}

class FighterResult {
  final int id;
  final int kos;
  final int deaths;
  final double damage;
  final int rank;

  const FighterResult(this.id, this.kos, this.deaths, this.damage, this.rank);

  Map<String, Object> toJson() =>
      {'id': id, 'kos': kos, 'deaths': deaths, 'dmg': damage.round(), 'rank': rank};

  static FighterResult fromJson(Map<String, dynamic> j) => FighterResult(
      j['id'] as int, j['kos'] as int, j['deaths'] as int,
      (j['dmg'] as num).toDouble(), j['rank'] as int);
}

class MatchSimulation {
  final MatchConfig config;
  final ArenaDef arena;
  late final ArenaRuntime props;
  final Rng rng;
  final List<Fighter> fighters;
  final Map<int, BotBrain> brains = {};

  int tick = 0;
  double time = 0;
  MatchPhase phase = MatchPhase.countdown;
  double phaseTime = 0;
  final List<SimEvent> _events = [];

  MatchSimulation(this.config, List<FighterSetup> setups)
      : arena = Arenas.byId(config.arenaId),
        rng = Rng(config.seed),
        fighters = [for (final s in setups) Fighter(s)] {
    props = ArenaRuntime(arena);
    for (final f in fighters) {
      f.survivalRules = config.survival;
    }
    final spawns = [...arena.spawns];
    for (var i = spawns.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final t = spawns[i];
      spawns[i] = spawns[j];
      spawns[j] = t;
    }
    for (var i = 0; i < fighters.length; i++) {
      final f = fighters[i];
      final (x, y) = spawns[i % spawns.length];
      f.resetForSpawn(x, y);
      f.invuln = 0;
      if (f.setup.isBot) setBot(f.id, true, f.setup.botLevel);
    }
  }

  static const dt = Tuning.dt;

  double get remaining => switch (phase) {
        MatchPhase.countdown => config.duration,
        MatchPhase.fighting => (config.duration - phaseTime).clamp(0.0, config.duration),
        MatchPhase.ended => 0,
      };

  double get countdownLeft =>
      phase == MatchPhase.countdown ? (Tuning.countdown - phaseTime) : 0;

  Fighter? byId(int id) {
    for (final f in fighters) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Human input. [pressed] edges accumulate until the next tick.
  void setInput(int id, double mx, double my, bool heavy, int pressed,
      {bool block = false}) {
    final f = byId(id);
    if (f == null || brains.containsKey(id)) return;
    f.input.mx = mx.clamp(-1.0, 1.0);
    f.input.my = my.clamp(-1.0, 1.0);
    f.input.heavyHeld = heavy;
    f.input.blockHeld = block;
    f.input.pressed |= pressed;
  }

  /// Hands a fighter to (or back from) the AI — used for bots and for
  /// players who disconnect mid-match.
  void setBot(int id, bool bot, [int level = 1]) {
    if (bot) {
      brains[id] = BotBrain(id, level, rng.nextU32());
    } else {
      brains.remove(id);
      byId(id)?.input.clear();
    }
  }

  void emit(SimEvent e) => _events.add(e);

  List<SimEvent> drainEvents() {
    final out = List<SimEvent>.of(_events);
    _events.clear();
    return out;
  }

  void step() {
    tick++;
    time += dt;
    phaseTime += dt;
    if (phase == MatchPhase.countdown && phaseTime >= Tuning.countdown) {
      phase = MatchPhase.fighting;
      phaseTime = 0;
    }
    final fighting = phase == MatchPhase.fighting;

    props.update(this, dt);
    if (fighting) {
      for (final b in brains.values) {
        final f = byId(b.fighterId);
        if (f != null) b.think(this, f, dt);
      }
    }
    for (final f in fighters) {
      FighterLogic.update(this, f, dt, allowActions: fighting);
    }
    Physics.step(this, dt);
    Combat.resolveAttacks(this);
    props.interact(this);
    _lifecycle();
    for (final f in fighters) {
      f.input.pressed = 0;
    }

    if (fighting &&
        (phaseTime >= config.duration ||
            (config.survival && fighters.length > 1 && standing <= 1))) {
      phase = MatchPhase.ended;
      phaseTime = 0;
    }
  }

  void startFall(Fighter f) {
    f.heavyCharge = 0;
    f.setState(FState.falling, Tuning.fallTime);
  }

  /// Credits the KO. Falls, self-inflicted and environmental deaths go to
  /// whoever hit the victim last since it respawned (damage or shove), no
  /// matter how long ago.
  void killFighter(Fighter victim, int killerId, int cause) {
    if (victim.state == FState.dead) return;
    var killer = killerId == victim.id ? -1 : killerId;
    if (killer < 0 && victim.lastAttacker >= 0) killer = victim.lastAttacker;
    victim.deaths++;
    if (killer >= 0) byId(killer)?.kos++;
    final drop = _healSpot(victim, killer);
    props.dropHeal(this, drop.x, drop.y, victim.id);
    victim.setState(FState.dead);
    victim.vel.set(0, 0);
    if (config.survival) {
      // Out for good; the timer only lets the corpse linger, then fade.
      victim.eliminated = true;
      victim.eliminatedAt = time;
      victim.respawnTimer = Tuning.respawnTime;
    } else {
      victim.respawnTimer = Tuning.respawnFor(victim.deaths);
    }
    victim.burnTime = 0;
    victim.madTime = 0;
    victim.rageTimer = 0;
    emit(SimEvent(EvType.ko,
        a: killer, b: victim.id, x: victim.pos.x, y: victim.pos.y, flags: cause));
  }

  /// Where a fallen chicken's heal lands: a step out from the body (its
  /// corpse used to hide it) and away from the killer (who'd eat it at
  /// once), always on solid ground. Falls start from the last safe spot.
  V2 _healSpot(Fighter victim, int killer) {
    final base = arena.isGround(victim.pos.x, victim.pos.y, time, 0.3)
        ? victim.pos.clone()
        : victim.safePos.clone();
    final k = killer >= 0 ? byId(killer) : null;
    final away = k == null ? V2.zero() : (base - k.pos).normalized();
    final inward = V2(-base.x, -base.y).normalized();
    for (final (dir, step) in [(away, 1.1), (inward, 1.1), (away, 0.7)]) {
      if (dir.length2 < 1e-6) continue;
      final p = base + dir * step;
      if (arena.isGround(p.x, p.y, time, 0.4)) return p;
    }
    return base;
  }

  void _lifecycle() {
    for (final f in fighters) {
      if (f.state == FState.falling) {
        f.stateTime += dt;
        if (f.stateTime >= f.stateDur) killFighter(f, -1, KoCause.ringOut);
      } else if (f.state == FState.dead && phase != MatchPhase.ended) {
        f.respawnTimer = f.respawnTimer > dt ? f.respawnTimer - dt : 0;
        if (f.respawnTimer <= 0 && !f.eliminated) _respawn(f);
      }
    }
  }

  void _respawn(Fighter f) {
    var best = arena.spawns.first;
    var bestScore = -1.0;
    for (final s in arena.spawns) {
      if (!arena.isGround(s.$1, s.$2, time, 0.3)) continue;
      var nearest = 99.0;
      for (final o in fighters) {
        if (identical(o, f) || !o.alive) continue;
        final dx = o.pos.x - s.$1, dy = o.pos.y - s.$2;
        final d = dx * dx + dy * dy;
        if (d < nearest) nearest = d;
      }
      final score = nearest + rng.nextDouble() * 2;
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    f.resetForSpawn(best.$1, best.$2);
    emit(SimEvent(EvType.respawn, a: f.id, x: f.pos.x, y: f.pos.y));
  }

  /// Chickens not yet eliminated (survival).
  int get standing => fighters.where((f) => !f.eliminated).length;

  /// Ranking: KOs desc, then deaths asc, then damage desc. Survival:
  /// whoever is still standing first, then the later someone was knocked
  /// out the better.
  List<FighterResult> results() {
    int byScore(Fighter a, Fighter b) {
      if (a.kos != b.kos) return b.kos.compareTo(a.kos);
      if (a.deaths != b.deaths) return a.deaths.compareTo(b.deaths);
      return b.damageDealt.compareTo(a.damageDealt);
    }

    int bySurvival(Fighter a, Fighter b) {
      if (a.eliminated != b.eliminated) return a.eliminated ? 1 : -1;
      if (a.eliminated && a.eliminatedAt != b.eliminatedAt) {
        return b.eliminatedAt.compareTo(a.eliminatedAt);
      }
      return byScore(a, b);
    }

    bool tied(Fighter p, Fighter f) => config.survival
        ? p.eliminated && f.eliminated && p.eliminatedAt == f.eliminatedAt
        : p.kos == f.kos && p.deaths == f.deaths;
    final sorted = [...fighters]..sort(config.survival ? bySurvival : byScore);
    final out = <FighterResult>[];
    for (var i = 0; i < sorted.length; i++) {
      final f = sorted[i];
      var rank = i + 1;
      if (i > 0 && tied(sorted[i - 1], f)) rank = out[i - 1].rank;
      out.add(FighterResult(f.id, f.kos, f.deaths, f.damageDealt, rank));
    }
    return out;
  }
}
