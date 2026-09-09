import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/services/data_source.dart';
import 'package:inspecionahu/core/services/offline_store.dart';
import 'package:inspecionahu/core/services/offline_sync_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.raiz);
  final String raiz;
  @override
  Future<String?> getApplicationDocumentsPath() async => raiz;
}

/// Item 1 — roteiro do fluxo do Inspetor em modo avião, passo a passo.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fluxo_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    OfflineStore.resetParaTeste();
    OfflineSyncService.online.value = true;
    DataSource.definirModoOffline(false);
  });

  tearDown(() async {
    OfflineSyncService.online.value = true;
    DataSource.definirModoOffline(false);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('fluxo completo em modo aviao', () async {
    // ── Preparo COM rede: baixar a tarefa ─────────────────────────────
    await OfflineStore.saveProfile('insp-1', {
      'id': 'insp-1',
      'full_name': 'Joao Silva',
      'role': 'inspector',
    });
    await OfflineStore.saveTaskBundle('task-1', {
      'task_id': 'task-1',
      'task': {
        'id': 'task-1',
        'checklist_id': 'cl-1',
        'sector_id': 'set-1',
        'hospital_id': 'h1',
        'inspector_id': 'insp-1',
        'assigned_by': 'dir-1',
        'due_date': DateTime.now().toIso8601String().substring(0, 10),
        'status': 'pending',
        'created_at': '2026-01-01T00:00:00.000',
      },
      'checklist': {'title': 'NR-32 UTI'},
      'sector_name': 'UTI Adulto',
      'items': [
        {
          'id': 'item-1',
          'checklist_id': 'cl-1',
          'order_index': 1,
          'description': 'Lavatorio exclusivo para higiene das maos',
          'criticality': 'alta',
          'requires_photo': true,
          'status': 'active',
          'created_at': '2026-01-01T00:00:00.000',
        },
      ],
      'inspection': {
        'id': 'insp-draft-1',
        'task_id': 'task-1',
        'checklist_id': 'cl-1',
        'sector_id': 'set-1',
        'hospital_id': 'h1',
        'inspector_id': 'insp-1',
        'overall_status': 'draft',
        'created_at': '2026-01-01T00:00:00.000',
      },
      'responses': [],
    });
    debugPrint('PREPARO (com rede): tarefa NR-32 UTI baixada');

    // ── 1. Entrar em modo offline ─────────────────────────────────────
    OfflineSyncService.online.value = false;
    DataSource.definirModoOffline(true);
    expect(DataSource.estaOffline, isTrue);
    debugPrint('PASSO 1 (modo aviao): DataSource.estaOffline = true');

    // ── 2. Painel do Inspetor ─────────────────────────────────────────
    final tarefas = await DataSource.tarefasLocais();
    debugPrint('PASSO 2 (painel): ${tarefas.length} tarefa(s) do local, '
        '${tarefas.first.checklistTitle} / ${tarefas.first.sectorName}');
    expect(tarefas.length, 1);
    expect(tarefas.first.checklistTitle, 'NR-32 UTI');

    // ── 3. Abrir a tarefa baixada ─────────────────────────────────────
    final pacote = await DataSource.pacoteDaTarefa('task-1');
    debugPrint('PASSO 3 (abrir tarefa): ${pacote!.itens.length} item(ns), '
        'inspecao draft = ${pacote.inspecao?.id}');
    expect(pacote.inspecao, isNotNull,
        reason: 'sem inspecao no pacote nao da para responder offline');
    expect(await DataSource.podeResponderOffline('task-1'), isTrue);

    // ── 4. Responder um item COM foto ─────────────────────────────────
    final foto = File('${tmp.path}/foto_teste.jpg');
    await foto.writeAsBytes(List.filled(1024, 7));
    final destino = await OfflineStore.persistPhoto(foto, 'foto-1.jpg');
    expect(destino, isNotNull);

    await OfflineSyncService.enqueueResponse(
      inspectionId: 'insp-draft-1',
      checklistItemId: 'item-1',
      payload: {
        'inspection_id': 'insp-draft-1',
        'checklist_item_id': 'item-1',
        'status': 'NC',
        'observation': 'Sem sabonete liquido',
      },
      photoLocalPath: destino,
      photoStoragePath: 'h1/insp-draft-1/foto-1.jpg',
    );
    var fila = await OfflineStore.loadQueue();
    debugPrint('PASSO 4 (responder com foto): ${fila.length} na fila, '
        'status=${(fila.first['payload'] as Map)['status']}, '
        'foto=${fila.first['photo_local_path'] != null}');
    expect(fila.length, 1);
    expect(await File(destino!).exists(), isTrue,
        reason: 'a foto nunca e descartada por falta de rede');

    // ── 5. Fechar e reabrir o app ─────────────────────────────────────
    OfflineStore.resetParaTeste();
    fila = await OfflineStore.loadQueue();
    final tarefasApos = await DataSource.tarefasLocais();
    debugPrint('PASSO 5 (fechar e reabrir): ${fila.length} na fila, '
        '${tarefasApos.length} tarefa(s) ainda no painel');
    expect(fila.length, 1, reason: 'a fila e em disco, sobrevive ao restart');
    expect(tarefasApos.length, 1);

    // ── 6. Religar a rede ─────────────────────────────────────────────
    OfflineSyncService.online.value = true;
    DataSource.definirModoOffline(false);
    expect(DataSource.estaOffline, isFalse);
    final pendentes = await OfflineStore.queueLength();
    debugPrint('PASSO 6 (rede de volta): estaOffline=false, '
        '$pendentes item(ns) aguardando envio');
    expect(pendentes, 1,
        reason: 'a fila continua ate o sync confirmar o envio');
  });

  test('sem nada baixado: lista vazia, nunca erro de rede', () async {
    OfflineSyncService.online.value = false;
    DataSource.definirModoOffline(true);

    final tarefas = await DataSource.tarefasLocais();
    expect(tarefas, isEmpty);
    debugPrint('SEM PACOTES: lista vazia (a tela mostra estado vazio, '
        'nao mensagem de erro)');
  });

  test('tarefa nunca aberta com rede nao pode ser respondida offline',
      () async {
    await OfflineStore.saveTaskBundle('task-2', {
      'task_id': 'task-2',
      'task': {
        'id': 'task-2',
        'checklist_id': 'cl-2',
        'sector_id': 's',
        'hospital_id': 'h',
        'inspector_id': 'i',
        'assigned_by': 'd',
        'due_date': '2026-03-01',
        'status': 'pending',
        'created_at': '2026-01-01T00:00:00.000',
      },
      'checklist': {'title': 'Sem inspecao'},
      'items': [],
      'inspection': null,
      'responses': [],
    });
    OfflineSyncService.online.value = false;
    DataSource.definirModoOffline(true);

    expect(await DataSource.podeResponderOffline('task-2'), isFalse);
    debugPrint('LIMITE CONHECIDO: tarefa sem inspecao no pacote nao abre '
        'offline, a linha de inspections nasce no servidor');
  });
}
