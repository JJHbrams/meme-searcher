import 'package:material_ui/material_ui.dart';

abstract final class MemeTheme {
  static const background = Color(0xff171a1b);
  static const surface = Color(0xff202526);
  static const surfaceRaised = Color(0xff282d2e);
  static const border = Color(0xff3b4341);
  static const text = Color(0xfff0f2ec);
  static const muted = Color(0xffa0aaa4);
  static const accent = Color(0xffb9f66b);
  static const accentInk = Color(0xff203012);
  static const cream = Color(0xfff5f1e7);

  static ThemeData build() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: text),
        bodyMedium: TextStyle(color: text),
        bodySmall: TextStyle(color: muted),
        titleLarge: TextStyle(color: text, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(color: text, fontWeight: FontWeight.w700),
      ),
      dividerColor: border,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: cream,
        hintStyle: TextStyle(color: Color(0xff68716d)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceRaised,
        contentTextStyle: TextStyle(
          color: text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
