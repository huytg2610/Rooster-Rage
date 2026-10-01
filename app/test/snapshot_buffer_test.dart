import 'package:flutter_test/flutter_test.dart';
import 'package:rooster_core/rooster_core.dart';
import 'package:rooster_rage/net/snapshot_buffer.dart';

/// Real snapshots from a running sim, one every 2 ticks (30 Hz).
List<MatchSnap> snapshots(int n) {
  final sim = MatchSimulation(const MatchConfig(seed: 9), [
    for (var i = 1; i <= 3; i++)
      FighterSetup(
        id: i,
        playerId: 'b$i',
        name: 'B$i',
        slot: i,
        isBot: true,
        classId: 'ninja',
        variant: Variant.wind,
        rarity: Rarity.common,
      ),
  ]);
  while (sim.phase == MatchPhase.countdown) {
    sim.step();
  }
  final out = <MatchSnap>[];
  final enc = SnapshotEncoder(), dec = SnapshotDecoder();
  while (out.length < n) {
    sim.step();
    if (sim.tick.isEven) {
      out.add(dec.decode(enc.encode(sim, sim.drainEvents()))!);
    }
  }
  return out;
}

Map<int, FighterInfo> infos() => {
  for (var i = 1; i <= 3; i++)
    i: FighterInfo(
      id: i,
      pid: 'b$i',
      name: 'B$i',
      slot: i,
      bot: true,
      classId: 'ninja',
      variant: Variant.wind,
      rarity: Rarity.common,
      maxHp: 62.5,
      maxStamina: 60,
      maxBalance: 80,
      skillCooldown: 6,
    ),
};

void main() {
  test('clean link keeps the buffer at the minimum delay', () {
    var now = 0.0;
    final b = SnapshotBuffer(minDelay: 0.05, clock: () => now)
      ..reset(infos(), 1);
    for (final s in snapshots(90)) {
      now += 1 / 30;
      b.add(s);
      b.update(1 / 30);
    }
    expect(b.delay, closeTo(0.05, 0.005));
    expect(b.jitter, lessThan(0.005));
  });

  test('bursty WiFi grows the delay instead of starving', () {
    var now = 0.0;
    final b = SnapshotBuffer(minDelay: 0.05, clock: () => now)
      ..reset(infos(), 1);
    final snaps = snapshots(120);
    for (var i = 0; i < snaps.length; i++) {
      now += 1 / 30;
      // Every 10th packet stalls 120 ms, then the backlog arrives at once.
      final late = i % 10 == 5 ? 0.12 : 0.0;
      b.add(snaps[i]);
      if (late > 0) now += late;
      b.update(1 / 30);
    }
    expect(b.jitter, greaterThan(0.08));
    expect(b.delay, greaterThan(0.12));
  });

  /// Drives the buffer like the game: packets arrive at [arrive] (local
  /// time), frames render at 60 Hz. Returns dry-buffer episodes after warmup.
  int run(
    SnapshotBuffer b,
    List<MatchSnap> snaps,
    double Function(int) arrive, {
    double warmup = 5,
    void Function(double now)? onFrame,
  }) {
    var now = 0.0, next = 0, dry = 0;
    final end = arrive(snaps.length - 1) + 0.2;
    while (now < end) {
      now += 1 / 60;
      while (next < snaps.length && arrive(next) <= now) {
        b.add(snaps[next++]);
      }
      b.update(1 / 60);
      final n = b.takeStarved();
      if (now > warmup) dry += n;
      onFrame?.call(now);
    }
    return dry;
  }

  test('power-saving WiFi (90 ms hold every 2 s) rarely runs dry', () {
    var now = 0.0;
    final b = SnapshotBuffer(minDelay: 0.05, clock: () => now)
      ..reset(infos(), 1);
    final snaps = snapshots(30 * 30); // 30 s
    double arrive(int i) {
      final sent = i / 30 + 0.005;
      // Each 2 s, packets sent in a 90 ms window are held to its end.
      final phase = sent % 2.0;
      return phase > 1.0 && phase < 1.09 ? sent - phase + 1.09 + 0.004 : sent;
    }

    final dry = run(b, snaps, arrive, onFrame: (t) => now = t);
    // Only the first spike (before the buffer learns it) should starve.
    expect(dry, lessThanOrEqualTo(2));
    expect(b.delay, greaterThan(0.09));
  });

  test('a host clock jump re-baselines within the offset window', () {
    var now = 0.0;
    final b = SnapshotBuffer(minDelay: 0.05, clock: () => now)
      ..reset(infos(), 1);
    final snaps = snapshots(30 * 20);
    // Host stalls at 5 s: everything after arrives 0.4 s later, steadily.
    double arrive(int i) => i / 30 + (i >= 150 ? 0.4 : 0) + 0.005;
    run(b, snaps, arrive, warmup: 0, onFrame: (t) => now = t);
    expect(b.delay, closeTo(0.05, 0.01));
  });

  test('starved buffer extrapolates remote chickens briefly', () {
    var now = 0.0;
    final b = SnapshotBuffer(minDelay: 0.05, clock: () => now)
      ..reset(infos(), null);
    final snaps = snapshots(30);
    for (final s in snaps) {
      now += 1 / 30;
      b.add(s);
      b.update(1 / 30);
    }
    // No more packets for 150 ms.
    RenderFrame? f;
    for (var i = 0; i < 9; i++) {
      now += 1 / 60;
      f = b.update(1 / 60);
    }
    expect(f, isNotNull);
    expect(b.takeStarved(), greaterThan(0));
    final last = snaps.last;
    for (final v in f!.fighters) {
      final s = last.fighter(v.id)!;
      final speed = s.vx.abs() + s.vy.abs();
      if (speed > 1 && s.state != FState.dead && s.state != FState.falling) {
        // Moved past the last known position along its velocity.
        expect((v.x - s.x) * s.vx + (v.y - s.y) * s.vy, greaterThan(0));
      }
    }
  });
}
