import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/app/routes.dart';

/// Item 2 — rota de detalhes de tarefa (somente leitura).
///
/// Confere que a rota existe e gera o path esperado, e que ela é DISTINTA
/// da rota de responder — a raiz do defeito era o app levar Supervisor e
/// Diretor para a rota de resposta, que é exclusiva do Inspetor.
void main() {
  group('AppRoutes.tarefaDetalhes', () {
    test('gera o path correto com o id da tarefa', () {
      expect(AppRoutes.tarefaDetalhes('abc-123'), '/tarefa/abc-123');
    });

    test('é uma rota DIFERENTE de responderChecklist', () {
      const taskId = 'mesma-tarefa';
      expect(
        AppRoutes.tarefaDetalhes(taskId),
        isNot(AppRoutes.responderChecklist(taskId)),
      );
    });

    test('não vive sob /inspector — Supervisor e Diretor podem acessar',
        () {
      // A guarda de rota em app.dart bloqueia Diretor/Supervisor apenas
      // em paths que começam com /director, /supervisor, /super-admin —
      // não havia guarda alguma para /inspector, que é por onde a rota
      // de responder escapava. Não repetir esse erro: a nova rota mora
      // fora de /inspector.
      expect(AppRoutes.tarefaDetalhes('x').startsWith('/inspector'), isFalse);
    });
  });
}
