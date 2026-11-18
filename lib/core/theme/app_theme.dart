import 'package:flutter/material.dart';

/// Tema Visual Moderno: Paleta Verde-Azul (Teal / Cyan / Slate)
/// Diseñado con estética de tarjetas suaves (Bootstrap/Bulma Cards) y alta legibilidad.
class AppTheme {
  // Paleta de Colores Verde-Azul (Teal / Cyan / Petróleo)
  static const Color tealPrimary = Color(0xFF006D77);     // Verde-Azul principal
  static const Color tealDark = Color(0xFF004D40);        // Verde-Azul petróleo profundo
  static const Color tealLight = Color(0xFF83C5BE);       // Verde-Azul suave
  static const Color tealAccent = Color(0xFF0097A7);      // Cyan vivo
  static const Color bgSurfaceLight = Color(0xFFF2F7F7);  // Fondo suave menta-gris
  static const Color cardBg = Colors.white;              // Superficie blanca limpia
  static const Color cardBorder = Color(0xFFCCE3DE);      // Borde suave Bulma-style
  static const Color textDark = Color(0xFF0F2F38);        // Texto principal oscuro 100% legible
  static const Color textSecondary = Color(0xFF475569);   // Texto secundario gris slate
  static const Color buttonGreen = Color(0xFF00897B);     // Verde-Azul de acción

  static ThemeData get solarLightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: tealPrimary,
      scaffoldBackgroundColor: bgSurfaceLight,
      colorScheme: const ColorScheme.light(
        primary: tealPrimary,
        secondary: tealAccent,
        surface: cardBg,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textDark,
      ),
      fontFamily: 'sans-serif',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 24.0,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        titleLarge: TextStyle(
          fontSize: 20.0,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        titleMedium: TextStyle(
          fontSize: 16.0,
          fontWeight: FontWeight.w600,
          color: textDark,
        ),
        bodyLarge: TextStyle(
          fontSize: 15.0,
          color: textDark,
        ),
        bodyMedium: TextStyle(
          fontSize: 14.0,
          color: textSecondary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 15.0),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14.0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.0),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.0),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.0),
          borderSide: const BorderSide(color: tealPrimary, width: 2.0),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(54.0),
          backgroundColor: buttonGreen,
          foregroundColor: Colors.white,
          elevation: 2.0,
          shadowColor: const Color(0x4D00897B),
          textStyle: const TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: tealDark,
        foregroundColor: Colors.white,
        elevation: 0.0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  static ThemeData get solarDarkTheme => solarLightTheme;
}
