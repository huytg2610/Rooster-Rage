import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../net/session.dart';
import '../ui/theme.dart';

/// Owner-only: confirm, then close the LAN room and kick every player.
Future<void> confirmCloseRoom(BuildContext context, Session session) async {
  final s = L10n.current;
  final others = (session.room?.players.length ?? 1) - 1;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.closeRoomTitle),
      content: Text(s.closeRoomContent(others)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: RC.red,
            foregroundColor: RC.cream,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(s.closeRoomConfirm),
        ),
      ],
    ),
  );
  if (ok == true) session.closeRoom();
}

/// Red "close room" button shown to the owner of a LAN room.
class CloseRoomButton extends ConsumerWidget {
  final Session session;
  final bool compact;
  const CloseRoomButton({
    super.key,
    required this.session,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(l10nProvider);
    final s = L10n.current;
    if (!session.isOwner || session.isLocal) return const SizedBox.shrink();
    void onTap() => confirmCloseRoom(context, session);
    return compact
        ? IconButton(
            tooltip: s.closeRoomBtn,
            onPressed: onTap,
            icon: const Icon(Icons.meeting_room_outlined, color: RC.red),
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: RC.red,
              side: const BorderSide(color: RC.red, width: 2),
            ),
            icon: const Icon(Icons.meeting_room_outlined),
            label: Text(s.closeRoomBtn),
          );
  }
}
