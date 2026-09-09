import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

/// Chip de filtro do app — construído do zero, SEM widget Chip.
///
/// Por que não usa FilterChip (sexta tentativa; não voltar atrás):
/// o FilterChip do Material resolve `labelStyle` como WidgetStateTextStyle e
/// depois faz merge com o estilo vindo do tema. Nesse merge a resolução por
/// estado se perde, e o texto do chip caía para branco sobre fundo branco —
/// exatamente o defeito que as cinco tentativas anteriores tentaram corrigir
/// mexendo em ChipThemeData, em `color`, em `labelStyle`. O problema não era
/// a configuração; era depender do Chip.
///
/// Aqui não há herança nenhuma: InkWell dentro de um Container, cor de fundo
/// e cor de texto explícitas em toda combinação de estado. Nada vem de
/// ChipThemeData, DefaultTextStyle ou TextTheme.
///
/// Estados:
///   • não selecionado → fundo branco, borda cinza visível, texto azul primary
///   • selecionado     → fundo primary, borda primary, texto branco
class AppFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  /// Contagem opcional exibida ao lado do rótulo, ex.: "Pendentes 4".
  final int? count;

  /// Cor do estado selecionado. O padrão é o primary; os filtros por
  /// situação (atrasada, pendente) usam a cor do próprio status.
  final Color? corSelecionado;

  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
    this.count,
    this.corSelecionado,
  });

  @override
  Widget build(BuildContext context) {
    final texto = count == null ? label : '$label  $count';
    final corAtiva = corSelecionado ?? AppColors.primary;
    final habilitado = onSelected != null;

    // Cores explícitas, uma por combinação. Nenhuma delas é nova na paleta.
    final Color fundo;
    final Color borda;
    final Color corTexto;
    if (!habilitado) {
      fundo = AppColors.background;
      borda = AppColors.border;
      corTexto = AppColors.textSecondary;
    } else if (selected) {
      fundo = corAtiva;
      borda = corAtiva;
      corTexto = Colors.white;
    } else {
      fundo = AppColors.surface;
      borda = AppColors.borderStrong;
      corTexto = AppColors.primary700;
    }

    const raio = BorderRadius.all(Radius.circular(999));

    return Material(
      color: fundo,
      borderRadius: raio,
      child: InkWell(
        borderRadius: raio,
        onTap: habilitado ? () => onSelected!(!selected) : null,
        child: Ink(
          decoration: BoxDecoration(
            color: fundo,
            borderRadius: raio,
            border: Border.all(color: borda, width: 0.8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              texto,
              // Estilo completo e absoluto: sem herdar, não há merge que
              // possa sobrescrever a cor.
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: corTexto,
                height: 1.2,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
