import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster_rage/controls/input_controller.dart';
import 'package:rooster_rage/l10n/l10n.dart';
import 'package:rooster_rage/widgets/controls_help.dart';

void main() {
  setUp(() {
    L10n.setLang(AppLang.vi);
  });

  test('H toggles the help panel and is not a game input', () {
    var toggles = 0;
    final c = InputController()..onHelpToggle = () => toggles++;
    const down = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyH,
      logicalKey: LogicalKeyboardKey.keyH,
      timeStamp: Duration.zero,
    );
    const up = KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.keyH,
      logicalKey: LogicalKeyboardKey.keyH,
      timeStamp: Duration.zero,
    );
    expect(c.handleKey(down), isTrue);
    expect(c.handleKey(up), isTrue);
    expect(toggles, 1);
    expect(c.sample(1 / 60).pressed, 0);
  });

  testWidgets('desktop sheet lists keys and the class skill', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ControlsHelp(touch: false, skillName: 'Flame Kick'),
          ),
        ),
      ),
    );
    expect(find.text('Đầy Nộ: bật Nộ + tung Flame Kick luôn'), findsOneWidget);
    expect(find.text('I'), findsNothing);
    expect(find.text('Giữ K'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
    expect(find.text('Ẩn / hiện bảng này'), findsOneWidget);
  });

  testWidgets('touch sheet lists gestures', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ControlsHelp(touch: true, skillName: 'Shadow Dash'),
          ),
        ),
      ),
    );
    expect(find.text('Vuốt lên'), findsOneWidget);
    expect(find.text('THỦ'), findsOneWidget);
    expect(find.text('Đầy Nộ: bật Nộ + tung Shadow Dash luôn'), findsOneWidget);
    expect(find.text('NỘ'), findsNothing);
    expect(find.text('H'), findsNothing);
  });

  testWidgets('controls help updates when language is switched to English', (tester) async {
    L10n.setLang(AppLang.en);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ControlsHelp(touch: false, skillName: 'Flame Kick'),
          ),
        ),
      ),
    );
    expect(find.text('CONTROLS'), findsOneWidget);
    expect(find.text('Rage full: unleash Rage + Flame Kick'), findsOneWidget);
  });
}
