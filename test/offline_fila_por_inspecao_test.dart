import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/services/offline_store.dart';
import 'package:inspecionahu/core/services/offline_sync_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake do path_provider: I/O real numa pasta temporária.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.raiz);
  final String raiz;

  @override
  Future<String?> getApplicationDocumentsPath() async => raiz;
}

/// A1 — "salvar offline É salvar".
///
/// O que se garante aqui é o que a tela de resposta passou a depender:
/// a fila em disco é a ÚNICA fonte do que foi respondido sem rede, ela
/// separa uma inspeção da outra, e reabrir um checklist encontra de volta
/// exatamente o que foi digitado. Antes existia também uma fila em memória
/// na tela; as duas drenavam a mesma inspeção sem se conhecer, e era daí
/// que vinha o risco de perder resposta ao alternar entre checklists.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('inspecionahu_fila_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    OfflineStore.resetParaTeste();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> responder(
    String inspecao,
    String item,
    String status, {
    String? observacao,
  }) =>
      OfflineSyncService.enqueueResponse(
        inspectionId: inspecao,
        checklistItemId: item,
        payload: {
          'inspection_id': inspecao,
          'checklist_item_id': item,
          'status': status,
          'observation': observacao,
        },
      );

  group('fila por inspeção', () {
    test('dois checklists respondidos offline não se misturam', () async {
      await responder('insp-A', 'item-1', 'compliant');
      await responder('insp-A', 'item-2', 'non_compliant',
          observacao: 'Sem tampa');
      await responder('insp-B', 'item-9', 'not_applicable');

      final a = await OfflineStore.queuedResponses('insp-A');
      final b = await OfflineStore.queuedResponses('insp-B');

      expect(a, hasLength(2));
      expect(b, hasLength(1));
      expect(
        a.map((op) => op['checklist_item_id']),
        containsAll(<String>['item-1', 'item-2']),
      );
      expect(b.single['checklist_item_id'], 'item-9');
    });

    test('responder o segundo checklist não apaga o primeiro', () async {
      await responder('insp-A', 'item-1', 'compliant');
      // Sai, abre o outro checklist, responde, volta.
      await responder('insp-B', 'item-9', 'compliant');
      await responder('insp-A', 'item-2', 'compliant');

      expect(await OfflineStore.queueLengthForInspection('insp-A'), 2);
      expect(await OfflineStore.queueLengthForInspection('insp-B'), 1);
      expect(await OfflineStore.queueLength(), 3);
    });

    test('reabrir traz de volta o que foi respondido, não o vazio', () async {
      await responder('insp-A', 'item-2', 'non_compliant',
          observacao: 'Coletor cheio');

      final fila = await OfflineStore.queuedResponses('insp-A');
      final payload = fila.single['payload'] as Map;

      expect(payload['status'], 'non_compliant');
      expect(payload['observation'], 'Coletor cheio');
    });

    test('reeditar o mesmo item guarda só a versão mais recente', () async {
      await responder('insp-A', 'item-1', 'compliant');
      await responder('insp-A', 'item-1', 'non_compliant',
          observacao: 'Reavaliado');

      final fila = await OfflineStore.queuedResponses('insp-A');
      expect(fila, hasLength(1), reason: 'id determinístico por item');
      expect((fila.single['payload'] as Map)['status'], 'non_compliant');
    });

    test('inspeção sem nada na fila devolve lista vazia, não erro', () async {
      expect(await OfflineStore.queuedResponses('insp-Z'), isEmpty);
      expect(await OfflineStore.queueLengthForInspection('insp-Z'), 0);
    });
  });
}
