import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rooster_core/rooster_core.dart';

import '../audio/sound_fx.dart';
import '../l10n/l10n.dart';
import '../net/session.dart';
import '../ui/theme.dart';
import '../widgets/chicken_avatar.dart';

/// Reveal cinematic (GDD §1A): face-down cards flip one by one, then your
/// chicken is presented with its role, skill, element and rarity.
class RevealView extends StatefulWidget {
  final Session session;
  const RevealView({super.key, required this.session});

  @override
  State<RevealView> createState() => _RevealViewState();
}

class _RevealViewState extends State<RevealView>
    with SingleTickerProviderStateMixin {
  late final double _dur = widget.session.revealDuration.clamp(1.5, 8.0);
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_dur * 1000).round()),
  )..forward();

  final _flipped = <int>{};

  @override
  void initState() {
    super.initState();
    // Render the fight loop now so the gong + music start without a hitch.
    Future<void>.delayed(const Duration(milliseconds: 400),
        () => SoundFx.instance.prepareMusic(MusicTrack.battle));
    // The finale loop too, so switching at 30 s left never hitches mid-fight.
    Future<void>.delayed(const Duration(milliseconds: 1600),
        () => SoundFx.instance.prepareMusic(MusicTrack.finale));
  }

  bool _fanfare = false;

  /// Card-flip ticks and a fanfare when your own chicken is presented.
  void _sounds(double t, double stagger, bool showMine) {
    final n = widget.session.reveal.length;
    for (var i = 0; i < n; i++) {
      if (!_flipped.contains(i) && t >= 0.8 + i * stagger + 0.17) {
        _flipped.add(i);
        SoundFx.instance.play(
          SoundId.cardFlip,
          volume: 0.7,
          rate: 0.9 + i * 0.03,
        );
      }
    }
    if (showMine && !_fanfare) {
      _fanfare = true;
      SoundFx.instance.play(SoundId.fanfare);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.session.reveal;
    final mine = entries
        .where((e) => e.pid == widget.session.myPid)
        .firstOrNull;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * _dur;
        // Leave ~3 s to read your own chicken (players found 1.6 s too fast).
        final mineFor = math.min(3.0, _dur * 0.45);
        final showMine = mine != null && t > _dur - mineFor;
        final stagger = math.min(
          0.3,
          (_dur - 2.2) / math.max(1, entries.length),
        );
        _sounds(t, stagger, showMine);
        return Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              colors: [Color(0xFF6E4428), RC.bg],
              radius: 1.1,
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      widget.session.room?.settings.mode == GameMode.competitive
                          ? L10n.current.fightersAssemble
                          : L10n.current.roosterDraw,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: RC.gold,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final (i, e) in entries.indexed)
                              _Card(
                                entry: e,
                                mine: e.pid == widget.session.myPid,
                                flip: ((t - 0.8 - i * stagger) / 0.35).clamp(
                                  0.0,
                                  1.0,
                                ),
                                shake: t < 0.8 ? math.sin(t * 40 + i) * 3 : 0,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (showMine)
                  _MineOverlay(
                    entry: mine,
                    k: ((t - (_dur - mineFor)) / 0.3).clamp(0.0, 1.0),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  final RevealEntry entry;
  final bool mine;
  final double flip;
  final double shake;
  const _Card({
    required this.entry,
    required this.mine,
    required this.flip,
    required this.shake,
  });

  @override
  Widget build(BuildContext context) {
    final front = flip >= 0.5;
    final angle = flip * math.pi;
    final rarity = Color(entry.chicken.rarity.color);
    return Transform.translate(
      offset: Offset(shake, 0),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.002)
          ..rotateY(front ? angle - math.pi : angle),
        child: Container(
          width: 110,
          height: 150,
          decoration: BoxDecoration(
            color: front ? RC.panel : RC.red,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: front ? rarity : RC.ink,
              width: mine ? 4 : 3,
            ),
            boxShadow: [
              if (front && entry.chicken.rarity.index >= 2)
                BoxShadow(color: rarity.withValues(alpha: 0.6), blurRadius: 16),
            ],
          ),
          child: front
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChickenAvatar(
                      chicken: entry.chicken,
                      slotColor: Color(slotColors[entry.slot % 8]),
                      size: 70,
                    ),
                    Text(
                      L10n.current.chickenName(entry.chicken.def),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      entry.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: Color(slotColors[entry.slot % 8]),
                      ),
                    ),
                    Text(
                      L10n.current.rarityName(entry.chicken.rarity),
                      style: TextStyle(fontSize: 10, color: rarity),
                    ),
                  ],
                )
              : const Center(
                  child: Text(
                    '?',
                    style: TextStyle(
                      fontSize: 54,
                      fontWeight: FontWeight.w900,
                      color: RC.gold,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _MineOverlay extends StatelessWidget {
  final RevealEntry entry;
  final double k;
  const _MineOverlay({required this.entry, required this.k});

  @override
  Widget build(BuildContext context) {
    final c = entry.chicken;
    final def = c.def;
    return Positioned.fill(
      child: ColoredBox(
        color: Color.fromRGBO(0, 0, 0, 0.6 * k),
        child: Center(
          child: Transform.scale(
            scale: 0.6 + 0.4 * Curves.easeOutBack.transform(k),
            child: WoodPanel(
              padding: const EdgeInsets.all(18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChickenAvatar(
                    chicken: c,
                    slotColor: Color(slotColors[entry.slot % 8]),
                    size: 130,
                    state: FState.crow,
                  ),
                  const SizedBox(width: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          L10n.current.youAre,
                          style: const TextStyle(
                            color: RC.muted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          L10n.current.chickenName(def),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: RC.gold,
                          ),
                        ),
                        Text(
                          '${L10n.current.roleName(def.role)} · ${L10n.currentLang == AppLang.en ? c.variant.nameEn : c.variant.nameVi} (${L10n.currentLang == AppLang.en ? c.variant.perkEn : c.variant.perkVi})',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          L10n.current.rarityName(c.rarity),
                          style: TextStyle(
                            color: Color(c.rarity.color),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          L10n.current.skillLabel(def.skillName),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          L10n.current.chickenSkillDesc(def),
                          style: const TextStyle(fontSize: 12, color: RC.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
