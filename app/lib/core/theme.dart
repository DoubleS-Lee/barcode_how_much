import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kPrimary = Color(0xFF0747AD);
const kPrimaryDark = Color(0xFF003280);
const kOnPrimary = Color(0xFFFFFFFF);
const kPrimaryContainer = Color(0xFFD7E2FF);
const kOnPrimaryContainer = Color(0xFF001A41);
const kAmber = Color(0xFFFEB300);
const kBackground = Color(0xFFFCFBFF);
const kSurface = Color(0xFFFFFFFF);
const kSurfaceContainerLow = Color(0xFFF3F3FC);
const kSurfaceContainerHigh = Color(0xFFE8E8EC);
const kOnSurface = Color(0xFF1A1C1E);
const kOnSurfaceVariant = Color(0xFF44474E);
const kOutline = Color(0xFF74777F);
const kOutlineVariant = Color(0xFFC4C6CF);
const kError = Color(0xFFBA1A1A);

final eolmaeTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.light(
    primary: kPrimary,
    onPrimary: kOnPrimary,
    primaryContainer: kPrimaryContainer,
    onPrimaryContainer: kOnPrimaryContainer,
    secondary: kAmber,
    onSecondary: Color(0xFF281900),
    secondaryContainer: Color(0xFFFFDEAC),
    onSecondaryContainer: Color(0xFF6A4800),
    surface: kSurface,
    onSurface: kOnSurface,
    onSurfaceVariant: kOnSurfaceVariant,
    outline: kOutline,
    outlineVariant: kOutlineVariant,
    error: kError,
    onError: kOnPrimary,
  ),
  scaffoldBackgroundColor: kBackground,
  textTheme: GoogleFonts.interTextTheme().copyWith(
    displayLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
    displayMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
    displaySmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
    headlineLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
    headlineMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
    headlineSmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
    titleLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
    titleMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
    titleSmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: kSurface,
    foregroundColor: kOnSurface,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    titleTextStyle: GoogleFonts.plusJakartaSans(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: kPrimaryDark,
    ),
    iconTheme: const IconThemeData(color: kPrimary),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kPrimary,
      foregroundColor: kOnPrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 16),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: kPrimary,
      side: const BorderSide(color: kPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 15),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurfaceContainerLow,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kOutlineVariant),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kOutlineVariant),
    ),
  ),
  dividerTheme: const DividerThemeData(color: kOutlineVariant, thickness: 1),
  checkboxTheme: CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return kPrimary;
      return Colors.transparent;
    }),
    side: const BorderSide(color: kPrimary, width: 2),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
  ),
);
