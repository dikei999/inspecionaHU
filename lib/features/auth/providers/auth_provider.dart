import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/profile.dart';
import '../../../core/utils/cpf_utils.dart';

enum AuthStatus { loading, unauthenticated, authenticated }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.loading;
  Profile? _profile;

  // Previne race condition: bloqueia o listener durante o fluxo de signUp
  // enquanto o INSERT em profiles ainda não foi concluído.
  bool _insertingProfile = false;

  AuthStatus get status => _status;
  Profile? get profile => _profile;

  final _supabase = Supabase.instance.client;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    final session = _supabase.auth.currentSession;
    if (session != null) {
      await _loadProfile();
    } else {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }

    _supabase.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.tokenRefreshed) {
        // Ignora o evento enquanto o signUp está inserindo o perfil —
        // o próprio signUp chama _loadProfile() após o INSERT.
        if (_insertingProfile) return;
        await _loadProfile();
      } else if (event == AuthChangeEvent.signedOut) {
        _profile = null;
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
    });
  }

  Future<void> _loadProfile() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();

      _profile = data != null ? Profile.fromJson(data) : null;
      _status = AuthStatus.authenticated;
    } catch (e) {
      debugPrint('[_loadProfile] erro: $e');
      _profile = null;
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  /// Retorna null em caso de sucesso ou mensagem de erro.
  Future<String?> signUp({
    required String fullName,
    required String email,
    required String cpf,
    required String password,
  }) async {
    try {
      // ── 1. Criar usuário no Supabase Auth ───────────────────────────────
      debugPrint('[signUp] iniciando auth.signUp para $email');
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
      );

      final user = response.user;
      if (user == null) {
        debugPrint('[signUp] response.user é null — conta não criada');
        return 'Não foi possível criar a conta. Tente novamente.';
      }
      debugPrint('[signUp] usuário criado no Auth: ${user.id}');

      // ── 2. Verificar sessão ─────────────────────────────────────────────
      // Se session == null, confirmação de e-mail está ATIVADA no Supabase.
      // Nesse caso auth.uid() é null e o INSERT em profiles será bloqueado
      // pelo RLS (policy profiles_insert_own exige id = auth.uid()).
      //
      // SOLUÇÃO: no Supabase → Authentication → Settings → Email →
      // desmarcar "Enable email confirmations".
      if (response.session == null) {
        debugPrint(
          '[signUp] ERRO: session é null. '
          'Confirmação de e-mail está ATIVADA no Supabase. '
          'Desabilite em Authentication → Settings → Email → '
          '"Enable email confirmations".',
        );
        return 'Confirmação de e-mail está ativa no Supabase. '
            'Desabilite em Authentication → Settings → Email.';
      }
      debugPrint('[signUp] sessão ativa: ${response.session!.accessToken.substring(0, 20)}...');

      // ── 3. INSERT em profiles ───────────────────────────────────────────
      // Bloqueia o listener onAuthStateChange para evitar race condition:
      // o evento signedIn já disparou com a criação da sessão e chamaria
      // _loadProfile() antes do INSERT terminar.
      _insertingProfile = true;
      try {
        debugPrint('[signUp] executando INSERT em profiles...');
        await _supabase.from('profiles').insert({
          'id': user.id,
          'full_name': fullName.trim(),
          'email': email.trim().toLowerCase(),
          'cpf': CpfUtils.strip(cpf),
          'status': 'active',
        });
        debugPrint('[signUp] INSERT executado sem exceção');
      } on PostgrestException catch (e) {
        debugPrint(
          '[signUp] INSERT profiles FALHOU\n'
          '  message: ${e.message}\n'
          '  code:    ${e.code}\n'
          '  details: ${e.details}\n'
          '  hint:    ${e.hint}',
        );
        return 'Erro ao salvar perfil: ${e.message}';
      } finally {
        _insertingProfile = false;
      }

      // ── 4. Confirmar que o perfil existe ────────────────────────────────
      debugPrint('[signUp] confirmando perfil com SELECT...');
      final check = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (check == null) {
        debugPrint(
          '[signUp] PERFIL NÃO ENCONTRADO após INSERT.\n'
          '  Possível falha silenciosa de RLS ou trigger de banco.\n'
          '  Verifique a policy "profiles_insert_own" no Supabase.',
        );
        return 'Perfil não encontrado após criação. Verifique as políticas RLS.';
      }

      debugPrint('[signUp] PROFILE CRIADO COM SUCESSO: $check');

      // ── 5. Carregar perfil no state → GoRouter navega para /aguardo ────
      await _loadProfile();
      return null; // sucesso
    } on AuthException catch (e) {
      debugPrint('[signUp] AuthException: ${e.message}');
      return _translateError(e.message);
    } catch (e) {
      debugPrint('[signUp] ERRO INESPERADO: $e');
      return 'Erro ao criar conta: $e';
    }
  }

  /// Retorna null em caso de sucesso ou mensagem de erro traduzida.
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('[signIn] iniciando para $email');
      await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await _loadProfile();
      debugPrint('[signIn] perfil carregado: ${_profile?.id}');
      return null;
    } on AuthException catch (e) {
      debugPrint('[signIn] AuthException: ${e.message}');
      return _translateError(e.message);
    } catch (e) {
      debugPrint('[signIn] erro: $e');
      return 'Erro ao entrar. Verifique sua conexão e tente novamente.';
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    _profile = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Recarrega o perfil — útil quando role é atribuído externamente.
  Future<void> refreshProfile() async {
    await _loadProfile();
  }

  /// Atualiza nome, email e/ou foto do perfil do usuário logado.
  Future<String?> updateProfile({
    String? fullName,
    String? email,
    String? photoUrl,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return 'Usuário não autenticado.';
    try {
      final updates = <String, dynamic>{};
      if (fullName != null) updates['full_name'] = fullName.trim();
      if (email != null) updates['email'] = email.trim().toLowerCase();
      if (photoUrl != null) updates['photo_url'] = photoUrl;
      if (updates.isEmpty) return null;
      await _supabase.from('profiles').update(updates).eq('id', uid);
      await _loadProfile();
      return null;
    } catch (e) {
      debugPrint('[updateProfile] erro: $e');
      return 'Erro ao salvar perfil.';
    }
  }

  /// Envia link de recuperação de senha para o email informado.
  Future<String?> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email.trim());
      return null;
    } on AuthException catch (e) {
      return _translateError(e.message);
    } catch (_) {
      return 'Erro ao enviar link de recuperação. Verifique sua conexão.';
    }
  }

  String _translateError(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'E-mail ou senha incorretos.';
    }
    if (message.contains('Email not confirmed')) {
      return 'Confirme seu e-mail antes de entrar.';
    }
    if (message.contains('User already registered')) {
      return 'Este e-mail já está cadastrado.';
    }
    if (message.contains('Password should be at least')) {
      return 'A senha deve ter no mínimo 6 caracteres.';
    }
    if (message.contains('Unable to validate email address')) {
      return 'E-mail inválido.';
    }
    return message;
  }
}
