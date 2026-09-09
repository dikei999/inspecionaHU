import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/app/theme.dart';
import 'package:inspecionahu/core/constants/app_colors.dart';
import 'package:inspecionahu/widgets/app_filter_chip.dart';
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

  group('A. Chip de filtro do app', () {
    // Este grupo lia o ChipTheme com ChipTheme.of(context) e passava mesmo
    // com o app mostrando texto branco sobre branco: media a configuração,
    // não o pixel. Agora mede o AppFilterChip renderizado, que é o único
    // chip de filtro do app e não usa widget Chip.
    ({Color fundo, Color texto, BorderSide borda}) pintado(WidgetTester t) {
      final texto = t.widget<Text>(find.byType(Text));
      final deco = (t.widget<Ink>(find.byType(Ink)).decoration!) as BoxDecoration;
      return (
        fundo: deco.color!,
        texto: texto.style!.color!,
        borda: deco.border!.top,
      );
    }

    testWidgets('não selecionado tem fundo e borda distintos do card',
        (t) async {
      await montar(
        t,
        AppFilterChip(label: 'Seg', selected: false, onSelected: (_) {}),
      );
      final e = pintado(t);
      expect(e.borda.width, greaterThan(0));
      expect(e.borda.color, isNot(Colors.transparent));
      expect(
        contraste(e.borda.color, AppColors.surface),
        greaterThan(1.2),
        reason: 'borda precisa se distinguir do card branco',
      );
    });

    testWidgets('não selecionado: texto escuro legível', (t) async {
      await montar(
        t,
        AppFilterChip(label: 'Todos', selected: false, onSelected: (_) {}),
      );
      final e = pintado(t);
      expect(e.texto, isNot(Colors.white));
      expect(contraste(e.texto, e.fundo), greaterThan(4.5));
    });

    testWidgets('selecionado: primary com texto branco legível', (t) async {
      await montar(
        t,
        AppFilterChip(label: 'Todos', selected: true, onSelected: (_) {}),
      );
      final e = pintado(t);
      expect(e.fundo, AppColors.primary);
      expect(e.texto, Colors.white);
      expect(contraste(e.texto, e.fundo), greaterThan(4.5));
    });

    testWidgets('nenhum chip do Material sobrou na árvore', (t) async {
      await montar(
        t,
        AppFilterChip(label: 'Todos', selected: false, onSelected: (_) {}),
      );
      expect(find.byType(RawChip), findsNothing);
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
