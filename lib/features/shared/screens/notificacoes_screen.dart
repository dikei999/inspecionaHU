import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/notification_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/app_date_utils.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton_loader.dart';

class NotificacoesScreen extends StatelessWidget {
  const NotificacoesScreen({super.key});

  // ── Navegação contextual pelo tipo/reference_id ─────────────────────────────
  void _openNotification(BuildContext context, NotificationModel n) {
    context.read<NotificationProvider>().markAsRead(n.id);

    switch (n.type) {
      case 'task_due_soon':
      case 'task_overdue':
        // reference_id = task → abre direto a resposta do checklist
        if (n.referenceId != null) {
          context.push(AppRoutes.responderChecklist(n.referenceId!));
        } else {
          context.go(AppRoutes.inspectorDashboard);
        }
      case 'draft_reminder':
        // reference_id = inspection → o quadro lista a tarefa em andamento
        context.go(AppRoutes.inspectorDashboard);
      case 'report_validated':
        context.push(AppRoutes.inspectorHistorico);
      case 'access_request':
        context.push(AppRoutes.pedidosAcesso);
      case 'access_approved':
      case 'access_denied':
        context.push(AppRoutes.acessoCompartilhado);
      default:
        break; // tipo desconhecido: apenas marca como lida
    }
  }

  static IconData _iconFor(String type) => switch (type) {
        'task_due_soon' => Icons.schedule_outlined,
        'task_overdue' => Icons.warning_amber_rounded,
        'draft_reminder' => Icons.edit_note_outlined,
        'report_validated' => Icons.verified_outlined,
        'access_request' => Icons.approval_outlined,
        'access_approved' => Icons.check_circle_outline,
        'access_denied' => Icons.block_outlined,
        _ => Icons.notifications_outlined,
      };

  static Color _colorFor(String type) => switch (type) {
        'task_overdue' || 'access_denied' => AppColors.nonCompliant,
        'task_due_soon' || 'draft_reminder' => AppColors.pending,
        'report_validated' || 'access_approved' => AppColors.compliant,
        _ => AppColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final notifications = provider.notifications;
    final hasUnread = provider.unreadCount > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          if (hasUnread)
            TextButton.icon(
              onPressed: () =>
                  context.read<NotificationProvider>().markAllAsRead(),
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Marcar todas'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<NotificationProvider>().refresh(),
        child: provider.loading && notifications.isEmpty
            ? const SkeletonList(itemHeight: 78)
            : notifications.isEmpty
                ? const EmptyState(
                    icon: Icons.notifications_none,
                    title: 'Nenhuma notificação',
                    subtitle:
                        'Avisos de prazos, relatórios validados e pedidos de acesso aparecerão aqui.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: notifications.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _NotificationCard(
                      notification: notifications[i],
                      icon: _iconFor(notifications[i].type),
                      color: _colorFor(notifications[i].type),
                      onTap: () =>
                          _openNotification(ctx, notifications[i]),
                    ),
                  ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unread = !notification.read;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            // Não-lida: fundo azulado sutil + borda mais forte
            color: unread ? AppColors.primary50 : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: unread ? AppColors.primary100 : AppColors.border,
              width: unread ? 1.0 : 0.5,
            ),
            boxShadow: unread ? AppShadows.card : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (notification.body != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        notification.body!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      AppDateUtils.formatDateTime(
                          notification.createdAt.toLocal()),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.textDisabled),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
