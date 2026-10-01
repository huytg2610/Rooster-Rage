/// Arena physics: movement integration, knockback friction, jumps, moving
/// platforms, fences, obstacles, chicken-vs-chicken pushing, ring-outs.
library;

import 'dart:math' as math;

import '../data/arenas.dart';
import '../data/chicken_classes.dart';
import '../data/tuning.dart';
import 'fighter.dart';
import 'fighter_logic.dart';
import 'match_sim.dart';

class Physics {
  static void step(MatchSimulation sim, double dt) {
    final arena = sim.arena;
    final t0 = sim.time - dt, t1 = sim.time;
    final r = Tuning.fighterRadius;

    for (final f in sim.fighters) {
      if (f.state == FState.dead) continue;
      if (f.state == FState.falling) {
        f.vel.scale(math.pow(0.05, dt).toDouble());
        f.pos.addScaled(f.vel, dt);
        continue;
      }

      // Ride moving platforms.
      if (f.grounded) {
        final gi = arena.groundAt(f.pos.x, f.pos.y, t0);
        if (gi >= 0 && arena.grounds[gi].motion != null) {
          final g = arena.grounds[gi];
          f.pos.x += g.ox(t1) - g.ox(t0);
          f.pos.y += g.oy(t1) - g.oy(t0);
        }
      }

      final slip = f.grounded && sim.props.slipperyAt(f.pos.x, f.pos.y);
      final desired = FighterLogic.desiredVelocity(f);
      final dashing = f.state == FState.dodge || f.state == FState.skill;
      if (!dashing) {
        if (!desired.x.isNaN && f.grounded) {
          final k = math.min(1.0, (slip ? Tuning.slipAccel : Tuning.accel) * dt);
          f.vel.x += (desired.x - f.vel.x) * k;
          f.vel.y += (desired.y - f.vel.y) * k;
        } else if (f.grounded) {
          final fr = slip ? Tuning.slipFriction : Tuning.knockFriction;
          f.vel.scale(math.exp(-fr * dt));
        } else if (!desired.x.isNaN) {
          // Light air control.
          f.vel.x += (desired.x - f.vel.x) * math.min(1.0, 2.0 * dt);
          f.vel.y += (desired.y - f.vel.y) * math.min(1.0, 2.0 * dt);
        }
      }

      // Wind fans.
      for (final p in arena.props) {
        if (p.type != PropType.fan || p.fanPhase(t1) != 2) continue;
        if (!p.inFanZone(f.pos.x, f.pos.y)) continue;
        final push = p.force * dt / f.mass;
        f.vel.x += p.dirX * push;
        f.vel.y += p.dirY * push;
      }

      f.pos.addScaled(f.vel, dt);

      // Vertical.
      if (f.z > 0 || f.vz > 0) {
        f.vz -= Tuning.gravity * dt;
        f.z += f.vz * dt;
        if (f.z <= 0) {
          f.z = 0;
          f.vz = 0;
        }
      }

      if (f.z <= Tuning.wallHeight) _walls(arena, f, r);
      _obstacles(sim, f, r);
    }

    _separate(sim, r);

    // Ring-out: standing over the void. Also remember a safe spot (well
    // inside the ground) for what a fallen chicken drops.
    for (final f in sim.fighters) {
      if (!f.alive || !f.grounded) continue;
      if (!arena.isGround(f.pos.x, f.pos.y, t1)) {
        sim.startFall(f);
      } else if (arena.isGround(f.pos.x, f.pos.y, t1, 0.6)) {
        f.safePos.setFrom(f.pos);
      }
    }
  }

  static void _walls(ArenaDef arena, Fighter f, double r) {
    for (final w in arena.walls) {
      final ex = w.bx - w.ax, ey = w.by - w.ay;
      final len2 = ex * ex + ey * ey;
      var u = ((f.pos.x - w.ax) * ex + (f.pos.y - w.ay) * ey) / len2;
      u = u.clamp(0.0, 1.0);
      final cx = w.ax + ex * u, cy = w.ay + ey * u;
      final dx = f.pos.x - cx, dy = f.pos.y - cy;
      final d2 = dx * dx + dy * dy;
      if (d2 >= r * r) continue;
      final d = math.sqrt(d2);
      double nx, ny;
      if (d > 1e-6) {
        nx = dx / d;
        ny = dy / d;
      } else {
        // Exactly on the wall: push toward arena center.
        final l = math.sqrt(cx * cx + cy * cy);
        nx = l > 0 ? -cx / l : 1;
        ny = l > 0 ? -cy / l : 0;
      }
      f.pos.x = cx + nx * r;
      f.pos.y = cy + ny * r;
      final vn = f.vel.x * nx + f.vel.y * ny;
      if (vn < 0) {
        f.vel.x -= 1.4 * vn * nx;
        f.vel.y -= 1.4 * vn * ny;
      }
    }
  }

  static void _obstacles(MatchSimulation sim, Fighter f, double r) {
    if (f.z > Tuning.wallHeight) return;
    for (final (ox, oy, orad, bucket) in sim.props.obstacles()) {
      final dx = f.pos.x - ox, dy = f.pos.y - oy;
      final min = r + orad;
      final d2 = dx * dx + dy * dy;
      if (d2 >= min * min) continue;
      final d = math.max(1e-6, math.sqrt(d2));
      final nx = dx / d, ny = dy / d;
      final vn = f.vel.x * nx + f.vel.y * ny;
      if (bucket >= 0 && vn < -6) {
        // Slammed into a bucket hard enough to knock it over.
        sim.props.spill(sim, bucket, -nx, -ny);
      }
      f.pos.x = ox + nx * min;
      f.pos.y = oy + ny * min;
      if (vn < 0) {
        f.vel.x -= 1.3 * vn * nx;
        f.vel.y -= 1.3 * vn * ny;
      }
    }
  }

  /// Soft circle separation between chickens (mass weighted).
  static void _separate(MatchSimulation sim, double r) {
    final fs = sim.fighters;
    for (var i = 0; i < fs.length; i++) {
      final a = fs[i];
      if (!_solid(a)) continue;
      for (var j = i + 1; j < fs.length; j++) {
        final b = fs[j];
        if (!_solid(b)) continue;
        if ((a.z - b.z).abs() > Tuning.stackHeight) continue;
        final dx = b.pos.x - a.pos.x, dy = b.pos.y - a.pos.y;
        final d2 = dx * dx + dy * dy;
        final min = 2 * r;
        if (d2 >= min * min) continue;
        final d = math.sqrt(d2);
        final nx = d > 1e-6 ? dx / d : 1.0, ny = d > 1e-6 ? dy / d : 0.0;
        final overlap = min - d;
        final wa = b.mass / (a.mass + b.mass), wb = 1 - wa;
        a.pos.x -= nx * overlap * wa;
        a.pos.y -= ny * overlap * wa;
        b.pos.x += nx * overlap * wb;
        b.pos.y += ny * overlap * wb;
      }
    }
  }

  static bool _solid(Fighter f) {
    if (!f.alive || f.state == FState.fakeDead) return false;
    // Shadow Dash passes through chickens.
    if (f.state == FState.skill && f.def.skill == SkillId.shadowDash) return false;
    return true;
  }
}
