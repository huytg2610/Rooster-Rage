/// Non-web fallbacks (Android/iOS use native APIs later).
class WebHelpers {
  static bool get isWeb => false;
  static Uri? defaultServerUri() => null;
  static void removeBootSplash() {}
  static Future<bool> probeHost() async => false;
  static Future<void> enterFullscreen() async {}
  static Future<void> keepScreenOn() async {}
  static bool get isFullscreen => false;
  static String get quality => 'auto';
  static void setQuality(String q) {}
}
