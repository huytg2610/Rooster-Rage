/// Chicken variants (element) and rarity (GDD §11).
///
/// Variants are small side-grades so party matches stay fair; rarity is
/// purely cosmetic (aura, crown, reveal fanfare).
library;

enum Variant { fire, water, earth, wind, thunder }

class VariantMods {
  final double damage;
  final double hp;
  final double speed;
  final double staminaRegen;
  final double balanceRegen;

  const VariantMods({
    this.damage = 1,
    this.hp = 1,
    this.speed = 1,
    this.staminaRegen = 1,
    this.balanceRegen = 1,
  });
}

extension VariantInfo on Variant {
  String get nameVi => switch (this) {
        Variant.fire => 'Hỏa',
        Variant.water => 'Thủy',
        Variant.earth => 'Thổ',
        Variant.wind => 'Phong',
        Variant.thunder => 'Lôi',
      };

  String get perkVi => switch (this) {
        Variant.fire => '+5% sát thương',
        Variant.water => '+20% hồi thăng bằng',
        Variant.earth => '+8% máu',
        Variant.wind => '+5% tốc độ',
        Variant.thunder => '+12% hồi thể lực',
      };

  VariantMods get mods => switch (this) {
        Variant.fire => const VariantMods(damage: 1.05),
        Variant.water => const VariantMods(balanceRegen: 1.2),
        Variant.earth => const VariantMods(hp: 1.08),
        Variant.wind => const VariantMods(speed: 1.05),
        Variant.thunder => const VariantMods(staminaRegen: 1.12),
      };

  /// Accent color (ARGB) for aura / skill effects.
  int get color => switch (this) {
        Variant.fire => 0xFFFF6A00,
        Variant.water => 0xFF2E9BFF,
        Variant.earth => 0xFFB5832F,
        Variant.wind => 0xFF4FE0B0,
        Variant.thunder => 0xFFFFE03A,
      };
}

enum Rarity { common, rare, epic, legendary }

extension RarityInfo on Rarity {
  String get nameVi => switch (this) {
        Rarity.common => 'Thường',
        Rarity.rare => 'Hiếm',
        Rarity.epic => 'Sử thi',
        Rarity.legendary => 'Huyền thoại',
      };

  double get weight => switch (this) {
        Rarity.common => 60,
        Rarity.rare => 28,
        Rarity.epic => 10,
        Rarity.legendary => 2,
      };

  int get color => switch (this) {
        Rarity.common => 0xFFBFC5CC,
        Rarity.rare => 0xFF3FA9F5,
        Rarity.epic => 0xFFB05CFF,
        Rarity.legendary => 0xFFFFC21A,
      };
}
