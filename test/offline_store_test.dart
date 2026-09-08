import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/services/offline_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake do path_provider: aponta a pasta de documentos para um diretório
/// temporário real, então o teste exercita I/O de verdade.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.raiz);
  final String raiz;

  @override
  Future<String?> getApplicationDocumentsPath() async => raiz;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('inspecionahu_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    // A raiz é memorizada num static: sem isto, um teste enxerga a pasta
    // temporária do anterior.
    OfflineStore.resetParaTeste();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('perfil em cache', () {
    test('grava e lê de volta, como num cold start', () async {
      await OfflineStore.saveProfile('user-1', {
        'id': 'user-1',
        'full_name': 'Fulano',
        'role': 'inspector',
      });

      // loadAnyProfile é o caminho usado quando não há sessão e, portanto,
      // não há uid para consultar.
      final cache = await OfflineStore.loadAnyProfile();
      expect(cache, isNotNull);
      expect(cache!.userId, 'user-1');
      expect(cache.profile['role'], 'inspector');
    });

    test('não entrega o perfil de outro usuário', () async {
      await OfflineStore.saveProfile('user-1', {'id': 'user-1'});
      expect(await OfflineStore.loadProfile('user-2'), isNull);
      expect(await OfflineStore.loadProfile('user-1'), isNotNull);
    });

    test('sem arquivo devolve null em vez de estourar', () async {
      expect(await OfflineStore.loadAnyProfile(), isNull);
    });
  });

  group('marca de saída explícita', () {
    test('começa ausente', () async {
      expect(await OfflineStore.isSignedOut(), isFalse);
    });

    test('markSignedOut liga, clearSignedOut desliga', () async {
      await OfflineStore.markSignedOut();
      expect(await OfflineStore.isSignedOut(), isTrue);

      await OfflineStore.clearSignedOut();
      expect(await OfflineStore.isSignedOut(), isFalse);
    });

    test('sobrevive entre "execuções" do app (arquivo em disco)', () async {
      await OfflineStore.markSignedOut();
      // Simula reabrir o app: o estado tem de vir do disco, não da memória.
      final arquivo = File('${tmp.path}/offline/signed_out.flag');
      expect(await arquivo.exists(), isTrue);
    });
  });

  group('fila de envio', () {
    test('mesma resposta duas vezes não duplica na fila', () async {
      final opId = 'resp_insp1_item1';
      await OfflineStore.enqueue(opId, {
        'queued_at': '2026-01-01T10:00:00.000',
        'payload': {'status': 'C'},
      });
      await OfflineStore.enqueue(opId, {
        'queued_at': '2026-01-01T10:05:00.000',
        'payload': {'status': 'NC'},
      });

      final fila = await OfflineStore.loadQueue();
      expect(fila.length, 1, reason: 'idempotência por opId');
      expect((fila.first['payload'] as Map)['status'], 'NC',
          reason: 'vence a versão mais recente');
    });

    test('fila sai ordenada por queued_at', () async {
      await OfflineStore.enqueue('b', {'queued_at': '2026-01-02T00:00:00.000'});
      await OfflineStore.enqueue('a', {'queued_at': '2026-01-01T00:00:00.000'});
      final fila = await OfflineStore.loadQueue();
      expect(fila.map((e) => e['_op_id']).toList(), ['a', 'b']);
    });

    test('entrada corrompida não derruba a fila inteira', () async {
      await OfflineStore.enqueue('boa', {'queued_at': '2026-01-01T00:00:00'});
      final dir = Directory('${tmp.path}/offline/queue');
      await File('${dir.path}/ruim.json').writeAsString('{ isso não é json');

      final fila = await OfflineStore.loadQueue();
      expect(fila.length, 1);
      expect(fila.first['_op_id'], 'boa');
    });
  });

  group('logout limpa o que é de trabalho', () {
    test('clearWorkData apaga fila e tarefas, preserva o perfil', () async {
      await OfflineStore.saveProfile('user-1', {'id': 'user-1'});
      await OfflineStore.enqueue('op1', {'queued_at': '2026-01-01T00:00:00'});
      await OfflineStore.saveTaskBundle('task1', {'task_id': 'task1'});

      await OfflineStore.clearWorkData();

      expect(await OfflineStore.loadQueue(), isEmpty);
      expect(await OfflineStore.loadTaskBundle('task1'), isNull);
      // clearWorkData NÃO mexe no perfil — quem apaga isso é o signOut.
      expect(await OfflineStore.loadAnyProfile(), isNotNull);
    });
  });

  group('JSON gravado', () {
    test('profile.json guarda user_id e profile', () async {
      await OfflineStore.saveProfile('abc', {'id': 'abc', 'role': 'director'});
      final f = File('${tmp.path}/offline/profile.json');
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      expect(map['user_id'], 'abc');
      expect((map['profile'] as Map)['role'], 'director');
    });
  });
}
