/// Game sound effects: `SoundFx.instance.play(SoundId.cluck)`.
///
/// Web builds play procedurally synthesized buffers through Web Audio; other
/// platforms get a silent stub for now.
library;

export 'sound_fx_stub.dart' if (dart.library.js_interop) 'sound_fx_web.dart';
export 'sound_ids.dart';
