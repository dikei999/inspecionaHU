import 'package:flutter/material.dart';
import '../../../core/constants/app_strings.dart';

/// Tela de resposta do checklist pelo Inspetor.
/// Regras críticas (seção 6):
/// - Câmera OBRIGATÓRIA — galeria BLOQUEADA
/// - NC exige observação (bloqueia envio se ausente)
/// - NC com requires_photo=true exige foto (bloqueia envio se ausente)
/// - Salvamento automático a cada resposta
/// - Botão "Salvar e sair" sempre visível
class RespostaChecklistScreen extends StatelessWidget {
  final String taskId;

  const RespostaChecklistScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Responder Checklist'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              AppStrings.saveAndExit,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Center(
        child: Text('Resposta do checklist (taskId: $taskId) — em desenvolvimento'),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: null, // habilitado somente quando todos os itens obrigatórios respondidos
          child: const Text(AppStrings.finishAndSend),
        ),
      ),
    );
  }
}
