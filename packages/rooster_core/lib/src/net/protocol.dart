/// Network DTOs and message types (GDD §7 Data layer, §10).
///
/// Transport: JSON objects over a reliable ordered channel (WebSocket on
/// LAN, in-memory for offline play). Every message has a `t` type field.
library;

import '../data/variants.dart';
import '../sim/fighter.dart';

const protocolVersion = 4; // 4: shield HP + broken flag, heal drops

class Msg {
  // client → host
  static const hello = 'hello'; // pid, name, games, v
  static const settings = 'settings'; // owner: mode, arena, dur, bots, lvl
  static const start = 'start'; // owner
  static const pick = 'pick'; // class, variant (competitive)
  static const toLobby = 'lobby'; // owner, from results
  static const rematch = 'rematch'; // owner, from results
  static const close = 'close'; // owner: close the room, kick everyone
  static const ping = 'ping'; // c (client clock, echoed back)

  // host → client
  static const welcome = 'welcome'; // pid, local
  static const room = 'room'; // RoomState
  static const reveal = 'reveal'; // entries, dur
  static const match = 'match'; // arena, dur, fighters, you
  static const results = 'results'; // results
  static const error = 'err'; // msg
  static const closed = 'closed'; // msg — room closed by its owner
  static const pong = 'pong'; // c
}

enum GameMode { party, competitive }

class LobbySettings {
  final GameMode mode;
  final String arenaId;
  final int duration; // seconds
  final int bots;
  final int botLevel;
  final bool survival; // no respawn: last chicken standing wins

  const LobbySettings({
    this.mode = GameMode.party,
    this.arenaId = 'village',
    this.duration = 180,
    this.bots = 3,
    this.botLevel = 1,
    this.survival = false,
  });

  LobbySettings copyWith({
    GameMode? mode,
    String? arenaId,
    int? duration,
    int? bots,
    int? botLevel,
    bool? survival,
  }) =>
      LobbySettings(
        mode: mode ?? this.mode,
        arenaId: arenaId ?? this.arenaId,
        duration: duration ?? this.duration,
        bots: bots ?? this.bots,
        botLevel: botLevel ?? this.botLevel,
        survival: survival ?? this.survival,
      );

  Map<String, Object> toJson() => {
        'mode': mode.name,
        'arena': arenaId,
        'dur': duration,
        'bots': bots,
        'lvl': botLevel,
        'surv': survival,
      };

  static LobbySettings fromJson(Map<String, dynamic> j) => LobbySettings(
        mode: GameMode.values.byName(j['mode'] as String? ?? 'party'),
        arenaId: j['arena'] as String? ?? 'village',
        duration: j['dur'] as int? ?? 180,
        bots: j['bots'] as int? ?? 0,
        botLevel: j['lvl'] as int? ?? 1,
        survival: j['surv'] as bool? ?? false,
      );
}

class LobbyPlayerDto {
  final String pid;
  final String name;
  final int slot;
  final bool connected;
  final String? picked;
  final String? pickedVariant;

  const LobbyPlayerDto({
    required this.pid,
    required this.name,
    required this.slot,
    required this.connected,
    this.picked,
    this.pickedVariant,
  });

  Map<String, Object?> toJson() => {
        'pid': pid,
        'name': name,
        'slot': slot,
        'on': connected,
        'pick': picked,
        'pv': pickedVariant,
      };

  static LobbyPlayerDto fromJson(Map<String, dynamic> j) => LobbyPlayerDto(
        pid: j['pid'] as String,
        name: j['name'] as String,
        slot: j['slot'] as int,
        connected: j['on'] as bool? ?? true,
        picked: j['pick'] as String?,
        pickedVariant: j['pv'] as String?,
      );
}

enum RoomPhase { lobby, picking, reveal, match, results }

class RoomState {
  final RoomPhase phase;
  final String? ownerPid;
  final LobbySettings settings;
  final List<LobbyPlayerDto> players;
  final List<String> joinUrls;
  final double timer;
  final bool local;

  const RoomState({
    required this.phase,
    required this.ownerPid,
    required this.settings,
    required this.players,
    required this.joinUrls,
    required this.timer,
    required this.local,
  });

  Map<String, Object?> toJson() => {
        't': Msg.room,
        'phase': phase.name,
        'owner': ownerPid,
        'settings': settings.toJson(),
        'players': [for (final p in players) p.toJson()],
        'urls': joinUrls,
        'timer': timer,
        'local': local,
      };

  static RoomState fromJson(Map<String, dynamic> j) => RoomState(
        phase: RoomPhase.values.byName(j['phase'] as String),
        ownerPid: j['owner'] as String?,
        settings: LobbySettings.fromJson((j['settings'] as Map).cast<String, dynamic>()),
        players: [
          for (final p in (j['players'] as List).cast<Map>())
            LobbyPlayerDto.fromJson(p.cast<String, dynamic>())
        ],
        joinUrls: (j['urls'] as List? ?? const []).cast<String>(),
        timer: (j['timer'] as num? ?? 0).toDouble(),
        local: j['local'] as bool? ?? false,
      );
}

/// Static per-fighter info sent once at match start.
class FighterInfo {
  final int id;
  final String pid;
  final String name;
  final int slot;
  final bool bot;
  final String classId;
  final Variant variant;
  final Rarity rarity;
  final double maxHp, maxStamina, maxBalance, skillCooldown;

  const FighterInfo({
    required this.id,
    required this.pid,
    required this.name,
    required this.slot,
    required this.bot,
    required this.classId,
    required this.variant,
    required this.rarity,
    required this.maxHp,
    required this.maxStamina,
    required this.maxBalance,
    required this.skillCooldown,
  });

  factory FighterInfo.of(Fighter f) => FighterInfo(
        id: f.id,
        pid: f.setup.playerId,
        name: f.setup.name,
        slot: f.setup.slot,
        bot: f.setup.isBot,
        classId: f.setup.classId,
        variant: f.setup.variant,
        rarity: f.setup.rarity,
        maxHp: f.maxHp,
        maxStamina: f.maxStamina,
        maxBalance: f.maxBalance,
        skillCooldown: f.def.skillCooldown,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'pid': pid,
        'name': name,
        'slot': slot,
        'bot': bot,
        'class': classId,
        'variant': variant.name,
        'rarity': rarity.name,
        'hp': maxHp,
        'sta': maxStamina,
        'bal': maxBalance,
        'scd': skillCooldown,
      };

  static FighterInfo fromJson(Map<String, dynamic> j) => FighterInfo(
        id: j['id'] as int,
        pid: j['pid'] as String,
        name: j['name'] as String,
        slot: j['slot'] as int,
        bot: j['bot'] as bool,
        classId: j['class'] as String,
        variant: Variant.values.byName(j['variant'] as String),
        rarity: Rarity.values.byName(j['rarity'] as String),
        maxHp: (j['hp'] as num).toDouble(),
        maxStamina: (j['sta'] as num).toDouble(),
        maxBalance: (j['bal'] as num).toDouble(),
        skillCooldown: (j['scd'] as num).toDouble(),
      );
}

/// Player slot colors (ARGB) — name tags, rings, scoreboard.
const slotColors = <int>[
  0xFFFF4D4D, // red
  0xFF3D8BFF, // blue
  0xFF2ECC71, // green
  0xFFFFC300, // yellow
  0xFFB45CFF, // purple
  0xFFFF8C1A, // orange
  0xFF1ADBD4, // cyan
  0xFFFF5CC8, // pink
];

const botNames = <String>[
  'Bot Tèo', 'Bot Tí', 'Bot Sửu', 'Bot Dần',
  'Bot Mão', 'Bot Thìn', 'Bot Tỵ', 'Bot Ngọ',
];
