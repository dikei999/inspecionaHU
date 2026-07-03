import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../app/routes.dart';
import '../core/constants/app_colors.dart';
import '../core/services/notification_service.dart';

/// Sino de notificações com badge reativo de não-lidas.
/// Usar nas actions do AppBar de todas as telas principais.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationProvider>().unreadCount;

    return IconButton(
      tooltip: 'Notificações',
      onPressed: () => context.push(AppRoutes.notificacoes),
      icon: Badge.count(
        count: unread,
        isLabelVisible: unread > 0,
        backgroundColor: AppColors.nonCompliant,
        textColor: Colors.white,
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
