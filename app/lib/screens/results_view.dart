import 'package:flutter/material.dart';
import 'package:rooster_core/rooster_core.dart';

import '../audio/sound_fx.dart';
import '../net/session.dart';
import '../ui/theme.dart';
import '../widgets/chicken_avatar.dart';
import '../widgets/close_room.dart';

class ResultsView extends StatelessWidget {
  final Session session;
  final VoidCallback onLeave;
  const ResultsView({super.key, required this.session, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    final results = session.results ?? const <FighterResult>[];
    final infos = session.match?.fighters ?? const {};
    final you = session.match?.you;
    final winner = results.isEmpty ? null : infos[results.first.id];
    final mvpDamage = results.isEmpty
        ? null
        : results.reduce((a, b) => a.damage >= b.damage ? a : b).id;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _PlayOnce(SoundId.fanfare),
                if (winner != null) ...[
                  Center(
                    child: ChickenAvatar(
                      chicken: ChickenInstance(
                        winner.classId,
                        winner.variant,
                        winner.rarity,
                      ),
                      slotColor: Color(slotColors[winner.slot % 8]),
                      size: 130,
                      state: FState.crow,
                    ),
                  ),
                  Text(
                    winner.id == you
                        ? 'BẠN VÔ ĐỊCH!'
                        : '${winner.name} VÔ ĐỊCH!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: RC.gold,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                WoodPanel(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          SizedBox(width: 28),
                          Expanded(
                            child: Text(
                              'Chiến kê',
                              style: TextStyle(color: RC.muted, fontSize: 12),
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            child: Text(
                              'KO',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: RC.muted, fontSize: 12),
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            child: Text(
                              'Gục',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: RC.muted, fontSize: 12),
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text(
                              'S.thương',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: RC.muted, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      for (final r in results)
                        if (infos[r.id] case final info?)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: r.id == you ? RC.panelHi : null,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '#${r.rank}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: r.rank == 1 ? RC.gold : RC.cream,
                                    ),
                                  ),
                                ),
                                ChickenAvatar(
                                  chicken: ChickenInstance(
                                    info.classId,
                                    info.variant,
                                    info.rarity,
                                  ),
                                  slotColor: Color(slotColors[info.slot % 8]),
                                  size: 40,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.id == you
                                            ? '${info.name} (bạn)'
                                            : info.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Color(
                                            slotColors[info.slot % 8],
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${ChickenClasses.byId(info.classId).nameVi}'
                                        '${r.id == mvpDamage ? ' · Đòn tay to nhất' : ''}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: RC.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    '${r.kos}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    '${r.deaths}',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                SizedBox(
                                  width: 52,
                                  child: Text(
                                    '${r.damage.round()}',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (session.isOwner) ...[
                  FilledButton(
                    onPressed: session.rematch,
                    child: const Text('ĐÁ TIẾP!'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: session.backToLobby,
                    child: const Text('Về phòng chờ'),
                  ),
                  if (!session.isLocal) ...[
                    const SizedBox(height: 8),
                    CloseRoomButton(session: session),
                  ],
                ] else
                  const Text(
                    'Chờ chủ phòng mở trận mới...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: RC.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                TextButton(onPressed: onLeave, child: const Text('Rời phòng')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Plays a sound once when it first appears in the tree.
class _PlayOnce extends StatefulWidget {
  final SoundId id;
  const _PlayOnce(this.id);

  @override
  State<_PlayOnce> createState() => _PlayOnceState();
}

class _PlayOnceState extends State<_PlayOnce> {
  @override
  void initState() {
    super.initState();
    SoundFx.instance.play(widget.id);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
