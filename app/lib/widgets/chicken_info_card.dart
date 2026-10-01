import 'package:flutter/material.dart';
import 'package:rooster_core/rooster_core.dart';

import '../ui/theme.dart';
import 'chicken_avatar.dart';

/// Everything a player needs to know about one chicken: role, stats,
/// rage skill, how to play. Used by the roster screen and the in-match
/// "my chicken" panel (players said the reveal flashes by too fast).
class ChickenInfoCard extends StatelessWidget {
  final ChickenClassDef def;
  final Variant? variant;
  final Rarity? rarity;
  final Color slotColor;
  final bool compact;

  const ChickenInfoCard({
    super.key,
    required this.def,
    this.variant,
    this.rarity,
    this.slotColor = RC.gold,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = def.stats;
    final v =
        variant ??
        Variant.values[ChickenClasses.all.indexOf(def) % Variant.values.length];
    Widget stat(
      String label,
      double value,
      double max,
      Color c, [
      String? shown,
    ]) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: RC.muted),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (value / max).clamp(0.0, 1.0),
                minHeight: 7,
                color: c,
                backgroundColor: RC.ink,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              shown ?? value.round().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    final header = Row(
      children: [
        ChickenAvatar(
          chicken: ChickenInstance(def.id, v, rarity ?? Rarity.common),
          slotColor: slotColor,
          size: compact ? 56 : 74,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                def.nameVi,
                style: TextStyle(
                  fontSize: compact ? 16 : 18,
                  fontWeight: FontWeight.w900,
                  color: RC.gold,
                ),
              ),
              Text(
                def.role.nameVi,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Row(
                children: [
                  const Text(
                    'Độ khó ',
                    style: TextStyle(fontSize: 11, color: RC.muted),
                  ),
                  for (var i = 1; i <= 3; i++)
                    Icon(
                      i <= def.difficulty ? Icons.star : Icons.star_border,
                      size: 13,
                      color: RC.gold,
                    ),
                ],
              ),
              if (variant != null)
                Text(
                  'Hệ ${variant!.nameVi}: ${variant!.perkVi}'
                  '${rarity != null ? ' · ${rarity!.nameVi}' : ''}',
                  style: TextStyle(fontSize: 11, color: Color(variant!.color)),
                ),
            ],
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xEE3A2416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RC.panelHi, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 8),
          stat('Máu', s.hp * Tuning.hpScale, 150, RC.hp),
          stat('Sát thương', s.damage, 120, RC.orange),
          stat('Tốc độ', s.speed, 120, RC.green),
          stat('Thể lực', s.stamina, 120, RC.stamina),
          stat('Thăng bằng', s.balance, 150, RC.balance),
          stat('Giáp %', s.armor * 100, 30, RC.muted),
          // Guard shield mend speed (balance + armor): longer bar = faster.
          stat(
            'Hồi khiên',
            Fighter.guardRatingOf(def),
            2,
            RC.blue,
            '${(Tuning.shieldRegenTime / Fighter.guardRatingOf(def)).toStringAsFixed(1)}s',
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Kỹ năng (U): ${def.skillName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                TextSpan(
                  text:
                      '  — chỉ khi NỘ, hồi '
                      '${(def.skillCooldown * Tuning.rageSkillCooldownMul).toStringAsFixed(1)}s',
                  style: const TextStyle(fontSize: 11, color: RC.rage),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            def.skillDescVi,
            style: const TextStyle(fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline, size: 15, color: RC.gold),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  def.tipVi,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: RC.muted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
