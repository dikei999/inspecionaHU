import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/app/theme.dart';
import 'package:inspecionahu/core/constants/app_colors.dart';
import 'package:inspecionahu/widgets/status_badge.dart';

/// Item 5 — auditoria de CONTRASTE componente por componente.
///
/// Não confia no tema: monta cada componente de verdade e lê a cor
/// efetivamente resolvida. Fundo igual ao branco do card = some na tela.
void main() {
  final tema = AppTheme.lightTheme;

  double lum(Color c) {
    double canal(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
    return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
  }

  double contraste(Color a, Color b) {
    final la = lum(a), lb = lum(b);
    final hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  Future<BuildContext> montar(WidgetTester t, Widget w) async {
    await t.pumpWidget(MaterialApp(
      theme: tema,
      home: Scaffold(
          backgroundColor: AppColors.surface, body: Center(child: w)),
    ));
    await t.pumpAndSettle();
    return t.element(find.byType(Scaffold));
  }

  group('A. Chips do Material', () {
    testWidgets('FilterChip não selecionado tem fundo visível', (t) async {
      final ctx = await montar(
          t,
          FilterChip(
              label: const Text('Seg'), selected: false, onSelected: (_) {}));
      final fundo = ChipTheme.of(ctx).color!.resolve(<WidgetState>{})!;
      expect(fundo, isNot(Colors.white));
      expect(fundo, isNot(AppColors.surface));
      expect(fundo, AppColors.surfaceSubtle);
    });

    testWidgets('ChoiceChip não selecionado tem fundo visível', (t) async {
      final ctx = await montar(
          t,
          ChoiceChip(
              label: const Text('Todos'), selected: false, onSelected: (_) {}));
      final fundo = ChipTheme.of(ctx).color!.resolve(<WidgetState>{})!;
      expect(fundo, AppColors.surfaceSubtle);
    });

    testWidgets('borda visível no estado não selecionado', (t) async {
      final ctx = await montar(
          t,
          ChoiceChip(
              label: const Text('Todos'), selected: false, onSelected: (_) {}));
      final lado = ChipTheme.of(ctx).side as WidgetStateBorderSide;
      final borda = lado.resolve(<WidgetState>{})!;
      expect(borda.width, greaterThan(0));
      expect(borda.color, isNot(Colors.transparent));
      expect(contraste(borda.color, AppColors.surface), greaterThan(1.2),
          reason: 'borda precisa se distinguir do card branco');
    });

    testWidgets('selecionado: primary com texto branco legível', (t) async {
      final ctx = await montar(
          t,
          ChoiceChip(
              label: const Text('Todos'), selected: true, onSelected: (_) {}));
      final ct = ChipTheme.of(ctx);
      expect(ct.color!.resolve({WidgetState.selected}), AppColors.primary);
      final estilo = ct.labelStyle as WidgetStateTextStyle;
      expect(estilo.resolve({WidgetState.selected}).color, Colors.white);
      expect(contraste(Colors.white, AppColors.primary), greaterThan(4.5));
    });

    testWidgets('não selecionado: texto escuro legível', (t) async {
      final ctx = await montar(
          t,
          ChoiceChip(
              label: const Text('Todos'), selected: false, onSelected: (_) {}));
      final estilo = ChipTheme.of(ctx).labelStyle as WidgetStateTextStyle;
      final cor = estilo.resolve(<WidgetState>{}).color!;
      expect(cor, AppColors.textPrimary);
      expect(contraste(cor, AppColors.surfaceSubtle), greaterThan(4.5));
    });
  });

  group('B. StatusBadge — etiqueta de status', () {
    for (final status in [
      'pending',
      'in_progress',
      'draft',
      'submitted',
      'validated',
      'overdue',
      'cancelled',
      'active',
      'inactive',
    ]) {
      testWidgets('"$status" legível sobre o fundo do badge', (t) async {
        await montar(t, StatusBadge(status: status));
        final txt = t.widget<Text>(find.byType(Text));
        final cor = txt.style!.color!;
        // O badge pinta cor.withValues(alpha:0.1) sobre branco, então o
        // fundo efetivo é quase branco: o texto usa a cor cheia.
        expect(contraste(cor, AppColors.surface), greaterThan(2.5),
            reason: 'texto de "$status" apagado demais sobre o badge claro');
      });
    }
  });

  group('C. ResponseBadge — C / NC / NA', () {
    for (final s in ['C', 'NC', 'NA', 'outro']) {
      testWidgets('"$s" legível', (t) async {
        await montar(t, ResponseBadge(status: s));
        final txt = t.widget<Text>(find.byType(Text));
        expect(contraste(txt.style!.color!, AppColors.surface),
            greaterThan(2.5));
      });
    }
  });
}
