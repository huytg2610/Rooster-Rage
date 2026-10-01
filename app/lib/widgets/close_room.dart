import 'package:flutter/material.dart';

import '../net/session.dart';
import '../ui/theme.dart';

/// Owner-only: confirm, then close the LAN room and kick every player.
Future<void> confirmCloseRoom(BuildContext context, Session session) async {
  final others = (session.room?.players.length ?? 1) - 1;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Đóng phòng LAN?'),
      content: Text(
        others > 0
            ? 'Tất cả $others người chơi khác sẽ bị đưa ra khỏi phòng.'
            : 'Phòng sẽ bị đóng.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: RC.red,
            foregroundColor: RC.cream,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('ĐÓNG PHÒNG'),
        ),
      ],
    ),
  );
  if (ok == true) session.closeRoom();
}

/// Red "close room" button shown to the owner of a LAN room.
class CloseRoomButton extends StatelessWidget {
  final Session session;
  final bool compact;
  const CloseRoomButton({
    super.key,
    required this.session,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!session.isOwner || session.isLocal) return const SizedBox.shrink();
    void onTap() => confirmCloseRoom(context, session);
    return compact
        ? IconButton(
            tooltip: 'Đóng phòng',
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
            label: const Text('Đóng phòng'),
          );
  }
}
