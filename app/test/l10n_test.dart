import 'package:flutter_test/flutter_test.dart';
import 'package:rooster_core/rooster_core.dart';
import 'package:rooster_rage/l10n/l10n.dart';

void main() {
  group('L10n bilingual support tests', () {
    test('Vietnamese translations are valid and non-empty', () {
      final vi = const L10nVi();
      expect(vi.appTitle, 'ROOSTER RAGE');
      expect(vi.appSubtitle, 'ĐẠI CHIẾN GÀ ĐÁ');
      expect(vi.chooseRooster, 'CHỌN CHIẾN KÊ');
      expect(vi.hudHp, 'MÁU');
      expect(vi.hudStamina, 'THỂ LỰC');
      expect(vi.bannerFight, 'ĐÁ!');

      final samurai = ChickenClasses.byId('samurai');
      expect(vi.chickenName(samurai), 'Gà Samurai');
      expect(vi.chickenSkillDesc(samurai), isNotEmpty);
      expect(vi.chickenTip(samurai), isNotEmpty);

      final arena = Arenas.all.first;
      expect(vi.arenaName(arena), isNotEmpty);
      expect(vi.arenaDesc(arena), isNotEmpty);
    });

    test('English translations are valid and non-empty', () {
      final en = const L10nEn();
      expect(en.appTitle, 'ROOSTER RAGE');
      expect(en.appSubtitle, 'ROOSTER BRAWL');
      expect(en.chooseRooster, 'CHOOSE ROOSTER');
      expect(en.hudHp, 'HP');
      expect(en.hudStamina, 'STAMINA');
      expect(en.bannerFight, 'FIGHT!');

      final samurai = ChickenClasses.byId('samurai');
      expect(en.chickenName(samurai), 'Samurai Chicken');
      expect(en.chickenSkillDesc(samurai), isNotEmpty);
      expect(en.chickenTip(samurai), isNotEmpty);

      final arena = Arenas.all.first;
      expect(en.arenaName(arena), isNotEmpty);
      expect(en.arenaDesc(arena), isNotEmpty);
    });

    test('setLang toggles static singleton L10n.current', () {
      L10n.setLang(AppLang.vi);
      expect(L10n.currentLang, AppLang.vi);
      expect(L10n.current.hudHp, 'MÁU');

      L10n.setLang(AppLang.en);
      expect(L10n.currentLang, AppLang.en);
      expect(L10n.current.hudHp, 'HP');
    });

    test('every ChickenClassDef has distinct English and Vietnamese names', () {
      for (final def in ChickenClasses.all) {
        expect(def.name, isNotEmpty);
        expect(def.nameVi, isNotEmpty);
        expect(def.name, isNot(equals(def.nameVi)));
      }
    });

    test('every Variant has distinct English and Vietnamese names & perks', () {
      for (final v in Variant.values) {
        expect(v.nameEn, isNotEmpty);
        expect(v.nameVi, isNotEmpty);
        expect(v.perkEn, isNotEmpty);
        expect(v.perkVi, isNotEmpty);
      }
    });
  });
}
