/// Player intent for one simulation tick (GDD §2 touch mapping).
library;

class Btn {
  static const light = 1; // tap right side
  static const jump = 2; // swipe up
  static const dodge = 4; // swipe down
  static const skill = 8; // class skill (slot 1)
  static const rage = 16; // rage mode (slot 2)
  static const crow = 32; // crow / taunt (slot 3)
}

class InputState {
  /// Movement stick, each axis in [-1, 1].
  double mx;
  double my;

  /// Heavy attack is "hold": true while the right-side finger / J is held.
  bool heavyHeld;

  /// Guard: true while the block button / K is held.
  bool blockHeld;

  /// Edge-triggered presses (bitmask of [Btn]) since the last tick.
  int pressed;

  InputState({
    this.mx = 0,
    this.my = 0,
    this.heavyHeld = false,
    this.blockHeld = false,
    this.pressed = 0,
  });

  void clear() {
    mx = 0;
    my = 0;
    heavyHeld = false;
    blockHeld = false;
    pressed = 0;
  }

  void copyFrom(InputState o) {
    mx = o.mx;
    my = o.my;
    heavyHeld = o.heavyHeld;
    blockHeld = o.blockHeld;
    pressed = o.pressed;
  }

  bool has(int b) => pressed & b != 0;
}
