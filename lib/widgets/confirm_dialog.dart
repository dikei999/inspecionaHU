import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

/// Confirmação padronizada para ações destrutivas ou difíceis de desfazer
/// (bloco 2). Antes cada tela escrevia o próprio AlertDialog, com títulos e
/// botões diferentes para a mesma ação — e algumas simplesmente não pediam
/// confirmação.
///
/// Regra: toda ação que desativa, apaga, arquiva ou desloga passa por aqui.
/// [destructive] pinta o botão de confirmação com a cor de não conformidade;
/// use false para ações reversíveis e neutras (reativar, desarquivar).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  String cancelLabel = 'Cancelar',
  bool destructive = true,
  IconData? icon,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: icon != null
          ? Icon(icon,
              color: destructive ? AppColors.nonCompliant : AppColors.primary)
          : null,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          style: destructive
              ? ElevatedButton.styleFrom(
                  backgroundColor: AppColors.nonCompliant,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Confirmação de logout — usada em TODAS as telas que oferecem "Sair".
///
/// Sair não é trivial neste app: derruba a sessão persistida, que é
/// justamente o que permite trabalhar offline (bloco 6). Um toque acidental
/// no ícone da AppBar em campo, sem internet, deixaria o Inspetor sem
/// conseguir voltar a entrar.
Future<bool> confirmSignOut(BuildContext context) => confirmAction(
      context,
      title: 'Sair da conta?',
      message: 'Será necessário conexão com a internet para entrar '
          'novamente. As respostas ainda não enviadas continuam salvas '
          'neste aparelho.',
      confirmLabel: 'Sair',
      icon: Icons.logout,
    );

/// SnackBar padronizado de resultado de ação (bloco 2): toda ação dá
/// retorno visível, com a cor certa para sucesso e erro.
void showActionFeedback(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
      behavior: SnackBarBehavior.floating,
    ));
}
