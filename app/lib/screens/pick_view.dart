import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rooster_core/rooster_core.dart';

import '../l10n/l10n.dart';
import '../net/session.dart';
import '../ui/theme.dart';
import '../widgets/chicken_avatar.dart';
import '../widgets/chicken_info_card.dart';

/// Competitive mode: everyone picks a class + element; picks are visible
/// so players can counter-pick (GDD §1B).
class PickView extends ConsumerStatefulWidget {
  final Session session;
  const PickView({super.key, required this.session});

  @override
  ConsumerState<PickView> createState() => _PickViewState();
}

class _PickViewState extends ConsumerState<PickView> {
  late final DateTime _end = DateTime.now().add(
    Duration(milliseconds: (widget.session.room!.timer * 1000).round()),
  );
  String? _class;
  Variant _variant = Variant.fire;

  void _send() {
    if (_class != null) widget.session.pick(_class!, _variant);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(l10nProvider);
    final s = L10n.current;
    final room = widget.session.room!;
    final others = room.players.where(
      (p) => p.pid != widget.session.myPid && p.picked != null,
    );
    final takenBy = <String, String>{
      for (final p in room.players)
        if (p.pid != widget.session.myPid && p.picked != null)
          p.picked!: p.name,
    };
    final wide = MediaQuery.sizeOf(context).width > 700;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.chooseRooster,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
                LanguageToggleButton(compact: true),
                const SizedBox(width: 8),
                _Countdown(end: _end),
              ],
            ),
            if (others.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      s.opponentsPicked,
                      style: const TextStyle(color: RC.muted),
                    ),
                    for (final p in others)
                      Chip(
                        avatar: CircleAvatar(
                          backgroundColor: Color(slotColors[p.slot % 8]),
                        ),
                        label: Text(
                          '${p.name}: ${s.chickenName(ChickenClasses.byId(p.picked!))}',
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (final c in ChickenClasses.all)
                  _ClassCard(
                    def: c,
                    variant: _variant,
                    selected: _class == c.id,
                    takenBy: takenBy[c.id],
                    width: wide ? 180 : 150,
                    onTap: () {
                      setState(() => _class = c.id);
                      _send();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final v in Variant.values)
                  ChoiceChip(
                    label: Text(L10n.currentLang == AppLang.en ? '${v.nameEn} · ${v.perkEn}' : '${v.nameVi} · ${v.perkVi}'),
                    selected: v == _variant,
                    selectedColor: Color(v.color),
                    onSelected: (_) {
                      setState(() => _variant = v);
                      _send();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _class == null
                  ? s.notSelectedPrompt
                  : s.chosenWaiting,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RC.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final ChickenClassDef def;
  final Variant variant;
  final bool selected;
  final double width;
  final String? takenBy; // another player already holds this chicken
  final VoidCallback onTap;
  const _ClassCard({
    required this.def,
    required this.variant,
    required this.selected,
    required this.width,
    required this.onTap,
    this.takenBy,
  });

  void _details(BuildContext context) => showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: ChickenInfoCard(def: def, variant: variant),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = L10n.current;
    final stats = def.stats;
    Widget stat(String n, double v, Color c) => Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(n, style: const TextStyle(fontSize: 11, color: RC.muted)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: v / 120,
              minHeight: 6,
              color: c,
              backgroundColor: RC.ink,
            ),
          ),
        ),
      ],
    );
    final locked = takenBy != null;
    final card = GestureDetector(
      onTap: locked ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? RC.panelHi : RC.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? RC.gold : RC.ink, width: 3),
        ),
        child: Column(
          children: [
            ChickenAvatar(
              chicken: ChickenInstance(def.id, variant, Rarity.common),
              slotColor: RC.gold,
              size: 72,
              state: selected ? FState.run : FState.idle,
            ),
            Text(
              l.chickenName(def),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              l.roleName(def.role),
              style: const TextStyle(fontSize: 12, color: RC.gold),
            ),
            const SizedBox(height: 6),
            stat(l.statHp, stats.hp, RC.hp),
            stat(l.statAtk, stats.damage, RC.orange),
            stat(l.statSpd, stats.speed, RC.green),
            stat(l.statStm, stats.stamina, RC.stamina),
            const SizedBox(height: 6),
            Text(
              def.skillName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            Text(
              l.chickenSkillDesc(def),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: RC.muted),
            ),
            TextButton(
              onPressed: () => _details(context),
              child: Text(l.details, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
    if (!locked) return card;
    return Stack(
      children: [
        Opacity(opacity: 0.35, child: card),
        Positioned.fill(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: RC.ink,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l.takenByPlayer(takenBy!),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Ticks on its own so the 8 chicken cards don't rebuild 4× a second.
class _Countdown extends StatefulWidget {
  final DateTime end;
  const _Countdown({required this.end});

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.end.difference(DateTime.now()).inSeconds.clamp(0, 99);
    return Text(
      '$left s',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        color: left <= 5 ? RC.red : RC.gold,
      ),
    );
  }
}
