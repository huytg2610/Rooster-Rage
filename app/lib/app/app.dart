import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/home_screen.dart';
import '../screens/room_screen.dart';
import '../screens/roster_screen.dart';
import '../audio/sound_fx.dart';
import '../ui/theme.dart';
import 'providers.dart';

class RoosterApp extends ConsumerStatefulWidget {
  const RoosterApp({super.key});

  @override
  ConsumerState<RoosterApp> createState() => _RoosterAppState();
}

class _RoosterAppState extends ConsumerState<RoosterApp> {
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/room', builder: (_, _) => const RoomScreen()),
      GoRoute(path: '/chickens', builder: (_, _) => const RosterScreen()),
    ],
    redirect: (context, state) {
      final inRoom = ref.read(sessionProvider) != null;
      if (state.matchedLocation == '/room' && !inRoom) return '/';
      return null;
    },
  );

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Rooster Rage',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    routerConfig: _router,
    // First tap anywhere unlocks Web Audio (autoplay policy). Touch screens
    // only grant audio permission on touch *end*, so unlock on up as well.
    builder: (context, child) => Listener(
      onPointerDown: (_) => SoundFx.instance.unlock(),
      onPointerUp: (_) => SoundFx.instance.unlock(),
      child: child,
    ),
  );
}
