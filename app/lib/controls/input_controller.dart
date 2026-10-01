import 'package:flutter/services.dart';
import 'package:rooster_core/rooster_core.dart';

import 'controls_layout.dart';

/// One frame of player intent.
class InputSample {
  final double mx, my;
  final bool heavy, block;
  final int pressed; // Btn bits
  const InputSample(this.mx, this.my, this.heavy, this.block, this.pressed);
}

/// Merges touch gestures and keyboard into one [InputSample] per frame.
///
/// Touch: left = move, right tap = light, hold = heavy, swipe up = jump,
/// swipe down = dash; buttons = ultimate, crow, guard (hold).
/// Keyboard: WASD/arrows move, J tap = light, hold J = heavy, K hold =
/// guard, L/Shift = dash, Space = jump, U = rage + ultimate, O = crow.
class InputController {
  static const holdThreshold = 0.18; // s before a touch becomes a heavy hold
  static const swipeDistance = 36.0; // px

  /// Live set of held keys (HardwareKeyboard in the app). Each frame the
  /// controller drops keys this no longer reports, so a key-up that went
  /// elsewhere (focus moved to a HUD button, window switched) can't leave a
  /// key stuck down.
  final Set<LogicalKeyboardKey> Function()? keyboardState;

  InputController({this.keyboardState});

  ControlsLayout? layout;
  bool touchSeen = false;

  // Joystick
  int? _stickPointer;
  Offset? stickOrigin;
  Offset stickVector = Offset.zero; // -1..1

  // Action finger
  int? _actionPointer;
  Offset _actionStart = Offset.zero;
  double _actionHeld = 0;
  bool _actionConsumed = false;
  bool touchHeavy = false;
  Offset? actionPos;

  // Buttons
  final Map<int, int> _buttonPointers = {};
  final List<bool> buttonDown = [false, false, false];
  // [ultimate (rage + skill), crow, guard]; guard (index 2) is a hold.
  static const _buttonBits = [Btn.skill, Btn.crow, 0];

  // Keyboard
  final Set<LogicalKeyboardKey> _keys = {};
  bool _jDown = false;
  double _jHeld = 0;
  bool _keyHeavy = false;
  bool _keyBlock = false;

  int _pressed = 0;

  /// Called on the H key (show/hide the controls cheat sheet).
  void Function()? onHelpToggle;

  // ------------------------------------------------------------ touch

  void pointerDown(int id, Offset p, PointerDeviceKindLike kind) {
    if (kind == PointerDeviceKindLike.touch) touchSeen = true;
    final l = layout;
    if (l == null || p.dy < l.hudTop) return;
    final b = l.buttonAt(p);
    if (b >= 0) {
      _buttonPointers[id] = b;
      buttonDown[b] = true;
      _pressed |= _buttonBits[b];
      return;
    }
    if (p.dx < l.splitX) {
      if (_stickPointer != null) return;
      _stickPointer = id;
      stickOrigin = p;
      stickVector = Offset.zero;
    } else {
      if (_actionPointer != null) return;
      _actionPointer = id;
      _actionStart = p;
      actionPos = p;
      _actionHeld = 0;
      _actionConsumed = false;
      touchHeavy = false;
    }
  }

  void pointerMove(int id, Offset p) {
    final l = layout;
    if (l == null) return;
    if (id == _stickPointer && stickOrigin != null) {
      var v = (p - stickOrigin!) / l.joystickRadius;
      if (v.distance > 1) {
        // Drag the base along so direction changes stay responsive.
        final over = v / v.distance;
        stickOrigin = p - over * l.joystickRadius;
        v = over;
      }
      stickVector = v;
    } else if (id == _actionPointer) {
      actionPos = p;
      if (_actionConsumed || touchHeavy) return;
      final d = p - _actionStart;
      if (d.distance >= swipeDistance) {
        _actionConsumed = true;
        if (d.dy < 0 && d.dy.abs() > d.dx.abs()) {
          _pressed |= Btn.jump;
        } else {
          _pressed |= Btn.dodge;
        }
      }
    }
  }

  void pointerUp(int id) {
    final b = _buttonPointers.remove(id);
    if (b != null) buttonDown[b] = false;
    if (id == _stickPointer) {
      _stickPointer = null;
      stickOrigin = null;
      stickVector = Offset.zero;
    } else if (id == _actionPointer) {
      if (!_actionConsumed && !touchHeavy) _pressed |= Btn.light;
      _actionPointer = null;
      actionPos = null;
      touchHeavy = false;
    }
  }

  // ------------------------------------------------------------ keyboard

  static final _left = {LogicalKeyboardKey.keyA, LogicalKeyboardKey.arrowLeft};
  static final _right = {
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.arrowRight,
  };
  static final _up = {LogicalKeyboardKey.keyW, LogicalKeyboardKey.arrowUp};
  static final _down = {LogicalKeyboardKey.keyS, LogicalKeyboardKey.arrowDown};

  bool handleKey(KeyEvent e) {
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyH) {
      if (e is KeyDownEvent) onHelpToggle?.call();
      return true;
    }
    if (e is KeyDownEvent) {
      _keys.add(k);
      if (k == LogicalKeyboardKey.keyJ) {
        // Tap vs hold is decided in sample(): release early = light.
        _jDown = true;
        _jHeld = 0;
        _keyHeavy = false;
      }
      final bit = switch (k) {
        LogicalKeyboardKey.space => Btn.jump,
        LogicalKeyboardKey.keyL || LogicalKeyboardKey.shiftLeft => Btn.dodge,
        LogicalKeyboardKey.keyU => Btn.skill, // rage + ultimate
        LogicalKeyboardKey.keyO => Btn.crow,
        _ => 0,
      };
      _pressed |= bit;
      if (k == LogicalKeyboardKey.keyK) _keyBlock = true;
    } else if (e is KeyUpEvent) {
      _keys.remove(k);
      if (k == LogicalKeyboardKey.keyJ && _jDown) {
        if (!_keyHeavy) _pressed |= Btn.light;
        _jDown = false;
        _keyHeavy = false; // releasing the hold fires the heavy attack
      }
      if (k == LogicalKeyboardKey.keyK) _keyBlock = false;
    }
    return _isGameKey(k);
  }

  bool _isGameKey(LogicalKeyboardKey k) =>
      _left.contains(k) ||
      _right.contains(k) ||
      _up.contains(k) ||
      _down.contains(k) ||
      const [
        LogicalKeyboardKey.keyJ,
        LogicalKeyboardKey.keyK,
        LogicalKeyboardKey.keyL,
        LogicalKeyboardKey.keyU,
        LogicalKeyboardKey.keyO,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.shiftLeft,
      ].contains(k);

  // ------------------------------------------------------------ sample

  /// Call once per frame; clears the edge-triggered presses.
  InputSample sample(double dt) {
    final live = keyboardState?.call();
    if (live != null) {
      _keys.removeWhere((k) => !live.contains(k));
      if (_jDown && !live.contains(LogicalKeyboardKey.keyJ)) {
        _jDown = false; // lost J release: cancel, don't fire a stray attack
        _keyHeavy = false;
      }
      if (_keyBlock && !live.contains(LogicalKeyboardKey.keyK)) {
        _keyBlock = false;
      }
    }
    if (_actionPointer != null && !_actionConsumed && !touchHeavy) {
      _actionHeld += dt;
      if (_actionHeld >= holdThreshold) touchHeavy = true;
    }
    if (_jDown && !_keyHeavy) {
      _jHeld += dt;
      if (_jHeld >= holdThreshold) _keyHeavy = true;
    }
    var mx = stickVector.dx, my = stickVector.dy;
    double axis(Set<LogicalKeyboardKey> neg, Set<LogicalKeyboardKey> pos) =>
        (_keys.any(pos.contains) ? 1.0 : 0.0) -
        (_keys.any(neg.contains) ? 1.0 : 0.0);
    final kx = axis(_left, _right), ky = axis(_up, _down);
    if (kx != 0 || ky != 0) {
      final len = Offset(kx, ky).distance;
      mx = kx / len;
      my = ky / len;
    }
    final pressed = _pressed;
    _pressed = 0;
    return InputSample(
      mx,
      my,
      touchHeavy || _keyHeavy,
      _keyBlock || buttonDown[2],
      pressed,
    );
  }

  void reset() {
    _stickPointer = null;
    _actionPointer = null;
    stickOrigin = null;
    stickVector = Offset.zero;
    touchHeavy = false;
    _keyHeavy = false;
    _keyBlock = false;
    _jDown = false;
    _keys.clear();
    _buttonPointers.clear();
    buttonDown.fillRange(0, buttonDown.length, false);
    _pressed = 0;
  }
}

enum PointerDeviceKindLike { touch, mouse, other }
