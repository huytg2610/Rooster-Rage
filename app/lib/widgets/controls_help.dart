import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../ui/theme.dart';

/// In-match controls cheat sheet: keyboard on desktop, gestures on touch.
class ControlsHelp extends ConsumerWidget {
  final bool touch;
  final String skillName;
  const ControlsHelp({super.key, required this.touch, required this.skillName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(l10nProvider);
    final s = L10n.current;
    final rows = touch ? s.touchControls(skillName) : s.keyboardControls(skillName);

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xD91B100A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RC.panelHi, width: 2),
      ),
      // Clips instead of overflowing on short screens (the sheet ignores
      // touches, so it never needs to actually scroll).
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.controlsTitle,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: RC.gold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.controlsExplanation,
              style: const TextStyle(fontSize: 11, color: RC.muted, height: 1.3),
            ),
            const SizedBox(height: 6),
            for (final (keys, action) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: touch ? 84 : 104,
                      child: Wrap(
                        spacing: 3,
                        runSpacing: 3,
                        children: [for (final k in keys) _KeyCap(k)],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        action,
                        style: const TextStyle(fontSize: 12, color: RC.cream),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  final String label;
  const _KeyCap(this.label);

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: RC.cream,
      borderRadius: BorderRadius.circular(5),
      boxShadow: const [BoxShadow(color: RC.muted, offset: Offset(0, 2))],
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: RC.ink,
      ),
    ),
  );
}
