import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/services/offline_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.raiz);
  final String raiz;
  @override
  Future<String?> getApplicationDocumentsPath() async => raiz;
}

/// Roteiro do item 1, passo a passo, contra o armazenamento REAL.
///
/// Reproduz exatamente o que signOut() e _loadProfile() fazem com o
/// OfflineStore — que é onde estava o defeito: o logout apagava o cache que
/// "Continuar offline" precisa.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('roteiro_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    OfflineStore.resetParaTeste();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('roteiro completo: entrar, baixar, sair, offline, responder', () async {
    // ── 1. Entrar com rede ────────────────────────────────────────────
    await OfflineStore.saveProfile('user-1', {
      'id': 'user-1',
      'full_name': 'João Silva',
      'role': 'inspector',
      'hospital_id': 'h1',
    });
    await OfflineStore.clearSignedOut();
    var cache = await OfflineStore.loadAnyProfile();
    expect(cache, isNotNull);
    debugPrint('PASSO 1 (entrar com rede): perfil em cache = ${cache!.userId}');

    // ── 2. Baixar tarefa ──────────────────────────────────────────────
    await OfflineStore.saveTaskBundle('task-1', {
      'task_id': 'task-1',
      'checklist': {'title': 'NR-32 UTI'},
      'items': [
        {'id': 'i1', 'description': 'Lavatório exclusivo'},
      ],
      'inspection': {'id': 'insp-1', 'overall_status': 'draft'},
      'responses': [],
    });
    var baixados = await OfflineStore.listTaskBundles();
    debugPrint('PASSO 2 (baixar tarefa): ${baixados.length} pacote(s) no aparelho');
    expect(baixados.length, 1);

    // ── 3. Sair ───────────────────────────────────────────────────────
    // É o que signOut() faz agora: marca a saída e NÃO apaga o cache.
    await OfflineStore.markSignedOut();

    expect(await OfflineStore.isSignedOut(), isTrue,
        reason: 'a marca bloqueia a entrada automática');
    cache = await OfflineStore.loadAnyProfile();
    baixados = await OfflineStore.listTaskBundles();
    debugPrint('PASSO 3 (sair): isSignedOut=true, '
        'perfil preservado=${cache != null}, '
        'pacotes preservados=${baixados.length}');
    expect(cache, isNotNull,
        reason: 'sem isto o botão Continuar offline seria impossível');
    expect(baixados.length, 1);

    // ── 4. Modo avião + abrir app ─────────────────────────────────────
    // _init() consulta a marca: entrada automática barrada, cai no login.
    final entradaAutomatica = !(await OfflineStore.isSignedOut());
    debugPrint('PASSO 4 (modo avião, abrir app): entrada automática = '
        '$entradaAutomatica -> tela de login');
    expect(entradaAutomatica, isFalse);

    // ── 5. Tocar em "Continuar offline" ───────────────────────────────
    // entrarOfflineManualmente() ignora a marca e usa o cache.
    final cacheManual = await OfflineStore.loadAnyProfile();
    debugPrint('PASSO 5 (Continuar offline): perfil carregado = '
        '${cacheManual?.profile['full_name']} '
        '(${cacheManual?.profile['role']})');
    expect(cacheManual, isNotNull,
        reason: 'ANTES da correção isto era null e o botão falhava');

    // ── 6. Abrir a tarefa baixada ─────────────────────────────────────
    final bundle = await OfflineStore.loadTaskBundle('task-1');
    debugPrint('PASSO 6 (abrir tarefa baixada): '
        'checklist = ${(bundle?['checklist'] as Map?)?['title']}, '
        'itens = ${(bundle?['items'] as List?)?.length}');
    expect(bundle, isNotNull);
    expect((bundle!['items'] as List).length, 1);

    // ── 7. Responder um item ──────────────────────────────────────────
    await OfflineStore.enqueue('resp_insp-1_i1', {
      'queued_at': DateTime.now().toIso8601String(),
      'inspection_id': 'insp-1',
      'checklist_item_id': 'i1',
      'payload': {'status': 'C'},
    });
    final fila = await OfflineStore.loadQueue();
    debugPrint('PASSO 7 (responder um item): ${fila.length} resposta(s) na fila '
        '= ${(fila.first['payload'] as Map)['status']}');
    expect(fila.length, 1);
  });

  test('outro usuário entrando limpa o trabalho do anterior', () async {
    await OfflineStore.saveProfile('user-1', {'id': 'user-1'});
    await OfflineStore.saveTaskBundle('task-1', {'task_id': 'task-1'});
    await OfflineStore.enqueue('op1', {'queued_at': '2026-01-01T00:00:00'});

    // É o que _loadProfile() faz ao detectar uid diferente.
    final anterior = await OfflineStore.loadAnyProfile();
    expect(anterior!.userId, 'user-1');
    if (anterior.userId != 'user-2') {
      await OfflineStore.clearWorkData();
    }
    await OfflineStore.saveProfile('user-2', {'id': 'user-2'});

    expect(await OfflineStore.loadQueue(), isEmpty,
        reason: 'ninguém herda fila de outra pessoa');
    expect(await OfflineStore.loadTaskBundle('task-1'), isNull);
    expect((await OfflineStore.loadAnyProfile())!.userId, 'user-2');
    debugPrint('TROCA DE USUÁRIO: fila e pacotes do anterior removidos');
  });
}
