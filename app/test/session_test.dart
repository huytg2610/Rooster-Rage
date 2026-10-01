import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster_core/rooster_core.dart';
import 'package:rooster_rage/app/profile.dart';
import 'package:rooster_rage/controls/controls_layout.dart';
import 'package:rooster_rage/controls/input_controller.dart';
import 'package:rooster_rage/net/client_link.dart';
import 'package:rooster_rage/net/session.dart';
import 'package:rooster_rage/net/snapshot_buffer.dart';

Future<void> waitFor(bool Function() cond, {int ms = 25000}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsedMilliseconds > ms) {
      throw TimeoutException('condition not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test(
    'offline session: lobby → reveal → match with interpolated frames',
    () async {
      final s = Session(
        link: LocalLink(settings: const LobbySettings(bots: 3, duration: 60)),
        profile: const Profile(pid: 'test-pid', name: 'Tester', gamesPlayed: 0),
        isLocal: true,
      );
      await waitFor(() => s.room != null);
      expect(s.isOwner, isTrue);
      expect(s.phase, RoomPhase.lobby);

      s.start();
      await waitFor(() => s.phase == RoomPhase.reveal);
      expect(s.reveal, hasLength(4));
      expect(s.reveal.where((e) => e.pid == 'test-pid'), hasLength(1));

      await waitFor(() => s.phase == RoomPhase.match && s.buffer.hasData);
      expect(s.match!.you, isNotNull);
      expect(s.match!.fighters, hasLength(4));

      // Frames interpolate and include every fighter.
      RenderFrame? f;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        f = s.buffer.update(1 / 60) ?? f;
      }
      expect(f, isNotNull);
      expect(f!.fighters, hasLength(4));
      expect(f.fighter(s.match!.you), isNotNull);

      // Input reaches the host after the countdown.
      await waitFor(
        () => s.buffer.latest!.phase == MatchPhase.fighting,
        ms: 10000,
      );
      final x0 = s.buffer.latest!.fighter(s.match!.you!)!.x;
      for (var i = 0; i < 40; i++) {
        s.sendInput(1, 0, false, 0);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      final x1 = s.buffer.latest!.fighter(s.match!.you!)!.x;
      expect(x1, greaterThan(x0 + 0.5));
      s.dispose();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  group('touch gestures (GDD §2)', () {
    InputController make() =>
        InputController()..layout = ControlsLayout.of(const Size(800, 400));

    test('left side drag moves', () {
      final c = make();
      c.pointerDown(1, const Offset(100, 300), PointerDeviceKindLike.touch);
      c.pointerMove(1, const Offset(160, 300));
      final smp = c.sample(1 / 60);
      expect(smp.mx, greaterThan(0.5));
      expect(smp.my.abs(), lessThan(0.01));
    });

    test(
      'right tap = light, hold = heavy, swipe up = jump, swipe down = dodge',
      () {
        final c = make();
        c.pointerDown(2, const Offset(550, 250), PointerDeviceKindLike.touch);
        c.pointerUp(2);
        expect(c.sample(1 / 60).pressed & Btn.light, isNonZero);

        c.pointerDown(3, const Offset(550, 250), PointerDeviceKindLike.touch);
        for (var i = 0; i < 15; i++) {
          c.sample(1 / 60);
        }
        expect(c.sample(1 / 60).heavy, isTrue); // heavy held
        c.pointerUp(3);
        final after = c.sample(1 / 60);
        expect(after.heavy, isFalse);
        expect(after.pressed & Btn.light, isZero); // releasing a hold is not a tap

        c.pointerDown(4, const Offset(550, 300), PointerDeviceKindLike.touch);
        c.pointerMove(4, const Offset(552, 240));
        c.pointerUp(4);
        expect(c.sample(1 / 60).pressed, Btn.jump);

        c.pointerDown(5, const Offset(550, 200), PointerDeviceKindLike.touch);
        c.pointerMove(5, const Offset(552, 260));
        c.pointerUp(5);
        expect(c.sample(1 / 60).pressed, Btn.dodge);
      },
    );

    test('touch buttons: CHIÊU (rage + ultimate) and GÁY fire their slot', () {
      final c = make();
      final l = c.layout!;
      expect(l.buttons, hasLength(3));
      c.pointerDown(6, l.buttons[0], PointerDeviceKindLike.touch);
      c.pointerDown(7, l.buttons[1], PointerDeviceKindLike.touch);
      expect(c.sample(1 / 60).pressed, Btn.skill | Btn.crow);
    });

    KeyDownEvent down(LogicalKeyboardKey k, PhysicalKeyboardKey p) =>
        KeyDownEvent(physicalKey: p, logicalKey: k, timeStamp: Duration.zero);
    KeyUpEvent up(LogicalKeyboardKey k, PhysicalKeyboardKey p) =>
        KeyUpEvent(physicalKey: p, logicalKey: k, timeStamp: Duration.zero);
    const j = (LogicalKeyboardKey.keyJ, PhysicalKeyboardKey.keyJ);
    const k = (LogicalKeyboardKey.keyK, PhysicalKeyboardKey.keyK);

    test('keyboard: WASD moves, tap J = light attack', () {
      final c = make();
      c.handleKey(down(LogicalKeyboardKey.keyD, PhysicalKeyboardKey.keyD));
      c.handleKey(down(j.$1, j.$2));
      c.handleKey(up(j.$1, j.$2));
      final smp = c.sample(1 / 60);
      expect(smp.mx, 1);
      expect(smp.pressed, Btn.light);
      expect(smp.heavy, isFalse);
    });

    test('keyboard: hold J = heavy (no light on release), hold K = guard', () {
      final c = make();
      c.handleKey(down(j.$1, j.$2));
      for (var i = 0; i < 15; i++) {
        c.sample(1 / 60);
      }
      expect(c.sample(1 / 60).heavy, isTrue);
      c.handleKey(up(j.$1, j.$2));
      final rel = c.sample(1 / 60);
      expect(rel.heavy, isFalse);
      expect(rel.pressed & Btn.light, isZero);

      c.handleKey(down(k.$1, k.$2));
      expect(c.sample(1 / 60).block, isTrue);
      c.handleKey(up(k.$1, k.$2));
      expect(c.sample(1 / 60).block, isFalse);
    });

    test('a lost key-up (focus moved away) never leaves a key stuck', () {
      final live = <LogicalKeyboardKey>{};
      final c = InputController(keyboardState: () => live);
      void press(LogicalKeyboardKey lk, PhysicalKeyboardKey pk) {
        live.add(lk);
        c.handleKey(down(lk, pk));
      }

      press(LogicalKeyboardKey.keyW, PhysicalKeyboardKey.keyW);
      press(j.$1, j.$2);
      press(k.$1, k.$2);
      for (var i = 0; i < 15; i++) {
        c.sample(1 / 60);
      }
      final held = c.sample(1 / 60);
      expect(held.my, lessThan(0));
      expect(held.heavy, isTrue);
      expect(held.block, isTrue);
      // The key-ups went to another widget: only the live state knows.
      live.clear();
      final after = c.sample(1 / 60);
      expect(after.my, 0);
      expect(after.heavy, isFalse);
      expect(after.block, isFalse);
      expect(after.pressed, 0); // no stray light attack
    });

    test('keyboard: L dash, U rage + ultimate, O crow; I is unbound', () {
      final c = make();
      for (final (lk, pk) in [
        (LogicalKeyboardKey.keyL, PhysicalKeyboardKey.keyL),
        (LogicalKeyboardKey.keyI, PhysicalKeyboardKey.keyI),
        (LogicalKeyboardKey.keyU, PhysicalKeyboardKey.keyU),
        (LogicalKeyboardKey.keyO, PhysicalKeyboardKey.keyO),
      ]) {
        c.handleKey(down(lk, pk));
        c.handleKey(up(lk, pk));
      }
      expect(c.sample(1 / 60).pressed, Btn.dodge | Btn.skill | Btn.crow);
    });

    test('touch guard button is a hold', () {
      final c = make();
      final l = c.layout!;
      c.pointerDown(9, l.buttons[2], PointerDeviceKindLike.touch);
      expect(c.sample(1 / 60).block, isTrue);
      c.pointerUp(9);
      expect(c.sample(1 / 60).block, isFalse);
    });
  });
}
