/// One-shot simulation events, forwarded to clients for VFX, feed and SFX.
library;

enum EvType {
  hit, // a=attacker b=target v=damage flags=HitFlag
  ko, // a=killer(-1 none) b=victim flags=KoCause
  fakeKo, // a=-1 b=troll — clients show a KO (owner sees it's fake)
  stun, // b=target
  pickup, // a=fighter b=food id v=FoodKind index
  spill, // a=bucket index
  trap, // a=trap index b=victim
  skill, // a=fighter v=SkillId index
  rage, // a=fighter
  crow, // a=fighter
  respawn, // a=fighter
  land, // a=fighter (jump / earth rooster landing)
  dodge, // a=fighter
  exhausted, // a=fighter
  surprise, // a=troll (fake death ambush)
  vortex, // a=silkie, x/y = vortex center, v = pull duration
  burst, // a=silkie, x/y = explosion center
  healDrop, // b=fallen chicken, x/y = where the heal landed
}

class HitFlag {
  static const backstab = 1;
  static const counter = 2;
  static const crit = 4; // ninja empowered
  static const heavy = 8;
  static const finisher = 16;
  static const skill = 32;
  static const burn = 64;
  static const blocked = 128;
  static const guardBreak = 256;
  static const shove = 512; // crow / rage-roar push (no damage)
}

class KoCause {
  static const hp = 0;
  static const ringOut = 1;
}

class SimEvent {
  final EvType type;
  final int a;
  final int b;
  final double x;
  final double y;
  final double v;
  final int flags;

  const SimEvent(this.type,
      {this.a = -1, this.b = -1, this.x = 0, this.y = 0, this.v = 0, this.flags = 0});

  List<Object> encode() => [
        type.index,
        a,
        b,
        (x * 100).round(),
        (y * 100).round(),
        (v * 10).round(),
        flags,
      ];

  static SimEvent decode(List<dynamic> l) => SimEvent(
        EvType.values[l[0] as int],
        a: l[1] as int,
        b: l[2] as int,
        x: (l[3] as num) / 100,
        y: (l[4] as num) / 100,
        v: (l[5] as num) / 10,
        flags: l[6] as int,
      );
}
