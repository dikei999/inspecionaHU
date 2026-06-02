import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Identidade visual (seção 11 do CLAUDE.md)
  static const Color primary = Color(0xFF1A56DB);
  static const Color compliant = Color(0xFF16A34A);
  static const Color nonCompliant = Color(0xFFDC2626);
  static const Color pending = Color(0xFFD97706);
  static const Color background = Color(0xFFF3F4F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE5E7EB);

  // Texto
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textDisabled = Color(0xFF9CA3AF);

  // Status de tarefas
  static const Color statusPending = pending;
  static const Color statusInProgress = primary;
  static const Color statusSubmitted = compliant;
  static const Color statusValidated = Color(0xFF059669);
  static const Color statusOverdue = nonCompliant;

  // NC Crítica
  static const Color criticalNc = nonCompliant;
}
