import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF6E4BC4);
  static const Color background = Color(0xFFF7F3FB);
  static const Color surface = Colors.white;
  static const Color active = Color(0xFFC9F5DA);
  static const Color activeText = Color(0xFF13864A);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: primary, brightness: Brightness.light),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardTheme(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE3DCEF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const StatusPill({super.key, required this.label, required this.background, required this.foreground});

  factory StatusPill.active() =>
      const StatusPill(label: 'Active', background: AppTheme.active, foreground: AppTheme.activeText);

  factory StatusPill.fromStatus(String status) {
    final lower = status.toLowerCase();
    if (lower == 'active') return StatusPill.active();
    return StatusPill(
      label: status.isEmpty ? 'Unknown' : status[0].toUpperCase() + status.substring(1),
      background: const Color(0xFFFFE9C7),
      foreground: const Color(0xFF8A5A00),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
