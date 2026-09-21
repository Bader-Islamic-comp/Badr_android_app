import 'package:flutter/material.dart';

/// The supplied Robert palette. The `design/ui-reference.png` layout is used for
/// hierarchy only; its dark violet colours are deliberately not adopted.
const ink = Color(0xFF153E40);
const teal = Color(0xFF236C67);
const ivory = Color(0xFFFAF7EF);
const orange = Color(0xFFB74D25);
const sage = Color(0xFFE4EEDE);
const sand = Color(0xFFF3E6D1);
const hairline = Color(0xFFE2E5DB);
const muted = Color(0xFF4F6D6B);

/// Scrims for the full-bleed layout. When the character room is composited
/// behind Flutter the page itself is transparent, so anything carrying text
/// needs its own surface: a 3D scene is not a background you can rely on for
/// contrast. Each is the ordinary colour at high opacity, so the palette reads
/// the same whether or not a room is present.
const ivoryScrim = Color(0xF2FAF7EF);
const sandScrim = Color(0xF2F3E6D1);

ThemeData companionTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: ivory,
      colorScheme: ColorScheme.fromSeed(
          seedColor: teal,
          primary: teal,
          secondary: orange,
          surface: ivory,
          onSurface: ink),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -1,
            color: ink),
        headlineSmall:
            TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ink),
        titleLarge:
            TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: ink),
        bodyLarge: TextStyle(fontSize: 17, height: 1.5, color: ink),
        bodyMedium: TextStyle(fontSize: 15, height: 1.45, color: ink),
        labelLarge:
            TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      )),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: ivoryScrim,
        indicatorColor: sage,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
