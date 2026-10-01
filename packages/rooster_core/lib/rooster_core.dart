/// Rooster Rage shared game core.
///
/// Layers (GDD §7): Domain (combat rules, skills, damage), Data (chicken
/// configs, arenas, network DTOs) and the authoritative simulation used by
/// every host (LAN server, offline mode, future Android host).
library;

export 'src/ai/bot_brain.dart';
export 'src/data/arenas.dart';
export 'src/data/chicken_classes.dart';
export 'src/data/tuning.dart';
export 'src/data/variants.dart';
export 'src/math/rng.dart';
export 'src/math/vec2.dart';
export 'src/net/protocol.dart';
export 'src/net/room_host.dart';
export 'src/net/bytes.dart';
export 'src/net/snapshot.dart';
export 'src/net/snapshot_codec.dart';
export 'src/random/chicken_generator.dart';
export 'src/sim/arena_runtime.dart';
export 'src/sim/combat.dart';
export 'src/sim/events.dart';
export 'src/sim/fighter.dart';
export 'src/sim/fighter_logic.dart';
export 'src/sim/input.dart';
export 'src/sim/match_sim.dart';
export 'src/sim/skills.dart';
