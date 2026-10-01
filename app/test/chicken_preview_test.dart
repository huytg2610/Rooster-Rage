// Renders a contact sheet of every class x state (plus flag/rarity rows) to
// build/chicken_preview.png for visual review of the procedural chickens.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rooster_core/rooster_core.dart';
import 'package:rooster_rage/game/render/chicken_painter.dart';

const double _cell = 124;
const double _scale = 2;

const _slots = <ui.Color>[
  ui.Color(0xFFE53935),
  ui.Color(0xFF1E88E5),
  ui.Color(0xFF43A047),
  ui.Color(0xFFFDD835),
  ui.Color(0xFF8E24AA),
  ui.Color(0xFFFF8F00),
  ui.Color(0xFF00ACC1),
  ui.Color(0xFFEC407A),
];

const _classes = [
  'samurai',
  'ninja',
  'tank',
  'berserker',
  'troll',
  'dongtao',
  'bantam',
  'silkie',
];
const _cols = 13;

typedef _Shot = ({ChickenLook look, ChickenPose pose, double z});

ChickenLook _look(int i, {Rarity rarity = Rarity.common, String? cls}) =>
    ChickenLook(
      classId: cls ?? _classes[i % _classes.length],
      variant: Variant.values[i % 5],
      rarity: rarity,
      slotColor: _slots[i % _slots.length],
    );

List<_Shot> _stateRow(int i) {
  final look = _look(i);
  _Shot s(
    FState st, {
    double t = 0.2,
    double dur = 0,
    double time = 1.0,
    double speed = 0,
    double charge = 0,
    int combo = 1,
    double z = 0,
  }) => (
    look: look,
    pose: ChickenPose(
      state: st,
      stateTime: t,
      stateDur: dur,
      time: time,
      speed01: speed,
      heavyCharge01: charge,
      comboStep: combo,
    ),
    z: z,
  );
  // Representative skill moments per class (troll's skill is fakeDead).
  const skillT = [0.2, 0.12, 0.4, 0.2, 0.1, 0.12, 0.375, 0.6];
  const skillDur = [0.44, 0.28, 2.0, 0.4, 3.0, 0.9, 1.0, 1.25];
  return [
    s(FState.idle, t: 0.5),
    s(FState.run, speed: 1, time: 0.13),
    s(FState.attack, t: 0.11, dur: 0.16),
    s(FState.heavyCharge, charge: 0.8),
    s(FState.jump, z: 6),
    s(FState.dodge, t: 0.1, dur: 0.24),
    s(FState.hitstun, t: 0.08, dur: 0.3),
    s(FState.stunned, t: 0.5, dur: 1.4),
    s(FState.exhausted, t: 0.3, dur: 1.1),
    s(
      i == 4 ? FState.fakeDead : FState.skill,
      t: skillT[i],
      dur: skillDur[i],
      z: i == 2 ? 6 : 0,
    ),
    s(FState.crow, t: 0.25, dur: 0.55),
    s(FState.dead, t: 1.0),
    s(FState.block, t: 0.3),
  ];
}

List<_Shot> _extraRows() {
  _Shot s(
    ChickenLook look,
    FState st, {
    double t = 0.2,
    double dur = 0,
    double time = 1.0,
    double speed = 0,
    int flags = 0,
    bool right = true,
    double flash = 0,
    int combo = 1,
  }) => (
    look: look,
    pose: ChickenPose(
      state: st,
      stateTime: t,
      stateDur: dur,
      time: time,
      speed01: speed,
      flags: flags,
      faceRight: right,
      hitFlash: flash,
      comboStep: combo,
    ),
    z: 0,
  );
  return [
    s(_look(0), FState.run, speed: 0.8, flags: FFlag.rage | FFlag.superArmor),
    s(_look(2), FState.idle, flags: FFlag.burning),
    s(_look(1), FState.idle, flags: FFlag.confused),
    s(_look(0, rarity: Rarity.legendary), FState.idle, time: 1.3),
    s(_look(4), FState.run, speed: 0.6, right: false),
    s(_look(1, rarity: Rarity.rare), FState.idle, time: 0.4),
    s(_look(3, rarity: Rarity.epic), FState.idle, time: 0.9),
    s(_look(3), FState.skill, t: 0.2, flags: FFlag.mad),
    s(_look(1), FState.idle, flags: FFlag.empowered),
    s(_look(2), FState.idle, flags: FFlag.superArmor),
    s(_look(0), FState.hitstun, t: 0.05, dur: 0.3, flash: 0.7),
    s(_look(2), FState.idle, flags: FFlag.invuln, time: 0.0),
    s(_look(5), FState.run, speed: 1, time: 0.2),
    // Row 2
    s(_look(0), FState.heavyAttack, t: 0.17, dur: 0.22),
    s(_look(4), FState.fakeDead, t: 1.0),
    s(_look(4), FState.dead, t: 1.0),
    s(_look(1), FState.falling, t: 0.3),
    s(_look(3), FState.rageRoar, t: 0.25, dur: 0.55, flags: FFlag.rage),
    s(_look(2), FState.recovery, t: 0.05, dur: 0.2),
    s(_look(0), FState.attack, t: 0.12, dur: 0.16, combo: 2),
    s(_look(1), FState.attack, t: 0.12, dur: 0.16, combo: 3),
    s(_look(2, rarity: Rarity.legendary), FState.idle, time: 1.3),
    s(_look(4, rarity: Rarity.legendary), FState.idle, time: 1.3),
    s(_look(3, rarity: Rarity.legendary), FState.run, speed: 1, time: 0.3),
    s(_look(0), FState.dead, t: 0.1),
    s(_look(6), FState.run, speed: 1, time: 0.2),
    // Row 3: the Vietnamese breeds in more moments.
    s(_look(5), FState.skill, t: 0.47, dur: 0.9),
    s(_look(5), FState.skill, t: 0.42, dur: 0.9),
    s(_look(6), FState.skill, t: 0.4, dur: 1.0, speed: 1),
    s(_look(6), FState.skill, t: 0.42, dur: 1.0),
    s(_look(7), FState.skill, t: 0.1, dur: 1.25, time: 2.0),
    s(_look(7), FState.run, speed: 1, time: 0.2),
    s(_look(5, rarity: Rarity.legendary), FState.idle, time: 1.3),
    s(_look(6, rarity: Rarity.legendary), FState.idle, time: 1.3),
    s(_look(7, rarity: Rarity.legendary), FState.idle, time: 1.3),
    s(_look(7), FState.idle, flags: FFlag.confused | FFlag.burning),
    s(_look(6), FState.idle, right: false, flags: FFlag.rage),
    s(_look(5), FState.hitstun, t: 0.05, dur: 0.3, flash: 0.6),
    s(_look(7), FState.attack, t: 0.12, dur: 0.16),
  ];
}

void _drawSheet(ui.Canvas canvas, List<List<_Shot>> rows, double w, double h) {
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w, h),
    ui.Paint()..color = const ui.Color(0xFFF4ECDA),
  );
  final grid = ui.Paint()
    ..color = const ui.Color(0xFFDCCFB4)
    ..style = ui.PaintingStyle.stroke;
  final shadow = ui.Paint()..color = const ui.Color(0x33000000);
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final shot = rows[r][c];
      final x = c * _cell, y = r * _cell;
      canvas.drawRect(ui.Rect.fromLTWH(x, y, _cell, _cell), grid);
      canvas.save();
      canvas.translate(x + _cell / 2, y + _cell * 0.86);
      canvas.scale(_scale);
      canvas.drawOval(
        ui.Rect.fromCenter(center: ui.Offset.zero, width: 26, height: 8),
        shadow,
      );
      canvas.translate(0, -shot.z);
      ChickenPainter.paint(canvas, shot.look, shot.pose);
      canvas.restore();
    }
  }
}

void main() {
  testWidgets('render chicken contact sheet', (tester) async {
    await tester.runAsync(() async {
      final extra = _extraRows();
      final rows = <List<_Shot>>[
        for (var i = 0; i < _classes.length; i++) _stateRow(i),
        for (var i = 0; i < extra.length; i += _cols)
          extra.sublist(i, i + _cols),
      ];
      final w = _cols * _cell, h = rows.length * _cell;
      final rec = ui.PictureRecorder();
      _drawSheet(ui.Canvas(rec), rows, w, h);
      final image = await rec.endRecording().toImage(w.toInt(), h.toInt());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/chicken_preview.png')
        ..createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      expect(file.lengthSync(), greaterThan(1000));
    });
  });
}
