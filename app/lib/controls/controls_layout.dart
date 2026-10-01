import 'dart:math' as math;
import 'dart:ui';

/// Screen-space layout shared by the touch handler and the HUD painter so
/// what you see is exactly what you can press (GDD §2 mobile UX).
class ControlsLayout {
  final Size size;
  final double buttonRadius;
  final List<Offset> buttons; // [ultimate, crow, guard]
  final double joystickRadius;
  final double splitX; // left of this = movement, right = actions
  final double hudTop; // touches above this are ignored (HUD)

  ControlsLayout._(
    this.size,
    this.buttonRadius,
    this.buttons,
    this.joystickRadius,
    this.splitX,
    this.hudTop,
  );

  factory ControlsLayout.of(Size size) {
    final short = math.min(size.width, size.height);
    final r = (short * 0.075).clamp(24.0, 38.0);
    final pad = math.max(10.0, short * 0.03);
    final x = size.width - pad - r;
    final bottom = size.height - pad - r;
    return ControlsLayout._(
      size,
      r,
      [
        Offset(x, bottom - r * 2.3), // ultimate: rage + class skill
        Offset(x, bottom), // crow
        Offset(x - r * 2.4, bottom), // guard (hold), next to the thumb
      ],
      (short * 0.14).clamp(44.0, 70.0),
      size.width * 0.45,
      56,
    );
  }

  /// Index of the button under [p], or -1. Hit area is 25% larger.
  int buttonAt(Offset p) {
    for (var i = 0; i < buttons.length; i++) {
      if ((p - buttons[i]).distance <= buttonRadius * 1.25) return i;
    }
    return -1;
  }
}
