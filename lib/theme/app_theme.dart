import 'package:flutter/material.dart';

/// HoneyChain light visual system.
///
/// The palette is intentionally warm and agricultural: soft cream surfaces,
/// honey amber for primary actions, deep brown ink, green for healthy state,
/// and red only for attention. Existing semantic names are retained so the
/// rest of the application does not need a logic rewrite.
class AppTheme {
  static const Color cream = Color(0xFFFFFBF4);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardWarm = Color(0xFFFFF5E3);
  static const Color bg = cream;

  static const Color honeyGold = Color(0xFFF0AE32);
  static const Color cardCream = cardWarm;

  static const Color ink = Color(0xFF2E2417);
  static const Color inkSoft = Color(0xFF6E6558);
  static const Color inkFaint = Color(0xFF978E7F);

  static const Color orange = Color(0xFFE8640E);
  static const Color orangeDark = Color(0xFFD2540A);
  static const Color orangeSoft = Color(0x1FE8640E);
  static const Color green = Color(0xFF2E7D32);
  static const Color greenDark = Color(0xFF256428);
  static const Color greenSoft = Color(0x1A2E7D32);
  static const Color red = Color(0xFFC93A3A);
  static const Color redSoft = Color(0x14C93A3A);

  static const Color honey = Color(0xFFE8A33D);
  static const Color honeyDark = Color(0xFFB97B1B);
  static const Color teal = Color(0xFF00897B);
  static const Color blue = Color(0xFF1565C0);
  static const Color purple = Color(0xFF5E35B1);
  static const Color grey = Color(0xFF757575);

  static const Color border = Color(0x1A2E2417);
  static const BorderRadius radiusCard =
      BorderRadius.all(Radius.circular(20));
  static const BorderRadius radiusField =
      BorderRadius.all(Radius.circular(14));

  static const BoxShadow shadowCard = BoxShadow(
    color: Color(0x12000000),
    blurRadius: 20,
    offset: Offset(0, 7),
  );

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: honeyGold,
      primary: honeyGold,
      surface: card,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: ink),
        titleTextStyle: TextStyle(
          color: ink,
          fontWeight: FontWeight.w800,
          fontSize: 21,
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: ink,
          fontSize: 26,
          fontWeight: FontWeight.w800,
        ),
        headlineMedium: TextStyle(
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: ink,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: ink, fontSize: 16),
        bodyMedium: TextStyle(color: ink, fontSize: 14, height: 1.35),
        labelMedium: TextStyle(
          color: ink,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radiusCard,
          side: const BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: honeyGold,
          foregroundColor: ink,
          elevation: 0,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: honeyDark,
          side: const BorderSide(color: honeyGold),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: honeyDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        side: BorderSide.none,
        selectedColor: honeyGold,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: inkSoft,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: radiusField,
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusField,
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusField,
          borderSide: const BorderSide(color: honeyGold, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusField,
          borderSide: const BorderSide(color: red),
        ),
        labelStyle: const TextStyle(
          color: inkSoft,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Color(0x26E8A33D),
        height: 66,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? honeyDark
                : inkFaint,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected)
                ? honeyDark
                : inkFaint,
          ),
        ),
      ),
    );
  }

  static Color tint(Color c) => c.withValues(alpha: 0.14);
}
