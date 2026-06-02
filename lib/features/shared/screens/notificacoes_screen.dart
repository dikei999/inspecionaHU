import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class NotificacoesScreen extends StatelessWidget {
  const NotificacoesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notificações')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 64, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text('Nenhuma notificação'),
          ],
        ),
      ),
    );
  }
}
