import 'package:flutter/material.dart';

const dualBg = Color(0xFF050E1B);
const dualSurface = Color(0xFF0A1A2D);
const dualSurface2 = Color(0xFF102742);
const dualSurface3 = Color(0xFF153453);
const dualBlue = Color(0xFF0A84FF);
const dualBlueBright = Color(0xFF19A7FF);
const dualCyan = Color(0xFF38D4FF);
const dualGreen = Color(0xFF20C779);
const dualRed = Color(0xFFFF4664);
const dualAmber = Color(0xFFFFC857);
const dualText = Color(0xFFF4F8FF);
const dualMuted = Color(0xFF8DAAC7);
const dualBorder = Color(0xFF1C3B5A);

ThemeData expressDualTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: dualBlue,
    brightness: Brightness.dark,
    surface: dualSurface,
  ).copyWith(
    primary: dualBlue,
    secondary: dualCyan,
    error: dualRed,
    surface: dualSurface,
    onSurface: dualText,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: dualBg,
    canvasColor: dualBg,
    cardColor: dualSurface,
    dividerColor: dualBorder,
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFF08172A),
      indicatorColor: Color(0xFF123B66),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF10233A),
      contentTextStyle: TextStyle(color: dualText),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: dualSurface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: dualSurface,
      modalBackgroundColor: dualSurface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dualSurface2,
      labelStyle: const TextStyle(color: dualMuted),
      hintStyle: const TextStyle(color: Color(0xFF67829F)),
      prefixIconColor: dualMuted,
      suffixIconColor: dualMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: dualBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: dualBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: dualBlue, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dualBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: dualText,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: dualBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: dualBlueBright),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: dualSurface2,
      selectedColor: const Color(0xFF123B66),
      side: const BorderSide(color: dualBorder),
      labelStyle: const TextStyle(color: dualText),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    ),
  );
}

class ExpressDualRoleSwitch extends StatelessWidget {
  final bool driver;
  final VoidCallback onPassenger;
  final VoidCallback onDriver;
  final bool compact;

  const ExpressDualRoleSwitch({
    super.key,
    required this.driver,
    required this.onPassenger,
    required this.onDriver,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 3 : 4),
      decoration: BoxDecoration(
        color: const Color(0xD908172A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: dualBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoleSegment(
            icon: Icons.person_rounded,
            label: compact ? 'Cliente' : 'Modo cliente',
            selected: !driver,
            onTap: onPassenger,
            compact: compact,
          ),
          _RoleSegment(
            icon: Icons.drive_eta_rounded,
            label: compact ? 'Conductor' : 'Modo conductor',
            selected: driver,
            onTap: onDriver,
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _RoleSegment extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  const _RoleSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? dualBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 13,
            vertical: compact ? 7 : 9,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 15 : 17, color: dualText),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: dualText,
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
