import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/services/offline_store.dart';
import '../core/services/offline_sync_service.dart';

/// Painel de pendências da fila de envio offline (item 1 da auditoria).
///
/// Aberto ao tocar na faixa de conexão. Mostra, por operação: o item
/// respondido, se tem foto, quantas tentativas já houve e — quando houver —
/// o motivo EXATO da última falha, do jeito que o servidor devolveu
/// (código + mensagem do Postgrest/Storage). Sem isso o erro só existia no
/// debugPrint do PC; em campo, no celular, a única informação era "5 envios
/// falharam", sem dizer por quê.
///
/// Tem um botão "Tentar enviar agora", que dispara uma rodada de sync
/// imediata sem esperar o heartbeat.
class PendingSyncSheet extends StatefulWidget {
  const PendingSyncSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PendingSyncSheet(),
    );
  }

  @override
  State<PendingSyncSheet> createState() => _PendingSyncSheetState();
}

class _PendingSyncSheetState extends State<PendingSyncSheet> {
  List<Map<String, dynamic>> _fila = [];
  bool _carregando = true;
  bool _tentandoAgora = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final fila = await OfflineStore.loadQueue();
    if (!mounted) return;
    setState(() {
      _fila = fila;
      _carregando = false;
    });
  }

  Future<void> _tentarAgora() async {
    setState(() => _tentandoAgora = true);
    await OfflineSyncService.syncPending();
    if (!mounted) return;
    await _carregar();
    if (!mounted) return;
    setState(() => _tentandoAgora = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Envios pendentes',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _carregando
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _fila.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_done_outlined,
                            size: 40,
                            color: AppColors.compliant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nada pendente. Tudo enviado.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _fila.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _linhaPendencia(_fila[i]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_fila.isEmpty || _tentandoAgora)
                      ? null
                      : _tentarAgora,
                  icon: _tentandoAgora
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 18),
                  label: Text(
                    _tentandoAgora ? 'Enviando…' : 'Tentar enviar agora',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaPendencia(Map<String, dynamic> op) {
    final payload = Map<String, dynamic>.from(
      (op['payload'] as Map?) ?? const {},
    );
    final status = payload['status'] as String?;
    final observacao = payload['observation'] as String?;
    final temFoto = op['photo_local_path'] != null;
    final tentativas = (op['attempts'] as int?) ?? 0;
    final codigo = op['last_error_code'] as String?;
    final mensagem = op['last_error_message'] as String?;
    final detalhe = op['last_error_detail'] as String?;
    final etapa = op['last_error_stage'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusChip(status),
              const SizedBox(width: 8),
              if (temFoto)
                const Icon(
                  Icons.photo_camera_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              const Spacer(),
              if (tentativas > 0)
                Text(
                  '$tentativas tentativa(s)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDisabled,
                  ),
                ),
            ],
          ),
          if (observacao != null && observacao.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              observacao,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (mensagem != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.nonCompliant50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.nonCompliant100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    etapa == 'foto'
                        ? 'Falha ao enviar a foto'
                        : 'Falha ao gravar a resposta',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.nonCompliant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    codigo != null ? '[$codigo] $mensagem' : mensagem,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.nonCompliant,
                    ),
                  ),
                  if (detalhe != null && detalhe.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: SelectableText(
                        detalhe,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String? status) {
    final Color cor;
    final String texto;
    switch (status) {
      case 'C':
        cor = AppColors.compliant;
        texto = 'Conforme';
        break;
      case 'NC':
        cor = AppColors.nonCompliant;
        texto = 'Não conforme';
        break;
      case 'NA':
        cor = AppColors.textSecondary;
        texto = 'N/A';
        break;
      default:
        cor = AppColors.textDisabled;
        texto = 'Sem status';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cor),
      ),
    );
  }
}
