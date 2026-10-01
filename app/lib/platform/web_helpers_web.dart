import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Browser integration: fullscreen + landscape lock + screen wake lock, so
/// phones stay awake and don't rotate mid-fight.
class WebHelpers {
  static bool get isWeb => true;

  /// `ws://<same host>/ws` when the page is served by the LAN host.
  static Uri? defaultServerUri() {
    final base = Uri.base;
    if (base.scheme != 'http' && base.scheme != 'https') return null;
    return Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/ws',
    );
  }

  static void removeBootSplash() =>
      web.document.getElementById('boot')?.remove();

  /// True if this page was served by a Rooster Rage LAN host (any port).
  static Future<bool> probeHost() async {
    try {
      final res = await web.window.fetch('rr-host'.toJS).toDart;
      return res.ok;
    } on Object {
      return false;
    }
  }

  /// Render quality: 'auto' (cap 2x), 'low' (1.25x), 'high' (native).
  /// Read by web/index.html before Flutter boots, so changes reload.
  static String get quality {
    try {
      return web.window.localStorage.getItem('rr_quality') ?? 'auto';
    } on Object {
      return 'auto';
    }
  }

  static void setQuality(String q) {
    try {
      web.window.localStorage.setItem('rr_quality', q);
      web.window.location.reload();
    } on Object {
      // Storage blocked — keep current quality.
    }
  }

  static bool get isFullscreen => web.document.fullscreenElement != null;

  static Future<void> enterFullscreen() async {
    try {
      await web.document.documentElement?.requestFullscreen().toDart;
    } on Object {
      // Not allowed (iOS Safari) — ignore.
    }
    try {
      await web.window.screen.orientation.lock('landscape').toDart;
    } on Object {
      // Orientation lock unsupported — ignore.
    }
    await keepScreenOn();
  }

  static Future<void> keepScreenOn() async {
    try {
      await web.window.navigator.wakeLock.request('screen').toDart;
    } on Object {
      // Wake lock unsupported — ignore.
    }
  }
}
