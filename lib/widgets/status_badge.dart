import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// Badge de status unificado para tarefas e inspeções.
/// Aceita os status internos em inglês e renderiza rótulos em português.
class StatusBadge extends StatelessWidget {
  final String status;
  final bool compact;

  const StatusBadge({super.key, required this.status, this.compact = false});

  static const _config = <String, (String, Color, IconData)>{
    'pending': ('Pendente', AppColors.pending, Icons.schedule_outlined),
    'in_progress': ('Em andamento', AppColors.primary, Icons.pending_outlined),
    'draft': ('Rascunho', AppColors.pending, Icons.edit_note_outlined),
    'submitted': ('Enviado', AppColors.statusSubmitted, Icons.send_outlined),
    'validated':
        ('Validado', AppColors.statusValidated, Icons.verified_outlined),
    'overdue': ('Atrasada', AppColors.statusOverdue, Icons.warning_amber_rounded),
    'active': ('Ativo', AppColors.compliant, Icons.check_circle_outline),
    'inactive': ('Inativo', AppColors.textSecondary, Icons.block_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _config[status] ??
        (status, AppColors.textSecondary, Icons.help_outline);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge para respostas C / NC / NA.
class ResponseBadge extends StatelessWidget {
  final String? status; // 'C' | 'NC' | 'NA' | null

  const ResponseBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'C' => ('Conforme', AppColors.compliant),
      'NC' => ('Não Conforme', AppColors.nonCompliant),
      'NA' => ('Não se aplica', AppColors.textSecondary),
      _ => ('Não respondido', AppColors.textDisabled),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
