/// Chicken class definitions (GDD §4).
///
/// Stats use the GDD 0-120 scale; `Fighter` converts them to runtime values.
library;

enum Role {
  balanced,
  assassin,
  defender,
  riskDamage,
  control,
  bruiser,
  skirmisher,
  mystic,
}

extension RoleInfo on Role {
  String get nameVi => switch (this) {
    Role.balanced => 'Cân bằng',
    Role.assassin => 'Sát thủ',
    Role.defender => 'Hộ vệ',
    Role.riskDamage => 'Liều mạng',
    Role.control => 'Khống chế',
    Role.bruiser => 'Đấu sĩ',
    Role.skirmisher => 'Du kích',
    Role.mystic => 'Pháp sư',
  };

  String get nameEn => switch (this) {
    Role.balanced => 'Balanced',
    Role.assassin => 'Assassin',
    Role.defender => 'Tank',
    Role.riskDamage => 'Berserker',
    Role.control => 'Disruptor',
    Role.bruiser => 'Fighter',
    Role.skirmisher => 'Skirmisher',
    Role.mystic => 'Mage',
  };
}

enum SkillId {
  flameKick,
  shadowDash,
  earthRooster,
  madRooster,
  fakeDeath,
  stompChain,
  peckFlurry,
  darkVortex,
}

class ChickenStats {
  final double hp;
  final double damage;
  final double speed;
  final double stamina;

  /// Fraction of incoming damage ignored (0..1).
  final double armor;

  /// Knockback resistance. 1.0 = normal.
  final double mass;

  /// Stamina/balance regen multiplier (GDD "recovery").
  final double recovery;

  /// Max balance (GDD "balance") — hits drain it, 0 => stunned.
  final double balance;

  const ChickenStats({
    required this.hp,
    required this.damage,
    required this.speed,
    required this.stamina,
    required this.armor,
    required this.mass,
    required this.recovery,
    required this.balance,
  });
}

class ChickenClassDef {
  final String id;
  final String name;
  final String nameVi;
  final Role role;
  final ChickenStats stats;
  final SkillId skill;
  final String skillName;
  final String skillDescVi;
  final double skillCooldown;
  final double skillStamina;

  /// 1 = easy to pick up, 3 = hard. Used by the random difficulty curve.
  final int difficulty;

  /// Base feather color (ARGB) — variants tint on top of it.
  final int color;

  /// How to play this chicken (shown in the roster / in-match info).
  final String tipVi;

  const ChickenClassDef({
    required this.id,
    required this.name,
    required this.nameVi,
    required this.role,
    required this.stats,
    required this.skill,
    required this.skillName,
    required this.skillDescVi,
    required this.skillCooldown,
    required this.skillStamina,
    required this.difficulty,
    required this.color,
    required this.tipVi,
  });
}

class ChickenClasses {
  static const samurai = ChickenClassDef(
    id: 'samurai',
    name: 'Samurai Chicken',
    nameVi: 'Gà Samurai',
    role: Role.balanced,
    stats: ChickenStats(
      hp: 80,
      damage: 80,
      speed: 70,
      stamina: 80,
      armor: 0.10,
      mass: 1.0,
      recovery: 1.0,
      balance: 100,
    ),
    skill: SkillId.flameKick,
    skillName: 'Flame Kick',
    skillDescVi: 'Lao tới tung cước lửa, đốt cháy đối thủ.',
    skillCooldown: 7,
    skillStamina: 18,
    difficulty: 1,
    color: 0xFFF2F2F2,
    tipVi:
        'Toàn diện, dễ chơi. Combo 3 đòn rồi Flame Kick để đốt máu, giữ thể lực ở mức vàng.',
  );

  static const ninja = ChickenClassDef(
    id: 'ninja',
    name: 'Ninja Chicken',
    nameVi: 'Gà Ninja',
    role: Role.assassin,
    stats: ChickenStats(
      hp: 50,
      damage: 100,
      speed: 100,
      stamina: 60,
      armor: 0,
      mass: 0.8,
      recovery: 1.2,
      balance: 80,
    ),
    skill: SkillId.shadowDash,
    skillName: 'Shadow Dash',
    skillDescVi: 'Lướt bóng xuyên qua địch, đòn kế tiếp chí mạng.',
    skillCooldown: 6,
    skillStamina: 14,
    difficulty: 3,
    color: 0xFF3A3A48,
    tipVi:
        'Máu mỏng nhưng tốc độ cao. Đánh lén sau lưng (+25%), Shadow Dash xuyên qua địch rồi đòn kế tiếp chí mạng.',
  );

  static const tank = ChickenClassDef(
    id: 'tank',
    name: 'Tank Chicken',
    nameVi: 'Gà Chiến Giáp',
    role: Role.defender,
    stats: ChickenStats(
      hp: 120,
      damage: 60,
      speed: 40,
      stamina: 120,
      armor: 0.2,
      mass: 1.25,
      recovery: 0.9,
      balance: 130,
    ),
    skill: SkillId.earthRooster,
    skillName: 'Earth Rooster',
    skillDescVi: 'Nhảy lên dậm đất, choáng mọi kẻ xung quanh.',
    skillCooldown: 11,
    skillStamina: 22,
    difficulty: 1,
    color: 0xFF8B5A2B,
    tipVi:
        'Trâu, giáp dày, khó bị hất. Đứng giữa sân, đỡ đòn (K) rồi Earth Rooster khi địch áp sát đông.',
  );

  static const berserker = ChickenClassDef(
    id: 'berserker',
    name: 'Berserker Chicken',
    nameVi: 'Gà Cuồng Nộ',
    role: Role.riskDamage,
    stats: ChickenStats(
      hp: 70,
      damage: 110,
      speed: 80,
      stamina: 50,
      armor: 0,
      mass: 1.1,
      recovery: 1.3,
      balance: 100,
    ),
    skill: SkillId.madRooster,
    skillName: 'Mad Rooster',
    skillDescVi:
        'Hóa điên 5 giây: đánh mạnh, nhanh, không tốn thể lực '
        'nhưng mất máu và chịu đòn đau hơn.',
    skillCooldown: 14,
    skillStamina: 0,
    difficulty: 2,
    color: 0xFFC0392B,
    tipVi:
        'Càng mất máu càng đánh đau. Bật Nộ + Mad Rooster để dồn sát thương, nhưng coi chừng bị phản.',
  );

  static const troll = ChickenClassDef(
    id: 'troll',
    name: 'Troll Chicken',
    nameVi: 'Gà Lầy',
    role: Role.control,
    stats: ChickenStats(
      hp: 70,
      damage: 50,
      speed: 80,
      stamina: 70,
      armor: 0.05,
      mass: 0.9,
      recovery: 1.1,
      balance: 90,
    ),
    skill: SkillId.fakeDeath,
    skillName: 'Fake Death',
    skillDescVi: 'Giả chết hồi máu, bật dậy nổ bất ngờ làm địch lú lẫn.',
    skillCooldown: 12,
    skillStamina: 10,
    difficulty: 3,
    color: 0xFF7FB800,
    tipVi:
        'Gây rối. Giả chết để hồi máu và dụ địch lại gần, bật dậy nổ làm địch lú lẫn (đảo điều khiển).',
  );

  static const dongtao = ChickenClassDef(
    id: 'dongtao',
    name: 'Dong Tao Chicken',
    nameVi: 'Gà Đông Tảo',
    role: Role.bruiser,
    stats: ChickenStats(
      hp: 90,
      damage: 80,
      speed: 50,
      stamina: 100,
      armor: 0.1,
      mass: 1.2,
      recovery: 0.95,
      balance: 115,
    ),
    skill: SkillId.stompChain,
    skillName: 'Stomp Chain',
    skillDescVi:
        'Cặp chân khủng dậm 3 phát liên hoàn về phía trước, '
        'mỗi phát làm choáng váng và hất lùi.',
    skillCooldown: 8,
    skillStamina: 18,
    difficulty: 1,
    color: 0xFF9E3B1E,
    tipVi:
        'Chân khủng, đấu sĩ cận chiến. Tiến thẳng mặt, Stomp Chain dậm 3 phát làm địch mất thăng bằng.',
  );

  static const bantam = ChickenClassDef(
    id: 'bantam',
    name: 'Bantam Chicken',
    nameVi: 'Gà Tre',
    role: Role.skirmisher,
    stats: ChickenStats(
      hp: 60,
      damage: 75,
      speed: 110,
      stamina: 95,
      armor: 0,
      mass: 0.7,
      recovery: 1.4,
      balance: 70,
    ),
    skill: SkillId.peckFlurry,
    skillName: 'Peck Flurry',
    skillDescVi:
        'Nhỏ mà có võ: mổ liên hoàn 6 phát cực nhanh, vừa mổ vừa di chuyển.',
    skillCooldown: 6,
    skillStamina: 12,
    difficulty: 2,
    color: 0xFFE8A33A,
    tipVi:
        'Nhỏ nhất, nhanh nhất nhưng nhẹ ký dễ bị hất văng. Chạy vòng, mổ liên hoàn rồi lướt ra.',
  );

  static const silkie = ChickenClassDef(
    id: 'silkie',
    name: 'Silkie Chicken',
    nameVi: 'Gà Ác',
    role: Role.mystic,
    stats: ChickenStats(
      hp: 65,
      damage: 65,
      speed: 75,
      stamina: 80,
      armor: 0,
      mass: 0.9,
      recovery: 1.1,
      balance: 90,
    ),
    skill: SkillId.darkVortex,
    skillName: 'Dark Vortex',
    skillDescVi:
        'Tạo lốc xoáy hắc ám phía trước, hút địch vào rồi nổ tung '
        'hất văng tứ phía — canh sát mép sân để đẩy địch xuống.',
    skillCooldown: 10,
    skillStamina: 16,
    difficulty: 3,
    color: 0xFF2A2630,
    tipVi:
        'Pháp sư khống chế. Đặt lốc xoáy gần mép sân: hút địch vào rồi nổ hất văng xuống ao.',
  );

  /// One class per player slot (8), so every chicken in a match is unique.
  static const all = <ChickenClassDef>[
    samurai,
    ninja,
    tank,
    berserker,
    troll,
    dongtao,
    bantam,
    silkie,
  ];

  static ChickenClassDef byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => samurai);
}
