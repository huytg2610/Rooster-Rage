import 'package:flutter/material.dart';

/// Saturday-morning cartoon palette: warm village browns + arcade accents.
class RC {
  static const bg = Color(0xFF2B1B12);
  static const bg2 = Color(0xFF45291A);
  static const panel = Color(0xFF5A3620);
  static const panelHi = Color(0xFF6E4428);
  static const ink = Color(0xFF1B100A);
  static const cream = Color(0xFFFFF1D6);
  static const gold = Color(0xFFFFC21A);
  static const orange = Color(0xFFFF7A1A);
  static const red = Color(0xFFE8412C);
  static const green = Color(0xFF55C24A);
  static const blue = Color(0xFF3FA9F5);
  static const muted = Color(0xFFC9A98A);

  static const hp = Color(0xFFE8412C);
  static const stamina = Color(0xFFFFC21A);
  static const balance = Color(0xFF3FA9F5);
  static const rage = Color(0xFFFF5A1F);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: RC.orange,
      brightness: Brightness.dark,
      surface: RC.bg,
      primary: RC.gold,
      secondary: RC.orange,
    ),
    scaffoldBackgroundColor: RC.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: RC.cream,
      displayColor: RC.cream,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: RC.gold,
        foregroundColor: RC.ink,
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: RC.cream,
        side: const BorderSide(color: RC.muted, width: 2),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RC.panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      labelStyle: const TextStyle(color: RC.muted),
    ),
  );
}

/// Rounded wooden panel used across menus.
class WoodPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const WoodPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: RC.panel,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: RC.ink, width: 3),
      boxShadow: const [
        BoxShadow(color: Color(0x66000000), offset: Offset(0, 5)),
      ],
    ),
    child: child,
  );
}

Color argb(int v) => Color(v);
