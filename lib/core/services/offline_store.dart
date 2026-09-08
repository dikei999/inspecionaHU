import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Armazenamento local do modo offline (bloco 6).
///
/// Escolha: arquivos JSON via path_provider, não Drift. O pubspec traz as
/// duas opções, mas Drift exige build_runner e code generation, e o volume
/// aqui é pequeno (uma tarefa baixada, dezenas de respostas). Arquivo é
/// suficiente, não gera código e não acrescenta um passo de build antes da
/// defesa. A pasta é a de documentos do app, que sobrevive ao fechamento.
///
/// Layout, dentro da pasta de documentos do app:
/// `offline/profile.json` (perfil em cache, 6.1),
/// `offline/tasks/[taskId].json` (pacote baixado, 6.2),
/// `offline/queue/[opId].json` (fila de envio, 6.3 e 6.4) e
/// `offline/photos/[uuid].jpg` (foto aguardando upload).
///
/// Nada aqui fala com o Supabase: é só persistência. Quem sincroniza é o
/// OfflineSyncService.
class OfflineStore {
  OfflineStore._();

  static Directory? _root;

  /// Raiz do armazenamento offline, criada sob demanda.
  static Future<Directory> _raiz() async {
    final r = _root ??= Directory(
      '${(await getApplicationDocumentsDirectory()).path}/offline',
    );
    if (!await r.exists()) {
      await r.create(recursive: true);
    }
    return r;
  }

  static Future<Directory> _dir(String sub) async {
    final raiz = await _raiz();
    if (sub == '.') return raiz;
    final d = Directory('${raiz.path}/$sub');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  /// Só para testes: descarta a raiz memorizada, para que a próxima chamada
  /// releia o path_provider. Em produção a raiz nunca muda.
  @visibleForTesting
  static void resetParaTeste() => _root = null;

  // ── 6.1 Perfil em cache ─────────────────────────────────────────────────
  // Sem isso o app cai para unauthenticated quando _loadProfile() falha por
  // falta de rede, mesmo com sessão válida persistida.

  static Future<void> saveProfile(String userId, Map<String, dynamic> json) async {
    try {
      final d = await _dir('.');
      final f = File('${d.path}/profile.json');
      await f.writeAsString(jsonEncode({'user_id': userId, 'profile': json}));
    } catch (e) {
      debugPrint('[OfflineStore] saveProfile: $e');
    }
  }

  /// Perfil em cache DESTE usuário. Devolve null se for de outro usuário —
  /// nunca entregar o perfil de quem logou antes neste aparelho.
  static Future<Map<String, dynamic>?> loadProfile(String userId) async {
    try {
      final d = await _dir('.');
      final f = File('${d.path}/profile.json');
      if (!await f.exists()) return null;
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (map['user_id'] != userId) return null;
      return map['profile'] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[OfflineStore] loadProfile: $e');
      return null;
    }
  }

  /// Perfil em cache SEM exigir o id do usuário.
  ///
  /// Necessário quando `currentSession` volta nulo: o access token expirou e
  /// a renovação falhou sem rede, então não há uid para consultar. Devolve
  /// o par (userId, perfil) do último login bem-sucedido neste aparelho.
  static Future<({String userId, Map<String, dynamic> profile})?>
      loadAnyProfile() async {
    try {
      final d = await _dir('.');
      final f = File('${d.path}/profile.json');
      if (!await f.exists()) return null;
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final uid = map['user_id'] as String?;
      final perfil = map['profile'] as Map<String, dynamic>?;
      if (uid == null || perfil == null) return null;
      return (userId: uid, profile: perfil);
    } catch (e) {
      debugPrint('[OfflineStore] loadAnyProfile: $e');
      return null;
    }
  }

  // ── Marca de saída explícita ────────────────────────────────────────────
  // Distingue "o usuário saiu" de "a renovação do token falhou sem rede".
  // Sem essa marca, um token expirado seria indistinguível de um logout e o
  // app voltaria para a tela de login em campo.

  static Future<void> markSignedOut() async {
    try {
      final d = await _dir('.');
      await File('${d.path}/signed_out.flag').writeAsString(
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('[OfflineStore] markSignedOut: $e');
    }
  }

  static Future<void> clearSignedOut() async {
    try {
      final d = await _dir('.');
      final f = File('${d.path}/signed_out.flag');
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('[OfflineStore] clearSignedOut: $e');
    }
  }

  /// true = o usuário saiu de propósito. false = nunca saiu, ou entrou de novo.
  static Future<bool> isSignedOut() async {
    try {
      final d = await _dir('.');
      return File('${d.path}/signed_out.flag').exists();
    } catch (e) {
      debugPrint('[OfflineStore] isSignedOut: $e');
      // Na dúvida NÃO bloqueia a entrada offline: prender o Inspetor fora do
      // app em campo é pior que abrir com perfil em cache.
      return false;
    }
  }

  static Future<void> clearProfile() async {
    try {
      final d = await _dir('.');
      final f = File('${d.path}/profile.json');
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('[OfflineStore] clearProfile: $e');
    }
  }

  // ── 6.2 Pacotes de tarefa baixados ──────────────────────────────────────

  static Future<void> saveTaskBundle(
    String taskId,
    Map<String, dynamic> bundle,
  ) async {
    try {
      final d = await _dir('tasks');
      await File('${d.path}/$taskId.json').writeAsString(jsonEncode(bundle));
    } catch (e) {
      debugPrint('[OfflineStore] saveTaskBundle: $e');
    }
  }

  static Future<Map<String, dynamic>?> loadTaskBundle(String taskId) async {
    try {
      final d = await _dir('tasks');
      final f = File('${d.path}/$taskId.json');
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[OfflineStore] loadTaskBundle: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> listTaskBundles() async {
    try {
      final d = await _dir('tasks');
      final out = <Map<String, dynamic>>[];
      await for (final e in d.list()) {
        if (e is File && e.path.endsWith('.json')) {
          try {
            out.add(jsonDecode(await e.readAsString()) as Map<String, dynamic>);
          } catch (_) {
            // Arquivo corrompido não pode derrubar a listagem inteira.
          }
        }
      }
      return out;
    } catch (e) {
      debugPrint('[OfflineStore] listTaskBundles: $e');
      return [];
    }
  }

  static Future<void> deleteTaskBundle(String taskId) async {
    try {
      final d = await _dir('tasks');
      final f = File('${d.path}/$taskId.json');
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('[OfflineStore] deleteTaskBundle: $e');
    }
  }

  // ── 6.3/6.4 Fila de envio ───────────────────────────────────────────────
  // Cada operação é um arquivo com id determinístico. Reescrever a mesma
  // resposta sobrescreve o arquivo em vez de empilhar duplicatas — é a
  // idempotência do 6.4 já na gravação.

  static Future<void> enqueue(String opId, Map<String, dynamic> op) async {
    try {
      final d = await _dir('queue');
      await File('${d.path}/$opId.json').writeAsString(jsonEncode(op));
    } catch (e) {
      debugPrint('[OfflineStore] enqueue: $e');
    }
  }

  /// Fila em ordem de criação (campo `queued_at`), como pede o 6.4.
  static Future<List<Map<String, dynamic>>> loadQueue() async {
    try {
      final d = await _dir('queue');
      final out = <Map<String, dynamic>>[];
      await for (final e in d.list()) {
        if (e is File && e.path.endsWith('.json')) {
          try {
            final op = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
            op['_op_id'] = e.uri.pathSegments.last.replaceAll('.json', '');
            out.add(op);
          } catch (_) {
            // Ignora entrada corrompida; o resto da fila continua válido.
          }
        }
      }
      out.sort((a, b) =>
          (a['queued_at'] as String? ?? '').compareTo(b['queued_at'] as String? ?? ''));
      return out;
    } catch (e) {
      debugPrint('[OfflineStore] loadQueue: $e');
      return [];
    }
  }

  static Future<void> dequeue(String opId) async {
    try {
      final d = await _dir('queue');
      final f = File('${d.path}/$opId.json');
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('[OfflineStore] dequeue: $e');
    }
  }

  static Future<int> queueLength() async => (await loadQueue()).length;

  // ── Fotos aguardando upload ─────────────────────────────────────────────
  // Foto NUNCA é descartada por falta de rede (6.3): sai do diretório
  // temporário do sistema e vai para a pasta do app, que não é limpa
  // automaticamente.

  static Future<String?> persistPhoto(File source, String fileName) async {
    try {
      final d = await _dir('photos');
      final dest = File('${d.path}/$fileName');
      await source.copy(dest.path);
      return dest.path;
    } catch (e) {
      debugPrint('[OfflineStore] persistPhoto: $e');
      return null;
    }
  }

  static Future<void> deletePhoto(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('[OfflineStore] deletePhoto: $e');
    }
  }

  /// Limpa tudo que é de trabalho, preservando o perfil em cache.
  /// Usado no logout: a sessão acabou, mas o app não deve carregar fila de
  /// um usuário para o próximo.
  static Future<void> clearWorkData() async {
    for (final sub in ['tasks', 'queue', 'photos']) {
      try {
        final d = await _dir(sub);
        if (await d.exists()) await d.delete(recursive: true);
      } catch (e) {
        debugPrint('[OfflineStore] clearWorkData($sub): $e');
      }
    }
  }
}
