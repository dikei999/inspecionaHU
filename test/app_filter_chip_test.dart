import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/app/theme.dart';
import 'package:inspecionahu/core/constants/app_colors.dart';
import 'package:inspecionahu/widgets/app_filter_chip.dart';

/// A2 — contraste do chip medido no que é PINTADO.
///
/// A versão anterior deste teste lia `chip.color.resolve(...)` e
/// `chip.labelStyle.resolve(...)` do FilterChip, ou seja, a configuração
/// entregue ao widget. Ela passava enquanto o app mostrava texto branco
/// sobre fundo branco, porque o FilterChip refazia o merge do labelStyle
/// depois — o teste media a intenção, não o resultado.
///
/// Agora o AppFilterChip não usa Chip nenhum, e o teste lê o TextStyle
/// efetivo do Text renderizado e a decoração efetiva do Ink. É o que o olho
/// vê na tela.
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

  /// Lê o que foi de fato renderizado: cor do texto, fundo e borda.
  ({Color fundo, Color texto, BorderSide borda}) pintado(WidgetTester t) {
    final texto = t.widget<Text>(find.byType(Text));
    final ink = t.widget<Ink>(find.byType(Ink));
    final deco = ink.decoration! as BoxDecoration;
    return (
      fundo: deco.color!,
      texto: texto.style!.color!,
      borda: deco.border!.top,
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
    testWidgets('texto NÃO é branco — a regressão histórica', (t) async {
      await montar(
        t,
        AppFilterChip(label: 'Pendente', selected: false, onSelected: (_) {}),
      );
      final e = pintado(t);

      expect(e.texto, isNot(Colors.white));
      expect(e.texto, AppColors.primary700);
      expect(
        contraste(e.texto, e.fundo),
        greaterThan(7.0),
        reason: 'texto do chip precisa ser confortável de ler (AAA)',
      );
    });

    testWidgets('borda separa o chip do card branco', (t) async {
      await montar(
        t,
        AppFilterChip(label: 'Pendente', selected: false, onSelected: (_) {}),
      );
      final e = pintado(t);

      expect(e.borda.width, greaterThan(0));
      expect(e.borda.color, AppColors.borderStrong);
      expect(contraste(e.borda.color, AppColors.surface), greaterThan(1.3));
    });
  });

  group('selecionado', () {
    testWidgets('fundo primary com texto branco', (t) async {
      await montar(
        t,
        AppFilterChip(label: 'Pendente', selected: true, onSelected: (_) {}),
      );
      final e = pintado(t);

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
        ),
      );
      final e = pintado(t);

      expect(e.fundo, AppColors.nonCompliant);
      expect(contraste(e.texto, e.fundo), greaterThan(4.5));
    });
  });

  group('independência do tema', () {
    testWidgets('um chipTheme hostil não muda o chip', (t) async {
      // Prova de que nada vem do tema: um ChipThemeData que pintaria tudo
      // de branco sobre branco não altera uma vírgula do que é renderizado.
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme.copyWith(
          chipTheme: const ChipThemeData(
            backgroundColor: Colors.white,
            labelStyle: TextStyle(color: Colors.white),
            side: BorderSide.none,
          ),
        ),
        home: Scaffold(
          backgroundColor: AppColors.surface,
          body: Center(
            child: AppFilterChip(
              label: 'Pendente',
              selected: false,
              onSelected: (_) {},
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      final e = pintado(t);

      expect(e.texto, AppColors.primary700);
      expect(e.borda.width, greaterThan(0));
      expect(contraste(e.texto, e.fundo), greaterThan(7.0));
    });

    testWidgets('não existe widget Chip na árvore', (t) async {
      await montar(
        t,
        AppFilterChip(label: 'Pendente', selected: false, onSelected: (_) {}),
      );
      expect(find.byType(FilterChip), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(RawChip), findsNothing);
    });
  });

  group('interação', () {
    testWidgets('toque alterna a seleção', (t) async {
      bool? recebido;
      await montar(
        t,
        AppFilterChip(
          label: 'Pendente',
          selected: false,
          onSelected: (v) => recebido = v,
        ),
      );
      await t.tap(find.text('Pendente'));
      expect(recebido, isTrue);
    });

    testWidgets('sem callback o chip não é tocável', (t) async {
      await montar(
        t,
        const AppFilterChip(label: 'Pendente', selected: false),
      );
      expect(t.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
    });
  });

  group('contagem', () {
    testWidgets('aparece junto do rótulo', (t) async {
      await montar(
        t,
        AppFilterChip(
          label: 'Pendentes',
          selected: false,
          count: 4,
          onSelected: (_) {},
        ),
      );
      expect(find.textContaining('Pendentes'), findsOneWidget);
      expect(find.textContaining('4'), findsOneWidget);
    });
  });
}
