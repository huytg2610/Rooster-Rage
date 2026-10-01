/// Runtime chicken entity (GDD §3, §8, §9).
library;

import '../data/chicken_classes.dart';
import '../data/tuning.dart';
import '../data/variants.dart';
import '../math/vec2.dart';
import 'input.dart';

/// Chicken state machine states (GDD §9). `recovery` follows every attack.
enum FState {
  idle,
  run,
  attack,
  heavyCharge,
  heavyAttack,
  jump,
  dodge,
  recovery,
  hitstun,
  stunned,
  exhausted,
  skill,
  crow,
  rageRoar,
  fakeDead,
  falling,
  dead,
  block,
}

/// Bit flags mirrored to clients for rendering.
class FFlag {
  static const rage = 1;
  static const invuln = 2;
  static const burning = 4;
  static const confused = 8;
  static const mad = 16;
  static const empowered = 32;
  static const superArmor = 64;
  static const slipping = 128;
  static const out = 256; // survival: eliminated for the rest of the match
}

class FighterSetup {
  final int id;
  final String playerId;
  final String name;
  final int slot;
  final bool isBot;
  final int botLevel;
  final String classId;
  final Variant variant;
  final Rarity rarity;

  const FighterSetup({
    required this.id,
    required this.playerId,
    required this.name,
    required this.slot,
    required this.isBot,
    this.botLevel = 1,
    required this.classId,
    required this.variant,
    required this.rarity,
  });
}

class Fighter {
  final FighterSetup setup;
  final ChickenClassDef def;

  // Derived stats
  late final double maxHp;
  late final double maxStamina;
  late final double maxBalance;
  late final double moveSpeed;
  late final double power;
  late final double armor;
  late final double mass;
  late final double staminaRegenMul;
  late final double balanceRegenMul;

  // Kinematics
  final V2 pos = V2.zero();
  final V2 vel = V2.zero();
  final V2 facing = V2(1, 0);
  double z = 0;
  double vz = 0;

  // State machine
  FState state = FState.idle;
  double stateTime = 0;
  double stateDur = 0; // duration for timed states
  FState? recoveringFrom;
  bool effectFired = false; // one-shot effect inside the current state
  int skillStep = 0; // multi-hit skills: hits already done
  final V2 skillPoint = V2.zero(); // targeted skills (vortex center)

  // Resources (GDD §5)
  late double hp;
  late double stamina;
  late double balance;
  double rage = 0;

  // Timers
  double rageTimer = 0;
  double skillCd = 0;
  double crowCd = 0;
  double invuln = 0;
  double staminaIdle = 0;
  double balanceIdle = 0;
  double burnTime = 0;
  int burnSource = -1;
  double confuseTime = 0;
  double madTime = 0;
  double empoweredTime = 0;
  double respawnTimer = 0;
  double shield = Tuning.shieldMax; // guard HP
  bool shieldBroken = false; // shattered: can't guard until it mends a bit
  double shieldIdle = 0; // since the last blocked hit
  final V2 safePos = V2(0, 0); // last spot comfortably on the ground

  // Attack bookkeeping
  double heavyCharge = 0;
  int comboStep = 0;
  double attackStaminaMul = 1;
  final Set<int> hitIds = {};
  bool attackHitProps = false;
  final V2 dashDir = V2(1, 0);

  // Input buffering
  int bufferedPress = 0;
  double bufferTime = 0;
  bool heavyWasHeld = false;

  // Credit / stats
  int lastAttacker = -1;
  double lastAttackerTime = -999;
  int kos = 0;
  int deaths = 0;
  bool eliminated = false; // survival mode: no respawn
  double eliminatedAt = -1;
  bool survivalRules = false; // set by the sim (a faking troll looks out)
  double damageDealt = 0;

  final InputState input = InputState();

  /// How fast the guard shield mends (1 = baseline): balance and armor.
  late final double guardRating;
  static double guardRatingOf(ChickenClassDef d) =>
      d.stats.balance / 100 + d.stats.armor * 2.5;

  /// Seconds for an empty shield to mend to full.
  double get shieldRegenTime => Tuning.shieldRegenTime / guardRating;

  Fighter(this.setup) : def = ChickenClasses.byId(setup.classId) {
    final s = def.stats;
    final m = setup.variant.mods;
    maxHp = s.hp * Tuning.hpScale * m.hp;
    maxStamina = s.stamina;
    maxBalance = s.balance;
    moveSpeed = (Tuning.baseSpeed + s.speed * Tuning.speedPerStat) * m.speed;
    power = s.damage / 80.0 * m.damage;
    armor = s.armor;
    mass = s.mass;
    staminaRegenMul = s.recovery * m.staminaRegen;
    balanceRegenMul = s.recovery * m.balanceRegen;
    guardRating = guardRatingOf(def);
    hp = maxHp;
    stamina = maxStamina;
    balance = maxBalance;
  }

  int get id => setup.id;
  bool get alive => state != FState.dead && state != FState.falling;
  bool get grounded => z <= 0;
  bool get rageActive => rageTimer > 0;
  bool get isMad => madTime > 0;

  /// Can start a new action (move/attack) this tick.
  bool get canAct =>
      state == FState.idle || state == FState.run;

  /// Attack speed factor: Mad Rooster makes all attack phases 20% faster.
  double get attackTimeScale => isMad ? 0.8 : 1.0;

  /// Super armor: no hitstun/stun (rage, Earth Rooster leap).
  bool get superArmor =>
      rageActive || (def.skill == SkillId.earthRooster && state == FState.skill);

  void setState(FState s, [double dur = 0]) {
    state = s;
    stateTime = 0;
    stateDur = dur;
    effectFired = false;
    skillStep = 0;
  }

  int get flags {
    var f = 0;
    if (rageActive) f |= FFlag.rage;
    if (invuln > 0) f |= FFlag.invuln;
    if (burnTime > 0) f |= FFlag.burning;
    if (confuseTime > 0) f |= FFlag.confused;
    if (isMad) f |= FFlag.mad;
    if (empoweredTime > 0) f |= FFlag.empowered;
    if (superArmor) f |= FFlag.superArmor;
    if (eliminated || (survivalRules && state == FState.fakeDead)) {
      f |= FFlag.out;
    }
    return f;
  }

  /// GDD: stamina 100% → 100% dmg, 50% → 70%, 0% → 40% (linear).
  static double staminaMultiplier(double stamina, double maxStamina) {
    final r = maxStamina <= 0 ? 0.0 : clampD(stamina / maxStamina, 0, 1);
    return 0.4 + 0.6 * r;
  }

  double get staminaMul => staminaMultiplier(stamina, maxStamina);

  /// Spends stamina; Mad Rooster attacks are free. Returns false if exhausted.
  void spendStamina(double amount, {bool attack = false}) {
    if (attack && isMad) return;
    stamina -= amount;
    staminaIdle = 0;
    if (stamina < 0) stamina = 0;
  }

  void resetForSpawn(double x, double y) {
    pos.set(x, y);
    vel.set(0, 0);
    z = 0;
    vz = 0;
    facing.set(-x, -y);
    if (facing.length2 < 1e-6) facing.set(1, 0);
    facing.normalize();
    hp = maxHp;
    stamina = maxStamina;
    balance = maxBalance;
    rage *= 0.5;
    rageTimer = 0;
    burnTime = 0;
    confuseTime = 0;
    madTime = 0;
    empoweredTime = 0;
    heavyCharge = 0;
    comboStep = 0;
    bufferedPress = 0;
    invuln = Tuning.spawnInvuln;
    lastAttacker = -1;
    shield = Tuning.shieldMax;
    shieldBroken = false;
    safePos.setFrom(pos);
    setState(FState.idle);
  }
}
