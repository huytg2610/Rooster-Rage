/// Every sound effect in the game. All are synthesized at runtime; there are
/// no audio assets.
enum SoundId {
  // UI / match flow
  uiClick,
  cardFlip,
  fanfare,
  countdownBeep,
  countdownGo,
  timeUp,
  // Movement
  whooshLight,
  whooshHeavy,
  dash,
  jump,
  land,
  landBig,
  // Combat
  hitLight,
  hitHeavy,
  hitCrit,
  block,
  guardBreak,
  // Arena / props
  ko,
  splash,
  fallWhistle,
  pickup,
  trapSnap,
  bucketSpill,
  // Chicken voice
  cluck,
  squawk,
  crow,
  rageRoar,
  // Skills
  flameKick,
  shadowDash,
  earthBoom,
  madSquawk,
  fakeDeath,
  surprise,
  stomp,
  peck,
  vortex,
  vortexBurst,
  respawn,
  exhausted,
  // Battle atmosphere
  taiko,
  gong,
  heartbeat,
  clockTick,
  crowdOoh,
  crowdCheer,
}

/// Looping background music.
enum MusicTrack {
  /// Main fight: war drums, pulsing bass, tense pad (~140 BPM).
  battle,

  /// Last 30 s: faster, denser, higher (~160 BPM).
  finale,
}
