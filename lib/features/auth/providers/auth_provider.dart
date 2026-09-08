import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/offline_store.dart';
import '../../../core/utils/cpf_utils.dart';

enum AuthStatus { loading, unauthenticated, authenticated }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.loading;
  Profile? _profile;

  // Previne race condition: bloqueia o listener durante o fluxo de signUp
  // enquanto o INSERT em profiles ainda não foi concluído.
  bool _insertingProfile = false;

  /// Entrou com o perfil em cache porque não havia rede (6.1).
  /// A UI usa para mostrar a faixa de status; o app funciona normalmente.
  bool _offlineMode = false;

  /// true só durante um signOut() explícito. É o que separa "o usuário saiu"
  /// de "a renovação do token falhou sem rede" no listener de auth.
  bool _signingOut = false;

  AuthStatus get status => _status;
  Profile? get profile => _profile;
  bool get offlineMode => _offlineMode;

  final _supabase = Supabase.instance.client;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    final session = _supabase.auth.currentSession;
    if (session != null) {
      await _loadProfile();
    } else if (await _tentarEntrarOffline()) {
      // Sessão nula NÃO significa que o usuário saiu: o access token dura
      // 1h e, sem rede, a renovação falha e o supabase_flutter descarta a
      // sessão. Era por isso que fechar o app em modo avião levava de volta
      // ao login. Havendo perfil em cache e nenhuma saída explícita, entra.
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
        // signedOut também é emitido quando a renovação do token falha.
        // Só derruba a sessão se o usuário REALMENTE tocou em Sair; caso
        // contrário tenta seguir offline com o perfil em cache.
        if (_signingOut) {
          _profile = null;
          _offlineMode = false;
          _status = AuthStatus.unauthenticated;
          notifyListeners();
          return;
        }
        if (await _tentarEntrarOffline()) return;
        _profile = null;
        _offlineMode = false;
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
    });
  }

  /// Entra com o perfil em cache quando não há sessão utilizável.
  ///
  /// Só acontece se o usuário NÃO saiu de propósito: a marca de saída é
  /// gravada apenas em signOut() e apagada em todo login bem-sucedido.
  /// Retorna true se conseguiu entrar em modo offline.
  Future<bool> _tentarEntrarOffline() async {
    if (await OfflineStore.isSignedOut()) return false;

    final cache = await OfflineStore.loadAnyProfile();
    if (cache == null) return false;

    _profile = Profile.fromJson(cache.profile);
    _status = AuthStatus.authenticated;
    _offlineMode = true;
    debugPrint('[AuthProvider] modo offline com perfil em cache');
    notifyListeners();
    return true;
  }

  /// Volta ao normal quando a rede retorna: tenta renovar a sessão e, dando
  /// certo, recarrega o perfil do servidor e sai do modo offline sozinho.
  Future<void> tentarSairDoModoOffline() async {
    if (!_offlineMode) return;

    try {
      if (_supabase.auth.currentSession == null) {
        // Sessão descartada: só um refresh explícito a traz de volta, usando
        // o refresh token que o supabase_flutter persistiu.
        await _supabase.auth.refreshSession();
      }
      if (_supabase.auth.currentSession != null) {
        await _loadProfile();
      }
    } catch (e) {
      // Ainda sem rede, ou refresh token expirado. Continua offline: quem
      // decide derrubar a sessão é o usuário, não uma falha de rede.
      debugPrint('[AuthProvider] tentarSairDoModoOffline: $e');
    }
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
      _offlineMode = false;

      // Guarda o perfil para a próxima abertura sem rede (6.1) e limpa a
      // marca de saída: a partir daqui, sessão perdida = falha de rede.
      if (data != null) {
        await OfflineStore.saveProfile(uid, data);
        await OfflineStore.clearSignedOut();
      }
    } catch (e) {
      debugPrint('[_loadProfile] erro: $e');

      // Causa raiz do "não passa do login" (6.1): a sessão do Supabase já é
      // persistida, mas esta busca falha sem rede e o app caía para
      // unauthenticated — a tela de login voltava mesmo com sessão válida.
      // Com sessão válida e perfil em cache, entra em modo offline.
      final cache = await OfflineStore.loadProfile(uid);
      if (cache != null) {
        _profile = Profile.fromJson(cache);
        _status = AuthStatus.authenticated;
        _offlineMode = true;
        debugPrint('[_loadProfile] entrando com perfil em cache (offline)');
      } else {
        // Sem cache não há como saber o papel do usuário: primeiro login
        // exige internet (limitação documentada em 6.7).
        _profile = null;
        _status = AuthStatus.unauthenticated;
        _offlineMode = false;
      }
    }
    notifyListeners();
  }

  /// Tenta trocar o perfil em cache pelo do servidor quando a rede volta.
  /// Silencioso: se ainda não houver rede, continua em modo offline.
  /// Passa por tentarSairDoModoOffline() porque a sessão pode ter sido
  /// descartada junto com o token expirado e precisa ser renovada antes.
  Future<void> revalidateProfileIfOffline() async {
    if (!_offlineMode) return;
    await tentarSairDoModoOffline();
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
    _signingOut = true;
    try {
      // Marca a saída ANTES de derrubar a sessão: se o app for fechado no
      // meio, a próxima abertura sabe que foi saída de verdade e não
      // reabre em modo offline.
      await OfflineStore.markSignedOut();
      try {
        await _supabase.auth.signOut();
      } catch (e) {
        // Sair sem rede falha no servidor, mas localmente tem de valer.
        debugPrint('[signOut] erro no servidor (ignorado): $e');
      }
      // Sair limpa o cache e os dados de trabalho: o próximo usuário deste
      // aparelho não pode herdar perfil nem fila de envio de outro.
      await OfflineStore.clearProfile();
      await OfflineStore.clearWorkData();
      _profile = null;
      _offlineMode = false;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    } finally {
      _signingOut = false;
    }
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
