import 'dart:math' as math;
import 'dart:ui' hide TextStyle;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart'
    show FontWeight, RadialGradient, TextStyle;
import 'package:rooster_core/rooster_core.dart';

import '../controls/controls_layout.dart';
import '../l10n/l10n.dart';
import '../net/snapshot_buffer.dart';
import '../ui/theme.dart';
import 'projection.dart' show Styles, TextCache;
import 'rooster_game.dart';

/// Screen-space HUD (GDD §2): own HP/Stamina/Balance/Rage, timer,
/// scoreboard, kill feed, countdown, and the touch control visuals.
class HudLayer extends PositionComponent with HasGameReference<RoosterGame> {
  HudLayer() : super(priority: 100);

  final _text = TextCache();
  final _fill = Paint();
  final _line = Paint()..style = PaintingStyle.stroke;

  TextStyle _s(double size, Color c, [FontWeight w = FontWeight.w900]) =>
      Styles.outlined(size, c, w);

  @override
  void render(Canvas canvas) {
    final s = L10n.current;
    final frame = game.frame;
    final size = game.size.toSize();
    if (frame == null) {
      _text.paint(
        canvas,
        s.hudSyncing,
        _s(16, RC.cream),
        size.center(Offset.zero),
      );
      return;
    }
    final me = frame.fighter(game.localId);
    if (me != null) _ownPanel(canvas, me.s, me.info);
    _timer(canvas, size, frame.latest);
    final boardBottom = _scoreboard(canvas, size, frame);
    _feed(canvas, size, boardBottom + 6);
    if (game.showTouchControls && me != null) _controls(canvas, me.s, me.info);
    if (me == null) {
      _text.paint(
        canvas,
        s.hudSpectating,
        _s(14, RC.muted),
        Offset(size.width / 2, size.height - 24),
      );
    } else if (me.s.has(FFlag.out) && me.s.state != FState.fakeDead) {
      _text.paint(
        canvas,
        s.hudEliminated,
        _s(15, RC.red),
        Offset(size.width / 2, size.height - 24),
      );
    }
    _banner(canvas, size, frame.latest);
    _finalCountdown(canvas, size, frame.latest);
  }

  /// Own stats, labelled inside each bar: MÁU · THỂ LỰC · THĂNG BẰNG · NỘ.
  void _ownPanel(Canvas canvas, FighterSnap s, FighterInfo info) {
    const x = 52.0, y = 8.0;
    // Shrink on narrow portrait screens so the centered timer stays clear.
    final w = (game.size.x / 2 - 100).clamp(92.0, 170.0);
    final l = L10n.current;
    final def = ChickenClasses.byId(info.classId);
    final nameTp = _text.get(
      l.chickenName(def),
      _s(12, Color(slotColors[info.slot % 8])),
    );
    nameTp.paint(canvas, const Offset(x, y - 1));
    var by = y + 16;
    final label = _s(9.5, RC.cream, FontWeight.w900);
    void bar(
      String name,
      String value,
      double v,
      double max,
      Color c,
      double h,
    ) {
      final r = Rect.fromLTWH(x, by, w, h);
      _fill.color = const Color(0xCC1B100A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.inflate(2), const Radius.circular(4)),
        _fill,
      );
      _fill.color = c;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, by, w * (v / max).clamp(0.0, 1.0), h),
          const Radius.circular(3),
        ),
        _fill,
      );
      final lt = _text.get(name, label);
      lt.paint(canvas, Offset(x + 4, by + (h - lt.height) / 2));
      if (value.isNotEmpty) {
        final vt = _text.get(value, label);
        vt.paint(
          canvas,
          Offset(x + w - vt.width - 4, by + (h - vt.height) / 2),
        );
      }
      by += h + 4;
    }

    bar(
      l.hudHp,
      '${s.hp.round()}/${info.maxHp.round()}',
      s.hp,
      info.maxHp,
      RC.hp,
      14,
    );
    final tired = s.stamina < info.maxStamina * 0.25;
    bar(
      tired ? l.hudStaminaLow : l.hudStamina,
      '${s.stamina.round()}',
      s.stamina,
      info.maxStamina,
      tired ? RC.orange : const Color(0xFFC99A12),
      13,
    );
    bar(l.hudBalance, '', s.balance, info.maxBalance, RC.balance, 12);
    if (s.shieldBroken) {
      // Shattered: grey while it mends back to a quarter.
      bar(
        l.hudShieldBroken,
        '${(s.shield / Tuning.shieldMax * 100).round()}%',
        s.shield,
        Tuning.shieldMax,
        const Color(0xFF8A96A0),
        11,
      );
    } else {
      bar(
        l.hudShield,
        '${(s.shield / Tuning.shieldMax * 100).round()}%',
        s.shield,
        Tuning.shieldMax,
        const Color(0xFF4FB8FF),
        11,
      );
    }
    final raging = s.has(FFlag.rage);
    final rageFull = s.rage >= Tuning.rageMax && !raging;
    final pulse = rageFull || raging
        ? 0.65 + 0.35 * math.sin(game.clock * 10)
        : 1.0;
    bar(
      raging ? l.hudRaging : (rageFull ? l.hudRageFull : l.hudRage),
      raging ? '${s.rageTimer.ceil()}s' : '${s.rage.floor()}%',
      raging ? s.rageTimer : s.rage,
      raging ? Tuning.rageDuration : Tuning.rageMax,
      RC.rage.withValues(alpha: pulse),
      12,
    );
  }

  void _timer(Canvas canvas, Size size, MatchSnap snap) {
    final rem = snap.remaining.ceil();
    final t = '${rem ~/ 60}:${(rem % 60).toString().padLeft(2, '0')}';
    final c = Offset(size.width / 2, 20);
    _fill.color = const Color(0xCC1B100A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 70, height: 30),
        const Radius.circular(12),
      ),
      _fill,
    );
    _text.paint(canvas, t, _s(18, rem <= 10 ? RC.red : RC.cream), c);
    if (game.survival) {
      final left = snap.fighters.where((f) => !f.has(FFlag.out)).length;
      _text.paint(
        canvas,
        L10n.current.hudSurvivalLeft(left),
        _s(10, RC.gold),
        c + const Offset(0, 22),
      );
    }
  }

  /// Returns the bottom y of the board.
  double _scoreboard(Canvas canvas, Size size, RenderFrame frame) {
    final list = [...frame.latest.fighters]
      ..sort((a, b) {
        // Survival: the ones still standing on top.
        final ao = a.has(FFlag.out), bo = b.has(FFlag.out);
        if (ao != bo) return ao ? 1 : -1;
        if (a.kos != b.kos) return b.kos.compareTo(a.kos);
        return a.deaths.compareTo(b.deaths);
      });
    final right = size.width - 8;
    var y = 10.0;
    final compact = size.width < 560;
    for (final f in list.take(compact ? 4 : 8)) {
      final info = game.info(f.id);
      if (info == null) continue;
      final mine = f.id == game.localId;
      final out = f.has(FFlag.out);
      final label = '${compact ? '' : '${info.name}  '}${f.kos}${out ? L10n.current.hudOutTag : ''}';
      final tp = _text.get(
        label,
        _s(11, out ? RC.muted : (mine ? RC.gold : RC.cream)),
      );
      final r = Rect.fromLTWH(right - tp.width - 22, y, tp.width + 22, 17);
      _fill.color = mine ? const Color(0xDD5A3620) : const Color(0xAA1B100A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(8)),
        _fill,
      );
      _fill.color = Color(slotColors[info.slot % 8]);
      canvas.drawCircle(Offset(r.left + 9, r.center.dy), 5, _fill);
      tp.paint(canvas, Offset(r.left + 17, r.top + 1.5));
      y += 20;
    }
    return y;
  }

  void _feed(Canvas canvas, Size size, double top) {
    var y = top;
    // Keep clear of the skill-button column on touch layouts.
    final l = game.input.layout;
    final right = game.showTouchControls && l != null
        ? l.buttons[0].dx - l.buttonRadius - 8
        : size.width - 10;
    for (final item in game.feed.take(4)) {
      final age = game.clock - item.time;
      // Quantized fade so the cached text layouts are reused.
      final a = ((1 - ((age - 3.5) / 0.5)).clamp(0.0, 1.0) * 6).ceil() / 6;
      if (a <= 0) continue;
      final tp = _text.get(
        item.text,
        _s(11, RC.cream.withValues(alpha: a), FontWeight.w700),
      );
      tp.paint(canvas, Offset(right - tp.width, y));
      y += 16;
    }
  }

  void _controls(Canvas canvas, FighterSnap s, FighterInfo info) {
    final input = game.input;
    final l = input.layout;
    if (l == null) return;
    // Joystick.
    final origin = input.stickOrigin;
    if (origin != null) {
      _fill.color = const Color(0x33FFFFFF);
      canvas.drawCircle(origin, l.joystickRadius, _fill);
      _line
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 2;
      canvas.drawCircle(origin, l.joystickRadius, _line);
      _fill.color = const Color(0xAAFFF1D6);
      canvas.drawCircle(
        origin + input.stickVector * l.joystickRadius,
        l.joystickRadius * 0.42,
        _fill,
      );
    }
    // Action finger (heavy charge ring).
    final ap = input.actionPos;
    if (ap != null && input.touchHeavy) {
      _line
        ..color = RC.orange
        ..strokeWidth = 4;
      final k = (s.heavyCharge / Tuning.heavyMaxCharge).clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: ap, radius: 34),
        -math.pi / 2,
        math.pi * 2 * k,
        false,
        _line,
      );
    }
    // Buttons: [ultimate (rage + skill), crow, guard (hold)].
    final def = ChickenClasses.byId(info.classId);
    final raging = s.has(FFlag.rage);
    final rageReady = s.rage >= Tuning.rageMax && !raging;
    final skillCdMax = info.skillCooldown * Tuning.rageSkillCooldownMul;
    final curL10n = L10n.current;
    final specs = <(String, double, Color, bool)>[
      // Fills up with the rage bar; full = "NỘ + CHIÊU" in one tap. While
      // raging it shows the skill and its short cooldown.
      raging
          ? (
              def.skillName,
              skillCdMax <= 0 ? 0 : s.skillCd / skillCdMax,
              Color(info.variant.color),
              s.skillCd <= 0,
            )
          : (
              rageReady ? curL10n.hudRageSkill : curL10n.hudSkillNeedsRage,
              rageReady ? 0 : 1 - (s.rage / Tuning.rageMax).clamp(0.0, 1.0),
              RC.rage,
              rageReady,
            ),
      (curL10n.hudCrow, s.crowCd / Tuning.crowCooldown, RC.cream, s.crowCd <= 0),
      s.shieldBroken
          ? (
              curL10n.hudShieldBroken,
              1 -
                  (s.shield / (Tuning.shieldMax * Tuning.shieldRaiseMin)).clamp(
                    0.0,
                    1.0,
                  ),
              RC.blue,
              false,
            )
          : (curL10n.hudGuard, 0, RC.blue, true),
    ];
    for (var i = 0; i < specs.length; i++) {
      final c = l.buttons[i];
      final (label, cd, color, ready) = specs[i];
      final r = l.buttonRadius * (input.buttonDown[i] ? 0.9 : 1);
      _fill.color = ready
          ? color.withValues(alpha: 0.85)
          : const Color(0x88333333);
      canvas.drawCircle(c, r, _fill);
      if (cd > 0) {
        _fill.color = const Color(0x99000000);
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          -math.pi / 2,
          math.pi * 2 * cd,
          true,
          _fill,
        );
      }
      _line
        ..color = ready ? RC.cream : const Color(0x88FFFFFF)
        ..strokeWidth = 3;
      canvas.drawCircle(c, r, _line);
      final words = label.split(' ');
      for (var w = 0; w < words.length; w++) {
        _text.paint(
          canvas,
          words[w],
          _s(words.length > 1 ? 9 : 12, ready ? RC.ink : RC.cream),
          c + Offset(0, (w - (words.length - 1) / 2) * 11),
        );
      }
    }
  }

  final _vignette = Paint();
  Size? _vignetteSize;

  /// Last 10 s: a huge number pops every second (bigger and redder at 3-2-1)
  /// with a pulsing red vignette.
  void _finalCountdown(Canvas canvas, Size size, MatchSnap snap) {
    if (snap.phase != MatchPhase.fighting) return;
    final rem = snap.remaining;
    if (rem > 10 || rem <= 0) return;
    final n = rem.ceil();
    final frac = (n - rem).clamp(0.0, 1.0); // 0 at the start of the second
    final pop = 1 - Curves.easeOut.transform((frac / 0.25).clamp(0.0, 1.0));
    final urgent = n <= 3;
    final alpha =
        ((1 - frac * 0.75) * 8).ceil() / 8; // quantized for the text cache

    // Red vignette, pulsing with each second. The gradient shader is built
    // once per screen size; intensity rides on the paint alpha.
    final rect = Offset.zero & size;
    if (_vignetteSize != size) {
      _vignetteSize = size;
      _vignette.shader = const RadialGradient(
        colors: [Color(0x00E8412C), RC.red],
        stops: [0.55, 1],
      ).createShader(rect);
    }
    final edge = (urgent ? 0.55 : 0.3) * (0.5 + 0.5 * pop);
    _vignette.color = Color.fromRGBO(0, 0, 0, (edge * 10).round() / 10);
    canvas.drawRect(rect, _vignette);

    final base = math.min(size.width, size.height) * (urgent ? 0.34 : 0.24);
    final color = (urgent ? RC.red : RC.gold).withValues(alpha: alpha);
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.45);
    canvas.scale(1 + 0.7 * pop);
    _text.paint(
      canvas,
      '$n',
      Styles.outlined(base, color, FontWeight.w900, 4),
      Offset.zero,
      0.5,
      1 + 0.7 * pop,
    );
    canvas.restore();
  }

  void _banner(Canvas canvas, Size size, MatchSnap snap) {
    String? text;
    Color color = RC.gold;
    final l = L10n.current;
    if (snap.phase == MatchPhase.countdown) {
      final n = snap.countdown.ceil();
      text = n > 0 ? '$n' : l.bannerFight;
    } else if (snap.phase == MatchPhase.fighting &&
        snap.remaining > game.duration - 0.8) {
      text = l.bannerFight;
      color = RC.orange;
    } else if (snap.phase == MatchPhase.ended) {
      final standing = snap.fighters.where((f) => !f.has(FFlag.out)).length;
      if (game.survival && standing <= 1) {
        final me = snap.fighter(game.localId ?? -1);
        final won = me != null && !me.has(FFlag.out);
        text = won ? l.bannerSurvived : l.bannerEnded;
        color = won ? RC.gold : RC.red;
      } else {
        text = l.bannerTimeUp;
        color = RC.red;
      }
    }
    if (text == null) return;
    _text.paint(
      canvas,
      text,
      _s(math.min(size.width, size.height) * 0.16, color),
      size.center(Offset.zero),
    );
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    game.input.layout = ControlsLayout.of(size.toSize());
  }
}
