import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rooster_core/rooster_core.dart';

import '../l10n/l10n.dart';
import '../net/session.dart';
import '../platform/web_helpers.dart';
import '../ui/theme.dart';
import '../widgets/close_room.dart';
import '../widgets/qr_view.dart';
import 'roster_screen.dart';

class LobbyView extends ConsumerWidget {
  final Session session;
  final VoidCallback onLeave;
  const LobbyView({super.key, required this.session, required this.onLeave});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(l10nProvider);
    final s = L10n.current;

    final room = session.room!;
    final owner = session.isOwner;
    final st = room.settings;
    final wide = MediaQuery.sizeOf(context).width > 600;
    final humans = room.players.length;
    final bots = st.bots.clamp(0, RoomHost.maxFighters - humans);

    final players = WoodPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${s.roostersHeader(humans)}${bots > 0 ? ' + $bots bot' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w900, color: RC.gold),
          ),
          const SizedBox(height: 8),
          for (final p in room.players)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: Color(slotColors[p.slot % 8]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${p.name}${p.pid == session.myPid ? ' ${s.you}' : ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: p.connected ? RC.cream : RC.muted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (p.pid == room.ownerPid)
                    const Icon(Icons.emoji_events, color: RC.gold, size: 18),
                ],
              ),
            ),
          for (var i = 0; i < bots; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(
                    Icons.smart_toy_outlined,
                    size: 18,
                    color: RC.muted,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    botNames[i % botNames.length],
                    style: const TextStyle(color: RC.muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    void set(LobbySettings s) => session.updateSettings(s);
    Widget choice<T>(
      String label,
      T value,
      T current,
      void Function(T) onTap,
    ) => ChoiceChip(
      label: Text(label),
      selected: value == current,
      onSelected: owner ? (_) => onTap(value) : null,
      selectedColor: RC.gold,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        color: value == current ? RC.ink : RC.cream,
      ),
    );
    Widget row(String title, List<Widget> chips) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: RC.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: chips),
        ],
      ),
    );

    final arena = Arenas.byId(st.arenaId);
    final settings = WoodPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            owner ? s.rulesHeader : '${s.rulesHeader} (${L10n.currentLang == AppLang.en ? "host controls" : "chủ phòng chỉnh"})',
            style: const TextStyle(fontWeight: FontWeight.w900, color: RC.gold),
          ),
          const SizedBox(height: 8),
          row(s.mode, [
            choice(
              s.randomChicken,
              GameMode.party,
              st.mode,
              (v) => set(st.copyWith(mode: v)),
            ),
            choice(
              s.pickChicken,
              GameMode.competitive,
              st.mode,
              (v) => set(st.copyWith(mode: v)),
            ),
          ]),
          row(s.rules, [
            choice(
              s.respawn,
              false,
              st.survival,
              (v) => set(st.copyWith(survival: v)),
            ),
            choice(
              s.survival,
              true,
              st.survival,
              (v) => set(st.copyWith(survival: v)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              st.survival ? s.survivalDesc : s.respawnDesc,
              style: const TextStyle(fontSize: 12, color: RC.cream),
            ),
          ),
          row(s.arena, [
            for (final a in Arenas.all)
              choice(
                s.arenaName(a),
                a.id,
                st.arenaId,
                (v) => set(st.copyWith(arenaId: v)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              s.arenaDesc(arena),
              style: const TextStyle(fontSize: 12, color: RC.cream),
            ),
          ),
          row(s.duration, [
            for (final d in const [60, 120, 180, 300])
              choice(
                s.minutes(d ~/ 60),
                d,
                st.duration,
                (v) => set(st.copyWith(duration: v)),
              ),
          ]),
          row(s.addBots, [
            for (var b = 0; b <= 7; b++)
              if (b + humans <= RoomHost.maxFighters)
                choice('$b', b, st.bots, (v) => set(st.copyWith(bots: v))),
          ]),
          row(s.botDifficulty, [
            choice(s.easy, 0, st.botLevel, (v) => set(st.copyWith(botLevel: v))),
            choice(s.medium, 1, st.botLevel, (v) => set(st.copyWith(botLevel: v))),
            choice(s.hard, 2, st.botLevel, (v) => set(st.copyWith(botLevel: v))),
          ]),
        ],
      ),
    );

    final join = room.local || room.joinUrls.isEmpty
        ? null
        : WoodPanel(
            child: Column(
              children: [
                Text(
                  s.scanToJoin.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: RC.gold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                QrView(data: room.joinUrls.first, size: wide ? 150 : 120),
                const SizedBox(height: 8),
                for (final u in room.joinUrls.take(2))
                  SelectableText(
                    u,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
              ],
            ),
          );

    final canStart = owner && humans + bots >= 2;
    final start = owner
        ? FilledButton(
            onPressed: canStart ? session.start : null,
            child: Text(canStart ? s.start : s.needAtLeastTwo),
          )
        : Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              s.waitingHostStart,
              textAlign: TextAlign.center,
              style: const TextStyle(color: RC.muted, fontWeight: FontWeight.w800),
            ),
          );

    final header = Row(
      children: [
        IconButton(onPressed: onLeave, icon: const Icon(Icons.arrow_back)),
        Expanded(
          child: Text(
            room.local ? s.practiceTitle : '${s.lobbyTitle} LAN',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
        ),
        const LanguageToggleButton(compact: true),
        const SizedBox(width: 4),
        IconButton(
          tooltip: s.viewRoster,
          onPressed: () => RosterScreen.open(context),
          icon: const Icon(Icons.menu_book, color: RC.gold),
        ),
        if (owner && !room.local) ...[
          CloseRoomButton(session: session, compact: !wide),
          const SizedBox(width: 6),
        ],
        if (WebHelpers.isWeb)
          IconButton(
            tooltip: 'Toàn màn hình',
            onPressed: WebHelpers.enterFullscreen,
            icon: const Icon(Icons.fullscreen),
          ),
      ],
    );

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      const SizedBox(height: 8),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  players,
                                  if (join != null) ...[
                                    const SizedBox(height: 12),
                                    join,
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(flex: 2, child: settings),
                          ],
                        )
                      else ...[
                        players,
                        const SizedBox(height: 12),
                        settings,
                        if (join != null) ...[const SizedBox(height: 12), join],
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Start stays reachable on short landscape phones.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: SizedBox(width: double.infinity, child: start),
            ),
          ),
        ],
      ),
    );
  }
}
