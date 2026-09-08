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
  // O que existe no aparelho define o texto: sair APAGA o perfil em cache,
  // os checklists baixados e a fila de envio. A mensagem antiga dizia que as
  // respostas continuavam salvas, o que deixou de ser verdade.
  final p = await AuthProvider.pendenciasAntesDeSair();
  final semRede = !OfflineSyncService.online.value;
  if (!context.mounted) return false;

  final partes = <String>[];
  if (p.naFila > 0) {
    partes.add(
        '${p.naFila} resposta(s) na fila de envio serão PERDIDAS, pois ainda '
        'não chegaram ao servidor.');
  }
  if (p.baixados > 0) {
    partes.add('${p.baixados} checklist(s) baixado(s) para uso offline serão '
        'removidos do aparelho.');
  }
  if (p.temCache) {
    partes.add('O acesso offline será perdido: entrar de novo exigirá '
        'conexão com a internet.');
  }
  if (partes.isEmpty) {
    partes.add('Será necessário conexão com a internet para entrar '
        'novamente.');
  }

  // Fila pendente e sem rede é o pior caso: sair agora joga fora trabalho
  // que ainda dá para enviar. O diálogo desencoraja em vez de facilitar.
  final arriscado = p.naFila > 0 && semRede;
  if (arriscado) {
    partes.add('Sem conexão no momento, não há como enviar antes de sair. '
        'O recomendado é aguardar a internet voltar.');
  }

  return confirmAction(
    context,
    title: arriscado ? 'Sair e descartar a fila?' : 'Sair da conta?',
    message: partes.join('\n\n'),
    confirmLabel: arriscado ? 'Sair e descartar' : 'Sair',
    cancelLabel: arriscado ? 'Aguardar conexão' : 'Cancelar',
    icon: arriscado ? Icons.warning_amber_rounded : Icons.logout,
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
