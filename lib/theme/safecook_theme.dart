import 'package:flutter/material.dart';

/// SafeCook centralized design system.
/// All screens must consume tokens from this file — no ad-hoc color values.
class SafeCookColors {
  SafeCookColors._();

  // ── Brand / Primary ───────────────────────────────────────────────────────
  static const Color primary = Color(0xFF0EA5E9); // sky-500
  static const Color primaryLight = Color(0xFF38BDF8); // sky-400
  static const Color primaryContainer = Color(0x1A0EA5E9); // 10% opacity

  // ── Backgrounds ───────────────────────────────────────────────────────────
  static const Color background = Color(0xFF0B1221); // deep navy
  static const Color surface = Color(0xFF162032); // slightly lifted
  static const Color surfaceElevated = Color(0xFF1C2B3D); // card background
  static const Color surfaceHighest = Color(0xFF243449); // elevated card

  // ── Safety states ─────────────────────────────────────────────────────────
  static const Color safe = Color(0xFF10B981); // emerald-500
  static const Color safeBg = Color(0x1A10B981);
  static const Color safeBorder = Color(0x4D10B981);

  static const Color caution = Color(0xFFF59E0B); // amber-400
  static const Color cautionBg = Color(0x1AF59E0B);
  static const Color cautionBorder = Color(0x4DF59E0B);

  static const Color danger = Color(0xFFEF4444); // red-500
  static const Color dangerBg = Color(0x1AEF4444);
  static const Color dangerBorder = Color(0x4DEF4444);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF1F5F9); // slate-100
  static const Color textSecondary = Color(0xFF94A3B8); // slate-400
  static const Color textMuted = Color(0xFF475569); // slate-600
  static const Color textDisabled = Color(0xFF334155); // slate-700

  // ── Dividers / Borders ────────────────────────────────────────────────────
  static const Color border = Color(0xFF1E3A5F);
  static const Color divider = Color(0xFF1E3A5F);

  // ── Accent states for sensor pills ───────────────────────────────────────
  static const Color bluetoothActive = Color(0xFF60A5FA); // blue-400
  static const Color bluetoothBg = Color(0x1A60A5FA);
}

class SafeCookRadius {
  SafeCookRadius._();

  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double full = 100.0;
}

class SafeCookSpacing {
  SafeCookSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  /// Standard horizontal page padding
  static const EdgeInsets pagePadding =
      EdgeInsets.symmetric(horizontal: 20.0);

  /// Standard section vertical gap
  static const double sectionGap = 24.0;
}

class SafeCookTextStyles {
  SafeCookTextStyles._();

  // Display — hero numbers / state labels
  static const TextStyle displayLarge = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 48,
    fontWeight: FontWeight.w900,
    color: SafeCookColors.textPrimary,
    letterSpacing: -1.0,
    height: 1.0,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 32,
    fontWeight: FontWeight.w800,
    color: SafeCookColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.1,
  );

  // Screen title
  static const TextStyle titleLarge = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: SafeCookColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: SafeCookColors.textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle titleSmall = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: SafeCookColors.textPrimary,
  );

  // Section labels / overlines
  static const TextStyle label = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: SafeCookColors.textSecondary,
    letterSpacing: 1.2,
  );

  // Body text
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: SafeCookColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: SafeCookColors.textSecondary,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: SafeCookColors.textMuted,
    height: 1.4,
  );

  // Step instruction — large readable cooking text
  static const TextStyle stepInstruction = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: SafeCookColors.textPrimary,
    height: 1.45,
  );

  // Numeric values on sensor cards
  static const TextStyle sensorValue = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: SafeCookColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle sensorValueSmall = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: SafeCookColors.textPrimary,
  );
}

/// The primary MaterialApp ThemeData for SafeCook.
ThemeData buildSafeCookTheme() {
  final colorScheme = const ColorScheme.dark(
    primary: SafeCookColors.primary,
    onPrimary: Colors.white,
    primaryContainer: SafeCookColors.primaryContainer,
    onPrimaryContainer: SafeCookColors.textPrimary,
    secondary: SafeCookColors.primaryLight,
    onSecondary: Colors.white,
    surface: SafeCookColors.surface,
    onSurface: SafeCookColors.textPrimary,
    onSurfaceVariant: SafeCookColors.textSecondary,
    error: SafeCookColors.danger,
    onError: Colors.white,
    outline: SafeCookColors.border,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: SafeCookColors.background,
    fontFamily: 'Nunito',

    appBarTheme: const AppBarTheme(
      backgroundColor: SafeCookColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: SafeCookColors.textPrimary,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: SafeCookColors.textPrimary, size: 24),
    ),

    cardTheme: CardThemeData(
      color: SafeCookColors.surfaceElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(SafeCookRadius.md)),
        side: BorderSide(color: SafeCookColors.border, width: 0.5),
      ),
      margin: EdgeInsets.zero,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SafeCookColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SafeCookRadius.sm),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
        elevation: 0,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SafeCookColors.textPrimary,
        minimumSize: const Size(0, 52),
        side: const BorderSide(color: SafeCookColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SafeCookRadius.sm),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SafeCookColors.primaryLight,
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SafeCookColors.surfaceElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SafeCookRadius.sm),
        borderSide: const BorderSide(color: SafeCookColors.border, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SafeCookRadius.sm),
        borderSide: const BorderSide(color: SafeCookColors.border, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SafeCookRadius.sm),
        borderSide: const BorderSide(color: SafeCookColors.primaryLight),
      ),
      hintStyle: const TextStyle(
        fontFamily: 'Nunito',
        color: SafeCookColors.textMuted,
        fontSize: 14,
      ),
      labelStyle: const TextStyle(
        fontFamily: 'Nunito',
        color: SafeCookColors.textSecondary,
        fontSize: 14,
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: SafeCookColors.surfaceElevated,
      selectedColor: SafeCookColors.primaryContainer,
      labelStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: SafeCookColors.textSecondary,
      ),
      side: const BorderSide(color: SafeCookColors.border, width: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SafeCookRadius.xs),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    ),

    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
      iconColor: SafeCookColors.textSecondary,
      titleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: SafeCookColors.textPrimary,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 12,
        color: SafeCookColors.textSecondary,
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: SafeCookColors.divider,
      thickness: 0.5,
      space: 0,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return SafeCookColors.safe;
        }
        return SafeCookColors.textMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return SafeCookColors.safeBg;
        }
        return SafeCookColors.surfaceHighest;
      }),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: SafeCookColors.surfaceHighest,
      contentTextStyle: const TextStyle(
        fontFamily: 'Nunito',
        color: SafeCookColors.textPrimary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SafeCookRadius.sm),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: SafeCookColors.primary,
      linearTrackColor: SafeCookColors.surfaceHighest,
    ),
  );
}
