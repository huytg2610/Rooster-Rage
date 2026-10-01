import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'audio/sound_fx.dart';
import 'platform/web_helpers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Skia's default GPU resource cache (256 MB) fills with cached path
    // tessellations in a busy match; phones run out of memory long before
    // that and the tab freezes or goes black.
    SystemChannels.skia
        .invokeMethod<void>('Skia.setResourceCacheMaxBytes', 48 << 20)
        .ignore();
  }
  // Browsers only allow audio after a user gesture: unlock on first key.
  HardwareKeyboard.instance.addHandler((_) {
    SoundFx.instance.unlock();
    return false;
  });
  SharedPreferences.getInstance()
      .then((p) {
        SoundFx.instance.muted = p.getBool(soundMutedPref) ?? false;
        SoundFx.instance.musicMuted = p.getBool(musicMutedPref) ?? false;
      })
      .ignore(); // storage blocked (private mode) — keep defaults
  runApp(const ProviderScope(child: RoosterApp()));
  // Keep the "loading" text until Flutter has actually painted.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => WebHelpers.removeBootSplash(),
  );
}

const soundMutedPref = 'sfx_muted';
const musicMutedPref = 'music_muted';
