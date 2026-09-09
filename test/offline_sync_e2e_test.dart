// Item 1 — ciclo completo: responder, salvar, sair, reconectar, envio
// automático, fila esvaziando, foto confirmada no servidor.
//
// Bate no Supabase real do projeto (conta demo), porque é a única forma
// de provar que o upload de foto + upsert de resposta + drenagem da fila
// funcionam de ponta a ponta contra a infraestrutura real, incluindo as
// políticas de RLS/Storage da migration_security_hardening.sql.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/services/offline_store.dart';
import 'package:inspecionahu/core/services/offline_sync_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.raiz);
  final String raiz;
  @override
  Future<String?> getApplicationDocumentsPath() async => raiz;
}

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    HttpOverrides.global = null;
    try {
      return HttpClient(context: context);
    } finally {
      HttpOverrides.global = this;
    }
  }
}

const _url = 'https://xccmdnwexdkevrlpynio.supabase.co';
const _anon = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhjY21kbndleGRrZXZybHB5bmlvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQzMTYwODUsImV4cCI6MjA4OTg5MjA4NX0'
    '._YNgH7mzjCUQ20LHDBgT-l4i1Y65a_zYBPH5-omt8R0';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('offline_e2e_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    OfflineStore.resetParaTeste();

    final store = <String, Object>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async {
        switch (call.method) {
          case 'getAll':
            return store;
          case 'setString':
          case 'setBool':
          case 'setInt':
          case 'setDouble':
          case 'setStringList':
            store[call.arguments['key'] as String] =
                call.arguments['value'] as Object;
            return true;
          case 'remove':
            store.remove(call.arguments['key']);
            return true;
          case 'clear':
            store.clear();
            return true;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test(
    'responder offline (simulado), sair, reconectar: fila drena e foto sobe',
    () async {
      await Supabase.initialize(url: _url, anonKey: _anon);
      final client = Supabase.instance.client;

      final auth = await client.auth.signInWithPassword(
        email: 'inspetor@demo.com',
        password: 'demo1234',
      );
      expect(auth.session, isNotNull);

      final inspections = await client
          .from('inspections')
          .select('id, hospital_id, checklist_id')
          .eq('overall_status', 'draft')
          .limit(1);
      expect(inspections, isNotEmpty,
          reason: 'precisa de inspeção draft no HU-DEMO');
      final inspectionId = inspections[0]['id'] as String;
      final hospitalId = inspections[0]['hospital_id'] as String;
      final checklistId = inspections[0]['checklist_id'] as String;

      final items = await client
          .from('checklist_items')
          .select('id')
          .eq('checklist_id', checklistId)
          .limit(2);
      expect(items.length, greaterThanOrEqualTo(2),
          reason: 'checklist precisa de ao menos 2 itens para o teste');
      final itemId1 = items[0]['id'] as String;
      final itemId2 = items[1]['id'] as String;

      // ── "Responder offline": grava direto na fila em disco, como
      // _saveResponse faz quando _isOnline é false. Não passa pela UI —
      // testa exatamente o contrato entre a tela e o serviço.
      final fakeJpeg = File('${tmp.path}/foto1.jpg');
      await fakeJpeg.writeAsBytes(
        [0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(300, 0x30)],
      );
      final fileName = 'e2e_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final persisted = await OfflineStore.persistPhoto(fakeJpeg, fileName);
      expect(persisted, isNotNull);
      final storagePath = '$hospitalId/$inspectionId/$fileName';

      await OfflineSyncService.enqueueResponse(
        inspectionId: inspectionId,
        checklistItemId: itemId1,
        payload: {
          'inspection_id': inspectionId,
          'checklist_item_id': itemId1,
          'status': 'NC',
          'observation': 'Item com foto — respondido offline no teste e2e',
          'photo_url': null,
          'photo_captured_at': DateTime.now().toIso8601String(),
          'photo_size_kb': 33,
          'answered_at': DateTime.now().toIso8601String(),
        },
        photoLocalPath: persisted,
        photoStoragePath: storagePath,
      );

      await OfflineSyncService.enqueueResponse(
        inspectionId: inspectionId,
        checklistItemId: itemId2,
        payload: {
          'inspection_id': inspectionId,
          'checklist_item_id': itemId2,
          'status': 'C',
          'observation': null,
          'photo_url': null,
          'photo_captured_at': null,
          'photo_size_kb': null,
          'answered_at': DateTime.now().toIso8601String(),
        },
      );

      // "Sair": nada de especial acontece — a fila fica no disco,
      // sobrevivendo ao fechamento da tela (e, no app real, ao fechamento
      // do processo).
      expect(await OfflineStore.queueLength(), 2);

      // ── "Reconectar": syncIfNeeded() é o gatilho do heartbeat e do
      // start(). Chamado sem que nada mais tenha disparado a transição de
      // conectividade — é exatamente o caminho que cobre o caso em que o
      // evento do connectivity_plus falha ou chega atrasado.
      OfflineSyncService.pendingCount.value =
          await OfflineStore.queueLength();
      await OfflineSyncService.syncIfNeeded();

      // ── "Envio automático": confere o resultado.
      final filaDepois = await OfflineStore.loadQueue();
      expect(filaDepois, isEmpty,
          reason: 'a fila tem que esvaziar sozinha ao reconectar');

      final fotoAindaNoDisco =
          persisted != null && await File(persisted).exists();
      expect(fotoAindaNoDisco, isFalse,
          reason: 'a foto só é apagada do disco DEPOIS do upload confirmado');

      // ── "Relatório íntegro no painel do Diretor com as fotos".
      final resp1 = await client
          .from('inspection_responses')
          .select()
          .eq('inspection_id', inspectionId)
          .eq('checklist_item_id', itemId1)
          .single();
      expect(resp1['status'], 'NC');
      expect(resp1['observation'],
          'Item com foto — respondido offline no teste e2e');
      expect(resp1['photo_url'], isNotNull,
          reason: 'a foto tem que estar de fato no relatório final');

      final resp2 = await client
          .from('inspection_responses')
          .select()
          .eq('inspection_id', inspectionId)
          .eq('checklist_item_id', itemId2)
          .single();
      expect(resp2['status'], 'C');

      // ── Limpeza: remove os dados de teste do ambiente demo.
      await client
          .from('inspection_responses')
          .delete()
          .eq('inspection_id', inspectionId)
          .eq('checklist_item_id', itemId1);
      await client
          .from('inspection_responses')
          .delete()
          .eq('inspection_id', inspectionId)
          .eq('checklist_item_id', itemId2);
      try {
        await client.storage.from('inspection-photos').remove([storagePath]);
      } catch (_) {
        // Inspetor não pode apagar do Storage (DELETE é só do Diretor,
        // desde a migration_security_hardening.sql) — resíduo aceitável
        // em ambiente demo, não afeta o veredito do teste.
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('syncIfNeeded() não faz nada com a fila vazia (sem custo de rede)',
      () async {
    OfflineSyncService.pendingCount.value = 0;
    // Não deveria nem chamar isOnline — mas o teste só garante que não
    // lança e não deixa nada pendurado.
    await OfflineSyncService.syncIfNeeded();
    expect(await OfflineStore.queueLength(), 0);
  });
}
