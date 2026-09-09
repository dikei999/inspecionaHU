import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

/// Chip de filtro/seleção do app — estilo definido AQUI, no widget.
///
/// Por que não no tema: o chipTheme do Material 3 já foi ajustado três
/// vezes e não alcançou todos os componentes. FilterChip e ChoiceChip
/// ignoram `backgroundColor`/`selectedColor` e nem sempre herdam `color`
/// como se espera, então o chip não selecionado continuava branco sobre
/// branco em algumas telas. Definindo tudo no próprio widget, com
/// WidgetStateProperty, não há herança para dar errado.
///
/// Estados:
///   • não selecionado → fundo cinza claro, borda visível, texto azul escuro
///   • selecionado     → fundo primary, texto branco
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

    return FilterChip(
      label: Text(texto),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,

      // Tudo explícito: nada aqui depende do ChipThemeData.
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return AppColors.background;
        return states.contains(WidgetState.selected)
            ? corAtiva
            : AppColors.surfaceSubtle;
      }),
      side: WidgetStateBorderSide.resolveWith((states) {
        return BorderSide(
          color: states.contains(WidgetState.selected)
              ? corAtiva
              : AppColors.borderStrong,
          width: 0.8,
        );
      }),
      labelStyle: WidgetStateTextStyle.resolveWith((states) {
        return TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.primary700,
        );
      }),
      backgroundColor: AppColors.surfaceSubtle,
      selectedColor: corAtiva,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
