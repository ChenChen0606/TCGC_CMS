// ─────────────────────────────────────────────────────────────────────────────
//  app_colors.dart
//  Single source of truth for the whole app palette.
//  Every screen imports this file instead of scattering raw Color(...) values,
//  so the theme stays consistent and easy to retune in one place.
// ─────────────────────────────────────────────────────────────────────────────
//
//  The palette is a Teal (Material 3 seed) + Slate neutral system. Verify a
//  change against login_screen, clinic_dashboard_screen and
//  individual_record_screen before committing new values.
//
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── PRIMARY (teal) ─────────────────────────────────────────────────────
  static const Color primary = Color(0xFF0D9488); // teal-600
  static const Color primaryDark = Color(0xFF0F766E); // teal-700
  static const Color primaryDeep = Color(0xFF134E4A); // teal-900
  static const Color primaryContainer = Color(0xFFCCFBF1); // teal-100
  static const Color onPrimaryContainer = Color(0xFF134E4A); // teal-900

  static const Color secondary = Color(0xFF14B8A6); // teal-500
  static const Color secondaryContainer = Color(0xFF99F6E4); // teal-200

  // ── NEUTRALS ───────────────────────────────────────────────────────────
  static const Color surface = Color(0xFFFFFFFF);
  static const Color bg = Color(0xFFF8FAFC); // slate-50
  static const Color bgAlt = Color(0xFFF1F5F9); // slate-100

  static const Color textMain = Color(0xFF1E293B); // slate-800
  static const Color textDark = Color(0xFF0F172A); // slate-900
  static const Color textSub = Color(0xFF64748B); // slate-500
  static const Color textMuted = Color(0xFF94A3B8); // slate-400

  static const Color border = Color(0xFFE2E8F0); // slate-200
  static const Color borderStrong = Color(0xFFCBD5E1); // slate-300

  static const Color fieldFill = Color(0xFFFAFCFE); // enabled input fill
  static const Color fieldFillDisabled =
      Color(0xFFF1F5F9); // read-only input fill

  // ── SEMANTIC ───────────────────────────────────────────────────────────
  static const Color danger = Color(0xFFDC2626); // red-600
  static const Color dangerContainer = Color(0xFFFEE2E2); // red-100
  static const Color success = Color(0xFF16A34A); // green-600
  static const Color successContainer = Color(0xFFDCFCE7); // green-100
  static const Color warning = Color(0xFFF59E0B); // amber-500
  static const Color info = Color(0xFF3B82F6); // blue-500

  // ── CATEGORY ACCENTS (Student / Faculty / Staff) ───────────────────────
  static const Color student = Color(0xFF2563EB); // blue-600
  static const Color faculty = Color(0xFFD97706); // amber-600
  static const Color staff = Color(0xFF7C3AED); // violet-600

  // ── SHADOWS ────────────────────────────────────────────────────────────
  static const Color shadowCard = Color(0x26000000); // ~15% black
  static const Color shadowStrong = Color(0x33000000); // ~20% black
}
