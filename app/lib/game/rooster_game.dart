import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart' show ValueNotifier;
import 'package:rooster_core/rooster_core.dart';

import '../controls/input_controller.dart';
import '../net/session.dart';
import '../net/snapshot_buffer.dart';
import 'arena_renderer.dart';
import 'effects_layer.dart';
import 'game_audio.dart';
import 'entity_layer.dart';
import 'hud_layer.dart';
import 'overhead_layer.dart';
import 'projection.dart';

class FeedItem {
  final String text;
  final double time;
  const FeedItem(this.text, this.time);
}

/// Presentation layer (GDD §7): renders interpolated host state, collects
/// input. Never simulates — the host is authoritative.
class RoosterGame extends FlameGame {
  final Session session;
  final InputController input;
  bool showTouchControls;

  late final ArenaDef arena = session.match!.arena;
  late final EffectsLayer _effects;
  late final GameAudio audio = GameAudio(this);
  RenderFrame? frame;
  double clock = 0;
  final feed = <FeedItem>[];
  final _hitTimes = <int, double>{};
  double _shake = 0;
  final _rng = math.Random();
  Vector2? _camPos;
  double? _camZoom;

  /// "FPS · ping · jitter · buffer" line for the help panel (2 Hz).
  final stats = ValueNotifier<String>('');
  double _fps = 60;
  double _statsTimer = 0;
  double _hitStop = 0;

  /// Freeze the picture for a few frames on big impacts (game feel only —
  /// the host simulation keeps running; the jitter buffer catches up).
  void hitStop(double seconds) => _hitStop = math.max(_hitStop, seconds);

  RoosterGame({
    required this.session,
    required this.input,
    this.showTouchControls = false,
  });

  int? get localId => session.match?.you;
  double get fps => _fps;
  int get duration => session.match?.duration ?? 180;
  bool get survival => session.match?.survival ?? false;
  double get renderTime => frame?.time ?? 0;
  PropsSnap get latestProps => frame?.latest.props ?? PropsSnap.empty;
  FighterInfo? info(int id) => session.match?.fighters[id];

  @override
  void onRemove() {
    audio.dispose();
    super.onRemove();
  }

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.center;
    _effects = EffectsLayer();
    world.addAll([
      EntityLayer(arena, underGround: true),
      ArenaRenderer(arena),
      EntityLayer(arena),
      _effects,
      OverheadLayer(),
    ]);
    camera.viewport.add(HudLayer());
  }

  @override
  void update(double dt) {
    clock += dt;
    _updateStats(dt);
    final s = input.sample(dt);
    session.sendInput(s.mx, s.my, s.heavy, s.pressed, block: s.block);
    audio.onLocalInput(s);
    if (_hitStop > 0) {
      _hitStop -= dt;
      super.update(dt * 0.1);
      return;
    }
    frame = session.buffer.update(dt);
    final f = frame;
    if (f != null) {
      for (final e in f.events) {
        _effects.onEvent(e);
        audio.onEvent(e);
      }
      audio.onFrame(f.latest);
      _updateCamera(f, dt);
    }
    super.update(dt);
  }

  void _updateStats(double dt) {
    if (dt > 0) _fps = _fps * 0.95 + (1 / dt) * 0.05;
    _statsTimer += dt;
    if (_statsTimer < 0.5) return;
    _statsTimer = 0;
    final b = session.buffer;
    final starved = b.takeStarved();
    final ping = session.isLocal
        ? 'offline'
        : 'ping ${session.rttMs?.round() ?? '?'} ms';
    stats.value =
        '${_fps.round()} FPS · $ping · jitter ${(b.jitter * 1000).round()} ms'
        ' · đệm ${(b.delay * 1000).round()} ms${starved > 0 ? ' · gói trễ $starved' : ''}';
  }

  void flashHit(int id) => _hitTimes[id] = clock;

  double hitFlash(int id) {
    final t = _hitTimes[id];
    if (t == null) return 0;
    return (1 - (clock - t) / 0.14).clamp(0.0, 1.0);
  }

  void shake(double amount) => _shake = math.max(_shake, amount);

  void addFeed(SimEvent e) {
    String name(int id) => id == localId ? 'Bạn' : (info(id)?.name ?? '?');
    final fall = switch (arena.voidKind) {
      VoidKind.pond => 'rơi xuống ao',
      VoidKind.sky => 'rơi khỏi mái',
      VoidKind.abyss => 'rơi xuống vực',
    };
    final victim = name(e.b);
    final String text;
    if (e.type == EvType.fakeKo) {
      text = e.b == localId ? 'Bạn giả chết... suỵt!' : '$victim gục ngã';
    } else if (e.flags == KoCause.ringOut) {
      text = e.a >= 0 ? '${name(e.a)} hất $victim $fall' : '$victim $fall';
    } else {
      text = e.a >= 0 ? '${name(e.a)} hạ gục $victim' : '$victim gục ngã';
    }
    feed.insert(0, FeedItem(survival ? '$text — LOẠI' : text, clock));
    if (feed.length > 5) feed.removeLast();
  }

  /// GDD camera: fixed arena framing + dynamic zoom following the players.
  void _updateCamera(RenderFrame f, double dt) {
    final vw = size.x, vh = size.y - 40; // leave room for the top HUD
    if (vw <= 0 || vh <= 0) return;
    final arenaW = Proj.sx(arena.viewHalfW * 2);
    final arenaH =
        Proj.sy(arena.viewHalfH * 2) + Proj.groundThickness * Proj.px;
    final fitZoom = math.min(vw / arenaW, vh / arenaH);

    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final v in f.fighters) {
      if (!(v.s.state != FState.dead && v.s.state != FState.falling)) continue;
      final p = Proj.p(v.x, v.y);
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy - 40);
      maxY = math.max(maxY, p.dy);
    }
    double targetZoom;
    Vector2 target;
    if (minX.isFinite) {
      const margin = 3.2 * Proj.px;
      final boxW = math.max(maxX - minX + margin * 2, Proj.sx(9));
      final boxH = math.max(maxY - minY + margin * 2, Proj.sy(9));
      targetZoom = math.min(vw / boxW, vh / boxH).clamp(fitZoom, fitZoom * 2.2);
      target = Vector2((minX + maxX) / 2, (minY + maxY) / 2);
    } else {
      targetZoom = fitZoom;
      target = Vector2.zero();
    }
    // Keep the view inside the arena framing.
    final halfW = vw / targetZoom / 2, halfH = vh / targetZoom / 2;
    final limX = math.max(0.0, arenaW / 2 - halfW);
    final limY = math.max(0.0, arenaH / 2 - halfH);
    target.x = target.x.clamp(-limX, limX);
    target.y = target.y.clamp(-limY, limY + 10);

    final k = 1 - math.exp(-3.5 * dt);
    final pos = _camPos ??= target.clone();
    pos.add((target - pos)..scale(k));
    _camZoom =
        (_camZoom ?? targetZoom) + (targetZoom - (_camZoom ?? targetZoom)) * k;
    camera.viewfinder.zoom = _camZoom!;

    var shakeOff = Vector2.zero();
    if (_shake > 0.1) {
      shakeOff = Vector2(_rng.nextDouble() - 0.5, _rng.nextDouble() - 0.5)
        ..scale(_shake * 2);
      _shake *= math.exp(-12 * dt);
    }
    // Shift down slightly so the HUD strip doesn't cover the arena.
    camera.viewfinder.position = pos + shakeOff - Vector2(0, 20 / _camZoom!);
  }
}
