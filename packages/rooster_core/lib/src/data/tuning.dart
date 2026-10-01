/// Gameplay tuning constants. World units are meters, time in seconds.
///
/// Everything feel-related lives here so playtest tweaks don't touch logic.
class Tuning {
  // Simulation
  static const tickRate = 60;
  static const dt = 1.0 / tickRate;

  // Body
  static const fighterRadius = 0.45;
  static const hpScale = 1.25; // GDD HP stat → hit points
  static const gravity = 26.0;
  static const wallHeight = 0.7; // z above which fences are cleared
  static const stackHeight = 0.6; // z above which fighters don't collide

  // Movement
  static const baseSpeed = 2.4; // m/s at speed stat 0
  static const speedPerStat = 0.036; // + m/s per speed stat point
  static const accel = 16.0; // velocity lerp rate when in control
  static const slipAccel = 2.5; // on puddles
  static const knockFriction = 5.0; // velocity damping when not in control
  static const slipFriction = 1.2;

  // Light attack (3-hit combo)
  static const lightWindup = 0.07;
  static const lightActive = 0.09;
  static const lightRecovery = 0.17;
  static const lightStamina = 6.0;
  static const lightDamage = 5.0;
  static const lightReach = 0.72;
  static const lightRadius = 0.58;
  static const lightKnock = 3.0;
  static const lightBalance = 12.0;
  static const lightHitstun = 0.2;
  static const comboFinisherDamage = 1.4;
  static const comboFinisherKnock = 2.4;
  static const comboFinisherBalance = 1.7;
  static const inputBuffer = 0.22;

  // Heavy attack (hold to charge)
  static const heavyMaxCharge = 0.9;
  static const heavyChargeMove = 0.3; // move speed factor while charging
  static const heavyWindup = 0.1;
  static const heavyActive = 0.12;
  static const heavyRecovery = 0.38;
  static const heavyStaminaMin = 14.0;
  static const heavyStaminaMax = 26.0;
  static const heavyDamageMin = 11.0;
  static const heavyDamageMax = 20.0;
  static const heavyReach = 0.85;
  static const heavyRadius = 0.72;
  static const heavyKnockMin = 6.5;
  static const heavyKnockMax = 12.0;
  static const heavyBalanceMin = 28.0;
  static const heavyBalanceMax = 52.0;
  static const heavyHitstun = 0.34;

  // Jump / horn attack
  static const jumpVz = 7.2;
  static const jumpForward = 4.6;
  static const jumpStamina = 12.0;
  static const jumpDamage = 8.0;
  static const jumpRadius = 1.15;
  static const jumpKnock = 7.0;
  static const jumpBalance = 26.0;
  static const landRecovery = 0.2;
  static const airHitHeight = 0.55; // ground attacks miss targets above this z

  // Dodge
  static const dodgeSpeed = 11.0;
  static const dodgeTime = 0.24;
  static const dodgeIFrames = 0.2;
  static const dodgeStamina = 15.0;
  static const dodgeRecovery = 0.12;

  // Resources
  static const stunTime = 1.4;
  static const exhaustedTime = 1.1;
  static const exhaustedMove = 0.5;
  static const staminaRegenDelay = 0.45;
  static const staminaRegen = 22.0;
  static const balanceRegenDelay = 0.9;
  static const balanceRegen = 30.0;
  static const rageMax = 100.0;
  static const rageOnDeal = 1.1;
  static const rageOnTake = 1.6;
  static const rageDuration = 7.0;
  static const rageDamageMul = 1.3;
  static const rageSpeedMul = 1.15;
  static const rageRoarTime = 0.55;
  static const rageRoarRadius = 2.0;
  static const rageRoarKnock = 6.0;
  /// Class skills unlock only during rage, with shortened cooldowns.
  static const rageSkillCooldownMul = 0.35;

  // Block / guard (hold K)
  static const blockDamageMul = 0.4; // still lose HP, just less
  static const blockKnockMul = 0.35;
  static const blockBalanceMul = 0.5;
  static const blockMove = 0.35;
  static const guardBreakStun = 0.9;

  // Guard shield: its own HP. A blocked hit chips off its raw damage; at
  // zero it shatters (stun) and can be raised again once it has mended to
  // [shieldRaiseMin]. It mends after [shieldRegenDelay] without a blocked
  // hit, filling in [shieldRegenTime] / the chicken's guard rating (sturdy,
  // well-balanced, armored chickens mend faster).
  static const shieldMax = 36.0;
  static const shieldRegenTime = 6.0; // empty → full at guard rating 1
  static const shieldRegenDelay = 1.5;
  static const shieldRaiseMin = 0.25; // of max, after shattering

  // Crow (universal skill 3)
  static const crowCooldown = 10.0;
  static const crowTime = 0.55;
  static const crowRadius = 2.2;
  static const crowKnock = 5.0;
  static const crowRage = 12.0;
  static const crowBalance = 15.0;

  // Hit multipliers
  static const backstabMul = 1.25;
  static const counterMul = 1.2;
  static const stunnedTargetMul = 1.15;
  static const empoweredMul = 1.5;
  static const maxHitMul = 2.0;

  // Knockback scaling from lost balance
  static const knockFromBalance = 1.2;
  static const knockStunnedMul = 1.3;

  // Life cycle
  static const fallTime = 0.9;
  static const respawnTime = 3.0; // first death
  static const respawnPerDeath = 1.0; // each further death waits longer
  static const respawnMax = 8.0;
  static const spawnInvuln = 1.5;

  /// Respawn wait after a fighter's [deaths]-th death.
  static double respawnFor(int deaths) {
    final t = respawnTime + respawnPerDeath * (deaths < 1 ? 0 : deaths - 1);
    return t < respawnMax ? t : respawnMax;
  }

  // A fallen chicken drops a heal (any chicken can eat it).
  static const healDropFraction = 0.3; // of the eater's max HP
  static const healDropTtl = 15.0;
  static const countdown = 3.0;

  // Status effects
  static const burnDps = 2.0;
  static const confuseTime = 2.5;
}
