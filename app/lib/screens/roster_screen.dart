import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rooster_core/rooster_core.dart';

import '../l10n/l10n.dart';
import '../ui/theme.dart';
import '../widgets/chicken_info_card.dart';

/// All chickens with stats, rage skill and tips — read at your own pace.
class RosterScreen extends ConsumerWidget {
  const RosterScreen({super.key});

  static void open(BuildContext context) => context.push('/chickens');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(l10nProvider);
    final s = L10n.current;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 1100 ? 3 : (width > 700 ? 2 : 1);
    final rules = WoodPanel(
      child: Text(
        s.rosterRules,
        style: const TextStyle(fontSize: 13, height: 1.45),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: RC.bg2,
        title: Text(
          s.rosterHeader(ChickenClasses.all.length),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: LanguageToggleButton(compact: true),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            rules,
            const SizedBox(height: 12),
            for (var i = 0; i < ChickenClasses.all.length; i += columns)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = i; j < i + columns; j++) ...[
                        if (j > i) const SizedBox(width: 12),
                        Expanded(
                          child: j < ChickenClasses.all.length
                              ? ChickenInfoCard(
                                  def: ChickenClasses.all[j],
                                  slotColor: Color(
                                    slotColors[j % slotColors.length],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
