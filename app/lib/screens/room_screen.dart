import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rooster_core/rooster_core.dart';

import '../app/providers.dart';
import '../net/client_link.dart';
import '../net/session.dart';
import '../ui/theme.dart';
import 'lobby_view.dart';
import 'match_view.dart';
import 'pick_view.dart';
import 'results_view.dart';
import 'reveal_view.dart';

/// Hosts every in-room phase and switches view as the host advances.
class RoomScreen extends ConsumerWidget {
  const RoomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/');
      });
      return const Scaffold();
    }
    void leave() {
      ref.read(sessionProvider.notifier).leave();
      context.go('/');
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          // The owner who closed the room goes straight home.
          if (session.closedByMe && session.closedReason != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) leave();
            });
          }
          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(child: _phaseView(session, leave)),
                if (session.linkStatus == LinkStatus.reconnecting ||
                    session.linkStatus == LinkStatus.connecting)
                  _Banner(
                    text: session.linkStatus == LinkStatus.connecting
                        ? 'Đang kết nối tới host...'
                        : 'Mất kết nối — đang nối lại...',
                  ),
                if (session.closedReason != null && !session.closedByMe)
                  _Disconnected(
                    onLeave: leave,
                    message: session.closedReason!,
                    icon: Icons.meeting_room_outlined,
                    hint: 'Bạn đã được đưa ra khỏi phòng.',
                  )
                else if (session.linkStatus == LinkStatus.closed &&
                    session.closedReason == null)
                  _Disconnected(onLeave: leave),
                if (session.error != null && session.room == null)
                  _Disconnected(onLeave: leave, message: session.error!),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _phaseView(Session s, VoidCallback leave) {
    if (s.room == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return switch (s.phase) {
      RoomPhase.lobby => LobbyView(session: s, onLeave: leave),
      RoomPhase.picking => PickView(session: s),
      RoomPhase.reveal => RevealView(session: s),
      RoomPhase.match =>
        s.match == null
            ? const Center(child: CircularProgressIndicator())
            : MatchView(key: ValueKey(s.match), session: s, onLeave: leave),
      RoomPhase.results => ResultsView(session: s, onLeave: leave),
    };
  }
}

class _Banner extends StatelessWidget {
  final String text;
  const _Banner({required this.text});

  @override
  Widget build(BuildContext context) => Positioned(
    top: 8,
    left: 0,
    right: 0,
    child: Center(
      child: Material(
        color: RC.red,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: RC.cream,
                ),
              ),
              const SizedBox(width: 10),
              Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Disconnected extends StatelessWidget {
  final VoidCallback onLeave;
  final String message;
  final IconData icon;
  final String hint;
  const _Disconnected({
    required this.onLeave,
    this.message = 'Không kết nối được tới host.',
    this.icon = Icons.wifi_off,
    this.hint = 'Kiểm tra cùng WiFi và host đang chạy.',
  });

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xCC000000),
      child: Center(
        child: WoodPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: RC.gold),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(hint, style: const TextStyle(color: RC.muted, fontSize: 13)),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: onLeave,
                child: const Text('VỀ MÀN HÌNH CHÍNH'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
