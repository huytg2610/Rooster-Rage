import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rooster_core/rooster_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

enum AppLang {
  vi('Tiếng Việt', 'VI', '🇻🇳'),
  en('English', 'EN', '🇬🇧');

  final String label;
  final String code;
  final String flag;
  const AppLang(this.label, this.code, this.flag);
}

class L10nNotifier extends Notifier<AppLang> {
  static const _prefKey = 'app_language';

  @override
  AppLang build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_prefKey);
      if (saved == 'en') {
        state = AppLang.en;
        L10n.current = L10nEn();
      } else if (saved == 'vi') {
        state = AppLang.vi;
        L10n.current = L10nVi();
      }
    }).ignore();
    return AppLang.vi;
  }

  Future<void> setLang(AppLang lang) async {
    state = lang;
    L10n.setLang(lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, lang.name);
  }

  Future<void> toggle() async {
    await setLang(state == AppLang.vi ? AppLang.en : AppLang.vi);
  }
}

final l10nProvider = NotifierProvider<L10nNotifier, AppLang>(L10nNotifier.new);

/// Synchronous access for non-widget contexts (like HUD render canvas)
abstract class L10n {
  static AppLang currentLang = AppLang.vi;
  static L10n current = L10nVi();

  static void setLang(AppLang lang) {
    currentLang = lang;
    current = lang == AppLang.en ? L10nEn() : L10nVi();
  }

  // App & Titles
  String get appTitle;
  String get appSubtitle;

  // Home Screen
  String get roosterName;
  String get nameRequired;
  String get invalidHost;
  String get joinLan;
  String get joinLanLower;
  String get playBots;
  String get playBotsOffline;
  String get viewRoster;
  String get graphics;
  String get graphicsAuto;
  String get graphicsSaver;
  String get graphicsHigh;
  String get lanHostAddress;
  String get helpPhone;
  String get helpDesktop;
  String get helpTips;

  // Lobby
  String get lobbyTitle;
  String get practiceTitle;
  String roostersHeader(int count);
  String get rulesHeader;
  String get mode;
  String get randomChicken;
  String get pickChicken;
  String get rules;
  String get respawn;
  String get survival;
  String get respawnDesc;
  String get survivalDesc;
  String get arena;
  String get duration;
  String minutes(int m);
  String get addBots;
  String get botDifficulty;
  String get easy;
  String get medium;
  String get hard;
  String get start;
  String get needAtLeastTwo;
  String get ready;
  String get cancelReady;
  String get waitingHost;
  String get waitingHostStart;
  String get you;
  String get hostBadge;
  String get roomQr;
  String get scanToJoin;
  String get roomUrl;
  String get copiedLink;
  String get orEnterBrowser;
  String get closeBtn;
  String get disconnected;

  // Pick Screen
  String get chooseRooster;
  String get lockedIn;
  String get notSelectedPrompt;
  String get chosenWaiting;
  String get opponentsPicked;
  String takenByPlayer(String name);
  String get elementFire;
  String get elementWater;
  String get elementEarth;
  String get elementWind;
  String get elementThunder;
  String get details;

  // Roles
  String roleName(Role role);

  // Stats
  String get statHp;
  String get statAtk;
  String get statSpd;
  String get statStm;
  String get statArmor;
  String get statMass;
  String get statRecovery;
  String get statBalance;
  String get statCooldown;
  String get statStaminaCost;
  String get statShieldRegen;
  String get difficulty;
  String skillHeader(String name);
  String rageOnlyCooldown(String cd);
  String variantBadge(Variant v, [Rarity? r]);

  // Chickens & Arenas
  String chickenName(ChickenClassDef def);
  String chickenSkillDesc(ChickenClassDef def);
  String chickenTip(ChickenClassDef def);
  String arenaName(ArenaDef arena);
  String arenaDesc(ArenaDef arena);

  // Reveal
  String get fightersAssemble;
  String get roosterDraw;
  String get youAre;
  String rarityName(Rarity r);
  String skillLabel(String name);

  // HUD
  String get hudHp;
  String get hudStamina;
  String get hudStaminaLow;
  String get hudBalance;
  String get hudShield;
  String get hudShieldBroken;
  String get hudRage;
  String get hudRageFull;
  String get hudRaging;
  String get hudSkillNeedsRage;
  String get hudRageSkill;
  String get hudCrow;
  String get hudGuard;
  String hudSurvivalLeft(int left);
  String get hudOutTag;
  String get bannerFight;
  String get bannerSurvived;
  String get bannerEnded;
  String get bannerTimeUp;
  String get hudSyncing;
  String get hudSpectating;
  String get hudEliminated;
  String get hudMatchEnded;
  String get hudYou;

  // Results
  String get resultsTitle;
  String get champCongrats;
  String get drawMatch;
  String get matchEnded;
  String championBanner(String name, bool isYou);
  String get mvpDamage;
  String get waitingHostNext;
  String get rankCol;
  String get roosterCol;
  String get koCol;
  String get fallsCol;
  String get dmgCol;
  String get rematch;
  String get backToLobby;
  String get leaveRoom;

  // Roster Screen
  String get rosterTitle;
  String rosterHeader(int count);
  String get rosterRules;
  String get tabStats;
  String get tabSkill;
  String get tabGuide;

  // Controls Help
  String get controlsTitle;
  String get controlsExplanation;
  List<(List<String>, String)> touchControls(String skillName);
  List<(List<String>, String)> keyboardControls(String skillName);

  // Close Room Dialog
  String get closeRoomTitle;
  String closeRoomContent(int others);
  String get cancel;
  String get closeRoomConfirm;
  String get closeRoomBtn;

  // Room & Match Dialogs
  String get connectingToHost;
  String get reconnectingToHost;
  String get kickedFromRoom;
  String get cannotConnectHost;
  String get wifiCheckHint;
  String get backToHome;
  String get leaveMatchTitle;
  String leaveMatchContent(bool canClose);
  String get stayBtn;
  String get leaveBtn;
  String get controlsGuideTouch;
  String get controlsGuideKeyboard;
  String get soundMutedTooltip;
  String get soundMusicOffTooltip;
  String get soundOnTooltip;
  String get yourRoosterInfo;
  String get uniqueSkillDefault;
}

class L10nVi implements L10n {
  const L10nVi();

  @override String get appTitle => 'ROOSTER RAGE';
  @override String get appSubtitle => 'ĐẠI CHIẾN GÀ ĐÁ';

  @override String get roosterName => 'Tên chiến kê';
  @override String get nameRequired => 'Nhập tên chiến kê của bạn trước đã!';
  @override String get invalidHost => 'Địa chỉ host phải dạng ws://IP:8080/ws';
  @override String get joinLan => 'VÀO PHÒNG LAN';
  @override String get joinLanLower => 'Vào phòng LAN';
  @override String get playBots => 'CHƠI VỚI BOT';
  @override String get playBotsOffline => 'Luyện với bot (offline)';
  @override String get viewRoster => 'Xem thông tin 8 chiến kê';
  @override String get graphics => 'Đồ họa:';
  @override String get graphicsAuto => 'Tự động';
  @override String get graphicsSaver => 'Tiết kiệm';
  @override String get graphicsHigh => 'Sắc nét';
  @override String get lanHostAddress => 'Địa chỉ host LAN';
  @override String get helpPhone => 'Điện thoại: kéo trái để chạy · chạm phải = đánh, giữ = đánh mạnh, vuốt xuống = lướt, vuốt lên = nhảy · giữ THỦ để đỡ.';
  @override String get helpDesktop => 'Máy tính: WASD chạy · J đánh (giữ J = mạnh) · giữ K đỡ · L lướt · Space nhảy · U Nộ + chiêu cuối · O gáy.';
  @override String get helpTips => 'Đánh trúng/bị đánh sẽ tích Nộ. Đầy Nộ thì bấm U (nút CHIÊU): vừa Nộ vừa tung chiêu cuối. Mỗi đòn tốn thể lực — hất đối thủ ra khỏi sân để hạ gục nhanh!';

  @override String get lobbyTitle => 'PHÒNG CHỜ';
  @override String get practiceTitle => 'LUYỆN TẬP OFFLINE';
  @override String roostersHeader(int count) => 'CHIẾN KÊ ($count)';
  @override String get rulesHeader => 'LUẬT CHƠI';
  @override String get mode => 'Chế độ';
  @override String get randomChicken => 'Gà ngẫu nhiên';
  @override String get pickChicken => 'Tự chọn gà';
  @override String get rules => 'Luật';
  @override String get respawn => 'Hồi sinh';
  @override String get survival => 'Sinh tồn';
  @override String get respawnDesc => 'Gục thì hồi sinh (chết càng nhiều chờ càng lâu). Nhiều KO nhất thắng.';
  @override String get survivalDesc => 'Chỉ 1 mạng. Gục là bị loại khỏi trận, kẻ sống sót cuối cùng thắng.';
  @override String get arena => 'Đấu trường';
  @override String get duration => 'Thời gian';
  @override String minutes(int m) => '$m phút';
  @override String get addBots => 'Thêm bot';
  @override String get botDifficulty => 'Bot';
  @override String get easy => 'Dễ';
  @override String get medium => 'Vừa';
  @override String get hard => 'Khó';
  @override String get start => 'BẮT ĐẦU!';
  @override String get needAtLeastTwo => 'Cần ít nhất 2 chiến kê';
  @override String get ready => 'SẴN SÀNG';
  @override String get cancelReady => 'HỦY SẴN SÀNG';
  @override String get waitingHost => 'CHỜ CHỦ PHÒNG';
  @override String get waitingHostStart => 'Chờ chủ phòng bắt đầu...';
  @override String get you => '(bạn)';
  @override String get hostBadge => 'Chủ phòng';
  @override String get roomQr => 'Mã QR phòng';
  @override String get scanToJoin => 'Vào cùng WiFi, mở máy ảnh quét mã để chơi:';
  @override String get roomUrl => 'Địa chỉ phòng:';
  @override String get copiedLink => 'Đã sao chép link phòng!';
  @override String get orEnterBrowser => 'Hoặc gõ URL vào trình duyệt điện thoại.';
  @override String get closeBtn => 'ĐÓNG';
  @override String get disconnected => 'Đã ngắt kết nối với phòng.';

  @override String get chooseRooster => 'CHỌN CHIẾN KÊ';
  @override String get lockedIn => 'Đã khóa lựa chọn';
  @override String get notSelectedPrompt => 'Chưa chọn — hết giờ sẽ được chọn ngẫu nhiên.';
  @override String get chosenWaiting => 'Đã chọn! Chờ mọi người...';
  @override String get opponentsPicked => 'Đối thủ đã chọn:';
  @override String takenByPlayer(String name) => 'Đã có: $name';
  @override String get elementFire => 'Hỏa · +5% sát thương';
  @override String get elementWater => 'Thủy · +20% hồi thăng bằng';
  @override String get elementEarth => 'Thổ · +8% máu';
  @override String get elementWind => 'Phong · +5% tốc độ';
  @override String get elementThunder => 'Lôi · +12% hồi thể lực';
  @override String get details => 'Chi tiết';

  @override String roleName(Role role) => role.nameVi;

  @override String get statHp => 'Máu';
  @override String get statAtk => 'Đòn';
  @override String get statSpd => 'Tốc';
  @override String get statStm => 'Sức';
  @override String get statArmor => 'Giáp';
  @override String get statMass => 'Kháng hất';
  @override String get statRecovery => 'Hồi phục';
  @override String get statBalance => 'Thăng bằng';
  @override String get statCooldown => 'Hồi chiêu';
  @override String get statStaminaCost => 'Hao thể lực';
  @override String get statShieldRegen => 'Hồi khiên';
  @override String get difficulty => 'Độ khó ';
  @override String skillHeader(String name) => 'Kỹ năng (U): $name';
  @override String rageOnlyCooldown(String cd) => '  — chỉ khi NỘ, hồi ${cd}s';
  @override String variantBadge(Variant v, [Rarity? r]) =>
      'Hệ ${v.nameVi}: ${v.perkVi}${r != null ? ' · ${r.nameVi}' : ''}';

  @override String chickenName(ChickenClassDef def) => def.nameVi;
  @override String chickenSkillDesc(ChickenClassDef def) => def.skillDescVi;
  @override String chickenTip(ChickenClassDef def) => def.tipVi;

  @override String arenaName(ArenaDef arena) => arena.nameVi;
  @override String arenaDesc(ArenaDef arena) => arena.descVi;

  @override String get fightersAssemble => 'RA SÂN!';
  @override String get roosterDraw => 'BỐC THĂM CHIẾN KÊ!';
  @override String get youAre => 'BẠN LÀ';
  @override String rarityName(Rarity r) => r.nameVi;
  @override String skillLabel(String name) => 'Kỹ năng: $name';

  @override String get hudHp => 'MÁU';
  @override String get hudStamina => 'THỂ LỰC';
  @override String get hudStaminaLow => 'THỂ LỰC — THẤP!';
  @override String get hudBalance => 'THĂNG BẰNG';
  @override String get hudShield => 'KHIÊN';
  @override String get hudShieldBroken => 'KHIÊN VỠ';
  @override String get hudRage => 'NỘ';
  @override String get hudRageFull => 'NỘ ĐẦY — BẤM U';
  @override String get hudRaging => 'ĐANG NỘ';
  @override String get hudSkillNeedsRage => 'CHIÊU cần NỘ';
  @override String get hudRageSkill => 'NỘ + CHIÊU';
  @override String get hudCrow => 'GÁY';
  @override String get hudGuard => 'THỦ';
  @override String hudSurvivalLeft(int left) => 'SINH TỒN · còn $left';
  @override String get hudOutTag => ' · loại';
  @override String get bannerFight => 'ĐÁ!';
  @override String get bannerSurvived => 'SỐNG SÓT!';
  @override String get bannerEnded => 'KẾT THÚC!';
  @override String get bannerTimeUp => 'HẾT GIỜ!';
  @override String get hudSyncing => 'Đang đồng bộ trận...';
  @override String get hudSpectating => 'Đang xem — bạn sẽ vào trận sau';
  @override String get hudEliminated => 'BẠN ĐÃ BỊ LOẠI — đang xem trận';
  @override String get hudMatchEnded => 'TRẬN ĐẤU KẾT THÚC';
  @override String get hudYou => 'BẠN';

  @override String get resultsTitle => 'KẾT QUẢ TRẬN ĐẤU';
  @override String get champCongrats => 'Chúc mừng nhà vô địch!';
  @override String get drawMatch => 'Trận đấu bất phân thắng bại!';
  @override String get matchEnded => 'Trận đấu kết thúc';
  @override String championBanner(String name, bool isYou) =>
      isYou ? 'BẠN VÔ ĐỊCH!' : '$name VÔ ĐỊCH!';
  @override String get mvpDamage => 'Đòn tay to nhất';
  @override String get waitingHostNext => 'Chờ chủ phòng mở trận mới...';
  @override String get rankCol => 'HẠNG';
  @override String get roosterCol => 'CHIẾN KÊ';
  @override String get koCol => 'HẠ GỤC';
  @override String get fallsCol => 'GỤC';
  @override String get dmgCol => 'SÁT THƯƠNG';
  @override String get rematch => 'ĐẤU LẠI';
  @override String get backToLobby => 'VỀ SẢNH';
  @override String get leaveRoom => 'RỜI PHÒNG';

  @override String get rosterTitle => 'DANH SÁCH CHIẾN KÊ';
  @override String rosterHeader(int count) => 'Các chiến kê ($count)';
  @override String get rosterRules =>
      'Mỗi trận mỗi người là 1 chiến kê khác nhau (tối đa 8).\n'
      '• Thể lực (vàng): mỗi đòn tốn thể lực, thể lực thấp đánh yếu, cạn thì thở dốc.\n'
      '• Thăng bằng (xanh): bị đánh nhiều sẽ tụt, về 0 thì choáng và bị hất văng xa hơn.\n'
      '• Nộ (cam): đánh trúng/bị đánh sẽ tích Nộ. Đầy Nộ thì bấm U (nút CHIÊU): '
      'bật Nộ (đánh mạnh +30%, nhanh hơn, không bị choáng) và tung chiêu cuối luôn; '
      'trong lúc Nộ bấm U lại để dùng chiêu khi hồi xong.\n'
      '• Đỡ (giữ K / nút THỦ): giảm 60% sát thương. Khiên có máu riêng (thanh KHIÊN): '
      'đỡ nhiều thì vỡ khiên và bị choáng; khiên tự hồi, hồi được 1/4 là giơ lại được. '
      'Gà thăng bằng cao, giáp dày hồi khiên nhanh hơn (xem "Hồi khiên").\n'
      '• Gà gục rơi ra cục máu (trái tim đỏ): ăn vào hồi 30% máu (đầy máu thì không ăn được).\n'
      '• Chết càng nhiều hồi sinh càng lâu (3 giây, mỗi lần thêm 1 giây, tối đa 8 giây).\n'
      '• Luật Sinh tồn (chọn ở phòng chờ): không hồi sinh, gục là bị loại — con gà cuối cùng còn đứng thắng.\n'
      '• Hất đối thủ ra khỏi sân là cách hạ gục nhanh nhất — rớt sân tính cho người đánh trúng cuối!';
  @override String get tabStats => 'Chỉ số';
  @override String get tabSkill => 'Kỹ năng';
  @override String get tabGuide => 'Cách chơi';

  @override String get controlsTitle => 'ĐIỀU KHIỂN';
  @override String get controlsExplanation =>
      'Góc trái: MÁU (đỏ) · THỂ LỰC (vàng, đánh/né tốn) · THĂNG BẰNG '
      '(xanh, về 0 là choáng) · NỘ (cam, đầy thì bấm Nộ).\n'
      'Trên đầu gà: đỏ = máu, vạch xanh = thăng bằng, chấm cam = Nộ sẵn sàng.\n'
      'Màu: cam/đỏ = đánh (! = đòn mạnh sắp ra) · xanh = đỡ · vàng = gáy đẩy.';
  @override List<(List<String>, String)> touchControls(String skillName) => [
    (['Kéo trái'], 'Chạy'),
    (['Chạm phải'], 'Đánh thường (chạm liên tục = combo)'),
    (['Giữ phải'], 'Đánh mạnh (giữ lâu = mạnh hơn)'),
    (['THỦ'], 'Giữ để đỡ: giảm sát thương; khiên có máu, vỡ thì chờ hồi'),
    (['Vuốt xuống'], 'Lướt'),
    (['Vuốt lên'], 'Nhảy đánh'),
    (['CHIÊU'], 'Đầy Nộ: bật Nộ + tung $skillName luôn'),
    (['GÁY'], 'Đẩy lùi, tăng nộ'),
  ];

  @override List<(List<String>, String)> keyboardControls(String skillName) => [
    (['W', 'A', 'S', 'D'], 'Di chuyển (hoặc phím mũi tên)'),
    (['J'], 'Đánh thường (bấm liên tục = combo)'),
    (['Giữ J'], 'Đánh mạnh — nhả ra để đánh'),
    (['Giữ K'], 'Đỡ đòn: giảm sát thương; khiên có máu, vỡ thì chờ hồi'),
    (['L', 'Shift'], 'Lướt'),
    (['Space'], 'Nhảy đánh'),
    (['U'], 'Đầy Nộ: bật Nộ + tung $skillName luôn'),
    (['O'], 'Gáy: đẩy lùi, tăng nộ'),
    (['H'], 'Ẩn / hiện bảng này'),
  ];

  @override String get closeRoomTitle => 'Đóng phòng LAN?';
  @override String closeRoomContent(int others) => others > 0
      ? 'Tất cả $others người chơi khác sẽ bị đưa ra khỏi phòng.'
      : 'Phòng sẽ bị đóng.';
  @override String get cancel => 'Huỷ';
  @override String get closeRoomConfirm => 'ĐÓNG PHÒNG';
  @override String get closeRoomBtn => 'Đóng phòng';

  @override String get connectingToHost => 'Đang kết nối tới host...';
  @override String get reconnectingToHost => 'Mất kết nối — đang nối lại...';
  @override String get kickedFromRoom => 'Bạn đã được đưa ra khỏi phòng.';
  @override String get cannotConnectHost => 'Không kết nối được tới host.';
  @override String get wifiCheckHint => 'Kiểm tra cùng WiFi và host đang chạy.';
  @override String get backToHome => 'VỀ MÀN HÌNH CHÍNH';
  @override String get leaveMatchTitle => 'Rời trận?';
  @override String leaveMatchContent(bool canClose) => canClose
      ? 'Rời trận: gà của bạn được bot điều khiển tiếp.\n'
          'Đóng phòng: kết thúc trận và đưa mọi người ra ngoài.'
      : 'Gà của bạn sẽ được bot điều khiển tiếp.';
  @override String get stayBtn => 'Ở lại';
  @override String get leaveBtn => 'Rời';
  @override String get controlsGuideTouch => 'Hướng dẫn';
  @override String get controlsGuideKeyboard => 'Hướng dẫn phím (H)';
  @override String get soundMutedTooltip => 'Đang tắt hết — bấm để bật';
  @override String get soundMusicOffTooltip => 'Đang tắt nhạc — bấm để tắt hết';
  @override String get soundOnTooltip => 'Bấm để tắt nhạc';
  @override String get yourRoosterInfo => 'Thông tin chiến kê của bạn';
  @override String get uniqueSkillDefault => 'kỹ năng riêng';
}

class L10nEn implements L10n {
  const L10nEn();

  @override String get appTitle => 'ROOSTER RAGE';
  @override String get appSubtitle => 'ROOSTER BRAWL';

  @override String get roosterName => 'Rooster Name';
  @override String get nameRequired => 'Enter your rooster name first!';
  @override String get invalidHost => 'Host address must be ws://IP:8080/ws';
  @override String get joinLan => 'JOIN LAN ROOM';
  @override String get joinLanLower => 'Join LAN Room';
  @override String get playBots => 'PLAY WITH BOTS';
  @override String get playBotsOffline => 'Practice with bots (offline)';
  @override String get viewRoster => 'View 8 Rooster Classes';
  @override String get graphics => 'Graphics:';
  @override String get graphicsAuto => 'Auto';
  @override String get graphicsSaver => 'Saver';
  @override String get graphicsHigh => 'High';
  @override String get lanHostAddress => 'LAN Host Address';
  @override String get helpPhone => 'Mobile: Drag left to move · tap right = attack, hold = heavy attack, swipe down = dash, swipe up = jump · hold GUARD to block.';
  @override String get helpDesktop => 'Desktop: WASD move · J attack (hold J = heavy) · hold K block · L dash · Space jump · U Rage + Ultimate · O crow.';
  @override String get helpTips => 'Hits & damage build Rage. When full, press U (SKILL): unleash Rage & Ultimate. Attacks cost stamina — knock opponents out of the arena to KO fast!';

  @override String get lobbyTitle => 'LOBBY';
  @override String get practiceTitle => 'OFFLINE PRACTICE';
  @override String roostersHeader(int count) => 'ROOSTERS ($count)';
  @override String get rulesHeader => 'GAME RULES';
  @override String get mode => 'Mode';
  @override String get randomChicken => 'Random Rooster';
  @override String get pickChicken => 'Pick Rooster';
  @override String get rules => 'Rules';
  @override String get respawn => 'Respawn';
  @override String get survival => 'Survival';
  @override String get respawnDesc => 'Respawn on KO (death penalty increases timer). Most KOs wins.';
  @override String get survivalDesc => '1 life only. Knocked out fighters are eliminated. Last rooster standing wins.';
  @override String get arena => 'Arena';
  @override String get duration => 'Duration';
  @override String minutes(int m) => '$m min';
  @override String get addBots => 'Add Bots';
  @override String get botDifficulty => 'Bot AI';
  @override String get easy => 'Easy';
  @override String get medium => 'Normal';
  @override String get hard => 'Hard';
  @override String get start => 'START MATCH!';
  @override String get needAtLeastTwo => 'Need at least 2 roosters';
  @override String get ready => 'READY';
  @override String get cancelReady => 'CANCEL READY';
  @override String get waitingHost => 'WAITING FOR HOST';
  @override String get waitingHostStart => 'Waiting for host to start...';
  @override String get you => '(you)';
  @override String get hostBadge => 'Host';
  @override String get roomQr => 'Room QR Code';
  @override String get scanToJoin => 'On same Wi-Fi, open camera and scan to play:';
  @override String get roomUrl => 'Room URL:';
  @override String get copiedLink => 'Room link copied!';
  @override String get orEnterBrowser => 'Or enter URL in your mobile browser.';
  @override String get closeBtn => 'CLOSE';
  @override String get disconnected => 'Disconnected from room.';

  @override String get chooseRooster => 'CHOOSE ROOSTER';
  @override String get lockedIn => 'Selection Locked';
  @override String get notSelectedPrompt => 'Not chosen — will pick randomly when timer expires.';
  @override String get chosenWaiting => 'Chosen! Waiting for others...';
  @override String get opponentsPicked => 'Opponents picked:';
  @override String takenByPlayer(String name) => 'Taken: $name';
  @override String get elementFire => 'Fire · +5% Damage';
  @override String get elementWater => 'Water · +20% Balance Regen';
  @override String get elementEarth => 'Earth · +8% HP';
  @override String get elementWind => 'Wind · +5% Speed';
  @override String get elementThunder => 'Thunder · +12% Stamina Regen';
  @override String get details => 'Details';

  @override String roleName(Role role) => switch (role) {
    Role.balanced => 'Balanced',
    Role.assassin => 'Assassin',
    Role.defender => 'Tank',
    Role.riskDamage => 'Berserker',
    Role.control => 'Disruptor',
    Role.bruiser => 'Fighter',
    Role.skirmisher => 'Skirmisher',
    Role.mystic => 'Mage',
  };

  @override String get statHp => 'HP';
  @override String get statAtk => 'ATK';
  @override String get statSpd => 'SPD';
  @override String get statStm => 'STM';
  @override String get statArmor => 'Armor';
  @override String get statMass => 'Weight';
  @override String get statRecovery => 'Recovery';
  @override String get statBalance => 'Balance';
  @override String get statCooldown => 'Cooldown';
  @override String get statStaminaCost => 'Stamina Cost';
  @override String get statShieldRegen => 'Shield Regen';
  @override String get difficulty => 'Difficulty ';
  @override String skillHeader(String name) => 'Skill (U): $name';
  @override String rageOnlyCooldown(String cd) => '  — during RAGE, CD ${cd}s';
  @override String variantBadge(Variant v, [Rarity? r]) =>
      '${v.nameEn} Element: ${v.perkEn}${r != null ? ' · ${r.nameEn}' : ''}';

  @override String chickenName(ChickenClassDef def) => def.name;
  @override String chickenSkillDesc(ChickenClassDef def) => switch (def.id) {
    'samurai' => 'Dashes forward with a flaming kick, igniting the opponent.',
    'ninja' => 'Shadow dashes through enemies; next strike deals critical damage.',
    'tank' => 'Leaps and slams the ground, stunning all nearby enemies.',
    'berserker' => 'Enters rage for 5s: high damage & speed with 0 stamina cost, but drains HP.',
    'troll' => 'Feigns death to regenerate HP, exploding upon rising to confuse opponents.',
    'dongtao' => 'Stomps 3 consecutive heavy shocks, stunning and knocking back foes.',
    'bantam' => 'Flurries 6 rapid pecks in quick succession while moving.',
    'silkie' => 'Summons a dark vortex pulling enemies in, then blasts them outward.',
    _ => def.skillDescVi,
  };

  @override String chickenTip(ChickenClassDef def) => switch (def.id) {
    'samurai' => 'All-rounder, beginner friendly. Chain 3 strikes then Flame Kick to burn HP.',
    'ninja' => 'Fragile but high speed. Backstab (+25%), Shadow Dash through foes for critical hits.',
    'tank' => 'Heavy armor, high knockback resist. Hold center, guard (K) and Earth Rooster when swarmed.',
    'berserker' => 'More damage the lower your HP. Activate Rage + Mad Rooster for massive burst.',
    'troll' => 'Disruptor. Play dead to bait enemies close, explode to reverse their controls.',
    'dongtao' => 'Heavy melee fighter. Charge forward, Stomp Chain to break opponent balance.',
    'bantam' => 'Fastest but lightest rooster. Circle around, peck flurry and dash away.',
    'silkie' => 'Crowd control mage. Cast vortex near ring edges to blast enemies into the abyss.',
    _ => def.tipVi,
  };

  @override String arenaName(ArenaDef arena) => switch (arena.id) {
    'village' => 'Village Courtyard',
    'rooftop' => 'City Rooftop',
    'temple' => 'Ancient Temple',
    _ => arena.nameVi,
  };

  @override String arenaDesc(ArenaDef arena) => switch (arena.id) {
    'village' => 'Dirt ground surrounded by pond. Bamboo fence with 4 ring-out gaps.',
    'rooftop' => 'Open roof with no guard rails. Huge fans push roosters towards the ledge.',
    'temple' => 'Stone platforms over an abyss. Oscillating side pedestals require precise jumps.',
    _ => arena.descVi,
  };

  @override String get fightersAssemble => 'ENTER THE ARENA!';
  @override String get roosterDraw => 'ROOSTER DRAW!';
  @override String get youAre => 'YOU ARE';
  @override String rarityName(Rarity r) => r.nameEn;
  @override String skillLabel(String name) => 'Skill: $name';

  @override String get hudHp => 'HP';
  @override String get hudStamina => 'STAMINA';
  @override String get hudStaminaLow => 'STAMINA — LOW!';
  @override String get hudBalance => 'BALANCE';
  @override String get hudShield => 'SHIELD';
  @override String get hudShieldBroken => 'BROKEN';
  @override String get hudRage => 'RAGE';
  @override String get hudRageFull => 'RAGE FULL — PRESS U';
  @override String get hudRaging => 'RAGING';
  @override String get hudSkillNeedsRage => 'SKILL needs RAGE';
  @override String get hudRageSkill => 'RAGE + SKILL';
  @override String get hudCrow => 'CROW';
  @override String get hudGuard => 'GUARD';
  @override String hudSurvivalLeft(int left) => 'SURVIVAL · $left left';
  @override String get hudOutTag => ' · out';
  @override String get bannerFight => 'FIGHT!';
  @override String get bannerSurvived => 'SURVIVED!';
  @override String get bannerEnded => 'MATCH OVER!';
  @override String get bannerTimeUp => 'TIME UP!';
  @override String get hudSyncing => 'Syncing match...';
  @override String get hudSpectating => 'Spectating — you will join next match';
  @override String get hudEliminated => 'YOU ARE ELIMINATED — spectating';
  @override String get hudMatchEnded => 'MATCH ENDED';
  @override String get hudYou => 'YOU';

  @override String get resultsTitle => 'MATCH RESULTS';
  @override String get champCongrats => 'Congratulations to the champion!';
  @override String get drawMatch => 'Match ended in a draw!';
  @override String get matchEnded => 'Match concluded';
  @override String championBanner(String name, bool isYou) =>
      isYou ? 'YOU ARE THE CHAMPION!' : '$name IS THE CHAMPION!';
  @override String get mvpDamage => 'Highest Damage';
  @override String get waitingHostNext => 'Waiting for host to start next match...';
  @override String get rankCol => 'RANK';
  @override String get roosterCol => 'ROOSTER';
  @override String get koCol => 'KO';
  @override String get fallsCol => 'FALLS';
  @override String get dmgCol => 'DAMAGE';
  @override String get rematch => 'REMATCH';
  @override String get backToLobby => 'BACK TO LOBBY';
  @override String get leaveRoom => 'LEAVE ROOM';

  @override String get rosterTitle => 'ROOSTER ROSTER';
  @override String rosterHeader(int count) => 'Rooster Roster ($count)';
  @override String get rosterRules =>
      'Each match assigns a unique rooster to each player (up to 8).\n'
      '• Stamina (yellow): every attack costs stamina. Low stamina weakens hits; exhaustion leaves you panting.\n'
      '• Balance (blue): drops when struck; reaching 0 stuns you and increases knockback distance.\n'
      '• Rage (orange): hits landed/taken build Rage. When full, press U (SKILL): '
      'activates Rage (+30% damage, faster, immune to flinch) and fires your ultimate; '
      'press U again during Rage to reuse when off cooldown.\n'
      '• Guard (hold K / GUARD): reduces damage by 60%. Shield has its own durability (SHIELD bar): '
      'taking too many hits breaks shield and stuns you. Shield regenerates over time; '
      'raise it once 25% restored. High balance and armor recover shields faster (see "Shield Regen").\n'
      '• Defeated roosters drop hearts: collect to recover 30% HP (cannot pick up at full HP).\n'
      '• Respawn timer increases with each KO (3s base + 1s per death, max 8s).\n'
      '• Survival mode (lobby option): no respawns, elimination on KO — last rooster standing wins.\n'
      '• Ring-outs are the fastest way to KO opponents — knock them off the edge to claim the point!';
  @override String get tabStats => 'Stats';
  @override String get tabSkill => 'Skill';
  @override String get tabGuide => 'Guide';

  @override String get controlsTitle => 'CONTROLS';
  @override String get controlsExplanation =>
      'Top-left: HP (red) · STAMINA (yellow, costs to attack/dash) · BALANCE '
      '(blue, 0 = stunned) · RAGE (orange, press when full).\n'
      'Overhead bars: red = HP, blue tick = balance, orange dot = Rage ready.\n'
      'Colors: orange/red = attack (! = heavy incoming) · blue = guard · yellow = crow push.';
  @override List<(List<String>, String)> touchControls(String skillName) => [
    (['Drag Left'], 'Move'),
    (['Tap Right'], 'Light attack (continuous = combo)'),
    (['Hold Right'], 'Heavy attack (hold longer = stronger)'),
    (['GUARD'], 'Hold to block: reduces damage; shield breaks on HP depletion'),
    (['Swipe Down'], 'Dash'),
    (['Swipe Up'], 'Jump attack'),
    (['SKILL'], 'Rage full: unleash Rage + $skillName'),
    (['CROW'], 'Push back enemies, gain rage'),
  ];

  @override List<(List<String>, String)> keyboardControls(String skillName) => [
    (['W', 'A', 'S', 'D'], 'Move (or Arrow keys)'),
    (['J'], 'Light attack (rapid tap = combo)'),
    (['Hold J'], 'Heavy attack — release to strike'),
    (['Hold K'], 'Block: reduces damage; shield breaks on HP depletion'),
    (['L', 'Shift'], 'Dash'),
    (['Space'], 'Jump attack'),
    (['U'], 'Rage full: unleash Rage + $skillName'),
    (['O'], 'Crow: push back, gain rage'),
    (['H'], 'Toggle this controls panel'),
  ];

  @override String get closeRoomTitle => 'Close LAN Room?';
  @override String closeRoomContent(int others) => others > 0
      ? 'All $others other players will be kicked from the room.'
      : 'The room will be closed.';
  @override String get cancel => 'Cancel';
  @override String get closeRoomConfirm => 'CLOSE ROOM';
  @override String get closeRoomBtn => 'Close Room';

  @override String get connectingToHost => 'Connecting to host...';
  @override String get reconnectingToHost => 'Connection lost — reconnecting...';
  @override String get kickedFromRoom => 'You have been removed from the room.';
  @override String get cannotConnectHost => 'Cannot connect to host.';
  @override String get wifiCheckHint => 'Check that you are on the same Wi-Fi and host is running.';
  @override String get backToHome => 'BACK TO HOME';
  @override String get leaveMatchTitle => 'Leave match?';
  @override String leaveMatchContent(bool canClose) => canClose
      ? 'Leave match: a bot will take over your rooster.\n'
          'Close room: ends the match and returns everyone to lobby.'
      : 'A bot will take over your rooster.';
  @override String get stayBtn => 'Stay';
  @override String get leaveBtn => 'Leave';
  @override String get controlsGuideTouch => 'Controls Guide';
  @override String get controlsGuideKeyboard => 'Controls Guide (H)';
  @override String get soundMutedTooltip => 'All audio muted — tap to unmute';
  @override String get soundMusicOffTooltip => 'Music muted — tap to mute all';
  @override String get soundOnTooltip => 'Tap to mute music';
  @override String get yourRoosterInfo => 'Your Rooster Info';
  @override String get uniqueSkillDefault => 'unique skill';
}

/// A compact, styled toggle button for switching English / Vietnamese
class LanguageToggleButton extends ConsumerWidget {
  final bool compact;
  const LanguageToggleButton({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(l10nProvider);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(l10nProvider.notifier).toggle(),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: const Color(0x991B100A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: RC.panelHi, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                current.flag,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 5),
              Text(
                current.code,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: RC.gold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.swap_horiz,
                size: 14,
                color: RC.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
