import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/app/theme.dart';
import 'package:inspecionahu/core/constants/app_colors.dart';
import 'package:inspecionahu/widgets/app_filter_chip.dart';

/// Item 2 — contraste verificado no WIDGET renderizado, não no tema.
///
/// O estilo do AppFilterChip é definido no próprio widget justamente
/// porque o chipTheme não alcançava todos os componentes. Este teste monta
/// o widget e lê a cor que o Flutter realmente resolveu.
void main() {
  double lum(Color c) {
    double canal(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
    return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
  }

  double contraste(Color a, Color b) {
    final la = lum(a), lb = lum(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Lê o estilo efetivo do FilterChip interno, como o Flutter o resolveu.
  ({Color fundo, Color texto, BorderSide borda}) estiloDe(
      WidgetTester t, bool selecionado) {
    final chip = t.widget<FilterChip>(find.byType(FilterChip));
    final estados = selecionado ? {WidgetState.selected} : <WidgetState>{};
    return (
      fundo: chip.color!.resolve(estados)!,
      texto: (chip.labelStyle as WidgetStateTextStyle).resolve(estados).color!,
      borda: (chip.side as WidgetStateBorderSide).resolve(estados)!,
    );
  }

  Future<void> montar(WidgetTester t, Widget w) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        // Fundo BRANCO de propósito: é sobre ele que o chip sumia.
        backgroundColor: AppColors.surface,
        body: Center(child: w),
      ),
    ));
    await t.pumpAndSettle();
  }

  group('não selecionado não some no branco', () {
    testWidgets('fundo é cinza claro, distinto do card', (t) async {
      await montar(
          t,
          AppFilterChip(
              label: 'Pendente', selected: false, onSelected: (_) {}));
      final e = estiloDe(t, false);

      expect(e.fundo, isNot(Colors.white));
      expect(e.fundo, isNot(AppColors.surface));
      expect(e.fundo, AppColors.surfaceSubtle);
      expect(contraste(e.fundo, AppColors.surface), greaterThan(1.0));
    });

    testWidgets('borda visível', (t) async {
      await montar(
          t,
          AppFilterChip(
              label: 'Pendente', selected: false, onSelected: (_) {}));
      final e = estiloDe(t, false);

      expect(e.borda.width, greaterThan(0));
      expect(e.borda.color, AppColors.borderStrong);
      expect(contraste(e.borda.color, AppColors.surface), greaterThan(1.3));
    });

    testWidgets('texto azul escuro, bem legível', (t) async {
      await montar(
          t,
          AppFilterChip(
              label: 'Pendente', selected: false, onSelected: (_) {}));
      final e = estiloDe(t, false);

      expect(e.texto, AppColors.primary700);
      expect(contraste(e.texto, e.fundo), greaterThan(7.0),
          reason: 'texto do chip precisa ser confortável de ler');
    });
  });

  group('selecionado', () {
    testWidgets('fundo primary com texto branco', (t) async {
      await montar(
          t,
          AppFilterChip(
              label: 'Pendente', selected: true, onSelected: (_) {}));
      final e = estiloDe(t, true);

      expect(e.fundo, AppColors.primary);
      expect(e.texto, Colors.white);
      expect(contraste(e.texto, e.fundo), greaterThan(4.5));
    });

    testWidgets('cor do status é respeitada quando informada', (t) async {
      await montar(
          t,
          AppFilterChip(
            label: 'Atrasadas',
            selected: true,
            corSelecionado: AppColors.nonCompliant,
            onSelected: (_) {},
          ));
      final e = estiloDe(t, true);

      expect(e.fundo, AppColors.nonCompliant);
      expect(contraste(e.texto, e.fundo), greaterThan(4.5));
    });
  });

  group('contagem', () {
    testWidgets('aparece junto do rótulo', (t) async {
      await montar(
          t,
          AppFilterChip(
              label: 'Pendentes', selected: false, count: 4, onSelected: (_) {}));
      expect(find.textContaining('Pendentes'), findsOneWidget);
      expect(find.textContaining('4'), findsOneWidget);
    });
  });
}
