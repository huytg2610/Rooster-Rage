import 'dart:math' as math;

import 'package:flame/extensions.dart';
import 'package:rooster_core/rooster_core.dart';

import '../audio/sound_fx.dart';
import '../controls/input_controller.dart';
import 'projection.dart';
import 'rooster_game.dart';

/// Maps simulation events + local input to sound effects.
///
/// Remote actions are heard when the host confirms them (hits, KOs,
/// skills); the local player's own swings/dashes play instantly on input so
/// controls feel responsive.
class GameAudio {
  final RoosterGame game;
  final _rng = math.Random(3);
  bool _heavyWasHeld = false;
  int _lastCountdown = 99;
  int _lastRemaining = 999;
  MatchPhase? _lastPhase;
  double _heartAt = 0;
  double _crowdAt = -9;
  // Sounds due later on the game clock (no Timers: nothing may fire after
  // the match view is gone).
  final _later = <(double, void Function())>[];

  GameAudio(this.game);

  SoundFx get _fx => SoundFx.instance;

  /// Chicken voice pitch per class (big birds low, bantam squeaky).
  static const _voice = <String, double>{
    'samurai': 1.0,
    'ninja': 1.1,
    'tank': 0.8,
    'berserker': 0.95,
    'troll': 1.15,
    'dongtao': 0.75,
    'bantam': 1.35,
    'silkie': 0.9,
  };

  double _voiceOf(int id) {
    final cls = game.info(id)?.classId;
    return (_voice[cls] ?? 1.0) * (0.94 + _rng.nextDouble() * 0.12);
  }

  /// Stereo pan + distance falloff relative to the camera center.
  (double, double) _space(double x, double y) {
    final vw = game.size.x;
    if (vw <= 0) return (1, 0);
    final screen = game.camera.localToGlobal(Proj.p(x, y).toVector2());
    final pan = ((screen.x - vw / 2) / (vw / 2)).clamp(-1.0, 1.0) * 0.7;
    final me = game.frame?.fighter(game.localId);
    var vol = 1.0;
    if (me != null) {
      final d = math.sqrt((me.x - x) * (me.x - x) + (me.y - y) * (me.y - y));
      vol = (1.1 - d / 14).clamp(0.35, 1.0);
    }
    return (vol, pan);
  }

  void _at(
    SoundId id,
    double x,
    double y, {
    double volume = 1,
    double rate = 1,
  }) {
    final (v, pan) = _space(x, y);
    _fx.play(id, volume: volume * v, rate: rate, pan: pan);
  }

  void onEvent(SimEvent e) {
    final mine = e.a == game.localId;
    switch (e.type) {
      case EvType.hit:
        final f = e.flags;
        if (f & HitFlag.guardBreak != 0) {
          _at(SoundId.guardBreak, e.x, e.y);
        } else if (f & HitFlag.blocked != 0) {
          _at(SoundId.block, e.x, e.y, volume: 0.9);
        } else if (e.v <= 0.4) {
          _at(SoundId.whooshLight, e.x, e.y, volume: 0.5); // shove
        } else {
          final crit =
              f & (HitFlag.crit | HitFlag.backstab | HitFlag.counter) != 0;
          final heavy =
              f & (HitFlag.heavy | HitFlag.finisher | HitFlag.skill) != 0;
          _at(
            crit
                ? SoundId.hitCrit
                : (heavy ? SoundId.hitHeavy : SoundId.hitLight),
            e.x,
            e.y,
          );
          // The victim squawks (always on big hits).
          if (heavy || crit || _rng.nextDouble() < 0.45) {
            _at(SoundId.squawk, e.x, e.y, volume: 0.75, rate: _voiceOf(e.b));
          }
          // The crowd reacts to big blows (rate-limited so it stays special).
          if ((heavy || crit) && _rng.nextDouble() < 0.4) {
            _crowd(SoundId.crowdOoh, 0.55);
          }
          if (e.a == game.localId || e.b == game.localId) {
            if (heavy || crit) game.hitStop(crit ? 0.085 : 0.06);
          }
        }
      case EvType.ko:
        _at(SoundId.ko, e.x, e.y);
        _crowd(SoundId.crowdCheer, 0.7);
        if (e.a == game.localId || e.b == game.localId) game.hitStop(0.1);
        if (e.flags == KoCause.ringOut) {
          _at(
            game.arena.voidKind == VoidKind.pond
                ? SoundId.splash
                : SoundId.fallWhistle,
            e.x,
            e.y,
          );
        }
      case EvType.fakeKo:
        _at(SoundId.ko, e.x, e.y);
        if (e.b == game.localId) _fx.play(SoundId.fakeDeath, volume: 0.8);
      case EvType.stun:
        _at(SoundId.squawk, e.x, e.y, rate: _voiceOf(e.b) * 0.9);
      case EvType.pickup:
        _at(SoundId.pickup, e.x, e.y, volume: mine ? 1 : 0.6);
      case EvType.healDrop:
        _at(SoundId.pickup, e.x, e.y, volume: 0.5, rate: 0.75);
      case EvType.spill:
        _at(SoundId.bucketSpill, e.x, e.y);
      case EvType.trap:
        _at(SoundId.trapSnap, e.x, e.y);
        _at(SoundId.squawk, e.x, e.y, rate: _voiceOf(e.b));
      case EvType.skill:
        _skill(e);
      case EvType.rage:
        _at(SoundId.rageRoar, e.x, e.y, rate: _voiceOf(e.a));
      case EvType.crow:
        _at(SoundId.crow, e.x, e.y, rate: _voiceOf(e.a));
      case EvType.respawn:
        _at(SoundId.respawn, e.x, e.y, volume: 0.6);
      case EvType.land:
        final id = e.v >= 2
            ? SoundId.earthBoom
            : (e.v > 1 ? SoundId.stomp : SoundId.land);
        _at(id, e.x, e.y);
      case EvType.dodge:
        if (!mine) _at(SoundId.dash, e.x, e.y, volume: 0.6);
      case EvType.exhausted:
        _at(
          SoundId.exhausted,
          e.x,
          e.y,
          volume: mine ? 1 : 0.5,
          rate: _voiceOf(e.a),
        );
      case EvType.surprise:
        _at(SoundId.surprise, e.x, e.y);
      case EvType.vortex:
        _at(SoundId.vortex, e.x, e.y);
      case EvType.burst:
        _at(SoundId.vortexBurst, e.x, e.y);
    }
  }

  void _skill(SimEvent e) {
    final skill =
        SkillId.values[e.v.round().clamp(0, SkillId.values.length - 1)];
    switch (skill) {
      case SkillId.flameKick:
        _at(SoundId.flameKick, e.x, e.y);
      case SkillId.shadowDash:
        _at(SoundId.shadowDash, e.x, e.y);
      case SkillId.earthRooster:
        _at(SoundId.jump, e.x, e.y, rate: 0.8); // boom plays on landing
      case SkillId.madRooster:
        _at(SoundId.madSquawk, e.x, e.y, rate: _voiceOf(e.a));
      case SkillId.fakeDeath:
        break; // handled by fakeKo (owner hears the joke)
      case SkillId.stompChain:
        break; // each stomp is a land event
      case SkillId.peckFlurry:
        // Pecks aren't separate events — play the rhythm locally.
        for (var i = 0; i < Skills.peckCount; i++) {
          _later.add((
            game.clock + 0.08 + i * Skills.peckEvery,
            () => _at(
              SoundId.peck,
              e.x,
              e.y,
              rate: 0.95 + _rng.nextDouble() * 0.2,
            ),
          ));
        }
      case SkillId.darkVortex:
        break; // vortex / burst events
    }
  }

  /// Instant feedback for the local player's own actions.
  void onLocalInput(InputSample s) {
    final me = game.frame?.fighter(game.localId);
    final canAct =
        me != null &&
        switch (me.s.state) {
          FState.idle || FState.run || FState.attack || FState.recovery => true,
          FState.heavyCharge || FState.block => true,
          _ => false,
        };
    if (canAct) {
      final voice = _voiceOf(me.id);
      if (s.pressed & Btn.light != 0) {
        _fx.play(SoundId.whooshLight, volume: 0.7);
        if (_rng.nextDouble() < 0.35) {
          _fx.play(SoundId.cluck, volume: 0.6, rate: voice);
        }
      }
      if (_heavyWasHeld && !s.heavy && me.s.state == FState.heavyCharge) {
        _fx.play(SoundId.whooshHeavy);
        _fx.play(SoundId.cluck, volume: 0.8, rate: voice * 0.9);
      }
      if (s.pressed & Btn.jump != 0) _fx.play(SoundId.jump, volume: 0.8);
      if (s.pressed & Btn.dodge != 0) _fx.play(SoundId.dash, volume: 0.8);
    }
    _heavyWasHeld = s.heavy;
  }

  void _crowd(SoundId id, double volume) {
    final now = game.clock;
    if (now - _crowdAt < 1.6) return;
    _crowdAt = now;
    _fx.play(id, volume: volume, rate: 0.95 + _rng.nextDouble() * 0.1);
  }

  /// Match atmosphere: taiko count-in + gong, battle music (finale in the
  /// last 30 s), ticking clock in the last 10 s, heartbeat at low HP.
  void onFrame(MatchSnap snap) {
    if (_later.isNotEmpty) {
      final now = game.clock;
      for (final (t, play) in [..._later]) {
        if (t <= now) play();
      }
      _later.removeWhere((x) => x.$1 <= now);
    }
    if (snap.phase == MatchPhase.countdown) {
      final n = snap.countdown.ceil();
      if (n != _lastCountdown && n > 0 && n <= 3) {
        _fx.play(SoundId.taiko, rate: 1 + (3 - n) * 0.06);
      }
      _lastCountdown = n;
    }
    if (snap.phase != _lastPhase) {
      if (snap.phase == MatchPhase.fighting) {
        _fx.play(SoundId.gong);
        _crowd(SoundId.crowdCheer, 0.6);
        _fx.playMusic(
          snap.remaining <= 30 ? MusicTrack.finale : MusicTrack.battle,
        );
      }
      if (snap.phase == MatchPhase.ended) {
        _fx.stopMusic();
        _fx.play(SoundId.timeUp);
        _fx.play(SoundId.gong, volume: 0.8);
        _crowdAt = -9;
        _crowd(SoundId.crowdCheer, 0.9);
      }
      _lastPhase = snap.phase;
    }
    if (snap.phase != MatchPhase.fighting) return;

    final left = snap.remaining.ceil();
    if (left != _lastRemaining) {
      if (left == 30) {
        _fx.prepareMusic(MusicTrack.finale);
        _fx.playMusic(MusicTrack.finale);
      }
      if (left <= 10 && left > 0) {
        // Tick-tock, with a war drum on the final three.
        _fx.play(
          SoundId.clockTick,
          volume: 0.9,
          rate: left.isEven ? 1.0 : 0.85,
        );
        if (left <= 3) {
          _fx.play(SoundId.taiko, rate: 1.1 + (3 - left) * 0.08);
          game.shake(4.0 + (3 - left) * 2);
        }
      }
      _lastRemaining = left;
    }

    final me = snap.fighter(game.localId ?? -1);
    final info = game.info(game.localId ?? -1);
    if (me != null &&
        info != null &&
        me.state != FState.dead &&
        me.hp < info.maxHp * 0.25) {
      if (game.clock - _heartAt > 0.85) {
        _heartAt = game.clock;
        _fx.play(SoundId.heartbeat, volume: 0.8);
      }
    }
  }

  void dispose() {
    _later.clear();
    _fx.stopMusic();
  }
}
