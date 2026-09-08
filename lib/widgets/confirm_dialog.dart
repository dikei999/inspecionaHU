import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/services/offline_sync_service.dart';
import '../features/auth/providers/auth_provider.dart';

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
Future<bool> confirmSignOut(BuildContext context) async {
  // Sair NÃO apaga mais o perfil em cache nem os checklists baixados: eles
  // ficam para que "Continuar offline" funcione depois do logout. O que a
  // saída faz é bloquear a entrada automática — reabrir o app cai no login.
  //
  // A limpeza acontece quando OUTRO usuário entra com senha no aparelho.
  final p = await AuthProvider.pendenciasAntesDeSair();
  final semRede = !OfflineSyncService.online.value;
  if (!context.mounted) return false;

  final partes = <String>[];

  if (p.naFila > 0) {
    partes.add('${p.naFila} resposta(s) ainda não enviada(s) continuam '
        'guardadas neste aparelho e serão enviadas no próximo acesso com '
        'internet.');
  }
  if (p.temCache) {
    partes.add('Para entrar de novo será preciso a senha. Sem internet, use '
        '"Continuar offline" na tela de login.');
  } else {
    partes.add('Será necessário conexão com a internet para entrar '
        'novamente.');
  }

  // Fila pendente e sem rede: sair agora adia o envio de trabalho já feito.
  // Não se perde nada, mas continua sendo melhor esperar.
  final arriscado = p.naFila > 0 && semRede;
  if (arriscado) {
    partes.add('Sem conexão no momento, não há como enviar antes de sair. '
        'O recomendado é aguardar a internet voltar.');
  }

  return confirmAction(
    context,
    title: arriscado ? 'Sair com envios pendentes?' : 'Sair da conta?',
    message: partes.join('\n\n'),
    confirmLabel: 'Sair',
    cancelLabel: arriscado ? 'Aguardar conexão' : 'Cancelar',
    icon: arriscado ? Icons.warning_amber_rounded : Icons.logout,
    destructive: arriscado,
  );
}

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
