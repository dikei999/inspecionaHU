import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/models/profile.dart';

Profile _p(String nome, {String? role}) => Profile(
      id: 'x',
      fullName: nome,
      email: 'a@b.c',
      cpf: '12345678901',
      role: role,
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('nome e sobrenome derivados de full_name', () {
    test('nome composto separa no primeiro espaço', () {
      final p = _p('João Pedro da Silva');
      expect(p.firstName, 'João');
      expect(p.lastName, 'Pedro da Silva');
    });

    test('nome único fica sem sobrenome', () {
      final p = _p('Madonna');
      expect(p.firstName, 'Madonna');
      expect(p.lastName, '');
    });

    test('espaços extras não viram sobrenome vazio', () {
      final p = _p('  Ana   Maria  ');
      expect(p.firstName, 'Ana');
      expect(p.lastName, 'Maria');
    });

    test('nome vazio não estoura', () {
      final p = _p('');
      expect(p.firstName, '');
      expect(p.lastName, '');
    });
  });

  group('joinName recompõe full_name', () {
    test('junta nome e sobrenome', () {
      expect(Profile.joinName('João', 'Silva'), 'João Silva');
    });

    test('sobrenome vazio não deixa espaço sobrando', () {
      expect(Profile.joinName('Madonna', ''), 'Madonna');
      expect(Profile.joinName('Madonna', '   '), 'Madonna');
    });

    test('ida e volta preserva o nome original', () {
      const original = 'Maria Clara de Souza';
      final p = _p(original);
      expect(Profile.joinName(p.firstName, p.lastName), original);
    });
  });

  group('saudação usa cargo + primeiro nome', () {
    test('Diretor João', () {
      expect(_p('João Silva', role: 'director').saudacao, 'Diretor João');
    });

    test('cada papel tem seu rótulo', () {
      expect(_p('Ana Lima', role: 'supervisor').saudacao, 'Supervisor Ana');
      expect(_p('Ana Lima', role: 'inspector').saudacao, 'Inspetor Ana');
      expect(_p('Ana Lima', role: 'super_admin').saudacao, 'Admin Ana');
    });

    test('sem papel definido, só o primeiro nome', () {
      expect(_p('Ana Lima').saudacao, 'Ana');
    });
  });

  group('telefone e cargo', () {
    test('fromJson lê as colunas novas', () {
      final p = Profile.fromJson({
        'id': 'x',
        'full_name': 'Ana Lima',
        'email': 'a@b.c',
        'cpf': '12345678901',
        'status': 'active',
        'created_at': '2026-01-01T00:00:00.000',
        'phone': '86999998888',
        'job_title': 'Enfermeira do Trabalho',
      });
      expect(p.phone, '86999998888');
      expect(p.jobTitle, 'Enfermeira do Trabalho');
    });

    test('ausência das colunas não quebra (base sem a migration)', () {
      final p = Profile.fromJson({
        'id': 'x',
        'full_name': 'Ana Lima',
        'email': 'a@b.c',
        'cpf': '12345678901',
        'status': 'active',
        'created_at': '2026-01-01T00:00:00.000',
      });
      expect(p.phone, isNull);
      expect(p.jobTitle, isNull);
    });

    test('job_title não se confunde com role', () {
      final p = Profile.fromJson({
        'id': 'x',
        'full_name': 'Ana Lima',
        'email': 'a@b.c',
        'cpf': '12345678901',
        'role': 'inspector',
        'status': 'active',
        'created_at': '2026-01-01T00:00:00.000',
        'job_title': 'Diretora Técnica',
      });
      // O cargo livre NÃO promove ninguém: a saudação segue o role.
      expect(p.saudacao, 'Inspetor Ana');
      expect(p.jobTitle, 'Diretora Técnica');
    });
  });
}
