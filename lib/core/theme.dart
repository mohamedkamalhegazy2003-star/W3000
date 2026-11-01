import 'package:flutter/material.dart';

const Color kBrand = Color(0xFF2563EB);
const Color kBrandDeep = Color(0xFF3730A3);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: kBrand, brightness: b).copyWith(primary: kBrand);
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Plex',
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0F1115) : const Color(0xFFF8FAFC),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: dark ? const Color(0xFF0F1115) : Colors.white,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF1A1D23) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    }),
  );
}
