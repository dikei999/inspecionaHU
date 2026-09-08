import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/app/theme.dart';
import 'package:inspecionahu/core/constants/app_colors.dart';

/// Item 4 — o chip não selecionado ficava branco sobre branco e sumia.
/// O teste trava o contraste no tema, que é a fonte única para todo o app.
void main() {
  final tema = AppTheme.lightTheme;
  final chip = tema.chipTheme;

  test('chip não selecionado tem fundo distinto do branco do card', () {
    expect(chip.backgroundColor, isNotNull,
        reason: 'sem cor de fundo o chip some sobre o card branco');
    expect(chip.backgroundColor, isNot(AppColors.surface));
    expect(chip.backgroundColor, isNot(Colors.white));
  });

  // No Material 3, FilterChip e ChoiceChip IGNORAM backgroundColor e
  // selectedColor: quem vale e a propriedade `color`. Sem ela o chip
  // continuava branco mesmo com backgroundColor definido — foi o que
  // aconteceu na primeira tentativa de correcao.
  test('color por estado esta definido (e o que o M3 usa de fato)', () {
    expect(chip.color, isNotNull,
        reason: 'sem `color` o FilterChip ignora o tema e fica branco');
    expect(chip.color!.resolve(<WidgetState>{}), AppColors.surfaceSubtle);
    expect(chip.color!.resolve({WidgetState.selected}), AppColors.primary);
  });

  test('chip não selecionado tem borda visível', () {
    final lado = chip.side as WidgetStateBorderSide;
    final borda = lado.resolve(<WidgetState>{})!;
    expect(borda.width, greaterThan(0),
        reason: 'BorderSide.none fazia o chip sumir sobre o card branco');
    expect(borda.color, isNot(Colors.transparent));
  });

  test('chip selecionado usa o azul primary', () {
    expect(chip.selectedColor, AppColors.primary);
  });

  test('texto do chip selecionado é branco, do não selecionado é escuro', () {
    // labelStyle e declarado como TextStyle, mas o tema fornece um
    // WidgetStateTextStyle — resolver exige o cast.
    final estilo = chip.labelStyle as WidgetStateTextStyle;
    final selecionado = estilo.resolve({WidgetState.selected}).color;
    final normal = estilo.resolve(<WidgetState>{}).color;

    expect(selecionado, Colors.white,
        reason: 'texto escuro sobre o azul primary ficaria ilegível');
    expect(normal, AppColors.textPrimary);
    expect(normal, isNot(Colors.white));
  });

  test('cores de status seguem intocadas pelo ajuste do chip', () {
    expect(AppColors.compliant, const Color(0xFF16A34A));
    expect(AppColors.nonCompliant, const Color(0xFFDC2626));
    expect(AppColors.pending, const Color(0xFFD97706));
    expect(AppColors.primary, const Color(0xFF00448E));
  });
}
