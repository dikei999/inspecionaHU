import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/services/offline_sync_service.dart';
import 'pending_sync_sheet.dart';

/// Faixa fina e global de status de conexão (6.5).
///
/// Só aparece quando há algo a dizer: sem conexão, ou com pendência na fila,
/// ou logo após uma rodada de envio. Estando online e com a fila vazia, ela
/// não ocupa um pixel — o fluxo online continua exatamente como era (6.6).
///
/// Usa o connectivity_plus que já estava no projeto, via OfflineSyncService.
class ConnectionBanner extends StatelessWidget {
  final Widget child;

  const ConnectionBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: ValueListenableBuilder<bool>(
            valueListenable: OfflineSyncService.online,
            builder: (context, online, _) {
              return ValueListenableBuilder<int>(
                valueListenable: OfflineSyncService.pendingCount,
                builder: (context, pendentes, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: OfflineSyncService.syncing,
                    builder: (context, enviando, _) {
                      return ValueListenableBuilder<SyncResult?>(
                        valueListenable: OfflineSyncService.lastResult,
                        builder: (context, resultado, _) {
                          return _faixa(
                            context,
                            online,
                            pendentes,
                            enviando,
                            resultado,
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _faixa(
    BuildContext context,
    bool online,
    int pendentes,
    bool enviando,
    SyncResult? resultado,
  ) {
    // Offline: o que mais importa saber.
    if (!online) {
      return _Faixa(
        cor: AppColors.pending100,
        corTexto: AppColors.pending,
        icone: Icons.wifi_off,
        texto: pendentes > 0
            ? 'Sem conexão · $pendentes ${_plural(pendentes)} na fila'
            : 'Sem conexão · trabalhando offline',
        // Tocável mesmo offline: o painel lê a fila do disco, não precisa
        // de rede — dá pra ver o que está pendente antes de reconectar.
        onTap: pendentes > 0 ? () => PendingSyncSheet.show(context) : null,
      );
    }

    // Online e com envio REALMENTE em curso. Ter fila parada não é enviar:
    // dizer "Enviando" com a fila estacionada é informação falsa (A1).
    if (enviando && pendentes > 0) {
      return _Faixa(
        cor: AppColors.primary50,
        corTexto: AppColors.primary,
        icone: Icons.sync,
        texto: 'Enviando · $pendentes ${_plural(pendentes)}',
        onTap: () => PendingSyncSheet.show(context),
      );
    }

    // Online, com fila, sem envio em curso: só informa que falta enviar.
    if (pendentes > 0) {
      return _Faixa(
        cor: AppColors.pending100,
        corTexto: AppColors.pending,
        icone: Icons.cloud_upload_outlined,
        texto: '$pendentes ${_plural(pendentes)} aguardando envio',
        onTap: () => PendingSyncSheet.show(context),
      );
    }

    // Fila zerada logo após um envio: confirma o resultado e some.
    if (resultado != null &&
        resultado.enviadas > 0 &&
        resultado.falharam == 0) {
      return _Faixa(
        cor: AppColors.compliant100,
        corTexto: AppColors.compliant,
        icone: Icons.cloud_done_outlined,
        texto:
            '${resultado.enviadas} ${_plural(resultado.enviadas)} enviada(s)',
      );
    }

    // Item 1.b: falha exposta na faixa com atalho direto pro motivo — antes
    // dizia só "tentando de novo" e não sumia, sem forma de ver o porquê
    // sem o PC. Tocar aqui abre o painel com o erro exato de cada uma.
    if (resultado != null && resultado.falharam > 0) {
      return _Faixa(
        cor: AppColors.nonCompliant100,
        corTexto: AppColors.nonCompliant,
        icone: Icons.error_outline,
        texto: '${resultado.falharam} envio(s) falharam · toque para ver',
        onTap: () => PendingSyncSheet.show(context),
      );
    }

    // Online e sem pendência: nada na tela.
    return const SizedBox.shrink();
  }

  String _plural(int n) => n == 1 ? 'resposta' : 'respostas';
}

class _Faixa extends StatelessWidget {
  final Color cor;
  final Color corTexto;
  final IconData icone;
  final String texto;

  /// Quando presente, a faixa vira tocável — item 1.b: painel com o
  /// motivo exato de cada pendência, sem precisar do PC.
  final VoidCallback? onTap;

  const _Faixa({
    required this.cor,
    required this.corTexto,
    required this.icone,
    required this.texto,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cor,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icone, size: 13, color: corTexto),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    texto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: corTexto,
                    ),
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 14, color: corTexto),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
