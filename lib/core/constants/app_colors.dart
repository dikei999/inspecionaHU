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

  // Escala tonal do primary (para superfícies, hovers e gradientes)
  static const Color primary50 = Color(0xFFEFF4FE);
  static const Color primary100 = Color(0xFFDBE6FD);
  static const Color primary200 = Color(0xFFBFD3FA);
  static const Color primary600 = Color(0xFF1548B8);
  static const Color primary700 = Color(0xFF113A95);
  static const Color primary800 = Color(0xFF0E2F78);
  static const Color primary900 = Color(0xFF0B2560);

  // Escalas tonais dos semânticos (fundos suaves)
  static const Color compliant50 = Color(0xFFF0FDF4);
  static const Color compliant100 = Color(0xFFDCFCE7);
  static const Color nonCompliant50 = Color(0xFFFEF2F2);
  static const Color nonCompliant100 = Color(0xFFFEE2E2);
  static const Color pending50 = Color(0xFFFFFBEB);
  static const Color pending100 = Color(0xFFFEF3C7);

  // Superfícies elevadas / neutros
  static const Color surfaceSubtle = Color(0xFFF9FAFB);
  static const Color borderStrong = Color(0xFFD1D5DB);

  // Texto
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textDisabled = Color(0xFF9CA3AF);

  // Status de tarefas
  // Enviado e Validado usam verdes distintos para diferenciar no calendario.
  static const Color sentLight = Color(0xFF22C55E); // enviado — verde claro
  static const Color validatedDark = Color(0xFF15803D); // validado — verde escuro

  static const Color statusPending = pending;
  static const Color statusInProgress = primary;
  static const Color statusSubmitted = sentLight;
  static const Color statusValidated = validatedDark;
  static const Color statusOverdue = nonCompliant;

  // NC Crítica
  static const Color criticalNc = nonCompliant;

  // Gradiente institucional (login hero, cabeçalhos)
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary700, primary, Color(0xFF2563EB)],
  );

  static const LinearGradient subtleCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [surface, surfaceSubtle],
  );
}

/// Sombras suaves padronizadas — usar no lugar de elevation do Material.
class AppShadows {
  AppShadows._();

  /// Card em repouso: quase imperceptível, só descola do fundo.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0A101828),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x060F1728),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// Card em destaque (hero, métricas principais).
  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x14101828),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x08101828),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Sombra colorida para botões/CTAs sobre fundo claro.
  static List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.28),
      blurRadius: 14,
      offset: const Offset(0, 6),
    ),
  ];
}
