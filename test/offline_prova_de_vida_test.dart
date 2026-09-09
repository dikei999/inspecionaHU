// Item 1 da auditoria (set/2026): prova de vida real antes de sincronizar.
//
// Testa contra o Supabase real do projeto (mesma rede que o app usa em
// produção) porque a causa raiz era exatamente esta: checkConnectivity()
// do connectivity_plus prova a INTERFACE, não a internet. Um mock de rede
// não reproduziria o problema real — precisa ser uma requisição de
// verdade batendo no endpoint de verdade.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/services/offline_sync_service.dart';
import 'package:inspecionahu/core/services/supabase_service.dart';

/// TestWidgetsFlutterBinding intercepta HttpClient e força status 400
/// sempre, para impedir que testes de unidade acidentalmente batam na
/// rede. Este teste PRECISA de rede real — é o próprio objeto sob teste.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  group('OfflineSyncService.isOnline — prova de vida real', () {
    test('responde true quando o servidor do projeto está acessível',
        () async {
      // Sanity check independente: se o endpoint em si não responde, o
      // teste não teria como passar por motivo nenhum válido — falha
      // clara em vez de um false negativo confuso.
      final direto = await HttpClient()
          .headUrl(Uri.parse('${SupabaseService.supabaseUrl}/auth/v1/health'))
          .then((r) => r.close());
      expect(direto.statusCode, greaterThan(0),
          reason: 'endpoint de saúde do projeto precisa responder para '
              'este teste fazer sentido');

      final online = await OfflineSyncService.isOnline;
      expect(online, isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('não trava — timeout aplicado mesmo com o Supabase real',
        () async {
      final sw = Stopwatch()..start();
      await OfflineSyncService.isOnline;
      sw.stop();
      // Generoso o bastante para CI lento, apertado o bastante para
      // provar que não há espera indefinida.
      expect(sw.elapsed, lessThan(const Duration(seconds: 15)));
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
