import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/nr32_clauses.dart';

/// Chip com a referência NR-32 de um item de checklist.
///
/// Quando a cláusula existe em [nr32Clauses], o chip é tocável e abre um
/// bottom sheet com o número, o texto integral da norma e a indicação de
/// criticidade ([showNr32ClauseSheet]). Referência sem cláusula no mapa:
/// o chip continua exibido, mas não é tocável.
class Nr32ClauseChip extends StatelessWidget {
  final String reference;
  final bool isCritical;

  const Nr32ClauseChip({
    super.key,
    required this.reference,
    this.isCritical = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasClause = nr32Clauses.containsKey(reference);

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            reference,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (hasClause) ...[
            const SizedBox(width: 3),
            const Icon(Icons.menu_book_outlined,
                size: 11, color: AppColors.primary),
          ],
        ],
      ),
    );

    if (!hasClause) return chip;

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => showNr32ClauseSheet(
        context,
        reference: reference,
        isCritical: isCritical,
      ),
      child: chip,
    );
  }
}

/// Bottom sheet com o texto integral de uma cláusula da NR-32.
Future<void> showNr32ClauseSheet(
  BuildContext context, {
  required String reference,
  bool isCritical = false,
}) {
  final clauseText = nr32Clauses[reference];
  if (clauseText == null) return Future.value();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final maxHeight = MediaQuery.of(ctx).size.height * 0.75;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'NR-32 · $reference',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isCritical
                            ? AppColors.nonCompliant100
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isCritical ? 'ITEM CRÍTICO' : 'ITEM NORMAL',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: isCritical
                              ? AppColors.nonCompliant
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      clauseText,
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                            height: 1.5,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Texto integral da NR-32 — Segurança e Saúde no Trabalho '
                  'em Serviços de Saúde.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
